// main_rule_test.go covers the M050/S04 tier-A capability set: the rule/why
// verbs, the --types multi-type filter (BM25 + storage layer), SHA staleness
// in rule-drift, and build --user consent + DB separation. Conventions follow
// main_json_test.go (package main, plain testing, t.Fatalf expected/got).
package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/overdrive-dev/aihaus-flow/aih-graph/internal/embed"
	"github.com/overdrive-dev/aihaus-flow/aih-graph/internal/storage"
)

// --- --types parser -------------------------------------------------------

func TestSplitTypesFilter(t *testing.T) {
	cases := []struct {
		name     string
		typesCSV string
		single   string
		want     []string
	}{
		{"empty both", "", "", nil},
		{"single back-compat", "", "Rule", []string{"Rule"}},
		{"csv basic", "Rule,Decision", "", []string{"Rule", "Decision"}},
		{"csv trims whitespace", " Rule , Decision ", "", []string{"Rule", "Decision"}},
		{"csv drops empties", "Rule,,Decision,", "", []string{"Rule", "Decision"}},
		{"csv supersedes single", "Rule,Decision", "Chunk", []string{"Rule", "Decision"}},
	}
	for _, c := range cases {
		got := splitTypesFilter(c.typesCSV, c.single)
		if !reflect.DeepEqual(got, c.want) {
			t.Fatalf("%s: splitTypesFilter(%q, %q) = %#v, want %#v", c.name, c.typesCSV, c.single, got, c.want)
		}
	}
}

// --- seed: rule graph -----------------------------------------------------

// seedRuleGraphDB builds a DB with one fully-linked Rule (BR-F1), a related
// Rule (BR-002), a Decision, a Symbol + File target, and the edges the build
// pipeline would derive. BR-F1 declares 3 implements refs but only 2 resolve
// (ghost.go:Gone is dangling).
func seedRuleGraphDB(t *testing.T) (string, string) {
	t.Helper()
	dir := t.TempDir()
	repoPath := filepath.Join(dir, "repo")
	if err := os.MkdirAll(repoPath, 0o755); err != nil {
		t.Fatal(err)
	}
	dbPath := filepath.Join(dir, "graph.db")
	db, err := storage.Open(dbPath)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	ruleID, err := db.UpsertNode("Rule", "BR-F1", map[string]any{
		"title":         "Flow guard enforces at the promotion boundary",
		"domain":        "software",
		"statement":     "Deploys require an active flow sentinel",
		"status":        "accepted",
		"scenarios":     []string{"Given a deploy command When no active flow exists Then the command is blocked"},
		"implements":    []string{"order.go:Submit", "order.go", "ghost.go:Gone"},
		"relates":       []string{"BR-002"},
		"decided_by":    []string{"ADR-TEST-A"},
		"last_reviewed": "abc1234",
	})
	if err != nil {
		t.Fatal(err)
	}
	rule2ID, err := db.UpsertNode("Rule", "BR-002", map[string]any{
		"title":  "Related rule",
		"status": "accepted",
	})
	if err != nil {
		t.Fatal(err)
	}
	symID, err := db.UpsertNode("Symbol", "order.go:Submit", map[string]any{
		"name":      "Submit",
		"file_path": "order.go",
	})
	if err != nil {
		t.Fatal(err)
	}
	fileID, err := db.UpsertNode("File", "order.go", map[string]any{
		"path": "order.go",
	})
	if err != nil {
		t.Fatal(err)
	}
	decID, err := db.UpsertNode("Decision", "ADR-TEST-A", map[string]any{
		"title":  "Test decision",
		"status": "Accepted",
	})
	if err != nil {
		t.Fatal(err)
	}
	for _, e := range []struct {
		from, to int64
		typ      string
	}{
		{ruleID, symID, "implements"},
		{ruleID, fileID, "implements"},
		{ruleID, decID, "decided_by"},
		{ruleID, rule2ID, "relates"},
	} {
		if err := db.UpsertEdge(e.from, e.to, e.typ, nil); err != nil {
			t.Fatal(err)
		}
	}
	return dbPath, repoPath
}

// --- rule <BR-id> ---------------------------------------------------------

func TestRunRuleJSONHappyPath(t *testing.T) {
	dbPath, repoPath := seedRuleGraphDB(t)
	code, stdout := captureStdout(t, func() int {
		return runRule([]string{"--repo", repoPath, "--db", dbPath, "--json", "BR-F1"})
	})
	if code != 0 {
		t.Fatalf("runRule returned %d", code)
	}
	var payload ruleVerbJSON
	decodeJSON(t, stdout, &payload)
	if payload.Command != "rule" || payload.ID != "BR-F1" {
		t.Fatalf("unexpected rule metadata: %#v", payload)
	}
	if payload.Rule.Identifier != "BR-F1" || payload.Rule.Type != "Rule" {
		t.Fatalf("unexpected rule node: %#v", payload.Rule)
	}
	if payload.Status != "accepted" || payload.Domain != "software" {
		t.Fatalf("expected status/domain fields, got status=%q domain=%q", payload.Status, payload.Domain)
	}
	if len(payload.Scenarios) != 1 || !strings.Contains(payload.Scenarios[0], "Given a deploy command") {
		t.Fatalf("expected Given/When/Then scenario, got %#v", payload.Scenarios)
	}
	edges := map[string][]string{}
	for _, b := range payload.Bindings {
		edges[b.Edge] = append(edges[b.Edge], b.Node.Identifier)
	}
	if !reflect.DeepEqual(edges["implements"], []string{"order.go", "order.go:Submit"}) {
		t.Fatalf("unexpected implements bindings: %#v", edges["implements"])
	}
	if !reflect.DeepEqual(edges["decided_by"], []string{"ADR-TEST-A"}) {
		t.Fatalf("unexpected decided_by bindings: %#v", edges["decided_by"])
	}
	if !reflect.DeepEqual(edges["relates"], []string{"BR-002"}) {
		t.Fatalf("unexpected relates bindings: %#v", edges["relates"])
	}
	// 3 declared implements, only 2 resolved → dangling-binding freshness.
	if payload.Review.State != "dangling-binding" || payload.Review.DeclaredLinks != 3 || payload.Review.BoundLinks != 2 {
		t.Fatalf("unexpected review block: %#v", payload.Review)
	}
	if payload.Review.LastReviewed != "abc1234" {
		t.Fatalf("expected last_reviewed passthrough, got %q", payload.Review.LastReviewed)
	}
}

func TestRunRuleMissingID(t *testing.T) {
	dbPath, repoPath := seedRuleGraphDB(t)
	code, _ := captureStdout(t, func() int {
		return runRule([]string{"--repo", repoPath, "--db", dbPath, "--json", "BR-NOPE"})
	})
	if code != 1 {
		t.Fatalf("expected exit 1 for missing rule id, got %d", code)
	}
}

// --- why <ref> ------------------------------------------------------------

func TestRunWhyJSONByFilePath(t *testing.T) {
	dbPath, repoPath := seedRuleGraphDB(t)
	code, stdout := captureStdout(t, func() int {
		return runWhy([]string{"--repo", repoPath, "--db", dbPath, "--json", "order.go"})
	})
	if code != 0 {
		t.Fatalf("runWhy returned %d", code)
	}
	var payload whyJSON
	decodeJSON(t, stdout, &payload)
	if payload.RuleCount != 1 || payload.Rules[0].Rule.Identifier != "BR-F1" {
		t.Fatalf("expected BR-F1 bound to order.go, got %#v", payload.Rules)
	}
	if payload.Rules[0].Edge != "implements" {
		t.Fatalf("expected implements edge, got %q", payload.Rules[0].Edge)
	}
	if len(payload.Rules[0].DecidedBy) != 1 || payload.Rules[0].DecidedBy[0].Identifier != "ADR-TEST-A" {
		t.Fatalf("expected decided_by chain to ADR-TEST-A, got %#v", payload.Rules[0].DecidedBy)
	}
	if len(payload.Decisions) != 1 || payload.Decisions[0].Identifier != "ADR-TEST-A" {
		t.Fatalf("expected aggregated decision, got %#v", payload.Decisions)
	}
}

func TestRunWhyJSONByBareSymbolName(t *testing.T) {
	dbPath, repoPath := seedRuleGraphDB(t)
	code, stdout := captureStdout(t, func() int {
		return runWhy([]string{"--repo", repoPath, "--db", dbPath, "--json", "Submit"})
	})
	if code != 0 {
		t.Fatalf("runWhy returned %d", code)
	}
	var payload whyJSON
	decodeJSON(t, stdout, &payload)
	if len(payload.Resolved) != 1 || payload.Resolved[0].Identifier != "order.go:Submit" {
		t.Fatalf("expected bare name to resolve to order.go:Submit, got %#v", payload.Resolved)
	}
	if payload.RuleCount != 1 || payload.Rules[0].Rule.Identifier != "BR-F1" {
		t.Fatalf("expected BR-F1 bound to Submit, got %#v", payload.Rules)
	}
}

func TestRunWhyJSONByBRID(t *testing.T) {
	dbPath, repoPath := seedRuleGraphDB(t)
	code, stdout := captureStdout(t, func() int {
		return runWhy([]string{"--repo", repoPath, "--db", dbPath, "--json", "BR-F1"})
	})
	if code != 0 {
		t.Fatalf("runWhy returned %d", code)
	}
	var payload whyJSON
	decodeJSON(t, stdout, &payload)
	if len(payload.Resolved) != 1 || payload.Resolved[0].Type != "Rule" {
		t.Fatalf("expected Rule target, got %#v", payload.Resolved)
	}
	ruleIDs := map[string]bool{}
	for _, r := range payload.Rules {
		ruleIDs[r.Rule.Identifier] = true
	}
	if !ruleIDs["BR-002"] {
		t.Fatalf("expected related rule BR-002 in why payload, got %#v", payload.Rules)
	}
	if len(payload.Decisions) != 1 || payload.Decisions[0].Identifier != "ADR-TEST-A" {
		t.Fatalf("expected deciding ADR in why payload, got %#v", payload.Decisions)
	}
}

func TestRunWhyMissingRef(t *testing.T) {
	dbPath, repoPath := seedRuleGraphDB(t)
	code, _ := captureStdout(t, func() int {
		return runWhy([]string{"--repo", repoPath, "--db", dbPath, "--json", "no-such-thing.go"})
	})
	if code != 1 {
		t.Fatalf("expected exit 1 for unresolvable ref, got %d", code)
	}
}

// --- --types multi-type filter (BM25 + storage) ----------------------------

// seedTypesFilterDB writes three FTS-indexed nodes of distinct types all
// matching the token "guard".
func seedTypesFilterDB(t *testing.T) (string, string) {
	t.Helper()
	dir := t.TempDir()
	repoPath := filepath.Join(dir, "repo")
	if err := os.MkdirAll(repoPath, 0o755); err != nil {
		t.Fatal(err)
	}
	dbPath := filepath.Join(dir, "graph.db")
	db, err := storage.Open(dbPath)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	for _, n := range []struct {
		typ, identifier, text string
	}{
		{"Rule", "BR-F1", "flow guard promotion boundary"},
		{"Decision", "ADR-TEST-A", "guard decision rationale"},
		{"Chunk", "chunk:guard", "guard chunk body text"},
	} {
		id, err := db.UpsertNode(n.typ, n.identifier, map[string]any{"title": n.text})
		if err != nil {
			t.Fatal(err)
		}
		if err := db.SaveFTS(id, n.text); err != nil {
			t.Fatal(err)
		}
	}
	return dbPath, repoPath
}

func TestRunQueryJSONTypesMultiTypeBM25(t *testing.T) {
	dbPath, repoPath := seedTypesFilterDB(t)
	code, stdout := captureStdout(t, func() int {
		return runQuery([]string{
			"--repo", repoPath,
			"--db", dbPath,
			"--types", "Rule,Decision",
			"--json",
			"guard",
		})
	})
	if code != 0 {
		t.Fatalf("runQuery returned %d", code)
	}
	var payload queryJSON
	decodeJSON(t, stdout, &payload)
	if payload.Mode != "hybrid_bm25" {
		t.Fatalf("expected hybrid_bm25 mode, got %q", payload.Mode)
	}
	if payload.TypeFilter != "Rule,Decision" {
		t.Fatalf("expected joined type_filter, got %q", payload.TypeFilter)
	}
	if payload.ResultCount != 2 {
		t.Fatalf("expected exactly 2 matches (Rule + Decision), got %d", payload.ResultCount)
	}
	for _, m := range payload.Matches {
		if m.Node.Type != "Rule" && m.Node.Type != "Decision" {
			t.Fatalf("type filter leaked %q into results", m.Node.Type)
		}
	}
}

func TestRunQueryJSONSingleTypeBackCompat(t *testing.T) {
	dbPath, repoPath := seedTypesFilterDB(t)
	code, stdout := captureStdout(t, func() int {
		return runQuery([]string{
			"--repo", repoPath,
			"--db", dbPath,
			"--type", "Rule",
			"--json",
			"guard",
		})
	})
	if code != 0 {
		t.Fatalf("runQuery returned %d", code)
	}
	var payload queryJSON
	decodeJSON(t, stdout, &payload)
	if payload.ResultCount != 1 || payload.Matches[0].Node.Type != "Rule" {
		t.Fatalf("expected single Rule match via --type back-compat, got %#v", payload.Matches)
	}
}

func TestRunQueryJSONTypesSupersedesType(t *testing.T) {
	dbPath, repoPath := seedTypesFilterDB(t)
	code, stdout := captureStdout(t, func() int {
		return runQuery([]string{
			"--repo", repoPath,
			"--db", dbPath,
			"--type", "Chunk",
			"--types", "Rule,Decision",
			"--json",
			"guard",
		})
	})
	if code != 0 {
		t.Fatalf("runQuery returned %d", code)
	}
	var payload queryJSON
	decodeJSON(t, stdout, &payload)
	for _, m := range payload.Matches {
		if m.Node.Type == "Chunk" {
			t.Fatal("--types should supersede --type, but Chunk leaked through")
		}
	}
	if payload.ResultCount != 2 {
		t.Fatalf("expected 2 matches under superseding --types, got %d", payload.ResultCount)
	}
}

func TestIterateEmbeddingsMultiTypeFilter(t *testing.T) {
	dbPath, _ := seedTypesFilterDB(t)
	db, err := storage.Open(dbPath)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	for _, n := range []struct{ typ, identifier string }{
		{"Rule", "BR-F1"},
		{"Decision", "ADR-TEST-A"},
		{"Chunk", "chunk:guard"},
	} {
		id, err := db.LookupNodeID(n.typ, n.identifier)
		if err != nil {
			t.Fatal(err)
		}
		if err := db.UpdateEmbedding(id, embed.EncodeVector([]float32{0.1, 0.2}), "test-model", "sha-"+n.identifier); err != nil {
			t.Fatal(err)
		}
	}

	rows, err := db.IterateEmbeddings([]string{"Rule", "Decision"})
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 2 {
		t.Fatalf("expected 2 filtered embedding rows, got %d", len(rows))
	}
	for _, r := range rows {
		if r.Type != "Rule" && r.Type != "Decision" {
			t.Fatalf("multi-type filter leaked %q", r.Type)
		}
	}
	all, err := db.IterateEmbeddings(nil)
	if err != nil {
		t.Fatal(err)
	}
	if len(all) != 3 {
		t.Fatalf("expected 3 unfiltered embedding rows, got %d", len(all))
	}
}

// --- rule-drift SHA staleness ----------------------------------------------

func runGit(t *testing.T, dir string, args ...string) string {
	t.Helper()
	cmd := exec.Command("git", append([]string{"-C", dir}, args...)...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
	return strings.TrimSpace(string(out))
}

type ruleDriftPayload struct {
	TotalRules int `json:"total_rules"`
	DriftCount int `json:"drift_count"`
	Drifts     []struct {
		Rule         string   `json:"rule"`
		Reason       string   `json:"reason"`
		LastReviewed string   `json:"last_reviewed"`
		StaleFiles   []string `json:"stale_files"`
		NewerCommits []string `json:"newer_commits"`
	} `json:"drifts"`
}

// seedDriftDB writes three rules into dbPath: one reviewed at reviewedSHA,
// one reviewed at freshSHA, one never reviewed. Both reviewed rules carry a
// resolved implements edge onto order.go:Submit (no dangling noise).
func seedDriftDB(t *testing.T, dbPath, reviewedSHA, freshSHA string) {
	t.Helper()
	db, err := storage.Open(dbPath)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	symID, err := db.UpsertNode("Symbol", "order.go:Submit", map[string]any{
		"name":      "Submit",
		"file_path": "order.go",
	})
	if err != nil {
		t.Fatal(err)
	}
	for _, r := range []struct {
		identifier, lastReviewed string
	}{
		{"BR-STALE", reviewedSHA},
		{"BR-FRESH", freshSHA},
		{"BR-NEVER", ""},
	} {
		id, err := db.UpsertNode("Rule", r.identifier, map[string]any{
			"title":         r.identifier,
			"implements":    []string{"order.go:Submit"},
			"last_reviewed": r.lastReviewed,
		})
		if err != nil {
			t.Fatal(err)
		}
		if err := db.UpsertEdge(id, symID, "implements", nil); err != nil {
			t.Fatal(err)
		}
	}
}

func TestRunRuleDriftSHAStale(t *testing.T) {
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git not available")
	}
	dir := t.TempDir()
	repoPath := filepath.Join(dir, "repo")
	if err := os.MkdirAll(repoPath, 0o755); err != nil {
		t.Fatal(err)
	}
	runGit(t, repoPath, "init", "-q")
	runGit(t, repoPath, "config", "user.email", "test@example.com")
	runGit(t, repoPath, "config", "user.name", "aih-graph test")
	runGit(t, repoPath, "config", "commit.gpgsign", "false")
	if err := os.WriteFile(filepath.Join(repoPath, "order.go"), []byte("package order\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	runGit(t, repoPath, "add", "order.go")
	runGit(t, repoPath, "commit", "-q", "-m", "c1: add order.go")
	reviewedSHA := runGit(t, repoPath, "rev-parse", "HEAD")
	if err := os.WriteFile(filepath.Join(repoPath, "order.go"), []byte("package order\n\nfunc Submit() {}\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	runGit(t, repoPath, "add", "order.go")
	runGit(t, repoPath, "commit", "-q", "-m", "c2: change order.go")
	freshSHA := runGit(t, repoPath, "rev-parse", "HEAD")

	dbPath := filepath.Join(dir, "graph.db")
	seedDriftDB(t, dbPath, reviewedSHA, freshSHA)

	code, stdout := captureStdout(t, func() int {
		return runRuleDrift([]string{"--repo", repoPath, "--db", dbPath, "--json"})
	})
	if code != 0 {
		t.Fatalf("runRuleDrift returned %d", code)
	}
	var payload ruleDriftPayload
	decodeJSON(t, stdout, &payload)
	if payload.TotalRules != 3 {
		t.Fatalf("expected 3 rules, got %d", payload.TotalRules)
	}
	reasons := map[string]string{}
	var staleCommits []string
	var staleFiles []string
	for _, d := range payload.Drifts {
		reasons[d.Rule] = d.Reason
		if d.Rule == "BR-STALE" {
			staleCommits = d.NewerCommits
			staleFiles = d.StaleFiles
		}
	}
	if reasons["BR-STALE"] != "sha-stale" {
		t.Fatalf("expected BR-STALE flagged sha-stale, got reasons %#v", reasons)
	}
	if len(staleCommits) != 1 || !strings.Contains(staleCommits[0], "c2: change order.go") {
		t.Fatalf("expected the newer commit listed, got %#v", staleCommits)
	}
	if !reflect.DeepEqual(staleFiles, []string{"order.go"}) {
		t.Fatalf("expected bound file order.go, got %#v", staleFiles)
	}
	if _, flagged := reasons["BR-FRESH"]; flagged {
		t.Fatalf("BR-FRESH (reviewed at HEAD) must not be flagged, got reasons %#v", reasons)
	}
	if reasons["BR-NEVER"] != "never-reviewed" {
		t.Fatalf("expected BR-NEVER to keep never-reviewed behavior, got reasons %#v", reasons)
	}
	if payload.DriftCount != 2 {
		t.Fatalf("expected 2 drifts (sha-stale + never-reviewed), got %d", payload.DriftCount)
	}
}

func TestRunRuleDriftNonGitRepoDegrades(t *testing.T) {
	dir := t.TempDir()
	repoPath := filepath.Join(dir, "repo")
	if err := os.MkdirAll(repoPath, 0o755); err != nil {
		t.Fatal(err)
	}
	dbPath := filepath.Join(dir, "graph.db")
	// "abc1234" looks like a SHA but there is no git repo — the check must
	// degrade silently to never-reviewed/dangling behavior only.
	seedDriftDB(t, dbPath, "abc1234", "def5678")

	code, stdout := captureStdout(t, func() int {
		return runRuleDrift([]string{"--repo", repoPath, "--db", dbPath, "--json"})
	})
	if code != 0 {
		t.Fatalf("runRuleDrift returned %d outside a git repo", code)
	}
	var payload ruleDriftPayload
	decodeJSON(t, stdout, &payload)
	for _, d := range payload.Drifts {
		if d.Reason == "sha-stale" {
			t.Fatalf("sha-stale must not fire outside a git repo, got %#v", payload.Drifts)
		}
	}
	if payload.DriftCount != 1 || payload.Drifts[0].Rule != "BR-NEVER" {
		t.Fatalf("expected only the never-reviewed drift, got %#v", payload.Drifts)
	}
}

// --- build --user ----------------------------------------------------------

func TestRunBuildUserConsentAndSeparation(t *testing.T) {
	userHome := t.TempDir()
	xdgHome := t.TempDir()
	t.Setenv("AIH_GRAPH_USER_HOME", userHome)
	t.Setenv("AIH_GRAPH_HOME", xdgHome)
	t.Setenv("AIH_GRAPH_OLLAMA_URL", "http://127.0.0.1:9")

	marker := filepath.Join(userHome, ".aih-graph-user-consent")
	userDB := filepath.Join(userHome, "state", "user-graph.db")

	// 1. Refusal without the user-scope consent marker.
	code, _ := captureStdout(t, func() int {
		return runBuild([]string{"--user"})
	})
	if code != 2 {
		t.Fatalf("expected consent refusal (exit 2), got %d", code)
	}
	if _, err := os.Stat(marker); !os.IsNotExist(err) {
		t.Fatalf("refusal must not create the consent marker, stat err=%v", err)
	}
	if _, err := os.Stat(userDB); !os.IsNotExist(err) {
		t.Fatalf("refusal must not create the user DB, stat err=%v", err)
	}

	// Seed user memory.
	memDir := filepath.Join(userHome, "memory", "user")
	if err := os.MkdirAll(memDir, 0o755); err != nil {
		t.Fatal(err)
	}
	prefs := "# Preferences\n\n## Workflow\n\n- PREF-001 [2026-06-11] (workflow) Prefer branch then PR then merge.\n"
	if err := os.WriteFile(filepath.Join(memDir, "preferences.md"), []byte(prefs), 0o644); err != nil {
		t.Fatal(err)
	}

	// 2. --accept records consent and builds the SEPARATE user DB.
	code, _ = captureStdout(t, func() int {
		return runBuild([]string{"--user", "--accept"})
	})
	if code != 0 {
		t.Fatalf("build --user --accept returned %d", code)
	}
	if _, err := os.Stat(marker); err != nil {
		t.Fatalf("expected consent marker at %s: %v", marker, err)
	}
	if _, err := os.Stat(userDB); err != nil {
		t.Fatalf("expected user-scope DB at %s: %v", userDB, err)
	}
	// Per-repo XDG state root must absorb NOTHING (ADR-260611-E separation).
	entries, err := os.ReadDir(xdgHome)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 0 {
		t.Fatalf("per-repo state root must stay empty on --user builds, got %d entries", len(entries))
	}
	db, err := storage.Open(userDB)
	if err != nil {
		t.Fatal(err)
	}
	counts, err := db.CountByType()
	if err != nil {
		t.Fatal(err)
	}
	if err := db.Close(); err != nil {
		t.Fatal(err)
	}
	if counts["Memory"] < 1 {
		t.Fatalf("expected user Memory nodes in user-graph.db, got counts %#v", counts)
	}

	// 3. With the marker on disk, subsequent builds need no --accept.
	code, _ = captureStdout(t, func() int {
		return runBuild([]string{"--user"})
	})
	if code != 0 {
		t.Fatalf("build --user with existing marker returned %d", code)
	}

	// 4. uninstall --user purges the DB + marker (own purge path).
	code, _ = captureStdout(t, func() int {
		return runUninstall([]string{"--user"})
	})
	if code != 0 {
		t.Fatalf("uninstall --user returned %d", code)
	}
	if _, err := os.Stat(userDB); !os.IsNotExist(err) {
		t.Fatalf("expected user DB removed, stat err=%v", err)
	}
	if _, err := os.Stat(marker); !os.IsNotExist(err) {
		t.Fatalf("expected consent marker removed, stat err=%v", err)
	}
}
