package extract

import "testing"

func TestParseMarkdownMemoryExtractsSections(t *testing.T) {
	root := t.TempDir()
	writeFile(t, root, "pkg/.aihaus/memory/global/gotchas.md", `# Global Gotchas

## First trap

Do not do the risky thing.

## Second trap

Prefer the safer thing.
`)

	memories, err := ParseMarkdownMemory(root)
	if err != nil {
		t.Fatalf("ParseMarkdownMemory returned error: %v", err)
	}
	if len(memories) != 2 {
		t.Fatalf("expected 2 memory sections, got %d: %#v", len(memories), memories)
	}
	if memories[0].Category != "global" {
		t.Fatalf("category = %q, want global", memories[0].Category)
	}
	if memories[0].FilePath != "pkg/.aihaus/memory/global/gotchas.md" {
		t.Fatalf("file path = %q", memories[0].FilePath)
	}
	if memories[0].Heading != "First trap" {
		t.Fatalf("heading = %q", memories[0].Heading)
	}
}
