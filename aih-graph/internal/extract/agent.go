package extract

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/overdrive-dev/aihaus-flow/aih-graph/internal/types"
)

// agentMemoryMaxLines + agentMemoryMaxBytes mirror native Claude Code's
// MEMORY.md injection limits per docs/cc-native-features-260515.md §1:
// "The subagent's system prompt also includes the first 200 lines or 25KB
// of MEMORY.md in the memory directory, whichever comes first."
const (
	agentMemoryMaxLines = 200
	agentMemoryMaxBytes = 25 * 1024
)

// readAgentMemory returns the (path, excerpt) tuple for an agent's
// .claude/agent-memory/<name>/MEMORY.md if present. Returns empty
// strings when the file does not exist (agent has memory:none, or memory
// directory hasn't been written yet). Excerpt is truncated to first 200
// lines or 25KB whichever comes first, matching native CC semantics.
func readAgentMemory(repoRoot, agentName string) (string, string) {
	rel := filepath.Join(".claude", "agent-memory", agentName, "MEMORY.md")
	abs := filepath.Join(repoRoot, rel)
	info, err := os.Stat(abs)
	if err != nil || info.IsDir() {
		return "", ""
	}
	data, err := os.ReadFile(abs)
	if err != nil {
		return "", ""
	}
	// Truncate by byte cap first (cheap).
	if len(data) > agentMemoryMaxBytes {
		data = data[:agentMemoryMaxBytes]
	}
	// Then by line cap.
	lines := strings.SplitN(string(data), "\n", agentMemoryMaxLines+1)
	if len(lines) > agentMemoryMaxLines {
		lines = lines[:agentMemoryMaxLines]
	}
	return rel, strings.Join(lines, "\n")
}

// agentFrontmatter mirrors the YAML frontmatter declared by every agent in
// pkg/.aihaus/agents/*.md. Smoke Check 6 enforces all 8 fields are present.
type agentFrontmatter struct {
	Name                  string `yaml:"name"`
	Tools                 any    `yaml:"tools"`                  // can be CSV string OR YAML list
	Model                 string `yaml:"model"`
	Effort                string `yaml:"effort"`
	Color                 string `yaml:"color"`
	Memory                string `yaml:"memory"`
	Resumable             bool   `yaml:"resumable"`
	CheckpointGranularity string `yaml:"checkpoint_granularity"`
	Description           string `yaml:"description"`
}

// ParseAgentsDir walks pkg/.aihaus/agents/*.md and returns one Agent per file.
// Files without YAML frontmatter are skipped (with a non-fatal warning to the
// caller via the returned errs slice — but only when fatally malformed).
func ParseAgentsDir(repoRoot string) ([]types.Agent, error) {
	pattern := filepath.Join(repoRoot, "pkg", ".aihaus", "agents", "*.md")
	matches, err := filepath.Glob(pattern)
	if err != nil {
		return nil, fmt.Errorf("glob agents: %w", err)
	}
	sort.Strings(matches)

	agents := make([]types.Agent, 0, len(matches))
	for _, path := range matches {
		// Skip README-like files at the agents/ root (e.g. memory/README.md placeholders).
		base := filepath.Base(path)
		if strings.HasPrefix(base, "README") || strings.HasPrefix(base, "_") {
			continue
		}
		var fm agentFrontmatter
		body, err := parseFrontmatterInto(path, &fm)
		if err != nil {
			return nil, fmt.Errorf("parse %s: %w", path, err)
		}
		if fm.Name == "" {
			// No frontmatter or empty frontmatter; not an agent definition.
			continue
		}
		a := types.Agent{
			Name:                  fm.Name,
			Tools:                 toolsToSlice(fm.Tools),
			Model:                 fm.Model,
			Effort:                fm.Effort,
			Color:                 fm.Color,
			Memory:                fm.Memory,
			Resumable:             fm.Resumable,
			CheckpointGranularity: fm.CheckpointGranularity,
			Description:           fm.Description,
		}
		if a.Description == "" {
			a.Description = firstParagraph(body)
		}
		// M046: index .claude/agent-memory/<name>/MEMORY.md if present.
		// Memory excerpt becomes part of the Agent node's properties → embedded
		// alongside frontmatter → queryable via BM25/FTS5 + semantic modes.
		a.MemoryPath, a.MemoryExcerpt = readAgentMemory(repoRoot, fm.Name)
		agents = append(agents, a)
	}
	return agents, nil
}

// toolsToSlice normalizes agent.Tools (which may be a YAML list or a
// space/comma-separated string per historical agent frontmatter shapes) into
// a clean []string. Empty/whitespace tokens are dropped.
func toolsToSlice(raw any) []string {
	switch v := raw.(type) {
	case nil:
		return nil
	case string:
		return splitFields(v)
	case []any:
		out := make([]string, 0, len(v))
		for _, item := range v {
			if s, ok := item.(string); ok {
				s = strings.TrimSpace(s)
				if s != "" {
					out = append(out, s)
				}
			}
		}
		return out
	default:
		return nil
	}
}

func splitFields(s string) []string {
	// Tools strings come in two shapes:
	//   "Read Bash Grep Glob"      (space-separated)
	//   "Read, Bash, Grep, Glob"   (comma-separated)
	// Normalize commas to spaces, then split on whitespace.
	s = strings.ReplaceAll(s, ",", " ")
	parts := strings.Fields(s)
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}

// firstParagraph returns the first non-empty paragraph from a markdown body.
// Skips leading whitespace lines and stops at the first blank line after content.
func firstParagraph(body []byte) string {
	var (
		started bool
		buf     strings.Builder
	)
	for _, line := range strings.Split(string(body), "\n") {
		trimmed := strings.TrimSpace(line)
		if !started {
			if trimmed == "" || strings.HasPrefix(trimmed, "#") {
				continue
			}
			started = true
			buf.WriteString(trimmed)
			continue
		}
		if trimmed == "" {
			break
		}
		buf.WriteByte(' ')
		buf.WriteString(trimmed)
	}
	return buf.String()
}
