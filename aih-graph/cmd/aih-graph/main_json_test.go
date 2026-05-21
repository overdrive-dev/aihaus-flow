package main

import (
	"strings"
	"testing"

	"github.com/overdrive-dev/aihaus-flow/aih-graph/internal/query"
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

func TestTruncateJSONStringDoesNotSplitUTF8(t *testing.T) {
	got := truncateJSONString("abçd", 3)
	if got != "ab" {
		t.Fatalf("expected UTF-8 safe byte truncation, got %q", got)
	}
}
