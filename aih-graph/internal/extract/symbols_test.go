package extract

import (
	"testing"

	"github.com/overdrive-dev/aihaus-flow/aih-graph/internal/types"
)

func TestParseRepositorySymbolsExtractsGoFunctionsAndCalls(t *testing.T) {
	root := t.TempDir()
	writeFile(t, root, "internal/demo/demo.go", `package demo

func Alpha() {
	Beta()
}

func Beta() {}
`)

	files := []types.RepoFile{{
		Path:     "internal/demo/demo.go",
		Language: "go",
	}}
	symbols, calls, err := ParseRepositorySymbols(root, files)
	if err != nil {
		t.Fatalf("ParseRepositorySymbols returned error: %v", err)
	}
	if len(symbols) != 2 {
		t.Fatalf("expected 2 symbols, got %d: %#v", len(symbols), symbols)
	}
	if len(calls) != 1 {
		t.Fatalf("expected 1 call, got %d: %#v", len(calls), calls)
	}
	if calls[0].CallerIdentifier != "internal/demo/demo.go:Alpha" {
		t.Fatalf("unexpected caller: %#v", calls[0])
	}
	if calls[0].CalleeIdentifier != "internal/demo/demo.go:Beta" {
		t.Fatalf("expected call to resolve to Beta symbol, got %#v", calls[0])
	}
}

func TestParseRepositorySymbolsExtractsShellAndPowerShellFunctions(t *testing.T) {
	root := t.TempDir()
	writeFile(t, root, "scripts/run.sh", "main() {\n  echo hi\n}\n")
	writeFile(t, root, "scripts/run.ps1", "function Invoke-Thing {\n}\n")

	files := []types.RepoFile{
		{Path: "scripts/run.sh", Language: "bash"},
		{Path: "scripts/run.ps1", Language: "powershell"},
	}
	symbols, calls, err := ParseRepositorySymbols(root, files)
	if err != nil {
		t.Fatalf("ParseRepositorySymbols returned error: %v", err)
	}
	if len(calls) != 0 {
		t.Fatalf("shell/powershell call extraction should not run yet, got %#v", calls)
	}
	seen := map[string]bool{}
	for _, s := range symbols {
		seen[s.Identifier] = true
	}
	for _, want := range []string{"scripts/run.sh:main", "scripts/run.ps1:Invoke-Thing"} {
		if !seen[want] {
			t.Fatalf("missing symbol %s in %#v", want, symbols)
		}
	}
}
