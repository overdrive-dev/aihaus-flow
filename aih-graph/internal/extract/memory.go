package extract

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"github.com/overdrive-dev/aihaus-flow/aih-graph/internal/types"
)

var markdownH2Re = regexp.MustCompile(`^##\s+(.+?)\s*$`)

// ParseMarkdownMemory extracts human-curated aihaus memory sections from the
// repository. Markdown stays the source of truth; these nodes are derived.
func ParseMarkdownMemory(repoRoot string) ([]types.MarkdownMemory, error) {
	var out []types.MarkdownMemory
	for _, root := range memoryRoots(repoRoot) {
		if _, err := os.Stat(root.abs); os.IsNotExist(err) {
			continue
		} else if err != nil {
			return nil, err
		}
		err := filepath.WalkDir(root.abs, func(path string, entry os.DirEntry, walkErr error) error {
			if walkErr != nil {
				return walkErr
			}
			if entry.IsDir() {
				return nil
			}
			if strings.ToLower(filepath.Ext(path)) != ".md" {
				return nil
			}
			rel, err := filepath.Rel(repoRoot, path)
			if err != nil {
				return err
			}
			items, err := parseMemoryFile(path, filepath.ToSlash(rel), root.category)
			if err != nil {
				return err
			}
			out = append(out, items...)
			return nil
		})
		if err != nil {
			return nil, err
		}
	}
	for _, file := range memoryFiles(repoRoot) {
		if _, err := os.Stat(file.abs); os.IsNotExist(err) {
			continue
		} else if err != nil {
			return nil, err
		}
		rel, err := filepath.Rel(repoRoot, file.abs)
		if err != nil {
			return nil, err
		}
		items, err := parseMemoryFile(file.abs, filepath.ToSlash(rel), file.category)
		if err != nil {
			return nil, err
		}
		out = append(out, items...)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Identifier < out[j].Identifier })
	return out, nil
}

// ParseUserMemoryDir extracts markdown memory sections from a user-scope
// memory directory (e.g. ~/.aihaus/memory/user) for `aih-graph build --user`
// (M050/S04, ADR-260611-E). Identifiers are prefixed `user/<rel-path>`; the
// category is fixed to "user". Returns an empty slice (nil error) when the
// directory does not exist — a fresh machine has no user memory yet.
func ParseUserMemoryDir(userRoot string) ([]types.MarkdownMemory, error) {
	if _, err := os.Stat(userRoot); os.IsNotExist(err) {
		return nil, nil
	} else if err != nil {
		return nil, err
	}
	var out []types.MarkdownMemory
	err := filepath.WalkDir(userRoot, func(path string, entry os.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.IsDir() {
			return nil
		}
		if strings.ToLower(filepath.Ext(path)) != ".md" {
			return nil
		}
		rel, err := filepath.Rel(userRoot, path)
		if err != nil {
			return err
		}
		items, err := parseMemoryFile(path, "user/"+filepath.ToSlash(rel), "user")
		if err != nil {
			return err
		}
		out = append(out, items...)
		return nil
	})
	if err != nil {
		return nil, err
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Identifier < out[j].Identifier })
	return out, nil
}

type memoryRoot struct {
	abs      string
	category string
}

func memoryRoots(repoRoot string) []memoryRoot {
	return []memoryRoot{
		{filepath.Join(repoRoot, ".aihaus", "memory"), ""},
		{filepath.Join(repoRoot, "pkg", ".aihaus", "memory"), ""},
		{filepath.Join(repoRoot, ".claude", "agent-memory"), "agent"},
	}
}

type memoryFile struct {
	abs      string
	category string
}

func memoryFiles(repoRoot string) []memoryFile {
	return []memoryFile{
		{filepath.Join(repoRoot, ".aihaus", "project.md"), "project"},
		{filepath.Join(repoRoot, ".aihaus", "knowledge.md"), "knowledge"},
		{filepath.Join(repoRoot, ".aihaus", "decisions.md"), "decision"},
		{filepath.Join(repoRoot, "pkg", ".aihaus", "project.md"), "project"},
		{filepath.Join(repoRoot, "pkg", ".aihaus", "knowledge.md"), "knowledge"},
		{filepath.Join(repoRoot, "pkg", ".aihaus", "decisions.md"), "decision"},
	}
}

func parseMemoryFile(absPath, relPath, forcedCategory string) ([]types.MarkdownMemory, error) {
	data, err := os.ReadFile(absPath)
	if err != nil {
		return nil, fmt.Errorf("read memory file %s: %w", relPath, err)
	}
	lines := strings.Split(string(data), "\n")
	type section struct {
		heading string
		start   int
	}
	var sections []section
	for i, line := range lines {
		if m := markdownH2Re.FindStringSubmatch(line); m != nil {
			sections = append(sections, section{heading: strings.TrimSpace(m[1]), start: i})
		}
	}
	if len(sections) == 0 {
		sections = append(sections, section{heading: filepath.Base(relPath), start: 0})
	}
	category := forcedCategory
	if category == "" {
		category = memoryCategory(relPath)
	}
	var out []types.MarkdownMemory
	for i, sec := range sections {
		end := len(lines)
		if i+1 < len(sections) {
			end = sections[i+1].start
		}
		body := strings.TrimSpace(strings.Join(lines[sec.start:end], "\n"))
		if body == "" {
			continue
		}
		out = append(out, types.MarkdownMemory{
			Identifier: relPath + ":" + slugForMemory(sec.heading, sec.start+1),
			Category:   category,
			FilePath:   relPath,
			Heading:    sec.heading,
			Body:       body,
			StartLine:  sec.start + 1,
			EndLine:    end,
		})
	}
	return out, nil
}

func memoryCategory(relPath string) string {
	parts := strings.Split(filepath.ToSlash(relPath), "/")
	for i, part := range parts {
		if part == "memory" && i+1 < len(parts) {
			return parts[i+1]
		}
	}
	return "memory"
}

func slugForMemory(heading string, line int) string {
	slug := strings.ToLower(heading)
	slug = regexp.MustCompile(`[^a-z0-9]+`).ReplaceAllString(slug, "-")
	slug = strings.Trim(slug, "-")
	if slug == "" {
		sum := sha256.Sum256([]byte(heading))
		slug = hex.EncodeToString(sum[:4])
	}
	return fmt.Sprintf("%s-L%d", slug, line)
}
