package extract

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/overdrive-dev/aihaus-flow/aih-graph/internal/types"
)

type instructionPattern struct {
	typ     string
	pattern string
}

// ParseInstructionsDir indexes the portable Map-adjacent instruction surface:
// roles, rooms, contracts, and deterministic tools. A consumer installation
// uses .aihaus/; the source repository falls back to pkg/.aihaus/.
func ParseInstructionsDir(repoRoot string) ([]types.Instruction, error) {
	source := filepath.Join(repoRoot, ".aihaus")
	if info, err := os.Stat(source); err != nil || !info.IsDir() {
		source = filepath.Join(repoRoot, "pkg", ".aihaus")
	}
	patterns := []instructionPattern{
		{typ: "Map", pattern: filepath.Join(source, "MAP.md")},
		{typ: "Convention", pattern: filepath.Join(source, "conventions.md")},
		{typ: "Role", pattern: filepath.Join(source, "roles", "*.md")},
		{typ: "Room", pattern: filepath.Join(source, "rooms", "*", "CONTEXT.md")},
		{typ: "Contract", pattern: filepath.Join(source, "contracts", "*.md")},
		{typ: "Tool", pattern: filepath.Join(source, "tools", "*.mjs")},
	}

	var out []types.Instruction
	for _, item := range patterns {
		matches, err := filepath.Glob(item.pattern)
		if err != nil {
			return nil, fmt.Errorf("glob %s instructions: %w", item.typ, err)
		}
		for _, file := range matches {
			data, err := os.ReadFile(file)
			if err != nil {
				return nil, fmt.Errorf("read instruction %s: %w", file, err)
			}
			rel, err := filepath.Rel(repoRoot, file)
			if err != nil {
				return nil, fmt.Errorf("relative instruction path %s: %w", file, err)
			}
			identifier := strings.TrimSuffix(filepath.Base(file), filepath.Ext(file))
			if item.typ == "Room" {
				identifier = filepath.Base(filepath.Dir(file))
			}
			body := string(data)
			out = append(out, types.Instruction{
				Type:       item.typ,
				Identifier: identifier,
				Path:       filepath.ToSlash(rel),
				Title:      firstMarkdownTitle(body, identifier),
				Body:       body,
			})
		}
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Type == out[j].Type {
			return out[i].Identifier < out[j].Identifier
		}
		return out[i].Type < out[j].Type
	})
	return out, nil
}

func firstMarkdownTitle(body, fallback string) string {
	for _, line := range strings.Split(body, "\n") {
		if strings.HasPrefix(line, "# ") {
			return strings.TrimSpace(strings.TrimPrefix(line, "# "))
		}
	}
	return fallback
}
