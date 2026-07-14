// rule.go parses an aihaus business-rules ledger (the decision-autonomy contract)
// by splitting on `^### BR-` section headers. Each section becomes one Rule per
// ADR-260531-A. The ledger source-of-truth is markdown
// (.aihaus/memory/project/business-rules.md); aih-graph indexes it as Rule
// nodes so agents can query rule↔code bindings. HTML-commented template examples
// (`<!-- … -->`) are skipped so the seed template contributes no phantom rules.
package extract

import (
	"bufio"
	"fmt"
	"os"
	"regexp"
	"strings"

	"github.com/overdrive-dev/aihaus-flow/aih-graph/internal/types"
)

// ruleHeaderRe matches a rule section header and captures id + title.
// Examples: `### BR-001 — Orders require a positive total`, `### BR-F1 — Domains`.
var ruleHeaderRe = regexp.MustCompile(`^###\s+(BR-[A-Za-z0-9\-]+)\s*[—\-:]\s*(.+)$`)

// Field lines look like `- **domain:** software` (the leading bullet is optional).
var (
	ruleDomainRe    = regexp.MustCompile(`(?m)^\s*-?\s*\*\*domain:\*\*\s*(.+?)\s*$`)
	ruleStatementRe = regexp.MustCompile(`(?m)^\s*-?\s*\*\*statement:\*\*\s*(.+?)\s*$`)
	ruleStatusRe    = regexp.MustCompile(`(?m)^\s*-?\s*\*\*status:\*\*\s*(.+?)\s*$`)
	ruleSourceRe    = regexp.MustCompile(`(?m)^\s*-?\s*\*\*source:\*\*\s*(.+?)\s*$`)
	ruleRationaleRe = regexp.MustCompile(`(?m)^\s*-?\s*\*\*rationale:\*\*\s*(.+?)\s*$`)
	ruleReviewedRe  = regexp.MustCompile(`(?m)^\s*-?\s*\*\*last-reviewed:\*\*\s*(.+?)\s*$`)
	ruleLinksRe     = regexp.MustCompile(`(?m)^\s*-?\s*\*\*links:\*\*\s*(.+?)\s*$`)
	ruleScenarioRe  = regexp.MustCompile(`(?im)^\s*-\s*(Given\b.+?\bThen\b.+)$`)
	implementsRe    = regexp.MustCompile(`implements:\s*\[([^\]]*)\]`)
	relatesRe       = regexp.MustCompile(`relates:\s*\[([^\]]*)\]`)
	decidedByRe     = regexp.MustCompile(`decided-by:\s*\[([^\]]*)\]`)
)

// ParseRulesFile reads an aihaus business-rules ledger and returns one Rule per
// `### BR-…` section. Returns an empty slice (nil error) when the file holds no
// recognizable rule sections — e.g. a fresh template whose only examples are
// HTML-commented out.
func ParseRulesFile(path string) ([]types.Rule, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("open %s: %w", path, err)
	}
	defer f.Close()

	var (
		rules     []types.Rule
		current   *types.Rule
		body      strings.Builder
		inComment bool
	)

	flush := func() {
		if current == nil {
			return
		}
		current.Body = strings.TrimRight(body.String(), "\n")
		extractRuleFields(current)
		rules = append(rules, *current)
		body.Reset()
	}

	scanner := bufio.NewScanner(f)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)

	for scanner.Scan() {
		line := scanner.Text()

		// Skip HTML-commented content (template examples live in <!-- … -->).
		if inComment {
			if strings.Contains(line, "-->") {
				inComment = false
			}
			continue
		}
		if strings.Contains(line, "<!--") {
			if !strings.Contains(line, "-->") {
				inComment = true
			}
			continue // skip the comment line (single- or multi-line opener)
		}

		if m := ruleHeaderRe.FindStringSubmatch(line); m != nil {
			flush()
			current = &types.Rule{
				Identifier: m[1],
				Title:      strings.TrimSpace(m[2]),
			}
			continue
		}
		// Any other H2/H3 header (e.g. a `## Software` domain section) ends the
		// active rule's body.
		if current != nil && (strings.HasPrefix(line, "## ") || strings.HasPrefix(line, "### ")) {
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
	return rules, nil
}

// extractRuleFields populates the typed fields of r by scanning its Body for the
// canonical `**field:**` lines, Given/When/Then scenarios, and the bracketed
// link lists.
func extractRuleFields(r *types.Rule) {
	if m := ruleDomainRe.FindStringSubmatch(r.Body); m != nil {
		r.Domain = strings.TrimSpace(m[1])
	}
	if m := ruleStatementRe.FindStringSubmatch(r.Body); m != nil {
		r.Statement = strings.TrimSpace(m[1])
	}
	if m := ruleStatusRe.FindStringSubmatch(r.Body); m != nil {
		r.Status = strings.TrimSpace(m[1])
	}
	if m := ruleSourceRe.FindStringSubmatch(r.Body); m != nil {
		r.Source = strings.TrimSpace(m[1])
	}
	if m := ruleRationaleRe.FindStringSubmatch(r.Body); m != nil {
		r.Rationale = strings.TrimSpace(m[1])
	}
	if m := ruleReviewedRe.FindStringSubmatch(r.Body); m != nil {
		r.LastReviewed = strings.TrimSpace(m[1])
	}
	for _, m := range ruleScenarioRe.FindAllStringSubmatch(r.Body, -1) {
		r.Scenarios = append(r.Scenarios, strings.TrimSpace(m[1]))
	}
	if m := ruleLinksRe.FindStringSubmatch(r.Body); m != nil {
		links := m[1]
		if im := implementsRe.FindStringSubmatch(links); im != nil {
			r.Implements = splitRefs(im[1])
		}
		if rel := relatesRe.FindStringSubmatch(links); rel != nil {
			r.Relates = splitRefs(rel[1])
		}
		if db := decidedByRe.FindStringSubmatch(links); db != nil {
			r.DecidedBy = splitRefs(db[1])
		}
	}
}

// splitRefs splits a bracketed, comma-separated reference list into trimmed,
// non-empty items. `[order.go:Submit, validate.go:Check]` → 2 items; `[]` → nil.
func splitRefs(s string) []string {
	var out []string
	for _, p := range strings.Split(s, ",") {
		if t := strings.TrimSpace(p); t != "" {
			out = append(out, t)
		}
	}
	return out
}
