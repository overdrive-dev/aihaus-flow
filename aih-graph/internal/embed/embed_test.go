package embed

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestOllamaProviderEmbedsWithLocalEndpoint(t *testing.T) {
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
		if req.Model != "embeddinggemma" {
			t.Fatalf("model = %q, want embeddinggemma", req.Model)
		}
		if req.Input != "hello repo" {
			t.Fatalf("input = %q, want hello repo", req.Input)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"model":"embeddinggemma","embeddings":[[0.1,0.2,0.3]]}`))
	}))
	defer server.Close()

	provider, err := NewOllamaProvider(OllamaOptions{
		Model:    "embeddinggemma",
		Endpoint: server.URL,
	})
	if err != nil {
		t.Fatalf("new provider: %v", err)
	}
	vec, err := provider.Embed("hello repo")
	if err != nil {
		t.Fatalf("embed: %v", err)
	}
	if provider.Model() != "ollama:embeddinggemma" {
		t.Fatalf("provider model = %q", provider.Model())
	}
	if len(vec) != 3 {
		t.Fatalf("vector len = %d, want 3", len(vec))
	}
	if provider.Dim() != 3 {
		t.Fatalf("provider dim = %d, want 3", provider.Dim())
	}
	if vec[0] != 0.1 || vec[1] != 0.2 || vec[2] != 0.3 {
		t.Fatalf("vector = %#v", vec)
	}
}

func TestOllamaProviderDefaultModel(t *testing.T) {
	provider, err := NewOllamaProvider(OllamaOptions{
		Endpoint: "http://localhost:11434",
	})
	if err != nil {
		t.Fatalf("new provider: %v", err)
	}
	if provider.Model() != "ollama:nomic-embed-text" {
		t.Fatalf("provider model = %q", provider.Model())
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
