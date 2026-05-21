package extract

import (
	"bytes"
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"github.com/overdrive-dev/aihaus-flow/aih-graph/internal/types"
)

var (
	shellFunctionRe      = regexp.MustCompile(`^(?:function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\{?|([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*\)\s*\{?)\s*$`)
	powerShellFunctionRe = regexp.MustCompile(`(?i)^\s*function\s+([A-Za-z_][A-Za-z0-9_-]*)\b`)
)

// ParseRepositorySymbols extracts first-pass code symbols and call sites from
// indexed repository files. It intentionally starts with high-confidence local
// extraction: Go AST for functions/methods/calls and regex definitions for
// shell/PowerShell functions.
func ParseRepositorySymbols(repoRoot string, files []types.RepoFile) ([]types.RepoSymbol, []types.RepoCall, error) {
	var symbols []types.RepoSymbol
	var calls []types.RepoCall

	for _, f := range files {
		abs := filepath.Join(repoRoot, filepath.FromSlash(f.Path))
		switch f.Language {
		case "go":
			fileSymbols, fileCalls, err := parseGoSymbols(abs, f.Path)
			if err != nil {
				return nil, nil, err
			}
			symbols = append(symbols, fileSymbols...)
			calls = append(calls, fileCalls...)
		case "bash":
			fileSymbols, err := parseLineFunctionSymbols(abs, f.Path, f.Language, shellFunctionRe)
			if err != nil {
				return nil, nil, err
			}
			symbols = append(symbols, fileSymbols...)
		case "powershell":
			fileSymbols, err := parseLineFunctionSymbols(abs, f.Path, f.Language, powerShellFunctionRe)
			if err != nil {
				return nil, nil, err
			}
			symbols = append(symbols, fileSymbols...)
		}
	}

	resolveCalls(symbols, calls)
	sort.Slice(symbols, func(i, j int) bool { return symbols[i].Identifier < symbols[j].Identifier })
	sort.Slice(calls, func(i, j int) bool { return calls[i].Identifier < calls[j].Identifier })
	return symbols, calls, nil
}

func parseGoSymbols(absPath, relPath string) ([]types.RepoSymbol, []types.RepoCall, error) {
	src, err := os.ReadFile(absPath)
	if err != nil {
		return nil, nil, fmt.Errorf("read go file %s: %w", relPath, err)
	}
	fset := token.NewFileSet()
	file, err := parser.ParseFile(fset, absPath, src, 0)
	if err != nil {
		return nil, nil, fmt.Errorf("parse go file %s: %w", relPath, err)
	}

	var symbols []types.RepoSymbol
	var calls []types.RepoCall
	for _, decl := range file.Decls {
		fn, ok := decl.(*ast.FuncDecl)
		if !ok {
			continue
		}
		start := fset.Position(fn.Pos())
		end := fset.Position(fn.End())
		name := goFuncName(fn)
		identifier := relPath + ":" + name
		symbols = append(symbols, types.RepoSymbol{
			Identifier: identifier,
			Name:       name,
			Kind:       "function",
			Language:   "go",
			FilePath:   relPath,
			StartLine:  start.Line,
			EndLine:    end.Line,
			Signature:  goFuncSignature(fn),
		})
		if fn.Body == nil {
			continue
		}
		callIndex := 0
		ast.Inspect(fn.Body, func(n ast.Node) bool {
			call, ok := n.(*ast.CallExpr)
			if !ok {
				return true
			}
			callIndex++
			pos := fset.Position(call.Lparen)
			callee, qualifier := goCallName(call.Fun)
			if callee == "" {
				return true
			}
			calls = append(calls, types.RepoCall{
				Identifier:       fmt.Sprintf("%s#call-%04d", identifier, callIndex),
				CallerIdentifier: identifier,
				CalleeName:       callee,
				CalleeQualifier:  qualifier,
				Language:         "go",
				FilePath:         relPath,
				Line:             pos.Line,
				Column:           pos.Column,
			})
			return true
		})
	}
	return symbols, calls, nil
}

func goFuncName(fn *ast.FuncDecl) string {
	if fn.Recv == nil || len(fn.Recv.List) == 0 {
		return fn.Name.Name
	}
	recv := exprName(fn.Recv.List[0].Type)
	if recv == "" {
		return fn.Name.Name
	}
	return recv + "." + fn.Name.Name
}

func goFuncSignature(fn *ast.FuncDecl) string {
	var b bytes.Buffer
	b.WriteString("func ")
	if fn.Recv != nil && len(fn.Recv.List) > 0 {
		b.WriteByte('(')
		b.WriteString(exprName(fn.Recv.List[0].Type))
		b.WriteString(") ")
	}
	b.WriteString(fn.Name.Name)
	b.WriteString("(...)")
	return b.String()
}

func goCallName(expr ast.Expr) (callee, qualifier string) {
	switch e := expr.(type) {
	case *ast.Ident:
		return e.Name, ""
	case *ast.SelectorExpr:
		return e.Sel.Name, exprName(e.X)
	default:
		return "", ""
	}
}

func exprName(expr ast.Expr) string {
	switch e := expr.(type) {
	case *ast.Ident:
		return e.Name
	case *ast.StarExpr:
		return exprName(e.X)
	case *ast.SelectorExpr:
		left := exprName(e.X)
		if left == "" {
			return e.Sel.Name
		}
		return left + "." + e.Sel.Name
	case *ast.IndexExpr:
		return exprName(e.X)
	case *ast.IndexListExpr:
		return exprName(e.X)
	default:
		return ""
	}
}

func parseLineFunctionSymbols(absPath, relPath, language string, re *regexp.Regexp) ([]types.RepoSymbol, error) {
	data, err := os.ReadFile(absPath)
	if err != nil {
		return nil, fmt.Errorf("read %s file %s: %w", language, relPath, err)
	}
	lines := strings.Split(string(data), "\n")
	var symbols []types.RepoSymbol
	for i, line := range lines {
		m := re.FindStringSubmatch(strings.TrimSpace(line))
		if m == nil {
			continue
		}
		name := firstCapture(m)
		if name == "" {
			continue
		}
		symbols = append(symbols, types.RepoSymbol{
			Identifier: relPath + ":" + name,
			Name:       name,
			Kind:       "function",
			Language:   language,
			FilePath:   relPath,
			StartLine:  i + 1,
			EndLine:    i + 1,
			Signature:  strings.TrimSpace(line),
		})
	}
	return symbols, nil
}

func firstCapture(matches []string) string {
	for _, m := range matches[1:] {
		if m != "" {
			return m
		}
	}
	return ""
}

func resolveCalls(symbols []types.RepoSymbol, calls []types.RepoCall) {
	byName := map[string][]string{}
	for _, s := range symbols {
		byName[s.Name] = append(byName[s.Name], s.Identifier)
		if idx := strings.LastIndex(s.Name, "."); idx >= 0 && idx < len(s.Name)-1 {
			short := s.Name[idx+1:]
			byName[short] = append(byName[short], s.Identifier)
		}
	}
	for i := range calls {
		if calls[i].CalleeQualifier != "" {
			continue
		}
		matches := byName[calls[i].CalleeName]
		if len(matches) == 1 {
			calls[i].CalleeIdentifier = matches[0]
		}
	}
}
