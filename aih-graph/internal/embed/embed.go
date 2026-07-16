// Package embed implements aih-graph's embedding pipeline. The only semantic
// embedding backend is local Ollama using the nomic-embed-text model; BM25/FTS5
// lives in storage as the lexical index and fallback search path.
package embed

import (
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"os"
	"strings"
	"time"
)

// Embedder produces a vector embedding for arbitrary input text. Implementations
// must return vectors of the same Dim() across all calls in a session.
type Embedder interface {
	// Embed returns a Dim()-length float32 vector for text.
	Embed(text string) ([]float32, error)
	// Dim is the fixed dimensionality of vectors produced by this embedder.
	Dim() int
	// Model is a human-readable identifier persisted alongside each
	// embedding.
	Model() string
}

// BatchEmbedder can embed multiple texts in one backend request. Callers use
// batches of at most 64 texts; a final batch may be smaller.
type BatchEmbedder interface {
	Embedder
	EmbedBatch(texts []string) ([][]float32, error)
}

// ---------------------------------------------------------------------------
// OllamaEmbedder calls a local Ollama embedding model.
// ---------------------------------------------------------------------------

const (
	ollamaDefaultEndpoint   = "http://localhost:11434/api/embed"
	ollamaDefaultModel      = "nomic-embed-text"
	ollamaDefaultMaxRetries = 2
	ollamaRetryBaseDelay    = 200 * time.Millisecond
)

// OllamaEmbedder calls Ollama's /api/embed endpoint. It is the preferred local
// semantic embedder for M048 because vectors stay on the developer machine.
type OllamaEmbedder struct {
	model      string
	endpoint   string
	dim        int
	client     *http.Client
	maxRetries int
	retryDelay time.Duration
}

// OllamaOptions configures the Ollama embedder.
type OllamaOptions struct {
	Endpoint string // defaults to $AIH_GRAPH_OLLAMA_URL, $OLLAMA_HOST, or localhost
	Model    string // defaults to $AIH_GRAPH_OLLAMA_MODEL or nomic-embed-text
	// MaxRetries is the number of retries after the first request. Zero uses
	// the default of two retries.
	MaxRetries int
	// RetryDelay is the initial retry delay. Zero uses the default.
	RetryDelay time.Duration
}

// NewOllamaEmbedder returns an embedder for Ollama's embedding endpoint.
func NewOllamaEmbedder(opts OllamaOptions) (*OllamaEmbedder, error) {
	endpoint := strings.TrimSpace(opts.Endpoint)
	if endpoint == "" {
		endpoint = strings.TrimSpace(os.Getenv("AIH_GRAPH_OLLAMA_URL"))
	}
	if endpoint == "" {
		endpoint = strings.TrimSpace(os.Getenv("OLLAMA_HOST"))
	}
	endpoint = normalizeOllamaEndpoint(endpoint)
	model := strings.TrimSpace(opts.Model)
	if model == "" {
		model = strings.TrimSpace(os.Getenv("AIH_GRAPH_OLLAMA_MODEL"))
	}
	if model == "" {
		model = ollamaDefaultModel
	}
	maxRetries := opts.MaxRetries
	if maxRetries == 0 {
		maxRetries = ollamaDefaultMaxRetries
	}
	if maxRetries < 0 {
		maxRetries = 0
	}
	retryDelay := opts.RetryDelay
	if retryDelay <= 0 {
		retryDelay = ollamaRetryBaseDelay
	}
	return &OllamaEmbedder{
		model:      model,
		endpoint:   endpoint,
		client:     &http.Client{Timeout: 60 * time.Second},
		maxRetries: maxRetries,
		retryDelay: retryDelay,
	}, nil
}

func (p *OllamaEmbedder) Dim() int      { return p.dim }
func (p *OllamaEmbedder) Model() string { return "ollama:" + p.model }

func (p *OllamaEmbedder) Embed(text string) ([]float32, error) {
	vectors, err := p.embedInput(text, 1)
	if err != nil {
		return nil, err
	}
	return vectors[0], nil
}

// EmbedBatch sends one native Ollama /api/embed request for all supplied
// texts. Ollama accepts an input array and returns embeddings in input order.
func (p *OllamaEmbedder) EmbedBatch(texts []string) ([][]float32, error) {
	if len(texts) == 0 {
		return nil, nil
	}
	return p.embedInput(texts, len(texts))
}

func (p *OllamaEmbedder) embedInput(input any, expected int) ([][]float32, error) {
	var lastErr error
	for attempt := 0; attempt <= p.maxRetries; attempt++ {
		vectors, retryable, err := p.requestEmbeddings(input)
		if err == nil {
			if len(vectors) != expected {
				return nil, fmt.Errorf("ollama: returned %d embeddings for %d inputs", len(vectors), expected)
			}
			for i, vector := range vectors {
				if len(vector) == 0 {
					return nil, fmt.Errorf("ollama: empty embedding at index %d", i)
				}
				if p.dim != 0 && len(vector) != p.dim {
					return nil, fmt.Errorf("ollama: embedding dimension changed from %d to %d", p.dim, len(vector))
				}
				if len(vector) != len(vectors[0]) {
					return nil, fmt.Errorf("ollama: inconsistent embedding dimensions in response")
				}
			}
			p.dim = len(vectors[0])
			return vectors, nil
		}
		lastErr = err
		if !retryable || attempt == p.maxRetries {
			break
		}
		time.Sleep(p.retryDelay * time.Duration(1<<attempt))
	}
	return nil, lastErr
}

func (p *OllamaEmbedder) requestEmbeddings(input any) ([][]float32, bool, error) {
	body, _ := json.Marshal(map[string]any{
		"model": p.model,
		"input": input,
	})
	req, err := http.NewRequest("POST", p.endpoint, bytes.NewReader(body))
	if err != nil {
		return nil, false, err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := p.client.Do(req)
	if err != nil {
		return nil, true, fmt.Errorf("ollama: HTTP request: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(resp.Body)
		retryable := resp.StatusCode == http.StatusTooManyRequests || resp.StatusCode >= http.StatusInternalServerError
		return nil, retryable, fmt.Errorf("ollama: HTTP %d: %s", resp.StatusCode, string(b))
	}
	var payload struct {
		Embeddings [][]float32 `json:"embeddings"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		return nil, false, fmt.Errorf("ollama: decode response: %w", err)
	}
	if len(payload.Embeddings) == 0 {
		return nil, false, fmt.Errorf("ollama: empty embeddings in response")
	}
	return payload.Embeddings, false, nil
}

func normalizeOllamaEndpoint(endpoint string) string {
	endpoint = strings.TrimSpace(endpoint)
	if endpoint == "" {
		endpoint = ollamaDefaultEndpoint
	}
	endpoint = strings.TrimRight(endpoint, "/")
	if strings.HasSuffix(endpoint, "/api/embed") {
		return endpoint
	}
	if strings.HasSuffix(endpoint, "/api") {
		return endpoint + "/embed"
	}
	return endpoint + "/api/embed"
}

// ---------------------------------------------------------------------------
// Encoding helpers — float32[] <-> BLOB (little-endian for stable persistence).
// ---------------------------------------------------------------------------

// EncodeVector serializes a float32 vector to LE-encoded bytes for BLOB storage.
func EncodeVector(v []float32) []byte {
	buf := make([]byte, len(v)*4)
	for i, f := range v {
		binary.LittleEndian.PutUint32(buf[i*4:i*4+4], math.Float32bits(f))
	}
	return buf
}

// DecodeVector reads an LE-encoded BLOB back into a float32 vector.
func DecodeVector(b []byte) []float32 {
	v := make([]float32, len(b)/4)
	for i := range v {
		v[i] = math.Float32frombits(binary.LittleEndian.Uint32(b[i*4 : i*4+4]))
	}
	return v
}

// SHA256Hex returns the hex SHA-256 of s. Used for content_sha change detection.
func SHA256Hex(s string) string {
	h := sha256.Sum256([]byte(s))
	const hexDigits = "0123456789abcdef"
	buf := make([]byte, 64)
	for i, b := range h {
		buf[i*2] = hexDigits[b>>4]
		buf[i*2+1] = hexDigits[b&0x0f]
	}
	return string(buf)
}
