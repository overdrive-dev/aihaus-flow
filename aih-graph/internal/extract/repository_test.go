package extract

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestParseRepositoryTextIndexesTextFilesAndChunks(t *testing.T) {
	root := t.TempDir()
	runRepositoryGit(t, root, "init")
	writeFile(t, root, "cmd/app/main.go", "package main\n\nfunc main() {}\n")
	writeFile(t, root, "README.md", strings.Repeat("repo memory\n", 700))
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

func TestParseRepositoryTextHonorsGitignoreRulesAndNegations(t *testing.T) {
	root := t.TempDir()
	runRepositoryGit(t, root, "init")
	writeFile(t, root, "tracked/generated.go", "package tracked\n")
	runRepositoryGit(t, root, "add", "tracked/generated.go")
	writeFile(t, root, ".gitignore", ".venv/\nbuild/\ntracked/\n")
	writeFile(t, root, "nested/.gitignore", "*.md\n!important.md\n")
	writeFile(t, root, "cmd/app/main.go", "package main\n")
	writeFile(t, root, ".venv/dependency.go", "package dependency\n")
	writeFile(t, root, "build/bundle.js", "generated();\n")
	writeFile(t, root, "nested/ignored.md", "ignored\n")
	writeFile(t, root, "nested/important.md", "kept by negation\n")

	files, _, err := ParseRepositoryText(root)
	if err != nil {
		t.Fatalf("ParseRepositoryText returned error: %v", err)
	}
	got := map[string]bool{}
	for _, file := range files {
		got[file.Path] = true
	}
	for _, want := range []string{"cmd/app/main.go", "nested/important.md", "tracked/generated.go"} {
		if !got[want] {
			t.Errorf("expected %s to be indexed; got %#v", want, got)
		}
	}
	for _, excluded := range []string{".venv/dependency.go", "build/bundle.js", "nested/ignored.md"} {
		if got[excluded] {
			t.Errorf("ignored path %s was indexed", excluded)
		}
	}
}

func TestParseRepositoryTextAlwaysAppliesSafetyExclusions(t *testing.T) {
	root := t.TempDir()
	runRepositoryGit(t, root, "init")
	writeFile(t, root, ".aihaus/state/private.json", "{\"secret\":true}\n")
	writeFile(t, root, "safe.json", "{\"safe\":true}\n")
	runRepositoryGit(t, root, "add", "-f", ".aihaus/state/private.json", "safe.json")

	files, _, err := ParseRepositoryText(root)
	if err != nil {
		t.Fatalf("ParseRepositoryText returned error: %v", err)
	}
	if len(files) != 1 || files[0].Path != "safe.json" {
		t.Fatalf("safety exclusion failed: %#v", files)
	}

	for _, path := range []string{
		".git/config",
		".aihaus/state/aih-graph.db",
		"cache.sqlite",
		"cache.sqlite3-wal",
		".aih-graph-consent",
		".aihaus-download/release.json",
		".aihaus-lab/run/output.json",
	} {
		if !neverIndexRepositoryPath(path) {
			t.Errorf("neverIndexRepositoryPath(%q) = false", path)
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

func runRepositoryGit(t *testing.T, dir string, args ...string) {
	t.Helper()
	cmd := exec.Command("git", append([]string{"-C", dir}, args...)...)
	if output, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, output)
	}
}
