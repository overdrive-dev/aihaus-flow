// Package extract implements markdown-only structured extraction for the 6
// aihaus typed nodes per ADR-260515-C-amend-02.
//
// adr.go parses pkg/.aihaus/decisions.md by splitting on `^## ADR-` section
// headers. Each section becomes one Decision.
package extract

import (
	"bufio"
	"fmt"
	"os"
	"regexp"
	"strings"

	"github.com/overdrive-dev/aihaus-flow/aih-graph/internal/types"
)

// adrHeaderRe matches a section header line and captures the identifier and title.
// Examples that must match:
//
//	## ADR-260514-B — array-aware merge ...
//	## ADR-260515-C-amend-01 — M032 pre-flight gate ...
//	## ADR-M030-CURATE-A — curator decision
var adrHeaderRe = regexp.MustCompile(`^##\s+(ADR-[A-Za-z0-9\-]+)\s*[—\-:]\s*(.+)$`)

// fieldRe matches `**Field:** value` lines anywhere in the section body.
var (
	statusFieldRe    = regexp.MustCompile(`(?m)^\*\*Status:\*\*\s*(.+?)\s*$`)
	dateFieldRe      = regexp.MustCompile(`(?m)^\*\*Date:\*\*\s*(.+?)\s*$`)
	milestoneFieldRe = regexp.MustCompile(`(?m)^\*\*Milestone:\*\*\s*(.+?)\s*$`)
	amendsFieldRe    = regexp.MustCompile(`(?m)^\*\*Amends:\*\*\s*(.+?)\s*$`)
)

// ParseDecisionsFile reads an aihaus decisions.md file and returns one
// Decision per `## ADR-…` section. Returns an empty slice and nil error if the
// file contains no recognizable ADR sections.
func ParseDecisionsFile(path string) ([]types.Decision, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("open %s: %w", path, err)
	}
	defer f.Close()

	var (
		decisions []types.Decision
		current   *types.Decision
		body      strings.Builder
	)

	flush := func() {
		if current == nil {
			return
		}
		current.Body = strings.TrimRight(body.String(), "\n")
		extractFields(current)
		decisions = append(decisions, *current)
		body.Reset()
	}

	scanner := bufio.NewScanner(f)
	// decisions.md sections can be long (some ADRs hit ~10k chars); raise buffer.
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)

	for scanner.Scan() {
		line := scanner.Text()
		if m := adrHeaderRe.FindStringSubmatch(line); m != nil {
			flush()
			current = &types.Decision{
				Identifier: m[1],
				Title:      strings.TrimSpace(m[2]),
			}
			continue
		}
		// Hit a non-ADR `## ` H2 between ADRs (e.g. doc-level intro headers)?
		// Drop active section and skip the line — these are not ADR content.
		if strings.HasPrefix(line, "## ") && current != nil && !strings.HasPrefix(line, "## ADR-") {
			flush()
			current = nil
			continue
		}
		if current != nil {
			body.WriteString(line)
			body.WriteByte('\n')
		}
	}
	flush()

	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("scan %s: %w", path, err)
	}
	return decisions, nil
}

// adrIdentRe matches the canonical ADR identifier shape at the start of a
// string, used to strip trailing prose from `**Amends:**` values like
// `ADR-260515-B (parent: ...)` → `ADR-260515-B`.
var adrIdentRe = regexp.MustCompile(`^(ADR-[A-Za-z0-9\-]+)`)

// extractFields populates Status / Date / Milestone / Amends on d by scanning
// its Body for the canonical bold-field lines.
func extractFields(d *types.Decision) {
	if m := statusFieldRe.FindStringSubmatch(d.Body); m != nil {
		d.Status = strings.TrimSpace(m[1])
	}
	if m := dateFieldRe.FindStringSubmatch(d.Body); m != nil {
		d.Date = strings.TrimSpace(m[1])
	}
	if m := milestoneFieldRe.FindStringSubmatch(d.Body); m != nil {
		d.Milestone = strings.TrimSpace(m[1])
	}
	if m := amendsFieldRe.FindStringSubmatch(d.Body); m != nil {
		raw := strings.TrimSpace(m[1])
		// Strip trailing prose: "ADR-X (parent: ...)" → "ADR-X"
		if ident := adrIdentRe.FindString(raw); ident != "" {
			d.Amends = ident
		} else {
			d.Amends = raw
		}
	}
}
