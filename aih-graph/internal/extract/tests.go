package extract

import (
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"unicode"

	"github.com/overdrive-dev/aihaus-flow/aih-graph/internal/types"
)

// ParseRepositoryTests extracts test nodes and best-effort links to production
// files/symbols. The first implementation favors high-signal repository-local
// conventions: Go *_test.go functions plus common script/spec filenames.
func ParseRepositoryTests(repoRoot string, files []types.RepoFile, symbols []types.RepoSymbol) ([]types.RepoTest, error) {
	fileSet := map[string]bool{}
	for _, f := range files {
		fileSet[f.Path] = true
	}
	symbolsByFile := map[string][]types.RepoSymbol{}
	for _, s := range symbols {
		symbolsByFile[s.FilePath] = append(symbolsByFile[s.FilePath], s)
	}
	var tests []types.RepoTest
	for _, f := range files {
		switch {
		case f.Language == "go" && strings.HasSuffix(f.Path, "_test.go"):
			fileTests, err := parseGoTests(repoRoot, f.Path, fileSet, symbolsByFile)
			if err != nil {
				return nil, err
			}
			tests = append(tests, fileTests...)
		case isGenericTestFile(f.Path):
			tests = append(tests, types.RepoTest{
				Identifier: f.Path,
				Name:       filepath.Base(f.Path),
				Kind:       "test_file",
				Language:   f.Language,
				FilePath:   f.Path,
				StartLine:  1,
				EndLine:    f.LineCount,
			})
		}
	}
	sort.Slice(tests, func(i, j int) bool { return tests[i].Identifier < tests[j].Identifier })
	return tests, nil
}

func parseGoTests(repoRoot, relPath string, fileSet map[string]bool, symbolsByFile map[string][]types.RepoSymbol) ([]types.RepoTest, error) {
	abs := filepath.Join(repoRoot, filepath.FromSlash(relPath))
	src, err := os.ReadFile(abs)
	if err != nil {
		return nil, fmt.Errorf("read go test file %s: %w", relPath, err)
	}
	fset := token.NewFileSet()
	file, err := parser.ParseFile(fset, abs, src, 0)
	if err != nil {
		return nil, fmt.Errorf("parse go test file %s: %w", relPath, err)
	}
	targetFile := strings.TrimSuffix(relPath, "_test.go") + ".go"
	if !fileSet[targetFile] {
		targetFile = ""
	}
	var tests []types.RepoTest
	for _, decl := range file.Decls {
		fn, ok := decl.(*ast.FuncDecl)
		if !ok || !isGoTestFunc(fn.Name.Name) {
			continue
		}
		start := fset.Position(fn.Pos())
		end := fset.Position(fn.End())
		targetSymbol := inferTargetSymbol(fn.Name.Name, symbolsByFile[targetFile])
		tests = append(tests, types.RepoTest{
			Identifier:             relPath + ":" + fn.Name.Name,
			Name:                   fn.Name.Name,
			Kind:                   "go_test",
			Language:               "go",
			FilePath:               relPath,
			StartLine:              start.Line,
			EndLine:                end.Line,
			TargetFilePath:         targetFile,
			TargetSymbolIdentifier: targetSymbol,
		})
	}
	if len(tests) == 0 {
		tests = append(tests, types.RepoTest{
			Identifier:     relPath,
			Name:           filepath.Base(relPath),
			Kind:           "test_file",
			Language:       "go",
			FilePath:       relPath,
			StartLine:      1,
			EndLine:        lineCount(src),
			TargetFilePath: targetFile,
		})
	}
	return tests, nil
}

func isGoTestFunc(name string) bool {
	for _, prefix := range []string{"Test", "Benchmark", "Fuzz"} {
		if strings.HasPrefix(name, prefix) && len(name) > len(prefix) {
			return true
		}
	}
	return false
}

func inferTargetSymbol(testName string, symbols []types.RepoSymbol) string {
	target := normalizeTestName(testName)
	if target == "" {
		return ""
	}
	type candidate struct {
		id   string
		key  string
		size int
	}
	var candidates []candidate
	for _, s := range symbols {
		keys := []string{normalizeIdentifier(s.Name)}
		if idx := strings.LastIndex(s.Name, "."); idx >= 0 && idx < len(s.Name)-1 {
			keys = append(keys, normalizeIdentifier(s.Name[idx+1:]))
		}
		for _, key := range keys {
			if key != "" && strings.HasPrefix(target, key) {
				candidates = append(candidates, candidate{s.Identifier, key, len(key)})
			}
		}
	}
	sort.Slice(candidates, func(i, j int) bool { return candidates[i].size > candidates[j].size })
	if len(candidates) == 0 {
		return ""
	}
	return candidates[0].id
}

func normalizeTestName(name string) string {
	for _, prefix := range []string{"Benchmark", "Test", "Fuzz"} {
		if strings.HasPrefix(name, prefix) {
			return normalizeIdentifier(strings.TrimPrefix(name, prefix))
		}
	}
	return normalizeIdentifier(name)
}

func normalizeIdentifier(value string) string {
	var b strings.Builder
	for _, r := range value {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			b.WriteRune(unicode.ToLower(r))
		}
	}
	return b.String()
}

func isGenericTestFile(path string) bool {
	base := strings.ToLower(filepath.Base(path))
	if strings.HasPrefix(base, "test-") && strings.HasSuffix(base, ".sh") {
		return true
	}
	if base == "smoke-test.sh" {
		return true
	}
	if regexp.MustCompile(`\.(test|spec)\.(js|jsx|ts|tsx)$`).MatchString(base) {
		return true
	}
	return strings.Contains(filepath.ToSlash(strings.ToLower(path)), "/__tests__/")
}

func lineCount(data []byte) int {
	if len(data) == 0 {
		return 0
	}
	lines := 1
	for _, b := range data {
		if b == '\n' {
			lines++
		}
	}
	return lines
}
