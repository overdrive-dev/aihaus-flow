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

// ---------------------------------------------------------------------------
// OllamaEmbedder calls a local Ollama embedding model.
// ---------------------------------------------------------------------------

const (
	ollamaDefaultEndpoint = "http://localhost:11434/api/embed"
	ollamaDefaultModel    = "nomic-embed-text"
)

// OllamaEmbedder calls Ollama's /api/embed endpoint. It is the preferred local
// semantic embedder for M048 because vectors stay on the developer machine.
type OllamaEmbedder struct {
	model    string
	endpoint string
	dim      int
	client   *http.Client
}

// OllamaOptions configures the Ollama embedder.
type OllamaOptions struct {
	Endpoint string // defaults to $AIH_GRAPH_OLLAMA_URL, $OLLAMA_HOST, or localhost
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
	return &OllamaEmbedder{
		model:    ollamaDefaultModel,
		endpoint: endpoint,
		client:   &http.Client{Timeout: 60 * time.Second},
	}, nil
}

func (p *OllamaEmbedder) Dim() int      { return p.dim }
func (p *OllamaEmbedder) Model() string { return "ollama:" + p.model }

func (p *OllamaEmbedder) Embed(text string) ([]float32, error) {
	body, _ := json.Marshal(map[string]any{
		"model": p.model,
		"input": text,
	})
	req, err := http.NewRequest("POST", p.endpoint, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := p.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("ollama: HTTP request: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("ollama: HTTP %d: %s", resp.StatusCode, string(b))
	}
	var payload struct {
		Embeddings [][]float32 `json:"embeddings"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		return nil, fmt.Errorf("ollama: decode response: %w", err)
	}
	if len(payload.Embeddings) == 0 || len(payload.Embeddings[0]) == 0 {
		return nil, fmt.Errorf("ollama: empty embeddings in response")
	}
	p.dim = len(payload.Embeddings[0])
	return payload.Embeddings[0], nil
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
