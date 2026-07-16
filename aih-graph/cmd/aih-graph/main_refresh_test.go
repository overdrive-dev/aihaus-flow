package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/overdrive-dev/aihaus-flow/aih-graph/internal/embed"
	"github.com/overdrive-dev/aihaus-flow/aih-graph/internal/storage"
	"github.com/overdrive-dev/aihaus-flow/aih-graph/internal/types"
)

type countingEmbedder struct {
	model string
	calls int
}

func (e *countingEmbedder) Embed(string) ([]float32, error) {
	e.calls++
	return []float32{0.1, 0.2}, nil
}

func (e *countingEmbedder) Dim() int      { return 2 }
func (e *countingEmbedder) Model() string { return e.model }

type failingEmbedder struct{ model string }

func (e *failingEmbedder) Embed(string) ([]float32, error) {
	return nil, fmt.Errorf("backend unavailable")
}

func (e *failingEmbedder) Dim() int      { return 2 }
func (e *failingEmbedder) Model() string { return e.model }

type countingBatchEmbedder struct {
	batchSizes []int
}

func (e *countingBatchEmbedder) Embed(string) ([]float32, error) {
	return nil, fmt.Errorf("unexpected single embed")
}

func (e *countingBatchEmbedder) EmbedBatch(texts []string) ([][]float32, error) {
	e.batchSizes = append(e.batchSizes, len(texts))
	vectors := make([][]float32, len(texts))
	for i := range vectors {
		vectors[i] = []float32{float32(i), 1}
	}
	return vectors, nil
}

func (e *countingBatchEmbedder) Dim() int      { return 2 }
func (e *countingBatchEmbedder) Model() string { return "ollama:nomic-embed-text" }

func TestPruneMissingNodesPreservesExistingEmbedding(t *testing.T) {
	db, err := storage.Open(filepath.Join(t.TempDir(), "graph.db"))
	if err != nil {
		t.Fatalf("open db: %v", err)
	}
	defer db.Close()

	keepID, err := db.UpsertNode("File", "keep.go", map[string]any{"path": "keep.go"})
	if err != nil {
		t.Fatalf("upsert keep: %v", err)
	}
	staleID, err := db.UpsertNode("File", "gone.go", map[string]any{"path": "gone.go"})
	if err != nil {
		t.Fatalf("upsert stale: %v", err)
	}
	if err := db.UpdateEmbedding(keepID, embed.EncodeVector([]float32{0.4, 0.5}), "ollama:bge-m3", "same-sha"); err != nil {
		t.Fatalf("embedding: %v", err)
	}
	if err := db.SaveFTS(keepID, "keep"); err != nil {
		t.Fatalf("fts keep: %v", err)
	}
	if err := db.SaveFTS(staleID, "gone"); err != nil {
		t.Fatalf("fts stale: %v", err)
	}
	if err := db.UpsertEdge(keepID, staleID, "touches", nil); err != nil {
		t.Fatalf("edge: %v", err)
	}

	if err := resetDerivedEdges(db); err != nil {
		t.Fatalf("reset edges: %v", err)
	}
	removed, err := pruneMissingNodes(db, map[derivedNodeKey]struct{}{
		{typ: "File", identifier: "keep.go"}: {},
	})
	if err != nil {
		t.Fatalf("prune: %v", err)
	}
	if removed != 1 {
		t.Fatalf("removed = %d, want 1", removed)
	}
	gotID, err := db.LookupNodeID("File", "keep.go")
	if err != nil || gotID != keepID {
		t.Fatalf("preserved node id = %d, err=%v; want %d", gotID, err, keepID)
	}
	sha, model, present, err := db.EmbeddingMetadata(keepID)
	if err != nil || !present || sha != "same-sha" || model != "ollama:bge-m3" {
		t.Fatalf("embedding metadata = (%q, %q, %v, %v)", sha, model, present, err)
	}
	if _, err := db.LookupNodeID("File", "gone.go"); err == nil {
		t.Fatal("missing node was not removed")
	}
	if count, err := db.CountFTS(); err != nil || count != 1 {
		t.Fatalf("FTS count = %d, err=%v; want 1", count, err)
	}
}

func TestEmbedPipelineReusesOnlyMatchingSHAAndModel(t *testing.T) {
	db, err := storage.Open(filepath.Join(t.TempDir(), "graph.db"))
	if err != nil {
		t.Fatalf("open db: %v", err)
	}
	defer db.Close()
	decision := types.Decision{Identifier: "ADR-1", Title: "One", Body: "body"}
	if _, err := db.UpsertNode("Decision", decision.Identifier, map[string]any{"body": decision.Body}); err != nil {
		t.Fatalf("upsert: %v", err)
	}

	first := &countingEmbedder{model: "ollama:nomic-embed-text"}
	runTestEmbedPipeline(t, db, first, []types.Decision{decision})
	runTestEmbedPipeline(t, db, first, []types.Decision{decision})
	if first.calls != 1 {
		t.Fatalf("same SHA/model calls = %d, want 1", first.calls)
	}

	changedModel := &countingEmbedder{model: "ollama:bge-m3"}
	runTestEmbedPipeline(t, db, changedModel, []types.Decision{decision})
	if changedModel.calls != 1 {
		t.Fatalf("changed model calls = %d, want 1", changedModel.calls)
	}
}

func TestEmbedPipelineClearsStaleEmbeddingWhenBackendFails(t *testing.T) {
	db, err := storage.Open(filepath.Join(t.TempDir(), "graph.db"))
	if err != nil {
		t.Fatalf("open db: %v", err)
	}
	defer db.Close()
	decision := types.Decision{Identifier: "ADR-1", Title: "One", Body: "old body"}
	if _, err := db.UpsertNode("Decision", decision.Identifier, map[string]any{"body": decision.Body}); err != nil {
		t.Fatalf("upsert: %v", err)
	}
	runTestEmbedPipeline(t, db, &countingEmbedder{model: "ollama:nomic-embed-text"}, []types.Decision{decision})

	decision.Body = "changed body"
	runTestEmbedPipeline(t, db, &failingEmbedder{model: "ollama:nomic-embed-text"}, []types.Decision{decision})
	nodeID, err := db.LookupNodeID("Decision", decision.Identifier)
	if err != nil {
		t.Fatal(err)
	}
	_, _, present, err := db.EmbeddingMetadata(nodeID)
	if err != nil {
		t.Fatal(err)
	}
	if present {
		t.Fatal("stale embedding remained present after content changed and backend failed")
	}
}

func TestEmbedPipelineUsesBatchesOfAtMost64(t *testing.T) {
	db, err := storage.Open(filepath.Join(t.TempDir(), "graph.db"))
	if err != nil {
		t.Fatalf("open db: %v", err)
	}
	defer db.Close()

	decisions := make([]types.Decision, 130)
	for i := range decisions {
		decisions[i] = types.Decision{
			Identifier: fmt.Sprintf("ADR-%03d", i),
			Title:      fmt.Sprintf("Decision %d", i),
			Body:       "body",
		}
		if _, err := db.UpsertNode("Decision", decisions[i].Identifier, map[string]any{"body": "body"}); err != nil {
			t.Fatalf("upsert %d: %v", i, err)
		}
	}

	embedder := &countingBatchEmbedder{}
	runTestEmbedPipeline(t, db, embedder, decisions)
	want := []int{64, 64, 2}
	if fmt.Sprint(embedder.batchSizes) != fmt.Sprint(want) {
		t.Fatalf("batch sizes = %v, want %v", embedder.batchSizes, want)
	}
}

func TestRunBuildRefreshPreservesUnchangedNodesAndPrunesMissing(t *testing.T) {
	requests := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests++
		var request struct {
			Input json.RawMessage `json:"input"`
		}
		if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
			t.Fatalf("decode Ollama request: %v", err)
		}
		count := 1
		if len(request.Input) > 0 && request.Input[0] == '[' {
			var inputs []string
			if err := json.Unmarshal(request.Input, &inputs); err != nil {
				t.Fatalf("decode batched input: %v", err)
			}
			count = len(inputs)
		}
		vectors := make([][]float32, count)
		for i := range vectors {
			vectors[i] = []float32{0.1, 0.2}
		}
		w.Header().Set("Content-Type", "application/json")
		if err := json.NewEncoder(w).Encode(map[string]any{"embeddings": vectors}); err != nil {
			t.Fatalf("encode Ollama response: %v", err)
		}
	}))
	defer server.Close()
	t.Setenv("AIH_GRAPH_OLLAMA_URL", server.URL)
	t.Setenv("AIH_GRAPH_OLLAMA_MODEL", "refresh-test")

	repo := t.TempDir()
	dbPath := filepath.Join(t.TempDir(), "graph.db")
	keepPath := filepath.Join(repo, "keep.md")
	gonePath := filepath.Join(repo, "gone.md")
	if err := os.WriteFile(keepPath, []byte("# Keep\n\nunchanged\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(gonePath, []byte("# Gone\n\nremove me\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	args := []string{"--db", dbPath, "--accept-all-repos", repo}
	if code := runBuild(args); code != 0 {
		t.Fatalf("first build returned %d", code)
	}

	db, err := storage.Open(dbPath)
	if err != nil {
		t.Fatal(err)
	}
	keepID, err := db.LookupNodeID("File", "keep.md")
	if err != nil {
		t.Fatal(err)
	}
	if err := db.Close(); err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(gonePath); err != nil {
		t.Fatal(err)
	}
	if code := runBuild(args); code != 0 {
		t.Fatalf("second build returned %d", code)
	}

	db, err = storage.Open(dbPath)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	refreshedID, err := db.LookupNodeID("File", "keep.md")
	if err != nil || refreshedID != keepID {
		t.Fatalf("refreshed keep ID = %d, err=%v; want %d", refreshedID, err, keepID)
	}
	_, model, present, err := db.EmbeddingMetadata(refreshedID)
	if err != nil || !present || model != "ollama:refresh-test" {
		t.Fatalf("preserved embedding = model %q, present %v, err %v", model, present, err)
	}
	if _, err := db.LookupNodeID("File", "gone.md"); err == nil {
		t.Fatal("removed file node still exists after refresh")
	}
	if requests != 1 {
		t.Fatalf("Ollama requests = %d, want one initial batch and none for unchanged refresh", requests)
	}
}

func runTestEmbedPipeline(t *testing.T, db *storage.DB, embedder embed.Embedder, decisions []types.Decision) {
	t.Helper()
	if err := runEmbedPipeline(db, embedder, decisions, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil); err != nil {
		t.Fatalf("runEmbedPipeline: %v", err)
	}
}
