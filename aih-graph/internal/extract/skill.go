package extract

import (
	"fmt"
	"path/filepath"
	"sort"
	"strings"

	"github.com/overdrive-dev/aihaus-flow/aih-graph/internal/types"
)

// skillFrontmatter mirrors the YAML frontmatter declared by every SKILL.md
// under pkg/.aihaus/skills/aih-*/. Smoke Check 4 enforces `name: aih-<slug>`.
type skillFrontmatter struct {
	Name                   string `yaml:"name"`
	Description            string `yaml:"description"`
	DisableModelInvocation bool   `yaml:"disable-model-invocation"`
	AllowedTools           any    `yaml:"allowed-tools"` // CSV string or YAML list
	ArgumentHint           string `yaml:"argument-hint"`
}

// ParseSkillsDir walks pkg/.aihaus/skills/aih-*/SKILL.md and returns one Skill
// per file. Files without YAML frontmatter or without a name are skipped.
func ParseSkillsDir(repoRoot string) ([]types.Skill, error) {
	pattern := filepath.Join(repoRoot, "pkg", ".aihaus", "skills", "aih-*", "SKILL.md")
	matches, err := filepath.Glob(pattern)
	if err != nil {
		return nil, fmt.Errorf("glob skills: %w", err)
	}
	sort.Strings(matches)

	skills := make([]types.Skill, 0, len(matches))
	for _, path := range matches {
		var fm skillFrontmatter
		_, err := parseFrontmatterInto(path, &fm)
		if err != nil {
			return nil, fmt.Errorf("parse %s: %w", path, err)
		}
		if fm.Name == "" {
			continue
		}
		if !strings.HasPrefix(fm.Name, "aih-") {
			// Smoke Check 4 invariant: skill name must be aih-*. Skip anomalies.
			continue
		}
		skills = append(skills, types.Skill{
			Name:                   fm.Name,
			Description:            fm.Description,
			DisableModelInvocation: fm.DisableModelInvocation,
			AllowedTools:           toolsToSlice(fm.AllowedTools),
			ArgumentHint:           fm.ArgumentHint,
		})
	}
	return skills, nil
}
