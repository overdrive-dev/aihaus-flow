package extract

import (
	"testing"

	"github.com/overdrive-dev/aihaus-flow/aih-graph/internal/types"
)

func TestParseRepositoryTestsLinksGoTestsToTargetSymbol(t *testing.T) {
	root := t.TempDir()
	writeFile(t, root, "internal/demo/repository.go", `package demo

func ParseRepositoryText() {}
`)
	writeFile(t, root, "internal/demo/repository_test.go", `package demo

func TestParseRepositoryTextIndexesFiles(t *testing.T) {}
`)

	files := []types.RepoFile{
		{Path: "internal/demo/repository.go", Language: "go"},
		{Path: "internal/demo/repository_test.go", Language: "go"},
	}
	symbols := []types.RepoSymbol{{
		Identifier: "internal/demo/repository.go:ParseRepositoryText",
		Name:       "ParseRepositoryText",
		FilePath:   "internal/demo/repository.go",
	}}
	tests, err := ParseRepositoryTests(root, files, symbols)
	if err != nil {
		t.Fatalf("ParseRepositoryTests returned error: %v", err)
	}
	if len(tests) != 1 {
		t.Fatalf("expected 1 test, got %d: %#v", len(tests), tests)
	}
	if tests[0].TargetFilePath != "internal/demo/repository.go" {
		t.Fatalf("target file = %q", tests[0].TargetFilePath)
	}
	if tests[0].TargetSymbolIdentifier != "internal/demo/repository.go:ParseRepositoryText" {
		t.Fatalf("target symbol = %q", tests[0].TargetSymbolIdentifier)
	}
}

func TestParseRepositoryTestsIndexesShellTestFile(t *testing.T) {
	root := t.TempDir()
	writeFile(t, root, "tools/test-install-flow.sh", "#!/usr/bin/env bash\n")
	files := []types.RepoFile{{Path: "tools/test-install-flow.sh", Language: "bash", LineCount: 1}}

	tests, err := ParseRepositoryTests(root, files, nil)
	if err != nil {
		t.Fatalf("ParseRepositoryTests returned error: %v", err)
	}
	if len(tests) != 1 {
		t.Fatalf("expected 1 test file, got %d: %#v", len(tests), tests)
	}
	if tests[0].Kind != "test_file" {
		t.Fatalf("kind = %q", tests[0].Kind)
	}
}
