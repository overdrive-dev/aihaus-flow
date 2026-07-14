package extract

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"

	"github.com/overdrive-dev/aihaus-flow/aih-graph/internal/types"
)

// RUN-MANIFEST.md (schema v3) layout the parser cares about:
//
//	## Metadata
//	slug: M030-260514-merge-settings-array-aware
//	status: completed
//	phase: complete
//	last_updated: 2026-05-14T19:30:00Z
//	pause_class: null
//	(more fields tolerated and ignored)
//
//	## Story Records
//	| id | agent | owned_files | status | sha | ts | notes |
//	|----|-------|-------------|--------|-----|----|--|
//	| S01 | analyst | ... | completed | abc1234 | 2026-05-14T... | ... |
//	...

var (
	mfMetaSection  = regexp.MustCompile(`(?ms)^## Metadata\s*$(.*?)(?:^## |\z)`)
	mfStorySection = regexp.MustCompile(`(?ms)^## Story Records\s*$(.*?)(?:^## |\z)`)
	mfKVLine       = regexp.MustCompile(`(?m)^([a-z_][a-z0-9_]*)\s*:\s*(.+?)\s*$`)
	milestoneIDRe  = regexp.MustCompile(`^(M\d{3})`)
)

// ParseMilestonesDir walks .aihaus/milestones/<slug>/RUN-MANIFEST.md and
// returns one Milestone per manifest + flattened Story slices.
// Returns empty slices (not error) if .aihaus/milestones/ does not exist.
func ParseMilestonesDir(repoRoot string) ([]types.Milestone, []types.Story, error) {
	milestonesRoot := filepath.Join(repoRoot, ".aihaus", "milestones")
	if _, err := os.Stat(milestonesRoot); os.IsNotExist(err) {
		return nil, nil, nil
	}

	pattern := filepath.Join(milestonesRoot, "*", "RUN-MANIFEST.md")
	matches, err := filepath.Glob(pattern)
	if err != nil {
		return nil, nil, fmt.Errorf("glob milestones: %w", err)
	}
	sort.Strings(matches)

	var (
		milestones []types.Milestone
		stories    []types.Story
	)
	for _, path := range matches {
		m, ss, err := parseManifest(path)
		if err != nil {
			return nil, nil, fmt.Errorf("parse %s: %w", path, err)
		}
		milestones = append(milestones, m)
		stories = append(stories, ss...)
	}
	return milestones, stories, nil
}

func parseManifest(path string) (types.Milestone, []types.Story, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return types.Milestone{}, nil, err
	}
	body, _, _ := splitFrontmatter(b) // not all manifests have frontmatter; safe to drop
	if len(body) == 0 {
		body = b
	}
	content := string(body)

	// Slug from path: .aihaus/milestones/<slug>/RUN-MANIFEST.md
	slug := filepath.Base(filepath.Dir(path))

	m := types.Milestone{Slug: slug}
	if idMatch := milestoneIDRe.FindStringSubmatch(slug); idMatch != nil {
		m.ID = idMatch[1]
	}

	// Metadata section: key: value lines.
	if sect := mfMetaSection.FindStringSubmatch(content); sect != nil {
		for _, kv := range mfKVLine.FindAllStringSubmatch(sect[1], -1) {
			key, val := kv[1], strings.TrimSpace(kv[2])
			switch key {
			case "status":
				m.Status = val
			case "phase":
				m.Phase = val
			case "pause_class":
				if val != "" && val != "null" {
					m.PauseClass = val
				}
			case "last_updated":
				if t, err := time.Parse(time.RFC3339, val); err == nil {
					m.LastUpdated = t
				}
			}
		}
	}

	// Story Records section.
	stories := parseStoryRecords(content, m.ID)
	return m, stories, nil
}

// parseStoryRecords extracts Story rows from a Story Records markdown table.
// Format (column count may vary across schema versions; we read positionally
// by header):
//
//	| id | agent | owned_files | status | sha | ts | notes |
//	|----|-------|-------------|--------|-----|----|--|
//	| S01 | ... |
func parseStoryRecords(content, milestoneID string) []types.Story {
	sect := mfStorySection.FindStringSubmatch(content)
	if sect == nil {
		return nil
	}
	lines := strings.Split(sect[1], "\n")

	var (
		headerCols []string
		stories    []types.Story
	)
	for _, raw := range lines {
		line := strings.TrimSpace(raw)
		if line == "" || !strings.HasPrefix(line, "|") {
			continue
		}
		// Separator row: `|---|...|`
		if strings.ContainsAny(line, "-=") && strings.ReplaceAll(strings.ReplaceAll(line, "|", ""), " ", "") != "" {
			trimmed := strings.Trim(line, "| ")
			if trimmed != "" && strings.IndexFunc(trimmed, func(r rune) bool {
				return r != '-' && r != ' ' && r != ':' && r != '|'
			}) == -1 {
				continue
			}
		}
		cells := splitMDRow(line)
		if headerCols == nil {
			headerCols = make([]string, len(cells))
			for i, c := range cells {
				headerCols[i] = strings.ToLower(strings.TrimSpace(c))
			}
			continue
		}
		s := types.Story{MilestoneID: milestoneID}
		for i, c := range cells {
			if i >= len(headerCols) {
				break
			}
			val := strings.TrimSpace(c)
			switch headerCols[i] {
			case "id", "story", "story_id":
				s.ID = val
			case "agent":
				// not stored on Story directly; could be a property if needed later
			case "owned_files", "files":
				if val != "" && val != "-" {
					s.OwnedFiles = splitManifestFields(val)
				}
			case "status":
				s.Status = val
			case "summary", "notes", "description":
				if s.Summary == "" {
					s.Summary = val
				}
			}
		}
		if s.ID != "" {
			stories = append(stories, s)
		}
	}
	return stories
}

func splitManifestFields(value string) []string {
	value = strings.ReplaceAll(value, ",", " ")
	return strings.Fields(value)
}

// splitMDRow splits a markdown table row "| a | b | c |" into ["a", "b", "c"],
// preserving empty cells but trimming surrounding whitespace.
func splitMDRow(line string) []string {
	line = strings.TrimSpace(line)
	line = strings.TrimPrefix(line, "|")
	line = strings.TrimSuffix(line, "|")
	parts := strings.Split(line, "|")
	out := make([]string, len(parts))
	for i, p := range parts {
		out[i] = strings.TrimSpace(p)
	}
	return out
}
