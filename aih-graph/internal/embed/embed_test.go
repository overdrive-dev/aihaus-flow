package embed

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestOllamaEmbedderEmbedsWithLocalEndpoint(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/embed" {
			t.Fatalf("path = %q, want /api/embed", r.URL.Path)
		}
		var req struct {
			Model string `json:"model"`
			Input string `json:"input"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			t.Fatalf("decode request: %v", err)
		}
		if req.Model != "nomic-embed-text" {
			t.Fatalf("model = %q, want nomic-embed-text", req.Model)
		}
		if req.Input != "hello repo" {
			t.Fatalf("input = %q, want hello repo", req.Input)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"model":"nomic-embed-text","embeddings":[[0.1,0.2,0.3]]}`))
	}))
	defer server.Close()

	embedder, err := NewOllamaEmbedder(OllamaOptions{
		Endpoint: server.URL,
	})
	if err != nil {
		t.Fatalf("new embedder: %v", err)
	}
	vec, err := embedder.Embed("hello repo")
	if err != nil {
		t.Fatalf("embed: %v", err)
	}
	if embedder.Model() != "ollama:nomic-embed-text" {
		t.Fatalf("embedder model = %q", embedder.Model())
	}
	if len(vec) != 3 {
		t.Fatalf("vector len = %d, want 3", len(vec))
	}
	if embedder.Dim() != 3 {
		t.Fatalf("embedder dim = %d, want 3", embedder.Dim())
	}
	if vec[0] != 0.1 || vec[1] != 0.2 || vec[2] != 0.3 {
		t.Fatalf("vector = %#v", vec)
	}
}

func TestOllamaEmbedderDefaultModel(t *testing.T) {
	embedder, err := NewOllamaEmbedder(OllamaOptions{
		Endpoint: "http://localhost:11434",
	})
	if err != nil {
		t.Fatalf("new embedder: %v", err)
	}
	if embedder.Model() != "ollama:nomic-embed-text" {
		t.Fatalf("embedder model = %q", embedder.Model())
	}
}

func TestOllamaEmbedderUsesConfiguredModel(t *testing.T) {
	t.Setenv("AIH_GRAPH_OLLAMA_MODEL", "bge-m3")
	embedder, err := NewOllamaEmbedder(OllamaOptions{
		Endpoint: "http://localhost:11434",
	})
	if err != nil {
		t.Fatalf("new embedder: %v", err)
	}
	if embedder.Model() != "ollama:bge-m3" {
		t.Fatalf("embedder model = %q", embedder.Model())
	}
}

func TestOllamaEmbedderBatchesAndRetries(t *testing.T) {
	attempts := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		attempts++
		var req struct {
			Model string   `json:"model"`
			Input []string `json:"input"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			t.Fatalf("decode request: %v", err)
		}
		if req.Model != "bge-m3" {
			t.Fatalf("model = %q, want bge-m3", req.Model)
		}
		if len(req.Input) != 2 || req.Input[0] != "first" || req.Input[1] != "second" {
			t.Fatalf("input = %#v", req.Input)
		}
		if attempts == 1 {
			http.Error(w, "temporary", http.StatusServiceUnavailable)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"embeddings":[[0.1,0.2],[0.3,0.4]]}`))
	}))
	defer server.Close()

	embedder, err := NewOllamaEmbedder(OllamaOptions{
		Endpoint:   server.URL,
		Model:      "bge-m3",
		MaxRetries: 2,
		RetryDelay: time.Millisecond,
	})
	if err != nil {
		t.Fatalf("new embedder: %v", err)
	}
	vectors, err := embedder.EmbedBatch([]string{"first", "second"})
	if err != nil {
		t.Fatalf("embed batch: %v", err)
	}
	if attempts != 2 {
		t.Fatalf("attempts = %d, want 2", attempts)
	}
	if len(vectors) != 2 || len(vectors[0]) != 2 || vectors[1][0] != 0.3 {
		t.Fatalf("vectors = %#v", vectors)
	}
}

func TestNormalizeOllamaEndpoint(t *testing.T) {
	tests := map[string]string{
		"":                            ollamaDefaultEndpoint,
		"http://localhost:11434":      "http://localhost:11434/api/embed",
		"http://localhost:11434/api":  "http://localhost:11434/api/embed",
		"http://localhost:11434/api/": "http://localhost:11434/api/embed",
	}
	for in, want := range tests {
		if got := normalizeOllamaEndpoint(in); got != want {
			t.Fatalf("normalizeOllamaEndpoint(%q) = %q, want %q", in, got, want)
		}
	}
}
