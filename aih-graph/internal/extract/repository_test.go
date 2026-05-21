package extract

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestParseRepositoryTextIndexesTextFilesAndChunks(t *testing.T) {
	root := t.TempDir()
	writeFile(t, root, "cmd/app/main.go", "package main\n\nfunc main() {}\n")
	writeFile(t, root, "README.md", strings.Repeat("repo memory\n", 700))
	writeFile(t, root, ".git/config", "should be skipped\n")
	writeFile(t, root, "image.png", "\x00\x01binary")

	files, chunks, err := ParseRepositoryText(root)
	if err != nil {
		t.Fatalf("ParseRepositoryText returned error: %v", err)
	}

	if len(files) != 2 {
		t.Fatalf("expected 2 indexed text files, got %d: %#v", len(files), files)
	}
	if len(chunks) < 3 {
		t.Fatalf("expected README to be split into multiple chunks, got %d chunks", len(chunks))
	}

	var sawGo, sawReadme bool
	for _, f := range files {
		switch f.Path {
		case "cmd/app/main.go":
			sawGo = true
			if f.Language != "go" || f.LineCount != 3 || f.ChunkCount != 1 {
				t.Fatalf("unexpected Go file metadata: %#v", f)
			}
		case "README.md":
			sawReadme = true
			if f.Language != "markdown" || f.ChunkCount < 2 {
				t.Fatalf("unexpected README metadata: %#v", f)
			}
		default:
			t.Fatalf("unexpected indexed file: %#v", f)
		}
	}
	if !sawGo || !sawReadme {
		t.Fatalf("missing expected files: sawGo=%v sawReadme=%v", sawGo, sawReadme)
	}

	for _, c := range chunks {
		if c.Identifier == "" || c.FilePath == "" || c.Text == "" || c.SHA256 == "" {
			t.Fatalf("chunk missing required fields: %#v", c)
		}
		if strings.Contains(c.FilePath, ".git") {
			t.Fatalf("chunk from skipped directory was indexed: %#v", c)
		}
	}
}

func writeFile(t *testing.T, root, rel, content string) {
	t.Helper()
	path := filepath.Join(root, filepath.FromSlash(rel))
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatalf("mkdir %s: %v", filepath.Dir(path), err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("write %s: %v", path, err)
	}
}
