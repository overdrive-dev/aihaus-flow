// Package embed implements aih-graph's pluggable embedding pipeline per
// ADR-260515-E-amend-02. v0.1 ships two providers:
//
//	voyage  — Voyage AI HTTP API (default; requires VOYAGE_API_KEY env var)
//	fake    — deterministic SHA-derived pseudo-embeddings (no network; test
//	          + offline scaffold mode; vectors are unit-normalized but
//	          semantically meaningless)
//
// A local-ONNX provider (e.g. all-MiniLM-L6-v2) is referenced in the ADR but
// deferred to a follow-on M035 commit (needs onnxruntime_go + model bundle).
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

// Provider produces a vector embedding for arbitrary input text. Implementations
// must return vectors of the same Dim() across all calls in a session.
type Provider interface {
	// Embed returns a Dim()-length float32 vector for text. Returns
	// ErrSkip if the provider intentionally declines (e.g. NoOp provider
	// when no API key is configured).
	Embed(text string) ([]float32, error)
	// Dim is the fixed dimensionality of vectors produced by this provider.
	Dim() int
	// Model is a human-readable identifier persisted alongside each
	// embedding (e.g. "voyage-3", "fake-sha256", "local-minilm-l6-v2").
	Model() string
}

// ErrSkip signals "no embedding produced; persist without one".
var ErrSkip = fmt.Errorf("embed: provider skipped")

// ---------------------------------------------------------------------------
// FakeProvider — deterministic SHA-derived embeddings; no network.
// ---------------------------------------------------------------------------

// FakeProvider hashes input text into a unit-normalized float32 vector of
// fixed Dim. Same text always yields same vector (idempotent). Vectors are
// NOT semantically meaningful — they exist so the full pipeline (storage,
// KNN, query) can be exercised offline without API keys.
type FakeProvider struct {
	dim int
}

// NewFakeProvider returns a FakeProvider with the given dimensionality.
// dim=1024 matches the canonical v0.1 default per ADR-260515-B-amend-02.
func NewFakeProvider(dim int) *FakeProvider {
	if dim <= 0 {
		dim = 1024
	}
	return &FakeProvider{dim: dim}
}

func (p *FakeProvider) Dim() int      { return p.dim }
func (p *FakeProvider) Model() string { return "fake-sha256" }

func (p *FakeProvider) Embed(text string) ([]float32, error) {
	// Expand a 32-byte SHA-256 digest into dim float32 values by re-hashing
	// with a counter suffix. Unit-normalize the result so cosine similarity
	// behaves sensibly.
	vec := make([]float32, p.dim)
	var sumSq float64
	for i := 0; i < p.dim; i += 8 {
		h := sha256.New()
		h.Write([]byte(text))
		var buf [4]byte
		binary.LittleEndian.PutUint32(buf[:], uint32(i))
		h.Write(buf[:])
		digest := h.Sum(nil)
		// Each SHA-256 digest yields 32 bytes = 8 float32s (4 bytes each).
		for j := 0; j < 8 && i+j < p.dim; j++ {
			// Convert 4 bytes to float32 in [-1, 1] range.
			u := binary.LittleEndian.Uint32(digest[j*4 : j*4+4])
			v := float32(u)/float32(math.MaxUint32)*2 - 1
			vec[i+j] = v
			sumSq += float64(v) * float64(v)
		}
	}
	// Unit-normalize.
	norm := float32(math.Sqrt(sumSq))
	if norm > 0 {
		for i := range vec {
			vec[i] /= norm
		}
	}
	return vec, nil
}

// ---------------------------------------------------------------------------
// VoyageProvider — Voyage AI HTTP API client.
// https://docs.voyageai.com/reference/embeddings-api
// ---------------------------------------------------------------------------

const (
	voyageDefaultEndpoint = "https://api.voyageai.com/v1/embeddings"
	voyageDefaultModel    = "voyage-3"
	voyageDefaultDim      = 1024
)

// VoyageProvider calls Voyage AI's embedding API. Requires VOYAGE_API_KEY in
// the environment (or supplied via VoyageOptions).
type VoyageProvider struct {
	apiKey   string
	model    string
	dim      int
	endpoint string
	client   *http.Client
}

// VoyageOptions configures a Voyage provider.
type VoyageOptions struct {
	APIKey   string // defaults to $VOYAGE_API_KEY
	Model    string // defaults to "voyage-3"
	Dim      int    // defaults to 1024
	Endpoint string // defaults to https://api.voyageai.com/v1/embeddings
}

// NewVoyageProvider returns a Voyage provider. If opts.APIKey is empty AND
// $VOYAGE_API_KEY is unset, returns nil + an error so callers can fall back
// to fake / skip provider.
func NewVoyageProvider(opts VoyageOptions) (*VoyageProvider, error) {
	key := opts.APIKey
	if key == "" {
		key = strings.TrimSpace(os.Getenv("VOYAGE_API_KEY"))
	}
	if key == "" {
		return nil, fmt.Errorf("voyage: no API key (set VOYAGE_API_KEY env)")
	}
	model := opts.Model
	if model == "" {
		model = voyageDefaultModel
	}
	dim := opts.Dim
	if dim <= 0 {
		dim = voyageDefaultDim
	}
	endpoint := opts.Endpoint
	if endpoint == "" {
		endpoint = voyageDefaultEndpoint
	}
	return &VoyageProvider{
		apiKey:   key,
		model:    model,
		dim:      dim,
		endpoint: endpoint,
		client:   &http.Client{Timeout: 30 * time.Second},
	}, nil
}

func (p *VoyageProvider) Dim() int      { return p.dim }
func (p *VoyageProvider) Model() string { return p.model }

func (p *VoyageProvider) Embed(text string) ([]float32, error) {
	body, _ := json.Marshal(map[string]any{
		"model":      p.model,
		"input":      []string{text},
		"input_type": "document",
	})
	req, err := http.NewRequest("POST", p.endpoint, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+p.apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := p.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("voyage: HTTP request: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("voyage: HTTP %d: %s", resp.StatusCode, string(b))
	}
	var payload struct {
		Data []struct {
			Embedding []float32 `json:"embedding"`
		} `json:"data"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		return nil, fmt.Errorf("voyage: decode response: %w", err)
	}
	if len(payload.Data) == 0 || len(payload.Data[0].Embedding) == 0 {
		return nil, fmt.Errorf("voyage: empty embeddings in response")
	}
	return payload.Data[0].Embedding, nil
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
