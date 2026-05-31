package extract

import (
	"os"
	"path/filepath"
	"testing"
)

const ruleFixture = `# Business Rules

## Software

### BR-001 — Orders require a positive total
- **domain:** software
- **statement:** An order cannot be submitted with a total of zero or less.
- **scenarios:**
  - Given a cart whose total is 0, When the user submits, Then submission is rejected.
- **status:** accepted
- **source:** product owner, 2026-05-31
- **rationale:** Zero-value orders are data-entry errors.
- **links:** implements:[order.go:Submit, validate.go:CheckTotal] · relates:[BR-002] · decided-by:[ADR-260531-A]
- **last-reviewed:** abc1234

### BR-002 — Audit trail retained seven years
- **domain:** data
- **statement:** Every order mutation is retained for seven years.

## Design

<!-- Example — delete once you add real rules:
### BR-999 — should be ignored
- **domain:** design
-->
`

func TestParseRulesFile(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "business-rules.md")
	if err := os.WriteFile(p, []byte(ruleFixture), 0o644); err != nil {
		t.Fatal(err)
	}
	rules, err := ParseRulesFile(p)
	if err != nil {
		t.Fatalf("ParseRulesFile: %v", err)
	}
	if len(rules) != 2 {
		t.Fatalf("want 2 rules, got %d: %+v", len(rules), rules)
	}

	r := rules[0]
	if r.Identifier != "BR-001" {
		t.Errorf("id: want BR-001, got %q", r.Identifier)
	}
	if r.Title != "Orders require a positive total" {
		t.Errorf("title: got %q", r.Title)
	}
	if r.Domain != "software" {
		t.Errorf("domain: want software, got %q", r.Domain)
	}
	if r.Status != "accepted" {
		t.Errorf("status: want accepted, got %q", r.Status)
	}
	if len(r.Scenarios) != 1 {
		t.Fatalf("want 1 scenario, got %d: %v", len(r.Scenarios), r.Scenarios)
	}
	if len(r.Implements) != 2 || r.Implements[0] != "order.go:Submit" {
		t.Errorf("implements: %v", r.Implements)
	}
	if len(r.Relates) != 1 || r.Relates[0] != "BR-002" {
		t.Errorf("relates: %v", r.Relates)
	}
	if len(r.DecidedBy) != 1 || r.DecidedBy[0] != "ADR-260531-A" {
		t.Errorf("decided-by: %v", r.DecidedBy)
	}
	if r.LastReviewed != "abc1234" {
		t.Errorf("last-reviewed: %q", r.LastReviewed)
	}

	if rules[1].Identifier != "BR-002" || rules[1].Domain != "data" {
		t.Errorf("rule 2: %+v", rules[1])
	}

	for _, x := range rules {
		if x.Identifier == "BR-999" {
			t.Fatal("commented-out rule leaked into results")
		}
	}
}

func TestParseRulesFile_EmptyTemplate(t *testing.T) {
	// A template whose only rule example is HTML-commented yields zero rules.
	dir := t.TempDir()
	p := filepath.Join(dir, "business-rules.md")
	const tmpl = "# Business Rules\n\n## Software\n\n<!--\n### BR-001 — example\n- **domain:** software\n-->\n"
	if err := os.WriteFile(p, []byte(tmpl), 0o644); err != nil {
		t.Fatal(err)
	}
	rules, err := ParseRulesFile(p)
	if err != nil {
		t.Fatalf("ParseRulesFile: %v", err)
	}
	if len(rules) != 0 {
		t.Fatalf("want 0 rules from commented template, got %d", len(rules))
	}
}
