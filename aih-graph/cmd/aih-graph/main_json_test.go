package main

import (
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/overdrive-dev/aihaus-flow/aih-graph/internal/embed"
	"github.com/overdrive-dev/aihaus-flow/aih-graph/internal/query"
	"github.com/overdrive-dev/aihaus-flow/aih-graph/internal/storage"
)

func TestBFSForJSONLimitsNeighborhood(t *testing.T) {
	results := []query.BFSResult{
		{
			Node: query.Node{Type: "File", Identifier: "a.go"},
			Path: []string{"a.go"},
		},
		{
			Distance: 1,
			Node:     query.Node{Type: "Symbol", Identifier: "a.go:one"},
			Path:     []string{"a.go", "a.go:one"},
		},
		{
			Distance: 1,
			Node:     query.Node{Type: "Symbol", Identifier: "a.go:two"},
			Path:     []string{"a.go", "a.go:two"},
		},
	}

	got, truncated := bfsForJSON(results, 2)
	if !truncated {
		t.Fatal("expected truncated neighborhood")
	}
	if len(got) != 2 {
		t.Fatalf("expected 2 results, got %d", len(got))
	}
	if got[1].Node.Identifier != "a.go:one" {
		t.Fatalf("expected traversal order to be preserved, got %q", got[1].Node.Identifier)
	}
}

func TestBFSForJSONLimitZeroReturnsFullNeighborhood(t *testing.T) {
	results := []query.BFSResult{
		{Node: query.Node{Type: "File", Identifier: "a.go"}},
		{Node: query.Node{Type: "Symbol", Identifier: "a.go:one"}},
	}

	got, truncated := bfsForJSON(results, 0)
	if truncated {
		t.Fatal("did not expect truncation with limit 0")
	}
	if len(got) != len(results) {
		t.Fatalf("expected full result set, got %d", len(got))
	}
}

func TestPropertiesForJSONTruncatesLongStrings(t *testing.T) {
	props := map[string]any{
		"text": strings.Repeat("x", jsonPropertyStringLimit+1),
		"path": "a.go",
	}

	got := propertiesForJSON(props)
	if got["path"] != "a.go" {
		t.Fatalf("expected short property to be preserved, got %#v", got["path"])
	}
	if got["text_truncated"] != true {
		t.Fatal("expected text_truncated marker")
	}
	if got["text_original_bytes"] != jsonPropertyStringLimit+1 {
		t.Fatalf("expected original byte count marker, got %#v", got["text_original_bytes"])
	}
	if len(got["text"].(string)) != jsonPropertyStringLimit {
		t.Fatalf("expected text to be truncated to %d bytes, got %d", jsonPropertyStringLimit, len(got["text"].(string)))
	}
	if len(props["text"].(string)) != jsonPropertyStringLimit+1 {
		t.Fatal("expected original properties map to remain untouched")
	}
}

func TestEmbedInputTextTruncatesLongStrings(t *testing.T) {
	got := embedInputText(strings.Repeat("x", embedInputStringLimit+1))
	if len(got) != embedInputStringLimit {
		t.Fatalf("expected embed input to be capped at %d bytes, got %d", embedInputStringLimit, len(got))
	}
}

func TestTruncateJSONStringDoesNotSplitUTF8(t *testing.T) {
	got := truncateJSONString("ab\u00e7d", 3)
	if got != "ab" {
		t.Fatalf("expected UTF-8 safe byte truncation, got %q", got)
	}
}

func TestRunContextJSONIncludesFreshnessAndBoundedNeighborhood(t *testing.T) {
	dbPath, repoPath := seedJSONCommandDB(t)
	markerDir := filepath.Join(repoPath, ".claude", "audit")
	if err := os.MkdirAll(markerDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(markerDir, "aih-graph.stale"), []byte("stale_since=now\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	code, stdout := captureStdout(t, func() int {
		return runContext([]string{
			"--repo", repoPath,
			"--db", dbPath,
			"--type", "Symbol",
			"--depth", "1",
			"--limit", "2",
			"--json",
			"a.go:Root",
		})
	})
	if code != 0 {
		t.Fatalf("runContext returned %d", code)
	}
	var payload contextJSON
	decodeJSON(t, stdout, &payload)
	if payload.Freshness.State != "stale" {
		t.Fatalf("expected stale freshness, got %q", payload.Freshness.State)
	}
	if payload.NeighborhoodReturned != 2 || !payload.NeighborhoodTruncated {
		t.Fatalf("expected bounded truncated neighborhood, got returned=%d truncated=%v", payload.NeighborhoodReturned, payload.NeighborhoodTruncated)
	}
}

func TestRunQueryJSONBFS(t *testing.T) {
	dbPath, repoPath := seedJSONCommandDB(t)
	code, stdout := captureStdout(t, func() int {
		return runQuery([]string{
			"--repo", repoPath,
			"--db", dbPath,
			"--bfs",
			"--type", "Symbol",
			"--depth", "1",
			"--limit", "2",
			"--json",
			"a.go:Root",
		})
	})
	if code != 0 {
		t.Fatalf("runQuery returned %d", code)
	}
	var payload queryJSON
	decodeJSON(t, stdout, &payload)
	if payload.Mode != "bfs" {
		t.Fatalf("expected bfs mode, got %q", payload.Mode)
	}
	if payload.ResultsReturned != 2 || !payload.ResultsTruncated {
		t.Fatalf("expected bounded truncated results, got returned=%d truncated=%v", payload.ResultsReturned, payload.ResultsTruncated)
	}
}

func TestRunQueryJSONSemanticBM25(t *testing.T) {
	dbPath, repoPath := seedJSONCommandDB(t)
	code, stdout := captureStdout(t, func() int {
		return runQuery([]string{
			"--repo", repoPath,
			"--db", dbPath,
			"--semantic",
			"--json",
			"Ollama",
		})
	})
	if code != 0 {
		t.Fatalf("runQuery returned %d", code)
	}
	var payload queryJSON
	decodeJSON(t, stdout, &payload)
	if payload.Mode != "semantic_bm25" {
		t.Fatalf("expected semantic_bm25 mode, got %q", payload.Mode)
	}
	if payload.ResultCount != 1 || payload.Matches[0].Node.Identifier != "chunk:ollama" {
		t.Fatalf("unexpected semantic payload: %#v", payload)
	}
}

func TestRunQueryJSONDefaultsToHybridBM25(t *testing.T) {
	dbPath, repoPath := seedJSONCommandDB(t)
	code, stdout := captureStdout(t, func() int {
		return runQuery([]string{
			"--repo", repoPath,
			"--db", dbPath,
			"--json",
			"Ollama",
		})
	})
	if code != 0 {
		t.Fatalf("runQuery returned %d", code)
	}
	var payload queryJSON
	decodeJSON(t, stdout, &payload)
	if payload.Mode != "hybrid_bm25" {
		t.Fatalf("expected hybrid_bm25 mode, got %q", payload.Mode)
	}
	if payload.ResultCount != 1 || payload.Matches[0].Node.Identifier != "chunk:ollama" {
		t.Fatalf("unexpected default query payload: %#v", payload)
	}
}

func TestRunCallersJSON(t *testing.T) {
	dbPath, _ := seedJSONCommandDB(t)
	code, stdout := captureStdout(t, func() int {
		return runCallers([]string{"--db", dbPath, "--json", "Helper"})
	})
	if code != 0 {
		t.Fatalf("runCallers returned %d", code)
	}
	var payload callersJSON
	decodeJSON(t, stdout, &payload)
	if len(payload.CallSites) != 1 {
		t.Fatalf("expected one call site, got %d", len(payload.CallSites))
	}
	if payload.CallSites[0].FilePath != "a.go" || payload.CallSites[0].Line != 7 {
		t.Fatalf("unexpected call site: %#v", payload.CallSites[0])
	}
}

func TestRunSearchJSONCommands(t *testing.T) {
	dbPath, _ := seedJSONCommandDB(t)

	code, stdout := captureStdout(t, func() int {
		return runGotchas([]string{"--db", dbPath, "--json", "git", "checkout"})
	})
	if code != 0 {
		t.Fatalf("runGotchas returned %d", code)
	}
	var gotchas searchJSON
	decodeJSON(t, stdout, &gotchas)
	if gotchas.Command != "gotchas" || gotchas.ResultCount != 1 {
		t.Fatalf("unexpected gotchas payload: %#v", gotchas)
	}

	code, stdout = captureStdout(t, func() int {
		return runMilestone([]string{"--db", dbPath, "--json", "Ollama"})
	})
	if code != 0 {
		t.Fatalf("runMilestone returned %d", code)
	}
	var milestone searchJSON
	decodeJSON(t, stdout, &milestone)
	if milestone.Command != "milestone" || milestone.ResultCount != 1 {
		t.Fatalf("unexpected milestone payload: %#v", milestone)
	}
}

func TestRunStatusJSONIncludesEmbeddingModels(t *testing.T) {
	dbPath, repoPath := seedJSONCommandDB(t)
	db, err := storage.Open(dbPath)
	if err != nil {
		t.Fatal(err)
	}
	nodeID, err := db.LookupNodeID("Symbol", "a.go:Root")
	if err != nil {
		t.Fatal(err)
	}
	if err := db.UpdateEmbedding(nodeID, embed.EncodeVector([]float32{0.1, 0.2}), "ollama:nomic-embed-text", "sha"); err != nil {
		t.Fatal(err)
	}
	if err := db.Close(); err != nil {
		t.Fatal(err)
	}

	code, stdout := captureStdout(t, func() int {
		return runStatus([]string{"--repo", repoPath, "--db", dbPath, "--json"})
	})
	if code != 0 {
		t.Fatalf("runStatus returned %d", code)
	}
	var payload statusJSON
	decodeJSON(t, stdout, &payload)
	if payload.EmbeddingRows != 1 {
		t.Fatalf("expected one embedding row, got %d", payload.EmbeddingRows)
	}
	if payload.EmbeddingModels["ollama:nomic-embed-text"] != 1 {
		t.Fatalf("unexpected embedding models: %#v", payload.EmbeddingModels)
	}
}

func TestRunRefreshJSONReturnsStatusPayload(t *testing.T) {
	t.Setenv("AIH_GRAPH_OLLAMA_URL", "http://127.0.0.1:9")
	repoPath, dbPath := seedRefreshRepo(t)
	code, stdout := captureStdout(t, func() int {
		return runRefresh([]string{
			"--repo", repoPath,
			"--db", dbPath,
			"--accept-all-repos",
			"--json",
		})
	})
	if code != 0 {
		t.Fatalf("runRefresh returned %d", code)
	}
	if strings.Contains(stdout, "aih-graph build") {
		t.Fatalf("expected refresh --json to suppress human build output, got:\n%s", stdout)
	}
	var payload refreshJSON
	decodeJSON(t, stdout, &payload)
	if payload.Command != "refresh" {
		t.Fatalf("unexpected refresh metadata: %#v", payload)
	}
	if !payload.Status.IndexBuilt {
		t.Fatal("expected refreshed index to be built")
	}
	if payload.Status.NodeCounts["Decision"] != 1 {
		t.Fatalf("expected one Decision node, got counts %#v", payload.Status.NodeCounts)
	}
	if payload.Status.BM25Rows == 0 {
		t.Fatalf("expected BM25 rows after refresh, got %#v", payload.Status)
	}
}

func seedJSONCommandDB(t *testing.T) (string, string) {
	t.Helper()
	dir := t.TempDir()
	repoPath := filepath.Join(dir, "repo")
	if err := os.MkdirAll(repoPath, 0o755); err != nil {
		t.Fatal(err)
	}
	dbPath := filepath.Join(dir, "graph.db")
	db, err := storage.Open(dbPath)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	rootID, err := db.UpsertNode("Symbol", "a.go:Root", map[string]any{
		"name":       "Root",
		"signature":  "func Root(...)",
		"file_path":  "a.go",
		"start_line": 1,
		"end_line":   10,
	})
	if err != nil {
		t.Fatal(err)
	}
	helperID, err := db.UpsertNode("Symbol", "a.go:Helper", map[string]any{
		"name":       "Helper",
		"signature":  "func Helper(...)",
		"file_path":  "a.go",
		"start_line": 11,
		"end_line":   20,
	})
	if err != nil {
		t.Fatal(err)
	}
	callID, err := db.UpsertNode("Call", "a.go:Root#call-0001", map[string]any{
		"caller_identifier": "a.go:Root",
		"callee_identifier": "a.go:Helper",
		"callee_name":       "Helper",
		"file_path":         "a.go",
		"line":              7,
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.UpsertEdge(rootID, helperID, "calls", nil); err != nil {
		t.Fatal(err)
	}
	if err := db.UpsertEdge(rootID, callID, "calls", nil); err != nil {
		t.Fatal(err)
	}
	memID, err := db.UpsertNode("Memory", "memory:git-checkout", map[string]any{
		"heading": "git checkout gotcha",
		"body":    "git checkout can race with concurrent sessions",
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.SaveFTS(memID, "git checkout gotcha concurrent sessions"); err != nil {
		t.Fatal(err)
	}
	chunkID, err := db.UpsertNode("Chunk", "chunk:ollama", map[string]any{
		"file_path": "embed.go",
		"text":      "Ollama local embedding backend",
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.SaveFTS(chunkID, "Ollama local embedding backend"); err != nil {
		t.Fatal(err)
	}
	return dbPath, repoPath
}

func seedRefreshRepo(t *testing.T) (string, string) {
	t.Helper()
	dir := t.TempDir()
	repoPath := filepath.Join(dir, "repo")
	if err := os.MkdirAll(filepath.Join(repoPath, "pkg", ".aihaus"), 0o755); err != nil {
		t.Fatal(err)
	}
	decisions := strings.Join([]string{
		"# Decisions",
		"",
		"## ADR-TEST-A - Refresh JSON",
		"**Status:** Accepted",
		"**Date:** 2026-05-21",
		"",
		"Refresh JSON must return a machine-readable status payload.",
		"",
	}, "\n")
	if err := os.WriteFile(filepath.Join(repoPath, "pkg", ".aihaus", "decisions.md"), []byte(decisions), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(repoPath, "README.md"), []byte("# Test Repo\n\nRepository memory refresh fixture.\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	return repoPath, filepath.Join(dir, "graph.db")
}

func captureStdout(t *testing.T, fn func() int) (int, string) {
	t.Helper()
	old := os.Stdout
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	os.Stdout = w
	defer func() {
		os.Stdout = old
	}()

	code := fn()
	if err := w.Close(); err != nil {
		t.Fatal(err)
	}
	out, err := io.ReadAll(r)
	if err != nil {
		t.Fatal(err)
	}
	return code, string(out)
}

func decodeJSON(t *testing.T, raw string, out any) {
	t.Helper()
	if err := json.Unmarshal([]byte(raw), out); err != nil {
		t.Fatalf("decode JSON: %v\n%s", err, raw)
	}
}
