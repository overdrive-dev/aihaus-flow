// Package main implements the aih-graph CLI.
//
// aih-graph is aihaus's standalone Go binary memory engine. It builds and
// queries a knowledge graph of aihaus-managed repositories with first-class
// aihaus types (Decision, Milestone, Story, Agent, Hook, Skill) plus M048
// native repository-memory nodes (File, Chunk, Symbol, Call).
//
// v0.1 forever-scope (per ADR-260515-B-amend-02 + C-amend-02 + E-amend-03,
// embedding surface narrowed per ADR-260516-A):
// Pure-Go (zero CGO) + markdown-only extraction for 6 aihaus typed nodes +
// modernc.org/sqlite storage + BM25/FTS5 lexical search + local Ollama
// nomic-embed-text embeddings + Go-native KNN + 3-mode query (BFS / semantic /
// hybrid) + 6 typed accessor structs.
// See PRD.md for full spec.
package main

import (
	"crypto/sha1"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"

	"github.com/overdrive-dev/aihaus-flow/aih-graph/internal/embed"
	"github.com/overdrive-dev/aihaus-flow/aih-graph/internal/extract"
	"github.com/overdrive-dev/aihaus-flow/aih-graph/internal/privacy"
	"github.com/overdrive-dev/aihaus-flow/aih-graph/internal/query"
	"github.com/overdrive-dev/aihaus-flow/aih-graph/internal/storage"
	"github.com/overdrive-dev/aihaus-flow/aih-graph/internal/types"
)

// version is overridden at release build via:
//
//	go build -ldflags="-X main.version=v0.1.X"
//
// (Go's -X only works on string vars, not consts — keeping this as var is
// load-bearing for release pipeline correctness.)
//
// 0.2.0: M050/S04 tier-A capability set (rule / why verbs, --types
// multi-type filter, SHA staleness in rule-drift, build --user). Flipped
// from 0.2.0-dev at S09 closeout (tag readiness — the aih-graph-v0.2.0
// tag is cut by the orchestrator after merge, BR-U4).
var version = "0.2.0"

const jsonPropertyStringLimit = 4000
const embedInputStringLimit = 4000

// usage prints the top-level CLI help.
func usage() {
	fmt.Fprintf(os.Stderr, `aih-graph %s — aihaus standalone memory engine

Usage:
  aih-graph <command> [flags]

Commands:
  build <repo-path>       Extract aihaus graph from repo
    --dry-run             Print extraction summary without persisting
    --accept-all-repos    Bypass consent gate for this run
    --user                Build the user-scope graph from ~/.aihaus/memory/user/**
                          into ~/.aihaus/state/user-graph.db (own consent marker;
                          never mixed into per-repo DBs)
    --accept              With --user: record user-scope consent (creates marker)
  refresh [--repo PATH]   Rebuild repository memory index
    --json                Print stable machine-readable output
  query "<question>"      Query the graph (default: hybrid)
    --repo PATH           Repository path for DB default and freshness checks
    --bfs                 Structural BFS only (no embeddings needed)
    --semantic            Vector similarity (cosine) ranking
    --budget N            Token cap on returned context
    --type T              Restrict to a single node type (back-compat)
    --types T1,T2         Comma-separated multi-type filter (supersedes --type)
    --json                Print stable machine-readable output
    --limit N             Maximum JSON BFS result nodes (default 80; 0 = all)
  rule <BR-id>            Show one business rule + its code bindings (implements/
                          relates/decided_by edges) and review freshness
    --json                Print stable machine-readable output
  why <ref>               Reverse lookup: rules/decisions bound to a file path,
                          symbol (file.go:Name or bare name), or BR-id
    --json                Print stable machine-readable output
  context <node-or-topic> Show exact-node neighborhood or hybrid retrieval
    --repo PATH           Repository path for DB default and freshness checks
    --json                Print stable machine-readable output
    --limit N             Maximum JSON neighborhood nodes (default 80; 0 = all)
  callers <symbol>        List call sites that target a symbol/name
    --json                Print stable machine-readable output
  impact <node>           Show graph neighborhood for impact analysis
    --repo PATH           Repository path for DB default and freshness checks
    --json                Print stable machine-readable output
    --limit N             Maximum JSON neighborhood nodes (default 80; 0 = all)
  gotchas [topic]         Search markdown memory for gotchas/learnings
    --json                Print stable machine-readable output
  milestone <target>      Search milestone, decision, commit, and memory links
    --json                Print stable machine-readable output
  status [--repo PATH]    Show memory index freshness and counts
    --json                Print stable machine-readable output
  obsidian-export         Export a read-only Obsidian markdown projection
    --repo PATH           Repository path for DB default and export metadata
    --out PATH            Output vault/folder root (default: .aihaus/state/obsidian-export)
    --include-chunks      Include Chunk nodes (off by default to avoid note floods)
    --include-calls       Include Call nodes (off by default to avoid note floods)
  rule-drift              Flag business rules that are unreviewed, have broken
                          code bindings, or are SHA-stale (bound files changed
                          since last-reviewed commit)
    --repo PATH           Repository path for DB default and git staleness checks
    --json                Print stable machine-readable output
  mark-stale [--reason R] Mark derived memory stale after repo changes
  uninstall [--purge]     Remove aih-graph state (single .db file delete)
    --user                Remove the user-scope graph (~/.aihaus/state/
                          user-graph.db) + its consent marker
  version                 Print version
  help                    Show this help

Specs:
  pkg/.aihaus/decisions.md  — ADR-260515-A through -E (+ amendments), ADR-260516-A
  aih-graph/PRD.md          — v0.1 forever-scope
`, version)
}

func openQueryDB(dbPath string) (*storage.DB, error) {
	return openQueryDBForRepo(dbPath, ".")
}

func openQueryDBForRepo(dbPath, repoPath string) (*storage.DB, error) {
	if dbPath == "" {
		if resolved, err := privacy.DefaultDBPath(repoPath); err == nil {
			dbPath = resolved
		} else {
			dbPath = "aih-graph.db"
		}
	}
	return storage.Open(dbPath)
}

func firstExistingPath(paths ...string) string {
	for _, path := range paths {
		if info, err := os.Stat(path); err == nil && !info.IsDir() {
			return path
		}
	}
	return ""
}

func resetDerivedIndex(db *storage.DB) error {
	_, err := db.SQL().Exec(`
		DELETE FROM edges;
		DELETE FROM nodes_fts;
		DELETE FROM nodes;
	`)
	return err
}

func resolveRepoPath(repoPath string) string {
	if repoPath == "" || filepath.IsAbs(repoPath) {
		return repoPath
	}
	if callerCWD := strings.TrimSpace(os.Getenv("AIH_GRAPH_CALLER_CWD")); callerCWD != "" {
		return filepath.Join(callerCWD, repoPath)
	}
	return repoPath
}

// runBuild implements the M033 build subcommand. Extracts Decision / Agent /
// Skill / Hook nodes; Milestone + Story parsers land in follow-on commits.
func runBuild(args []string) int {
	fs := flag.NewFlagSet("build", flag.ExitOnError)
	dryRun := fs.Bool("dry-run", false, "print extraction summary without persisting")
	dbPath := fs.String("db", "", "path to SQLite database file (default: XDG state dir, per-repo isolated)")
	acceptAll := fs.Bool("accept-all-repos", false, "bypass consent gate for this run")
	userScope := fs.Bool("user", false, "build the user-scope graph from ~/.aihaus/memory/user/** into ~/.aihaus/state/user-graph.db")
	acceptUser := fs.Bool("accept", false, "with --user: record user-scope consent (creates the marker)")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *userScope {
		return runBuildUser(*dbPath, *acceptUser, *dryRun)
	}
	if fs.NArg() < 1 {
		fmt.Fprintln(os.Stderr, "build: <repo-path> required")
		fmt.Fprintln(os.Stderr, "usage: aih-graph build [--db PATH] [--accept-all-repos] [--dry-run] <repo-path>")
		return 2
	}

	repoPath := resolveRepoPath(fs.Arg(0))
	decisionsPath := firstExistingPath(
		filepath.Join(repoPath, ".aihaus", "decisions.md"),
		filepath.Join(repoPath, "pkg", ".aihaus", "decisions.md"),
	)
	// Business-rules ledger — the decision-autonomy contract (ADR-260531-A).
	// Source-of-truth is the runtime ledger; absent on a fresh repo (→ 0 Rules).
	rulesPath := firstExistingPath(
		filepath.Join(repoPath, ".aihaus", "memory", "workflows", "business-rules.md"),
	)

	// Consent gate (ADR-260515-A privacy contract).
	consented, err := privacy.HasConsent(repoPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "build: consent check: %v\n", err)
		return 1
	}
	if !consented {
		if !*acceptAll {
			markerPath, _ := privacy.ConsentMarkerPath(repoPath)
			fmt.Fprintf(os.Stderr, "build: refusing — no consent marker at %s\n", markerPath)
			fmt.Fprintln(os.Stderr, "       create the marker (`touch .aih-graph-consent` at repo root) OR pass --accept-all-repos")
			return 2
		}
		fmt.Fprintf(os.Stderr, "build: consent accepted for this run (--accept-all-repos)\n")
	}

	// Resolve DB path (XDG isolation if not explicitly set).
	if *dbPath == "" {
		p, err := privacy.DefaultDBPath(repoPath)
		if err != nil {
			fmt.Fprintf(os.Stderr, "build: resolve db path: %v\n", err)
			return 1
		}
		*dbPath = p
	}

	fmt.Printf("aih-graph build %s\n", repoPath)
	fmt.Printf("  db: %s\n", *dbPath)

	// Decision (ADR) extraction.
	var decisions []types.Decision
	if decisionsPath != "" {
		decisions, err = extract.ParseDecisionsFile(decisionsPath)
		if err != nil {
			fmt.Fprintf(os.Stderr, "build: parse decisions.md: %v\n", err)
			return 1
		}
	} else {
		fmt.Fprintln(os.Stderr, "build: decisions.md not found in .aihaus/ or pkg/.aihaus/; continuing without Decision nodes")
	}
	statusCounts := map[string]int{}
	amendCount := 0
	for _, d := range decisions {
		statusCounts[d.Status]++
		if d.Amends != "" {
			amendCount++
		}
	}
	fmt.Printf("  Decisions: %d (%d are amendments)\n", len(decisions), amendCount)

	// Business-rule (contract) extraction.
	var rules []types.Rule
	if rulesPath != "" {
		rules, err = extract.ParseRulesFile(rulesPath)
		if err != nil {
			fmt.Fprintf(os.Stderr, "build: parse business-rules.md: %v\n", err)
			return 1
		}
	}
	fmt.Printf("  Rules: %d\n", len(rules))

	// Agent extraction.
	agents, err := extract.ParseAgentsDir(repoPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "build: parse agents: %v\n", err)
		return 1
	}
	modelCounts := map[string]int{}
	memoryCount := 0
	for _, a := range agents {
		modelCounts[a.Model]++
		if a.MemoryPath != "" {
			memoryCount++
		}
	}
	fmt.Printf("  Agents:    %d", len(agents))
	if len(modelCounts) > 0 {
		fmt.Print(" (")
		first := true
		for _, k := range keysSorted(modelCounts) {
			if !first {
				fmt.Print(", ")
			}
			label := k
			if label == "" {
				label = "(no model)"
			}
			fmt.Printf("%s=%d", label, modelCounts[k])
			first = false
		}
		fmt.Print(")")
	}
	if memoryCount > 0 {
		fmt.Printf(" [%d w/ memory]", memoryCount)
	}
	fmt.Println()

	// Skill extraction.
	skills, err := extract.ParseSkillsDir(repoPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "build: parse skills: %v\n", err)
		return 1
	}
	fmt.Printf("  Skills:    %d\n", len(skills))

	// Hook extraction.
	hooks, err := extract.ParseHooksDir(repoPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "build: parse hooks: %v\n", err)
		return 1
	}
	totalFns := 0
	for _, h := range hooks {
		totalFns += len(h.Functions)
	}
	fmt.Printf("  Hooks:     %d (%d declared functions)\n", len(hooks), totalFns)

	// Milestone + Story extraction. .aihaus/milestones/ may not exist (fresh
	// install or runtime artifacts purged); parsers return empty slices.
	milestones, stories, err := extract.ParseMilestonesDir(repoPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "build: parse milestones: %v\n", err)
		return 1
	}
	fmt.Printf("  Milestones: %d\n", len(milestones))
	fmt.Printf("  Stories:    %d\n", len(stories))

	// M048: generic repository file/chunk extraction. This is the first
	// native codebase-memory layer; parser-backed symbols land in follow-up
	// stories.
	repoFiles, repoChunks, err := extract.ParseRepositoryText(repoPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "build: parse repository text: %v\n", err)
		return 1
	}
	fmt.Printf("  Files:      %d\n", len(repoFiles))
	fmt.Printf("  Chunks:     %d\n", len(repoChunks))
	repoSymbols, repoCalls, err := extract.ParseRepositorySymbols(repoPath, repoFiles)
	if err != nil {
		fmt.Fprintf(os.Stderr, "build: parse repository symbols: %v\n", err)
		return 1
	}
	fmt.Printf("  Symbols:    %d\n", len(repoSymbols))
	fmt.Printf("  Calls:      %d\n", len(repoCalls))
	repoTests, err := extract.ParseRepositoryTests(repoPath, repoFiles, repoSymbols)
	if err != nil {
		fmt.Fprintf(os.Stderr, "build: parse repository tests: %v\n", err)
		return 1
	}
	memories, err := extract.ParseMarkdownMemory(repoPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "build: parse markdown memory: %v\n", err)
		return 1
	}
	commits, err := extract.ParseGitCommits(repoPath, 200)
	if err != nil {
		fmt.Fprintf(os.Stderr, "build: parse git commits: %v\n", err)
		return 1
	}
	fmt.Printf("  Tests:      %d\n", len(repoTests))
	fmt.Printf("  Memories:   %d\n", len(memories))
	fmt.Printf("  Commits:    %d\n", len(commits))

	// Status breakdown for Decisions (most informative type-level summary).
	fmt.Println()
	fmt.Println("  Decisions by status:")
	for _, s := range keysSorted(statusCounts) {
		label := s
		if label == "" {
			label = "(no Status field)"
		}
		fmt.Printf("    %-50s %d\n", label, statusCounts[s])
	}

	fmt.Println()
	if *dryRun {
		fmt.Println("(dry-run: nothing persisted)")
		return 0
	}

	// M034: persist via modernc/sqlite.
	db, err := storage.Open(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "build: open db %s: %v\n", *dbPath, err)
		return 1
	}
	defer db.Close()
	if err := resetDerivedIndex(db); err != nil {
		fmt.Fprintf(os.Stderr, "build: reset derived index: %v\n", err)
		return 1
	}

	persisted := 0
	for _, d := range decisions {
		props := map[string]any{
			"title":     d.Title,
			"status":    d.Status,
			"date":      d.Date,
			"milestone": d.Milestone,
			"amends":    d.Amends,
			"body":      d.Body,
		}
		if _, err := db.UpsertNode("Decision", d.Identifier, props); err != nil {
			fmt.Fprintf(os.Stderr, "build: upsert decision %s: %v\n", d.Identifier, err)
			return 1
		}
		persisted++
	}
	for _, a := range agents {
		if _, err := db.UpsertNode("Agent", a.Name, agentProps(a)); err != nil {
			fmt.Fprintf(os.Stderr, "build: upsert agent %s: %v\n", a.Name, err)
			return 1
		}
		persisted++
	}
	for _, s := range skills {
		props := map[string]any{
			"description":              s.Description,
			"disable_model_invocation": s.DisableModelInvocation,
			"allowed_tools":            s.AllowedTools,
			"argument_hint":            s.ArgumentHint,
		}
		if _, err := db.UpsertNode("Skill", s.Name, props); err != nil {
			fmt.Fprintf(os.Stderr, "build: upsert skill %s: %v\n", s.Name, err)
			return 1
		}
		persisted++
	}
	for _, h := range hooks {
		props := map[string]any{
			"path":       h.Path,
			"purpose":    h.Purpose,
			"functions":  h.Functions,
			"size_bytes": h.SizeBytes,
		}
		if _, err := db.UpsertNode("Hook", h.Name, props); err != nil {
			fmt.Fprintf(os.Stderr, "build: upsert hook %s: %v\n", h.Name, err)
			return 1
		}
		persisted++
	}
	for _, m := range milestones {
		props := map[string]any{
			"slug":         m.Slug,
			"status":       m.Status,
			"phase":        m.Phase,
			"pause_class":  m.PauseClass,
			"last_updated": m.LastUpdated,
		}
		identifier := m.ID
		if identifier == "" {
			identifier = m.Slug
		}
		if _, err := db.UpsertNode("Milestone", identifier, props); err != nil {
			fmt.Fprintf(os.Stderr, "build: upsert milestone %s: %v\n", identifier, err)
			return 1
		}
		persisted++
	}
	for _, s := range stories {
		props := map[string]any{
			"milestone_id": s.MilestoneID,
			"summary":      s.Summary,
			"status":       s.Status,
			"owned_files":  s.OwnedFiles,
		}
		identifier := s.MilestoneID + "/" + s.ID
		if _, err := db.UpsertNode("Story", identifier, props); err != nil {
			fmt.Fprintf(os.Stderr, "build: upsert story %s: %v\n", identifier, err)
			return 1
		}
		persisted++
	}
	for _, f := range repoFiles {
		if _, err := db.UpsertNode("File", f.Path, repoFileProps(f)); err != nil {
			fmt.Fprintf(os.Stderr, "build: upsert file %s: %v\n", f.Path, err)
			return 1
		}
		persisted++
	}
	for _, c := range repoChunks {
		if _, err := db.UpsertNode("Chunk", c.Identifier, repoChunkProps(c)); err != nil {
			fmt.Fprintf(os.Stderr, "build: upsert chunk %s: %v\n", c.Identifier, err)
			return 1
		}
		persisted++
	}
	for _, s := range repoSymbols {
		if _, err := db.UpsertNode("Symbol", s.Identifier, repoSymbolProps(s)); err != nil {
			fmt.Fprintf(os.Stderr, "build: upsert symbol %s: %v\n", s.Identifier, err)
			return 1
		}
		persisted++
	}
	for _, c := range repoCalls {
		if _, err := db.UpsertNode("Call", c.Identifier, repoCallProps(c)); err != nil {
			fmt.Fprintf(os.Stderr, "build: upsert call %s: %v\n", c.Identifier, err)
			return 1
		}
		persisted++
	}
	for _, t := range repoTests {
		if _, err := db.UpsertNode("Test", t.Identifier, repoTestProps(t)); err != nil {
			fmt.Fprintf(os.Stderr, "build: upsert test %s: %v\n", t.Identifier, err)
			return 1
		}
		persisted++
	}
	for _, m := range memories {
		if _, err := db.UpsertNode("Memory", m.Identifier, memoryProps(m)); err != nil {
			fmt.Fprintf(os.Stderr, "build: upsert memory %s: %v\n", m.Identifier, err)
			return 1
		}
		persisted++
	}
	for _, c := range commits {
		if _, err := db.UpsertNode("Commit", c.Hash, commitProps(c)); err != nil {
			fmt.Fprintf(os.Stderr, "build: upsert commit %s: %v\n", c.Hash, err)
			return 1
		}
		persisted++
	}
	for _, r := range rules {
		if _, err := db.UpsertNode("Rule", r.Identifier, ruleProps(r)); err != nil {
			fmt.Fprintf(os.Stderr, "build: upsert rule %s: %v\n", r.Identifier, err)
			return 1
		}
		persisted++
	}

	// Edge derivation: Decision.Amends → Decision-[amends]→Decision;
	// Story.MilestoneID → Story-[in_milestone]→Milestone. More edge types
	// (Hook-[invoked_by]→Skill, Agent-[spawned_by]→Skill, ...) land in M035.
	edgesAdded := 0
	for _, d := range decisions {
		if d.Amends == "" {
			continue
		}
		fromID, err := db.LookupNodeID("Decision", d.Identifier)
		if err != nil {
			continue
		}
		// Amends value may be "ADR-260515-C" or longer prose; try direct lookup.
		toID, err := db.LookupNodeID("Decision", d.Amends)
		if err != nil {
			continue
		}
		if err := db.UpsertEdge(fromID, toID, "amends", nil); err == nil {
			edgesAdded++
		}
	}
	for _, s := range stories {
		if s.MilestoneID == "" || s.ID == "" {
			continue
		}
		fromID, err := db.LookupNodeID("Story", s.MilestoneID+"/"+s.ID)
		if err != nil {
			continue
		}
		toID, err := db.LookupNodeID("Milestone", s.MilestoneID)
		if err != nil {
			continue
		}
		if err := db.UpsertEdge(fromID, toID, "in_milestone", nil); err == nil {
			edgesAdded++
		}
	}

	// Rule edges (ADR-260531-A): Rule-[implements]→Symbol|File|Test;
	// Rule-[relates]→Rule; Rule-[decided_by]→Decision. implements: refs are
	// best-effort exact-id matches (symbols are "<relpath>:<name>", files are
	// "<relpath>"); unresolved refs are skipped, never errors.
	for _, r := range rules {
		fromID, err := db.LookupNodeID("Rule", r.Identifier)
		if err != nil {
			continue
		}
		for _, ref := range r.Implements {
			if toID, ok := lookupCodeRef(db, ref); ok {
				if err := db.UpsertEdge(fromID, toID, "implements", nil); err == nil {
					edgesAdded++
				}
			}
		}
		for _, ref := range r.Relates {
			if toID, err := db.LookupNodeID("Rule", ref); err == nil {
				if err := db.UpsertEdge(fromID, toID, "relates", nil); err == nil {
					edgesAdded++
				}
			}
		}
		for _, ref := range r.DecidedBy {
			if toID, err := db.LookupNodeID("Decision", ref); err == nil {
				if err := db.UpsertEdge(fromID, toID, "decided_by", nil); err == nil {
					edgesAdded++
				}
			}
		}
	}

	for _, c := range repoChunks {
		fromID, err := db.LookupNodeID("File", c.FilePath)
		if err != nil {
			continue
		}
		toID, err := db.LookupNodeID("Chunk", c.Identifier)
		if err != nil {
			continue
		}
		if err := db.UpsertEdge(fromID, toID, "contains", nil); err == nil {
			edgesAdded++
		}
	}
	for _, s := range repoSymbols {
		fromID, err := db.LookupNodeID("File", s.FilePath)
		if err != nil {
			continue
		}
		toID, err := db.LookupNodeID("Symbol", s.Identifier)
		if err != nil {
			continue
		}
		if err := db.UpsertEdge(fromID, toID, "defines", nil); err == nil {
			edgesAdded++
		}
	}
	for _, c := range repoCalls {
		fromID, err := db.LookupNodeID("Symbol", c.CallerIdentifier)
		if err == nil {
			if toID, err := db.LookupNodeID("Call", c.Identifier); err == nil {
				if err := db.UpsertEdge(fromID, toID, "calls", nil); err == nil {
					edgesAdded++
				}
			}
		}
		if c.CalleeIdentifier != "" {
			fromID, err := db.LookupNodeID("Symbol", c.CallerIdentifier)
			if err != nil {
				continue
			}
			toID, err := db.LookupNodeID("Symbol", c.CalleeIdentifier)
			if err != nil {
				continue
			}
			if err := db.UpsertEdge(fromID, toID, "calls", nil); err == nil {
				edgesAdded++
			}
		}
	}
	for _, t := range repoTests {
		testID, err := db.LookupNodeID("Test", t.Identifier)
		if err != nil {
			continue
		}
		if fromID, err := db.LookupNodeID("File", t.FilePath); err == nil {
			if err := db.UpsertEdge(fromID, testID, "defines", nil); err == nil {
				edgesAdded++
			}
		}
		if t.TargetFilePath != "" {
			if targetID, err := db.LookupNodeID("File", t.TargetFilePath); err == nil {
				if err := db.UpsertEdge(testID, targetID, "tests", nil); err == nil {
					edgesAdded++
				}
			}
		}
		if t.TargetSymbolIdentifier != "" {
			if targetID, err := db.LookupNodeID("Symbol", t.TargetSymbolIdentifier); err == nil {
				if err := db.UpsertEdge(testID, targetID, "tests", nil); err == nil {
					edgesAdded++
				}
			}
		}
	}
	for _, m := range memories {
		fromID, err := db.LookupNodeID("File", m.FilePath)
		if err != nil {
			continue
		}
		toID, err := db.LookupNodeID("Memory", m.Identifier)
		if err != nil {
			continue
		}
		if err := db.UpsertEdge(fromID, toID, "contains", nil); err == nil {
			edgesAdded++
		}
	}
	for _, c := range commits {
		fromID, err := db.LookupNodeID("Commit", c.Hash)
		if err != nil {
			continue
		}
		for _, path := range c.Files {
			toID, err := db.LookupNodeID("File", path)
			if err != nil {
				continue
			}
			if err := db.UpsertEdge(fromID, toID, "touches", nil); err == nil {
				edgesAdded++
			}
		}
	}

	// Persistence summary.
	counts, err := db.CountByType()
	if err != nil {
		fmt.Fprintf(os.Stderr, "build: count: %v\n", err)
		return 1
	}
	fmt.Printf("Persisted %d nodes to %s\n", persisted, *dbPath)
	for _, t := range keysSorted(counts) {
		fmt.Printf("  %s: %d\n", t, counts[t])
	}
	if edgesAdded > 0 {
		edgeCounts, _ := db.CountEdges()
		fmt.Printf("Edges: %d new this run\n", edgesAdded)
		for _, t := range keysSorted(edgeCounts) {
			fmt.Printf("  %s: %d\n", t, edgeCounts[t])
		}
	}

	// Search pipeline: BM25 is always refreshed; Ollama/nomic embeddings are
	// added when the local server is available.
	if err := runBM25Pipeline(db, decisions, agents, skills, hooks, milestones, stories, repoFiles, repoChunks, repoSymbols, repoCalls, repoTests, memories, commits, rules); err != nil {
		fmt.Fprintf(os.Stderr, "build: bm25: %v\n", err)
		return 1
	}
	runOllamaEmbeddingPipeline(db, decisions, agents, skills, hooks, milestones, stories, repoFiles, repoChunks, repoSymbols, repoCalls, repoTests, memories, commits, rules)
	clearStaleMarker(repoPath)
	return 0
}

// runBuildUser implements `build --user` (M050/S04, ADR-260611-A tier C /
// ADR-260611-E §3): indexes ~/.aihaus/memory/user/** into the SEPARATE
// user-scope graph at ~/.aihaus/state/user-graph.db. The user scope carries
// its OWN consent marker (~/.aihaus/.aih-graph-user-consent) and its OWN
// purge path (`uninstall --user`). Per-repo DBs NEVER absorb cross-repo or
// user-scope data — the ADR-260515-A privacy contract is preserved by
// construction (separate source dir, separate DB, separate consent).
func runBuildUser(dbPath string, accept, dryRun bool) int {
	consented, err := privacy.HasUserConsent()
	if err != nil {
		fmt.Fprintf(os.Stderr, "build --user: consent check: %v\n", err)
		return 1
	}
	if !consented {
		if !accept {
			markerPath, _ := privacy.UserConsentMarkerPath()
			fmt.Fprintf(os.Stderr, "build --user: refusing — no user-scope consent marker at %s\n", markerPath)
			fmt.Fprintln(os.Stderr, "             create the marker manually OR pass --accept (records consent)")
			return 2
		}
		if err := privacy.CreateUserConsent(); err != nil {
			fmt.Fprintf(os.Stderr, "build --user: record consent: %v\n", err)
			return 1
		}
		markerPath, _ := privacy.UserConsentMarkerPath()
		fmt.Fprintf(os.Stderr, "build --user: consent recorded at %s\n", markerPath)
	}

	if dbPath == "" {
		dbPath, err = privacy.UserDBPath()
		if err != nil {
			fmt.Fprintf(os.Stderr, "build --user: resolve user db path: %v\n", err)
			return 1
		}
	}
	userRoot, err := privacy.UserMemoryRoot()
	if err != nil {
		fmt.Fprintf(os.Stderr, "build --user: resolve user memory root: %v\n", err)
		return 1
	}
	memories, err := extract.ParseUserMemoryDir(userRoot)
	if err != nil {
		fmt.Fprintf(os.Stderr, "build --user: parse user memory: %v\n", err)
		return 1
	}

	fmt.Println("aih-graph build --user")
	fmt.Printf("  source: %s\n", userRoot)
	fmt.Printf("  db: %s\n", dbPath)
	fmt.Printf("  Memories: %d\n", len(memories))
	if dryRun {
		fmt.Println("(dry-run: nothing persisted)")
		return 0
	}

	db, err := storage.Open(dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "build --user: open db %s: %v\n", dbPath, err)
		return 1
	}
	defer db.Close()
	if err := resetDerivedIndex(db); err != nil {
		fmt.Fprintf(os.Stderr, "build --user: reset derived index: %v\n", err)
		return 1
	}
	persisted := 0
	for _, m := range memories {
		if _, err := db.UpsertNode("Memory", m.Identifier, memoryProps(m)); err != nil {
			fmt.Fprintf(os.Stderr, "build --user: upsert memory %s: %v\n", m.Identifier, err)
			return 1
		}
		persisted++
	}
	fmt.Printf("Persisted %d nodes to %s\n", persisted, dbPath)

	// Same search pipeline as repo builds: BM25 always; Ollama embeddings when
	// the local server is available. Only the memories slice is populated.
	if err := runBM25Pipeline(db, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, memories, nil, nil); err != nil {
		fmt.Fprintf(os.Stderr, "build --user: bm25: %v\n", err)
		return 1
	}
	runOllamaEmbeddingPipeline(db, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, memories, nil, nil)
	return 0
}

func runRefresh(args []string) int {
	fs := flag.NewFlagSet("refresh", flag.ExitOnError)
	repoPath := fs.String("repo", ".", "repository path")
	dbPath := fs.String("db", "", "path to SQLite database file")
	acceptAll := fs.Bool("accept-all-repos", false, "bypass consent gate")
	jsonOut := fs.Bool("json", false, "print stable machine-readable output")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if fs.NArg() > 0 {
		*repoPath = fs.Arg(0)
	}
	*repoPath = resolveRepoPath(*repoPath)
	resolvedDB := *dbPath
	if resolvedDB == "" {
		p, err := privacy.DefaultDBPath(*repoPath)
		if err != nil {
			fmt.Fprintf(os.Stderr, "refresh: resolve db path: %v\n", err)
			return 1
		}
		resolvedDB = p
	}
	buildArgs := []string{"--db", resolvedDB}
	if *acceptAll {
		buildArgs = append(buildArgs, "--accept-all-repos")
	}
	buildArgs = append(buildArgs, *repoPath)
	if !*jsonOut {
		return runBuild(buildArgs)
	}
	code := runWithStdoutDiscard(func() int {
		return runBuild(buildArgs)
	})
	if code != 0 {
		return code
	}
	status, err := collectStatusJSON(*repoPath, resolvedDB)
	if err != nil {
		fmt.Fprintf(os.Stderr, "refresh: %v\n", err)
		return 1
	}
	return writeJSON(refreshJSON{
		Command: "refresh",
		Status:  status,
	})
}

// runBM25Pipeline writes one FTS5 row per node. Per-node text is the same
// text used for vector embeddings (same embedTextFor* helpers), so
// the lexical search is over the same canonical content. SaveFTS is idempotent
// (delete-then-insert by rowid) so re-runs are safe.
func runBM25Pipeline(
	db *storage.DB,
	decisions []types.Decision,
	agents []types.Agent,
	skills []types.Skill,
	hooks []types.Hook,
	milestones []types.Milestone,
	stories []types.Story,
	repoFiles []types.RepoFile,
	repoChunks []types.RepoChunk,
	repoSymbols []types.RepoSymbol,
	repoCalls []types.RepoCall,
	repoTests []types.RepoTest,
	memories []types.MarkdownMemory,
	commits []types.RepoCommit,
	rules []types.Rule,
) error {
	type unit struct{ typ, identifier, text string }
	var units []unit
	for _, d := range decisions {
		units = append(units, unit{"Decision", d.Identifier, embedTextForDecision(d)})
	}
	for _, a := range agents {
		units = append(units, unit{"Agent", a.Name, embedTextForAgent(a)})
	}
	for _, s := range skills {
		units = append(units, unit{"Skill", s.Name, embedTextForSkill(s)})
	}
	for _, h := range hooks {
		units = append(units, unit{"Hook", h.Name, embedTextForHook(h)})
	}
	for _, m := range milestones {
		id := m.ID
		if id == "" {
			id = m.Slug
		}
		units = append(units, unit{"Milestone", id, embedTextForMilestone(m)})
	}
	for _, s := range stories {
		units = append(units, unit{"Story", s.MilestoneID + "/" + s.ID, embedTextForStory(s)})
	}
	for _, f := range repoFiles {
		units = append(units, unit{"File", f.Path, embedTextForRepoFile(f)})
	}
	for _, c := range repoChunks {
		units = append(units, unit{"Chunk", c.Identifier, embedTextForRepoChunk(c)})
	}
	for _, s := range repoSymbols {
		units = append(units, unit{"Symbol", s.Identifier, embedTextForRepoSymbol(s)})
	}
	for _, c := range repoCalls {
		units = append(units, unit{"Call", c.Identifier, embedTextForRepoCall(c)})
	}
	for _, t := range repoTests {
		units = append(units, unit{"Test", t.Identifier, embedTextForRepoTest(t)})
	}
	for _, m := range memories {
		units = append(units, unit{"Memory", m.Identifier, embedTextForMemory(m)})
	}
	for _, c := range commits {
		units = append(units, unit{"Commit", c.Hash, embedTextForCommit(c)})
	}
	for _, r := range rules {
		units = append(units, unit{"Rule", r.Identifier, embedTextForRule(r)})
	}

	indexed, errs := 0, 0
	for _, u := range units {
		nodeID, err := db.LookupNodeID(u.typ, u.identifier)
		if err != nil {
			errs++
			continue
		}
		if err := db.SaveFTS(nodeID, u.text); err != nil {
			errs++
			continue
		}
		indexed++
	}
	total, _ := db.CountFTS()
	fmt.Printf("Indexed %d nodes via BM25/FTS5 (%d total rows; %d errors)\n", indexed, total, errs)
	return nil
}

// embedTextForDecision returns the text aih-graph embeds for each Decision
// node. We include the title + status + body so vector queries can match
// against the actual decision narrative.
func embedTextForDecision(d types.Decision) string {
	return d.Identifier + "\n" + d.Title + "\n" + d.Status + "\n" + d.Body
}

func embedTextForRule(r types.Rule) string {
	return r.Identifier + "\n" + r.Title + "\n" + r.Domain + "\n" + r.Statement + "\n" + r.Body
}

func embedTextForAgent(a types.Agent) string {
	return a.Name + "\n" + a.Description + "\n" + a.MemoryPath + "\n" + a.MemoryExcerpt
}

func embedTextForSkill(s types.Skill) string {
	return s.Name + "\n" + s.Description
}

func embedTextForHook(h types.Hook) string {
	return h.Name + "\n" + h.Purpose
}

func embedTextForMilestone(m types.Milestone) string {
	return m.ID + "\n" + m.Slug + "\n" + m.Status + "\n" + m.Phase
}

func embedTextForStory(s types.Story) string {
	return s.MilestoneID + "/" + s.ID + "\n" + s.Status + "\n" + s.Summary
}

func embedTextForRepoFile(f types.RepoFile) string {
	return f.Path + "\n" + f.Language + "\n" + f.Extension
}

func embedTextForRepoChunk(c types.RepoChunk) string {
	return c.FilePath + "\n" + c.Identifier + "\n" + c.Text
}

func embedTextForRepoSymbol(s types.RepoSymbol) string {
	return s.Identifier + "\n" + s.Name + "\n" + s.Kind + "\n" + s.Signature + "\n" + s.FilePath
}

func embedTextForRepoCall(c types.RepoCall) string {
	return c.Identifier + "\n" + c.CallerIdentifier + "\n" + c.CalleeName + "\n" + c.CalleeQualifier + "\n" + c.FilePath
}

func embedTextForRepoTest(t types.RepoTest) string {
	return t.Identifier + "\n" + t.Name + "\n" + t.Kind + "\n" + t.FilePath + "\n" + t.TargetFilePath + "\n" + t.TargetSymbolIdentifier
}

func embedTextForMemory(m types.MarkdownMemory) string {
	return m.Identifier + "\n" + m.Category + "\n" + m.FilePath + "\n" + m.Heading + "\n" + m.Body
}

func embedTextForCommit(c types.RepoCommit) string {
	return c.ShortHash + "\n" + c.AuthorDate + "\n" + c.Subject + "\n" + strings.Join(c.Files, "\n")
}

func embedInputText(text string) string {
	return truncateJSONString(text, embedInputStringLimit)
}

func runOllamaEmbeddingPipeline(
	db *storage.DB,
	decisions []types.Decision,
	agents []types.Agent,
	skills []types.Skill,
	hooks []types.Hook,
	milestones []types.Milestone,
	stories []types.Story,
	repoFiles []types.RepoFile,
	repoChunks []types.RepoChunk,
	repoSymbols []types.RepoSymbol,
	repoCalls []types.RepoCall,
	repoTests []types.RepoTest,
	memories []types.MarkdownMemory,
	commits []types.RepoCommit,
	rules []types.Rule,
) {
	embedder, err := embed.NewOllamaEmbedder(embed.OllamaOptions{})
	if err != nil {
		fmt.Fprintf(os.Stderr, "build: Ollama embeddings skipped: %v\n", err)
		return
	}
	if _, err := embedder.Embed("aih-graph readiness check"); err != nil {
		fmt.Fprintf(os.Stderr, "build: Ollama embeddings skipped: %v\n", err)
		return
	}
	if err := runEmbedPipeline(db, embedder, decisions, agents, skills, hooks, milestones, stories, repoFiles, repoChunks, repoSymbols, repoCalls, repoTests, memories, commits, rules); err != nil {
		fmt.Fprintf(os.Stderr, "build: embed: %v\n", err)
	}
}

// runEmbedPipeline iterates extracted nodes and writes embeddings + content
// SHAs onto the persisted rows. SHA-based change detection skips nodes whose
// stored content_sha already matches the current text.
func runEmbedPipeline(
	db *storage.DB,
	embedder embed.Embedder,
	decisions []types.Decision,
	agents []types.Agent,
	skills []types.Skill,
	hooks []types.Hook,
	milestones []types.Milestone,
	stories []types.Story,
	repoFiles []types.RepoFile,
	repoChunks []types.RepoChunk,
	repoSymbols []types.RepoSymbol,
	repoCalls []types.RepoCall,
	repoTests []types.RepoTest,
	memories []types.MarkdownMemory,
	commits []types.RepoCommit,
	rules []types.Rule,
) error {
	type unit struct {
		typ        string
		identifier string
		text       string
	}
	var units []unit
	for _, d := range decisions {
		units = append(units, unit{"Decision", d.Identifier, embedTextForDecision(d)})
	}
	for _, a := range agents {
		units = append(units, unit{"Agent", a.Name, embedTextForAgent(a)})
	}
	for _, s := range skills {
		units = append(units, unit{"Skill", s.Name, embedTextForSkill(s)})
	}
	for _, h := range hooks {
		units = append(units, unit{"Hook", h.Name, embedTextForHook(h)})
	}
	for _, m := range milestones {
		id := m.ID
		if id == "" {
			id = m.Slug
		}
		units = append(units, unit{"Milestone", id, embedTextForMilestone(m)})
	}
	for _, s := range stories {
		units = append(units, unit{"Story", s.MilestoneID + "/" + s.ID, embedTextForStory(s)})
	}
	for _, f := range repoFiles {
		units = append(units, unit{"File", f.Path, embedTextForRepoFile(f)})
	}
	for _, c := range repoChunks {
		units = append(units, unit{"Chunk", c.Identifier, embedTextForRepoChunk(c)})
	}
	for _, s := range repoSymbols {
		units = append(units, unit{"Symbol", s.Identifier, embedTextForRepoSymbol(s)})
	}
	for _, c := range repoCalls {
		units = append(units, unit{"Call", c.Identifier, embedTextForRepoCall(c)})
	}
	for _, t := range repoTests {
		units = append(units, unit{"Test", t.Identifier, embedTextForRepoTest(t)})
	}
	for _, m := range memories {
		units = append(units, unit{"Memory", m.Identifier, embedTextForMemory(m)})
	}
	for _, c := range commits {
		units = append(units, unit{"Commit", c.Hash, embedTextForCommit(c)})
	}
	for _, r := range rules {
		units = append(units, unit{"Rule", r.Identifier, embedTextForRule(r)})
	}

	embedded, skipped, errs := 0, 0, 0
	for _, u := range units {
		nodeID, err := db.LookupNodeID(u.typ, u.identifier)
		if err != nil {
			errs++
			continue
		}
		sha := embed.SHA256Hex(u.text)
		// Skip if existing SHA matches (content unchanged).
		if existing, _ := db.EmbeddingSHA(nodeID); existing == sha {
			skipped++
			continue
		}
		vec, err := embedder.Embed(embedInputText(u.text))
		if err != nil {
			fmt.Fprintf(os.Stderr, "  embed: skip %s %s: %v\n", u.typ, u.identifier, err)
			errs++
			continue
		}
		if err := db.UpdateEmbedding(nodeID, embed.EncodeVector(vec), embedder.Model(), sha); err != nil {
			errs++
			continue
		}
		embedded++
	}
	fmt.Printf("Embedded %d nodes (%s; %d skipped — SHA match; %d errors)\n",
		embedded, embedder.Model(), skipped, errs)
	return nil
}

// runQuery implements the M035 query subcommand. BFS (structural) and
// --semantic (vector similarity) supported. Hybrid query (SQL pre-filter +
// vector ranking + edge expansion) lands in subsequent M035 commit.
func runQuery(args []string) int {
	fs := flag.NewFlagSet("query", flag.ExitOnError)
	dbPath := fs.String("db", "", "path to SQLite database (default: privacy.DefaultDBPath for cwd, matching `build`)")
	repoPath := fs.String("repo", ".", "repository path for DB default and freshness checks")
	bfs := fs.Bool("bfs", false, "structural BFS query over an exact node identifier")
	semantic := fs.Bool("semantic", false, "vector similarity (cosine) ranking — pure KNN")
	hybrid := fs.Bool("hybrid", false, "hybrid mode: KNN top-K + 1-hop edge expansion per match")
	depth := fs.Int("depth", 1, "BFS depth (hops outward from root)")
	typ := fs.String("type", "", "restrict root match (BFS) or candidate type (semantic/hybrid) to a node type")
	typesCSV := fs.String("types", "", "comma-separated multi-type filter (e.g. Rule,Decision); supersedes --type")
	topK := fs.Int("top", 10, "semantic/hybrid: number of top matches to return")
	limit := fs.Int("limit", 80, "maximum JSON BFS result nodes (0 = no limit)")
	jsonOut := fs.Bool("json", false, "print stable machine-readable output")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if fs.NArg() < 1 {
		fmt.Fprintln(os.Stderr, "query: <identifier-or-text> required")
		fmt.Fprintln(os.Stderr, "usage: aih-graph query [--bfs|--semantic|--hybrid] [--type T] [--types T1,T2] [--depth N] [--top K] [--repo PATH] [--db PATH] [--json] <identifier-or-text>")
		return 2
	}
	// Default mode: hybrid free-text retrieval; exact graph traversal is
	// explicit via --bfs.
	if !*semantic && !*bfs && !*hybrid {
		*hybrid = true
	}
	typeFilters := splitTypesFilter(*typesCSV, *typ)

	*repoPath = resolveRepoPath(*repoPath)
	freshness := loadMemoryFreshness(*repoPath)
	db, err := openQueryDBForRepo(*dbPath, *repoPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "query: open db: %v\n", err)
		return 1
	}
	defer db.Close()

	if *hybrid {
		if *jsonOut {
			return runQueryHybridJSON(db, fs.Arg(0), typeFilters, *topK, freshness)
		}
		return runHybrid(db, fs.Arg(0), typeFilters, *topK)
	}
	if *semantic {
		if *jsonOut {
			return runQuerySemanticJSON(db, fs.Arg(0), typeFilters, *topK, freshness)
		}
		return runSemantic(db, fs.Arg(0), typeFilters, *topK)
	}

	// BFS mode: the root match is a single (type, identifier) lookup — a
	// multi-type filter does not map onto it.
	if len(typeFilters) > 1 {
		fmt.Fprintln(os.Stderr, "query: --types with multiple types is not supported in --bfs mode (use --type T)")
		return 2
	}
	bfsType := ""
	if len(typeFilters) == 1 {
		bfsType = typeFilters[0]
	}
	identifier := fs.Arg(0)
	eng := query.New(db.SQL())
	results, err := eng.BFS(bfsType, identifier, *depth)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			fmt.Fprintf(os.Stderr, "query: no node matches identifier %q (type filter=%q)\n", identifier, bfsType)
			return 1
		}
		fmt.Fprintf(os.Stderr, "query: %v\n", err)
		return 1
	}

	if *jsonOut {
		resultsJSON, truncated := bfsForJSON(results, *limit)
		return writeJSON(queryJSON{
			Command:          "query",
			Query:            identifier,
			Mode:             "bfs",
			TypeFilter:       strings.Join(typeFilters, ","),
			Depth:            *depth,
			Freshness:        freshness,
			ResultCount:      len(resultsJSON),
			Results:          resultsJSON,
			ResultsTotal:     len(results),
			ResultsReturned:  len(resultsJSON),
			ResultsTruncated: truncated,
		})
	}
	for _, r := range results {
		title := titleFromProperties(r.Node.Properties)
		if len(title) > 80 {
			title = title[:77] + "..."
		}
		fmt.Printf("[d=%d] %-10s %-40s %s\n", r.Distance, r.Node.Type, r.Node.Identifier, title)
	}
	return 0
}

// splitTypesFilter merges the `--types` (comma-separated, supersedes) and
// `--type` (single value, back-compat) flags into a normalized type-filter
// slice. nil means "no filter" (scan all types).
func splitTypesFilter(typesCSV, single string) []string {
	if strings.TrimSpace(typesCSV) != "" {
		var out []string
		for _, t := range strings.Split(typesCSV, ",") {
			if t = strings.TrimSpace(t); t != "" {
				out = append(out, t)
			}
		}
		return out
	}
	if t := strings.TrimSpace(single); t != "" {
		return []string{t}
	}
	return nil
}

// runSemantic executes a --semantic query. It uses stored Ollama embeddings
// when available, otherwise falls back to BM25/FTS5 lexical ranking.
func runSemantic(db *storage.DB, queryText string, typeFilters []string, topK int) int {
	rows, err := db.IterateEmbeddings(typeFilters)
	if err != nil {
		fmt.Fprintf(os.Stderr, "query: scan embeddings: %v\n", err)
		return 1
	}
	if len(rows) == 0 {
		return runSemanticBM25(db, queryText, typeFilters, topK)
	}
	embedder, err := resolveEmbedder()
	if err != nil {
		fmt.Fprintf(os.Stderr, "query: %v\n", err)
		return runSemanticBM25(db, queryText, typeFilters, topK)
	}

	queryVec, err := embedder.Embed(embedInputText(queryText))
	if err != nil {
		fmt.Fprintf(os.Stderr, "query: embed query: %v\n", err)
		return runSemanticBM25(db, queryText, typeFilters, topK)
	}

	candidates := make([]embed.Candidate, 0, len(rows))
	idMap := map[int64]struct {
		typ, identifier string
	}{}
	for _, r := range rows {
		candidates = append(candidates, embed.Candidate{
			NodeID:    r.NodeID,
			Embedding: embed.DecodeVector(r.Embedding),
		})
		idMap[r.NodeID] = struct{ typ, identifier string }{r.Type, r.Identifier}
	}
	matches := embed.TopK(queryVec, candidates, topK)
	if len(matches) == 0 {
		fmt.Fprintln(os.Stderr, "query: no matches")
		return 1
	}

	eng := query.New(db.SQL())
	for _, m := range matches {
		meta := idMap[m.NodeID]
		node, err := eng.GetByIdentifier(meta.typ, meta.identifier)
		title := ""
		if err == nil {
			title = titleFromProperties(node.Properties)
		}
		if len(title) > 80 {
			title = title[:77] + "..."
		}
		fmt.Printf("[s=%.3f] %-10s %-40s %s\n", m.Score, meta.typ, meta.identifier, title)
	}
	return 0
}

func runQuerySemanticJSON(db *storage.DB, queryText string, typeFilters []string, topK int, freshness memoryFreshness) int {
	rows, err := db.IterateEmbeddings(typeFilters)
	if err != nil {
		fmt.Fprintf(os.Stderr, "query: scan embeddings: %v\n", err)
		return 1
	}
	if len(rows) == 0 {
		return runQueryBM25JSON(db, "semantic_bm25", queryText, typeFilters, topK, freshness)
	}
	return runQueryVectorJSON(db, "semantic_vector", queryText, typeFilters, topK, false, freshness)
}

func runQueryHybridJSON(db *storage.DB, queryText string, typeFilters []string, topK int, freshness memoryFreshness) int {
	embRows, err := db.IterateEmbeddings(typeFilters)
	if err != nil {
		fmt.Fprintf(os.Stderr, "query: scan embeddings: %v\n", err)
		return 1
	}
	if len(embRows) == 0 {
		return runQueryBM25JSON(db, "hybrid_bm25", queryText, typeFilters, topK, freshness)
	}
	return runQueryVectorJSON(db, "hybrid_vector", queryText, typeFilters, topK, true, freshness)
}

func runQueryBM25JSON(db *storage.DB, mode, queryText string, typeFilters []string, topK int, freshness memoryFreshness) int {
	eng := query.New(db.SQL())
	matches, err := bm25MatchesForJSON(db, eng, queryText, typeFilters, topK)
	if err != nil {
		fmt.Fprintf(os.Stderr, "query: bm25 json: %v\n", err)
		return 1
	}
	if len(matches) == 0 {
		fmt.Fprintf(os.Stderr, "query: no BM25 matches for %q\n", queryText)
		return 1
	}
	return writeJSON(queryJSON{
		Command:     "query",
		Query:       queryText,
		Mode:        mode,
		TypeFilter:  strings.Join(typeFilters, ","),
		Freshness:   freshness,
		ResultCount: len(matches),
		Matches:     matches,
	})
}

func runQueryVectorJSON(db *storage.DB, mode, queryText string, typeFilters []string, topK int, includeNeighbors bool, freshness memoryFreshness) int {
	embedder, err := resolveEmbedder()
	if err != nil {
		fmt.Fprintf(os.Stderr, "query: %v\n", err)
		return runQueryBM25JSON(db, vectorFallbackMode(mode), queryText, typeFilters, topK, freshness)
	}
	queryVec, err := embedder.Embed(embedInputText(queryText))
	if err != nil {
		fmt.Fprintf(os.Stderr, "query: embed query: %v\n", err)
		return runQueryBM25JSON(db, vectorFallbackMode(mode), queryText, typeFilters, topK, freshness)
	}
	rows, err := db.IterateEmbeddings(typeFilters)
	if err != nil {
		fmt.Fprintf(os.Stderr, "query: scan embeddings: %v\n", err)
		return 1
	}
	if len(rows) == 0 {
		fmt.Fprintln(os.Stderr, "query: no Ollama embeddings stored (run `aih-graph refresh` with local Ollama available)")
		return 1
	}

	candidates := make([]embed.Candidate, 0, len(rows))
	idMap := map[int64]struct {
		typ, identifier string
	}{}
	for _, r := range rows {
		candidates = append(candidates, embed.Candidate{
			NodeID:    r.NodeID,
			Embedding: embed.DecodeVector(r.Embedding),
		})
		idMap[r.NodeID] = struct{ typ, identifier string }{r.Type, r.Identifier}
	}
	matches := embed.TopK(queryVec, candidates, topK)
	if len(matches) == 0 {
		fmt.Fprintln(os.Stderr, "query: no matches")
		return 1
	}

	eng := query.New(db.SQL())
	out := make([]bm25MatchJSON, 0, len(matches))
	for _, m := range matches {
		meta := idMap[m.NodeID]
		node, err := eng.GetByIdentifier(meta.typ, meta.identifier)
		if err != nil {
			node = &query.Node{
				ID:         m.NodeID,
				Type:       meta.typ,
				Identifier: meta.identifier,
			}
		}
		var jsonNeighbors []jsonNode
		if includeNeighbors {
			neighbors, err := eng.LoadNeighbors(m.NodeID, 5)
			if err == nil {
				jsonNeighbors = make([]jsonNode, 0, len(neighbors))
				for _, n := range neighbors {
					jsonNeighbors = append(jsonNeighbors, nodeForJSON(n))
				}
			}
		}
		out = append(out, bm25MatchJSON{
			Score:     float64(m.Score),
			Node:      nodeForJSON(*node),
			Neighbors: jsonNeighbors,
		})
	}
	return writeJSON(queryJSON{
		Command:     "query",
		Query:       queryText,
		Mode:        mode,
		TypeFilter:  strings.Join(typeFilters, ","),
		Freshness:   freshness,
		ResultCount: len(out),
		Matches:     out,
	})
}

func vectorFallbackMode(mode string) string {
	if strings.HasPrefix(mode, "semantic") {
		return "semantic_bm25"
	}
	return "hybrid_bm25"
}

func runContext(args []string) int {
	fs := flag.NewFlagSet("context", flag.ExitOnError)
	dbPath := fs.String("db", "", "path to SQLite database")
	repoPath := fs.String("repo", ".", "repository path for DB default and freshness checks")
	typ := fs.String("type", "", "optional exact type filter")
	depth := fs.Int("depth", 1, "exact-node graph depth")
	topK := fs.Int("top", 8, "hybrid fallback result count")
	limit := fs.Int("limit", 80, "maximum JSON neighborhood nodes (0 = no limit)")
	jsonOut := fs.Bool("json", false, "print stable machine-readable output")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if fs.NArg() < 1 {
		fmt.Fprintln(os.Stderr, "usage: aih-graph context [--repo PATH] [--db PATH] [--type T] [--json] <node-or-topic>")
		return 2
	}
	*repoPath = resolveRepoPath(*repoPath)
	freshness := loadMemoryFreshness(*repoPath)
	db, err := openQueryDBForRepo(*dbPath, *repoPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "context: open db: %v\n", err)
		return 1
	}
	defer db.Close()

	target := fs.Arg(0)
	eng := query.New(db.SQL())
	node, err := resolveNode(eng, target, *typ)
	if err != nil {
		if *jsonOut {
			matches, err := bm25MatchesForJSON(db, eng, target, splitTypesFilter("", *typ), *topK)
			if err != nil {
				fmt.Fprintf(os.Stderr, "context: bm25 fallback: %v\n", err)
				return 1
			}
			if len(matches) == 0 {
				fmt.Fprintf(os.Stderr, "context: no exact node or BM25 matches for %q\n", target)
				return 1
			}
			return writeJSON(contextJSON{
				Query:      target,
				TypeFilter: *typ,
				Mode:       "bm25_fallback",
				Freshness:  freshness,
				Matches:    matches,
			})
		}
		printFreshnessWarning(freshness)
		fmt.Printf("No exact node for %q; showing hybrid memory matches.\n", target)
		return runHybrid(db, target, splitTypesFilter("", *typ), *topK)
	}
	results, err := eng.BFS(node.Type, node.Identifier, *depth)
	if err != nil {
		fmt.Fprintf(os.Stderr, "context: bfs: %v\n", err)
		return 1
	}
	if *jsonOut {
		targetNode := nodeForJSON(*node)
		neighborhood, truncated := bfsForJSON(results, *limit)
		return writeJSON(contextJSON{
			Query:                 target,
			TypeFilter:            *typ,
			Mode:                  "exact",
			Target:                &targetNode,
			Freshness:             freshness,
			Neighborhood:          neighborhood,
			NeighborhoodTotal:     len(results),
			NeighborhoodReturned:  len(neighborhood),
			NeighborhoodTruncated: truncated,
		})
	}
	printFreshnessWarning(freshness)
	fmt.Println("Exact memory context:")
	printNodeSummary(*node)
	for _, r := range results {
		if r.Distance == 0 {
			continue
		}
		fmt.Printf("[d=%d] ", r.Distance)
		printNodeSummary(r.Node)
	}
	return 0
}

func runCallers(args []string) int {
	fs := flag.NewFlagSet("callers", flag.ExitOnError)
	dbPath := fs.String("db", "", "path to SQLite database")
	jsonOut := fs.Bool("json", false, "print stable machine-readable output")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if fs.NArg() < 1 {
		fmt.Fprintln(os.Stderr, "usage: aih-graph callers [--db PATH] [--json] <symbol-name-or-identifier>")
		return 2
	}
	db, err := openQueryDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "callers: open db: %v\n", err)
		return 1
	}
	defer db.Close()
	eng := query.New(db.SQL())

	target := fs.Arg(0)
	targetIDs := map[string]bool{}
	if node, err := resolveNode(eng, target, "Symbol"); err == nil {
		targetIDs[node.Identifier] = true
		if name := propString(node.Properties, "name"); name != "" {
			targetIDs[name] = true
		}
	}
	targetIDs[target] = true

	calls, err := eng.ListByType("Call")
	if err != nil {
		fmt.Fprintf(os.Stderr, "callers: list calls: %v\n", err)
		return 1
	}
	found := 0
	var callSites []callSiteJSON
	for _, c := range calls {
		calleeID := propString(c.Properties, "callee_identifier")
		calleeName := propString(c.Properties, "callee_name")
		if !targetIDs[calleeID] && !targetIDs[calleeName] {
			continue
		}
		found++
		caller := propString(c.Properties, "caller_identifier")
		file := propString(c.Properties, "file_path")
		line := int(propFloat(c.Properties, "line"))
		if *jsonOut {
			callSites = append(callSites, callSiteJSON{
				CallerIdentifier: caller,
				CalleeIdentifier: calleeID,
				CalleeName:       calleeName,
				FilePath:         file,
				Line:             line,
				Call:             nodeForJSON(c),
			})
			continue
		}
		fmt.Printf("%-55s %s:%d calls %s\n", caller, file, line, calleeName)
	}
	if *jsonOut {
		if found == 0 {
			fmt.Fprintf(os.Stderr, "callers: no call sites found for %q\n", target)
			return 1
		}
		return writeJSON(callersJSON{
			Query:     target,
			CallSites: callSites,
		})
	}
	if found == 0 {
		fmt.Fprintf(os.Stderr, "callers: no call sites found for %q\n", target)
		return 1
	}
	return 0
}

func runImpact(args []string) int {
	fs := flag.NewFlagSet("impact", flag.ExitOnError)
	dbPath := fs.String("db", "", "path to SQLite database")
	repoPath := fs.String("repo", ".", "repository path for DB default and freshness checks")
	typ := fs.String("type", "", "optional exact type filter")
	depth := fs.Int("depth", 2, "graph depth")
	limit := fs.Int("limit", 80, "maximum JSON neighborhood nodes (0 = no limit)")
	jsonOut := fs.Bool("json", false, "print stable machine-readable output")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if fs.NArg() < 1 {
		fmt.Fprintln(os.Stderr, "usage: aih-graph impact [--repo PATH] [--db PATH] [--type T] [--json] <node>")
		return 2
	}
	*repoPath = resolveRepoPath(*repoPath)
	freshness := loadMemoryFreshness(*repoPath)
	db, err := openQueryDBForRepo(*dbPath, *repoPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "impact: open db: %v\n", err)
		return 1
	}
	defer db.Close()
	eng := query.New(db.SQL())
	target := fs.Arg(0)
	node, err := resolveNode(eng, target, *typ)
	if err != nil {
		fmt.Fprintf(os.Stderr, "impact: no exact node found for %q; use `query --json` to discover identifiers\n", target)
		return 1
	}
	results, err := eng.BFS(node.Type, node.Identifier, *depth)
	if err != nil {
		fmt.Fprintf(os.Stderr, "impact: bfs: %v\n", err)
		return 1
	}
	if *jsonOut {
		neighborhood, truncated := bfsForJSON(results, *limit)
		return writeJSON(impactJSON{
			Query:        target,
			TypeFilter:   *typ,
			Depth:        *depth,
			Target:       nodeForJSON(*node),
			Freshness:    freshness,
			RelatedTests: bfsByTypeForJSON(results, "Test", 8),
			RecentCommits: bfsByTypeForJSON(
				results,
				"Commit",
				5,
			),
			Neighborhood:          neighborhood,
			NeighborhoodTotal:     len(results),
			NeighborhoodReturned:  len(neighborhood),
			NeighborhoodTruncated: truncated,
		})
	}
	printFreshnessWarning(freshness)
	printImpactSummary(results)
	fmt.Println("Impact neighborhood:")
	printNodeSummary(*node)
	for _, r := range results {
		if r.Distance == 0 {
			continue
		}
		fmt.Printf("[d=%d] ", r.Distance)
		printNodeSummary(r.Node)
	}
	return 0
}

func printImpactSummary(results []query.BFSResult) {
	var tests, commits []query.BFSResult
	for _, r := range results {
		switch r.Node.Type {
		case "Test":
			tests = append(tests, r)
		case "Commit":
			commits = append(commits, r)
		}
	}
	if len(tests) > 0 {
		fmt.Println("Related tests:")
		for i, r := range tests {
			if i >= 8 {
				fmt.Printf("  ... %d more\n", len(tests)-i)
				break
			}
			fmt.Print("  ")
			printNodeSummary(r.Node)
		}
	}
	if len(commits) > 0 {
		fmt.Println("Recent commits:")
		for i, r := range commits {
			if i >= 5 {
				fmt.Printf("  ... %d more\n", len(commits)-i)
				break
			}
			fmt.Print("  ")
			printNodeSummary(r.Node)
		}
	}
}

func printStatusState(state, staleSince, marker string) {
	if state == "stale" {
		fmt.Printf("  state: stale (since %s)\n", staleSince)
		fmt.Printf("  marker: %s\n", marker)
		return
	}
	fmt.Println("  state: fresh")
}

func collectStatusJSON(repoPath, dbPath string) (statusJSON, error) {
	status := statusJSON{
		Repo:            repoPath,
		DB:              dbPath,
		State:           "fresh",
		NodeCounts:      map[string]int{},
		EmbeddingModels: map[string]int{},
	}
	stalePath, staleInfo, staleFound := firstExistingStaleMarker(repoPath)
	if staleFound {
		status.State = "stale"
		status.StaleSince = staleInfo.ModTime().Format(time.RFC3339)
		status.Marker = stalePath
	}

	if _, err := os.Stat(dbPath); err != nil {
		if os.IsNotExist(err) {
			return status, nil
		}
		return status, fmt.Errorf("stat db: %w", err)
	}
	db, err := storage.Open(dbPath)
	if err != nil {
		return status, fmt.Errorf("open db: %w", err)
	}
	defer db.Close()

	counts, err := db.CountByType()
	if err != nil {
		return status, fmt.Errorf("count nodes: %w", err)
	}
	total := 0
	for _, n := range counts {
		total += n
	}
	ftsRows, _ := db.CountFTS()
	embeddingRows := 0
	_ = db.SQL().QueryRow("SELECT COUNT(*) FROM nodes WHERE embedding IS NOT NULL").Scan(&embeddingRows)

	status.IndexBuilt = true
	status.NodesTotal = total
	status.NodeCounts = counts
	status.BM25Rows = ftsRows
	status.EmbeddingRows = embeddingRows
	status.EmbeddingModels = countEmbeddingModels(db)
	return status, nil
}

func countEmbeddingModels(db *storage.DB) map[string]int {
	rows, err := db.SQL().Query(`
		SELECT COALESCE(NULLIF(embedding_model, ''), '(unknown)'), COUNT(*)
		FROM nodes
		WHERE embedding IS NOT NULL
		GROUP BY COALESCE(NULLIF(embedding_model, ''), '(unknown)')
		ORDER BY 1
	`)
	if err != nil {
		return map[string]int{}
	}
	defer rows.Close()
	out := map[string]int{}
	for rows.Next() {
		var model string
		var count int
		if err := rows.Scan(&model, &count); err != nil {
			return map[string]int{}
		}
		out[model] = count
	}
	if err := rows.Err(); err != nil {
		return map[string]int{}
	}
	return out
}

func runWithStdoutDiscard(fn func() int) int {
	devNull, err := os.OpenFile(os.DevNull, os.O_WRONLY, 0)
	if err != nil {
		return fn()
	}
	old := os.Stdout
	os.Stdout = devNull
	defer func() {
		os.Stdout = old
		_ = devNull.Close()
	}()
	return fn()
}

func loadMemoryFreshness(repoPath string) memoryFreshness {
	freshness := memoryFreshness{
		Repo:  repoPath,
		State: "fresh",
	}
	stalePath, staleInfo, staleFound := firstExistingStaleMarker(repoPath)
	if staleFound {
		freshness.State = "stale"
		freshness.StaleSince = staleInfo.ModTime().Format(time.RFC3339)
		freshness.Marker = stalePath
	}
	return freshness
}

func printFreshnessWarning(f memoryFreshness) {
	if f.State != "stale" {
		return
	}
	fmt.Printf("Memory warning: index stale since %s; refresh with `aih-graph refresh --repo %s`.\n", f.StaleSince, f.Repo)
}

func runGotchas(args []string) int {
	fs := flag.NewFlagSet("gotchas", flag.ExitOnError)
	dbPath := fs.String("db", "", "path to SQLite database")
	topK := fs.Int("top", 8, "result count")
	jsonOut := fs.Bool("json", false, "print stable machine-readable output")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	queryText := "gotcha OR gotchas OR trap OR pitfall"
	if fs.NArg() > 0 {
		queryText = strings.Join(fs.Args(), " ")
	}
	db, err := openQueryDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "gotchas: open db: %v\n", err)
		return 1
	}
	defer db.Close()
	if *jsonOut {
		return runBM25SearchJSON(db, "gotchas", queryText, []string{"Memory"}, *topK)
	}
	return runHybrid(db, queryText, []string{"Memory"}, *topK)
}

func runMilestone(args []string) int {
	fs := flag.NewFlagSet("milestone", flag.ExitOnError)
	dbPath := fs.String("db", "", "path to SQLite database")
	topK := fs.Int("top", 10, "result count")
	jsonOut := fs.Bool("json", false, "print stable machine-readable output")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if fs.NArg() < 1 {
		fmt.Fprintln(os.Stderr, "usage: aih-graph milestone [--db PATH] [--json] <file|symbol|commit|milestone-topic>")
		return 2
	}
	db, err := openQueryDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "milestone: open db: %v\n", err)
		return 1
	}
	defer db.Close()
	queryText := strings.Join(fs.Args(), " ")
	if *jsonOut {
		return runBM25SearchJSON(db, "milestone", queryText, nil, *topK)
	}
	return runHybrid(db, queryText, nil, *topK)
}

// reviewedSHARe matches a `last-reviewed:` value that looks like a git commit
// SHA (7..40 hex chars) — the staleness anchor per the rule record schema in
// pkg/.aihaus/protocols/business-rules.md.
var reviewedSHARe = regexp.MustCompile(`^[0-9a-fA-F]{7,40}$`)

// runRuleDrift reports business rules whose binding is suspect (BRC-S3,
// ADR-260531-A): a rule is flagged when it was never reviewed (last_reviewed
// empty or "-"), when its declared implements: refs outnumber the code edges
// that actually resolved (a dangling binding — code moved/renamed/removed),
// or — M050/S04 — when the files its implements: refs point at have commits
// newer than the last-reviewed SHA (sha-stale). The SHA check degrades
// gracefully outside a git repo (or with an unknown SHA): it simply never
// fires; never-reviewed/dangling-binding behavior is unchanged.
func runRuleDrift(args []string) int {
	fs := flag.NewFlagSet("rule-drift", flag.ExitOnError)
	dbPath := fs.String("db", "", "path to SQLite database")
	repoPath := fs.String("repo", ".", "repository path for DB default and git staleness checks")
	jsonOut := fs.Bool("json", false, "print stable machine-readable output")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	*repoPath = resolveRepoPath(*repoPath)
	db, err := openQueryDBForRepo(*dbPath, *repoPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "rule-drift: open db: %v\n", err)
		return 1
	}
	defer db.Close()

	// Collect rule rows first, then per-rule edge counts (avoid nested cursor).
	type ruleRow struct {
		id           int64
		ident, props string
	}
	rows, err := db.SQL().Query("SELECT id, identifier, properties FROM nodes WHERE type='Rule' ORDER BY identifier")
	if err != nil {
		fmt.Fprintf(os.Stderr, "rule-drift: query rules: %v\n", err)
		return 1
	}
	var ruleRows []ruleRow
	for rows.Next() {
		var r ruleRow
		if err := rows.Scan(&r.id, &r.ident, &r.props); err != nil {
			continue
		}
		ruleRows = append(ruleRows, r)
	}
	_ = rows.Err()
	rows.Close()

	type ruleDrift struct {
		Rule          string   `json:"rule"`
		Reason        string   `json:"reason"`
		LastReviewed  string   `json:"last_reviewed"`
		DeclaredLinks int      `json:"declared_links"`
		BoundLinks    int      `json:"bound_links"`
		StaleFiles    []string `json:"stale_files,omitempty"`
		NewerCommits  []string `json:"newer_commits,omitempty"`
	}
	inGitRepo := isGitRepo(*repoPath)
	var drifts []ruleDrift
	for _, r := range ruleRows {
		var p struct {
			LastReviewed string   `json:"last_reviewed"`
			Implements   []string `json:"implements"`
		}
		_ = json.Unmarshal([]byte(r.props), &p)

		lr := strings.TrimSpace(p.LastReviewed)
		if lr == "" || lr == "-" {
			drifts = append(drifts, ruleDrift{Rule: r.ident, Reason: "never-reviewed", LastReviewed: lr, DeclaredLinks: len(p.Implements)})
			continue
		}
		var bound int
		_ = db.SQL().QueryRow("SELECT COUNT(*) FROM edges WHERE from_id=? AND type='implements'", r.id).Scan(&bound)
		if len(p.Implements) > bound {
			drifts = append(drifts, ruleDrift{Rule: r.ident, Reason: "dangling-binding", LastReviewed: lr, DeclaredLinks: len(p.Implements), BoundLinks: bound})
		}

		// SHA staleness (M050/S04): bound files changed since the reviewed SHA.
		if inGitRepo && reviewedSHARe.MatchString(lr) {
			files := ruleBoundFiles(p.Implements)
			if len(files) == 0 {
				continue
			}
			newer, err := gitCommitsSince(*repoPath, lr, files)
			if err != nil || len(newer) == 0 {
				// Unknown SHA / git error → degrade silently (no positive
				// staleness evidence); zero newer commits → fresh.
				continue
			}
			drifts = append(drifts, ruleDrift{
				Rule:          r.ident,
				Reason:        "sha-stale",
				LastReviewed:  lr,
				DeclaredLinks: len(p.Implements),
				BoundLinks:    bound,
				StaleFiles:    files,
				NewerCommits:  newer,
			})
		}
	}

	if *jsonOut {
		return writeJSON(map[string]any{"total_rules": len(ruleRows), "drift_count": len(drifts), "drifts": drifts})
	}
	fmt.Printf("aih-graph rule-drift: %d rule(s), %d drift(s)\n", len(ruleRows), len(drifts))
	for _, d := range drifts {
		switch d.Reason {
		case "never-reviewed":
			fmt.Printf("  [never-reviewed]   %s\n", d.Rule)
		case "dangling-binding":
			fmt.Printf("  [dangling-binding] %s — %d declared, %d bound to code\n", d.Rule, d.DeclaredLinks, d.BoundLinks)
		case "sha-stale":
			fmt.Printf("  [sha-stale]        %s — %d commit(s) touch bound files since %s\n", d.Rule, len(d.NewerCommits), d.LastReviewed)
			for _, c := range d.NewerCommits {
				fmt.Printf("                     %s\n", c)
			}
		}
	}
	if len(drifts) == 0 {
		fmt.Println("  no drift detected")
	}
	return 0
}

// ruleBoundFiles maps a rule's declared implements: refs onto the file paths
// git should watch. Symbol/Test refs are "<relpath>:<name>" → the relpath
// part; plain file refs pass through. Duplicates are dropped, order preserved.
func ruleBoundFiles(refs []string) []string {
	seen := map[string]bool{}
	var out []string
	for _, ref := range refs {
		file := strings.TrimSpace(ref)
		if i := strings.LastIndex(file, ":"); i > 0 {
			file = file[:i]
		}
		if file == "" || seen[file] {
			continue
		}
		seen[file] = true
		out = append(out, file)
	}
	return out
}

// isGitRepo reports whether repoPath is inside a git work tree. False when
// the git binary is missing — every git-backed feature then degrades to a
// no-op (graceful outside-a-repo behavior).
func isGitRepo(repoPath string) bool {
	return exec.Command("git", "-C", repoPath, "rev-parse", "--git-dir").Run() == nil
}

// gitCommitsSince returns "shortsha subject" lines for commits in
// (sha, HEAD] that touch any of files. Errors (unknown SHA, no git, not a
// repo) surface to the caller, which treats them as "no staleness evidence".
func gitCommitsSince(repoPath, sha string, files []string) ([]string, error) {
	args := []string{"-C", repoPath, "log", "--format=%h %s", sha + "..HEAD", "--"}
	args = append(args, files...)
	out, err := exec.Command("git", args...).Output()
	if err != nil {
		return nil, err
	}
	var commits []string
	for _, line := range strings.Split(string(out), "\n") {
		if line = strings.TrimSpace(line); line != "" {
			commits = append(commits, line)
		}
	}
	return commits, nil
}

// ruleBindingJSON is one resolved edge off a Rule node: implements →
// Symbol|File|Test, relates → Rule, decided_by → Decision.
type ruleBindingJSON struct {
	Edge string   `json:"edge"`
	Node jsonNode `json:"node"`
}

// ruleReviewJSON summarizes a rule's freshness for the `rule` verb. State is
// "reviewed", "never-reviewed", or "dangling-binding" (declared implements:
// refs that did not resolve to indexed code).
type ruleReviewJSON struct {
	State         string `json:"state"`
	LastReviewed  string `json:"last_reviewed,omitempty"`
	DeclaredLinks int    `json:"declared_links"`
	BoundLinks    int    `json:"bound_links"`
}

// ruleVerbJSON is the stable payload of `aih-graph rule <BR-id> --json` —
// the rule → implementing code + tests direction promised at
// pkg/.aihaus/protocols/business-rules.md (Residence §).
type ruleVerbJSON struct {
	Command            string            `json:"command"`
	ID                 string            `json:"id"`
	Rule               jsonNode          `json:"rule"`
	Status             string            `json:"status,omitempty"`
	Domain             string            `json:"domain,omitempty"`
	Statement          string            `json:"statement,omitempty"`
	Scenarios          []string          `json:"scenarios,omitempty"`
	Bindings           []ruleBindingJSON `json:"bindings"`
	DeclaredImplements []string          `json:"declared_implements,omitempty"`
	DeclaredRelates    []string          `json:"declared_relates,omitempty"`
	DeclaredDecidedBy  []string          `json:"declared_decided_by,omitempty"`
	Review             ruleReviewJSON    `json:"review"`
	Freshness          memoryFreshness   `json:"freshness"`
}

// whyRuleJSON is one rule that binds the queried ref, with the edge that
// reached it and the rule's own decided_by chain.
type whyRuleJSON struct {
	Edge      string     `json:"edge"`
	Rule      jsonNode   `json:"rule"`
	DecidedBy []jsonNode `json:"decided_by,omitempty"`
}

// whyJSON is the stable payload of `aih-graph why <ref> --json` — the
// code → rules-it-serves direction promised at
// pkg/.aihaus/protocols/business-rules.md (Residence §).
type whyJSON struct {
	Command   string          `json:"command"`
	Ref       string          `json:"ref"`
	Resolved  []jsonNode      `json:"resolved"`
	RuleCount int             `json:"rule_count"`
	Rules     []whyRuleJSON   `json:"rules"`
	Decisions []jsonNode      `json:"decisions,omitempty"`
	Freshness memoryFreshness `json:"freshness"`
}

// loadRuleBindings returns the outbound rule edges (implements / relates /
// decided_by) of a Rule node with their target nodes, ordered for stable
// output.
func loadRuleBindings(db *storage.DB, ruleNodeID int64) ([]ruleBindingJSON, error) {
	rows, err := db.SQL().Query(`
		SELECT e.type, n.id, n.type, n.identifier, n.properties
		FROM edges e
		JOIN nodes n ON n.id = e.to_id
		WHERE e.from_id = ? AND e.type IN ('implements','relates','decided_by')
		ORDER BY e.type, n.type, n.identifier
	`, ruleNodeID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []ruleBindingJSON
	for rows.Next() {
		var (
			edge       string
			n          query.Node
			propsBytes []byte
		)
		if err := rows.Scan(&edge, &n.ID, &n.Type, &n.Identifier, &propsBytes); err != nil {
			return nil, err
		}
		if len(propsBytes) > 0 {
			_ = json.Unmarshal(propsBytes, &n.Properties)
		}
		out = append(out, ruleBindingJSON{Edge: edge, Node: nodeForJSON(n)})
	}
	return out, rows.Err()
}

// runRule implements `aih-graph rule <BR-id>` (M050/S04): resolve one Rule
// node from the indexed ledger and print it with its bindings + freshness.
// Closes documented-but-unimplemented hole 5
// (pkg/.aihaus/protocols/business-rules.md Residence §).
func runRule(args []string) int {
	fs := flag.NewFlagSet("rule", flag.ExitOnError)
	dbPath := fs.String("db", "", "path to SQLite database")
	repoPath := fs.String("repo", ".", "repository path for DB default and freshness checks")
	jsonOut := fs.Bool("json", false, "print stable machine-readable output")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if fs.NArg() < 1 {
		fmt.Fprintln(os.Stderr, "rule: <BR-id> required")
		fmt.Fprintln(os.Stderr, "usage: aih-graph rule [--repo PATH] [--db PATH] [--json] <BR-id>")
		return 2
	}
	*repoPath = resolveRepoPath(*repoPath)
	freshness := loadMemoryFreshness(*repoPath)
	db, err := openQueryDBForRepo(*dbPath, *repoPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "rule: open db: %v\n", err)
		return 1
	}
	defer db.Close()

	id := fs.Arg(0)
	eng := query.New(db.SQL())
	node, err := eng.GetByIdentifier("Rule", id)
	if err != nil {
		fmt.Fprintf(os.Stderr, "rule: no Rule node matches %q (is the ledger indexed? run `aih-graph refresh`)\n", id)
		return 1
	}
	bindings, err := loadRuleBindings(db, node.ID)
	if err != nil {
		fmt.Fprintf(os.Stderr, "rule: load bindings: %v\n", err)
		return 1
	}

	declaredImplements := propStringSlice(node.Properties, "implements")
	declaredRelates := propStringSlice(node.Properties, "relates")
	declaredDecidedBy := propStringSlice(node.Properties, "decided_by")
	boundImplements := 0
	for _, b := range bindings {
		if b.Edge == "implements" {
			boundImplements++
		}
	}
	lastReviewed := strings.TrimSpace(propString(node.Properties, "last_reviewed"))
	review := ruleReviewJSON{
		State:         "reviewed",
		LastReviewed:  lastReviewed,
		DeclaredLinks: len(declaredImplements),
		BoundLinks:    boundImplements,
	}
	if lastReviewed == "" || lastReviewed == "-" {
		review.State = "never-reviewed"
	} else if len(declaredImplements) > boundImplements {
		review.State = "dangling-binding"
	}

	if *jsonOut {
		if bindings == nil {
			bindings = []ruleBindingJSON{}
		}
		return writeJSON(ruleVerbJSON{
			Command:            "rule",
			ID:                 id,
			Rule:               nodeForJSON(*node),
			Status:             propString(node.Properties, "status"),
			Domain:             propString(node.Properties, "domain"),
			Statement:          propString(node.Properties, "statement"),
			Scenarios:          propStringSlice(node.Properties, "scenarios"),
			Bindings:           bindings,
			DeclaredImplements: declaredImplements,
			DeclaredRelates:    declaredRelates,
			DeclaredDecidedBy:  declaredDecidedBy,
			Review:             review,
			Freshness:          freshness,
		})
	}

	printFreshnessWarning(freshness)
	fmt.Printf("%s — %s\n", node.Identifier, titleFromProperties(node.Properties))
	if s := propString(node.Properties, "status"); s != "" {
		fmt.Printf("  status: %s\n", s)
	}
	if d := propString(node.Properties, "domain"); d != "" {
		fmt.Printf("  domain: %s\n", d)
	}
	if st := propString(node.Properties, "statement"); st != "" {
		fmt.Printf("  statement: %s\n", st)
	}
	fmt.Printf("  review: %s", review.State)
	if review.LastReviewed != "" {
		fmt.Printf(" (last-reviewed %s)", review.LastReviewed)
	}
	fmt.Println()
	if scenarios := propStringSlice(node.Properties, "scenarios"); len(scenarios) > 0 {
		fmt.Println("  scenarios:")
		for _, s := range scenarios {
			fmt.Printf("    - %s\n", s)
		}
	}
	if len(bindings) > 0 {
		fmt.Println("  bindings:")
		for _, b := range bindings {
			fmt.Printf("    [%s] %-8s %s\n", b.Edge, b.Node.Type, b.Node.Identifier)
		}
	}
	if unresolved := unresolvedRefs(declaredImplements, bindings, "implements"); len(unresolved) > 0 {
		fmt.Println("  declared but unresolved (dangling):")
		for _, ref := range unresolved {
			fmt.Printf("    [implements] %s\n", ref)
		}
	}
	return 0
}

// unresolvedRefs returns declared refs with no matching resolved binding of
// the given edge type (identifier match).
func unresolvedRefs(declared []string, bindings []ruleBindingJSON, edge string) []string {
	resolved := map[string]bool{}
	for _, b := range bindings {
		if b.Edge == edge {
			resolved[b.Node.Identifier] = true
		}
	}
	var out []string
	for _, ref := range declared {
		if !resolved[ref] {
			out = append(out, ref)
		}
	}
	return out
}

// propStringSlice reads a []string-shaped property (stored as JSON array).
func propStringSlice(props map[string]any, key string) []string {
	items, ok := props[key].([]any)
	if !ok {
		return nil
	}
	var out []string
	for _, item := range items {
		if s, ok := item.(string); ok {
			out = append(out, s)
		}
	}
	return out
}

// resolveWhyTargets resolves a `why` ref to candidate target nodes: exact
// Symbol/File/Test/Decision/Rule identifiers first, then bare-name Symbol
// matches (e.g. "Submit" → "order.go:Submit").
func resolveWhyTargets(eng *query.Engine, ref string) []query.Node {
	var out []query.Node
	seen := map[int64]bool{}
	add := func(n *query.Node) {
		if n != nil && !seen[n.ID] {
			seen[n.ID] = true
			out = append(out, *n)
		}
	}
	for _, typ := range []string{"Symbol", "File", "Test", "Decision", "Rule"} {
		if n, err := eng.GetByIdentifier(typ, ref); err == nil {
			add(n)
		}
	}
	if symbols, err := eng.ListByType("Symbol"); err == nil {
		for i := range symbols {
			if propString(symbols[i].Properties, "name") == ref {
				add(&symbols[i])
			}
		}
	}
	return out
}

// runWhy implements `aih-graph why <ref>` (M050/S04): reverse lookup from a
// file path, symbol, or BR-id to the rules/decisions bound to it — "why does
// this code behave this way". Inbound Rule-[implements|relates|decided_by]→X
// edges are walked, plus each rule's own decided_by chain.
func runWhy(args []string) int {
	fs := flag.NewFlagSet("why", flag.ExitOnError)
	dbPath := fs.String("db", "", "path to SQLite database")
	repoPath := fs.String("repo", ".", "repository path for DB default and freshness checks")
	jsonOut := fs.Bool("json", false, "print stable machine-readable output")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if fs.NArg() < 1 {
		fmt.Fprintln(os.Stderr, "why: <file|symbol|BR-id> required")
		fmt.Fprintln(os.Stderr, "usage: aih-graph why [--repo PATH] [--db PATH] [--json] <file|symbol|BR-id>")
		return 2
	}
	*repoPath = resolveRepoPath(*repoPath)
	freshness := loadMemoryFreshness(*repoPath)
	db, err := openQueryDBForRepo(*dbPath, *repoPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "why: open db: %v\n", err)
		return 1
	}
	defer db.Close()

	ref := fs.Arg(0)
	eng := query.New(db.SQL())
	targets := resolveWhyTargets(eng, ref)
	if len(targets) == 0 {
		fmt.Fprintf(os.Stderr, "why: no node matches ref %q (try a file path, \"file:Symbol\", or a BR-id)\n", ref)
		return 1
	}

	seenRules := map[int64]bool{}
	seenDecisions := map[int64]bool{}
	rules := []whyRuleJSON{}
	decisions := []jsonNode{}
	addDecision := func(n query.Node) {
		if !seenDecisions[n.ID] {
			seenDecisions[n.ID] = true
			decisions = append(decisions, nodeForJSON(n))
		}
	}
	addRule := func(edge string, n query.Node) error {
		if seenRules[n.ID] {
			return nil
		}
		seenRules[n.ID] = true
		entry := whyRuleJSON{Edge: edge, Rule: nodeForJSON(n)}
		// decided_by chain of the rule itself.
		chain, err := loadRuleBindings(db, n.ID)
		if err != nil {
			return err
		}
		for _, b := range chain {
			if b.Edge == "decided_by" {
				entry.DecidedBy = append(entry.DecidedBy, b.Node)
				if d, err := eng.GetByIdentifier(b.Node.Type, b.Node.Identifier); err == nil {
					addDecision(*d)
				}
			}
		}
		rules = append(rules, entry)
		return nil
	}

	for _, target := range targets {
		// Inbound edges FROM Rule nodes onto the target — implements (code),
		// relates (rule↔rule), decided_by (rule↔decision; a Decision target
		// yields the rules it decided).
		rows, err := db.SQL().Query(`
			SELECT e.type, r.id, r.type, r.identifier, r.properties
			FROM edges e
			JOIN nodes r ON r.id = e.from_id
			WHERE e.to_id = ? AND r.type = 'Rule'
			ORDER BY e.type, r.identifier
		`, target.ID)
		if err != nil {
			fmt.Fprintf(os.Stderr, "why: query inbound rule edges: %v\n", err)
			return 1
		}
		type inbound struct {
			edge string
			node query.Node
		}
		var inbounds []inbound
		for rows.Next() {
			var (
				edge       string
				n          query.Node
				propsBytes []byte
			)
			if err := rows.Scan(&edge, &n.ID, &n.Type, &n.Identifier, &propsBytes); err != nil {
				rows.Close()
				fmt.Fprintf(os.Stderr, "why: scan inbound rule edge: %v\n", err)
				return 1
			}
			if len(propsBytes) > 0 {
				_ = json.Unmarshal(propsBytes, &n.Properties)
			}
			inbounds = append(inbounds, inbound{edge: edge, node: n})
		}
		rows.Close()
		for _, in := range inbounds {
			if err := addRule(in.edge, in.node); err != nil {
				fmt.Fprintf(os.Stderr, "why: load rule chain: %v\n", err)
				return 1
			}
		}

		// A Rule target (BR-id ref) also answers with its own outbound
		// neighborhood: relates → rules, decided_by → decisions.
		if target.Type == "Rule" {
			bindings, err := loadRuleBindings(db, target.ID)
			if err != nil {
				fmt.Fprintf(os.Stderr, "why: load rule bindings: %v\n", err)
				return 1
			}
			for _, b := range bindings {
				switch b.Edge {
				case "relates":
					if n, err := eng.GetByIdentifier("Rule", b.Node.Identifier); err == nil {
						if err := addRule("relates", *n); err != nil {
							fmt.Fprintf(os.Stderr, "why: load rule chain: %v\n", err)
							return 1
						}
					}
				case "decided_by":
					if d, err := eng.GetByIdentifier(b.Node.Type, b.Node.Identifier); err == nil {
						addDecision(*d)
					}
				}
			}
		}
	}

	if *jsonOut {
		resolved := make([]jsonNode, 0, len(targets))
		for _, t := range targets {
			resolved = append(resolved, nodeForJSON(t))
		}
		return writeJSON(whyJSON{
			Command:   "why",
			Ref:       ref,
			Resolved:  resolved,
			RuleCount: len(rules),
			Rules:     rules,
			Decisions: decisions,
			Freshness: freshness,
		})
	}

	printFreshnessWarning(freshness)
	fmt.Printf("why %s\n", ref)
	for _, t := range targets {
		fmt.Printf("  resolved: %-8s %s\n", t.Type, t.Identifier)
	}
	if len(rules) == 0 && len(decisions) == 0 {
		fmt.Println("  no rules or decisions bound to this ref")
		return 0
	}
	for _, r := range rules {
		fmt.Printf("  [%s] %-10s %s", r.Edge, r.Rule.Identifier, r.Rule.Title)
		fmt.Println()
		for _, d := range r.DecidedBy {
			fmt.Printf("       decided_by %s %s\n", d.Identifier, d.Title)
		}
	}
	for _, d := range decisions {
		fmt.Printf("  [decision] %s %s\n", d.Identifier, d.Title)
	}
	return 0
}

func runStatus(args []string) int {
	fs := flag.NewFlagSet("status", flag.ExitOnError)
	dbPath := fs.String("db", "", "path to SQLite database")
	repoPath := fs.String("repo", ".", "repository path for default DB and stale marker")
	jsonOut := fs.Bool("json", false, "print stable machine-readable output")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if fs.NArg() > 0 {
		*repoPath = fs.Arg(0)
	}
	*repoPath = resolveRepoPath(*repoPath)
	resolvedDB := *dbPath
	var err error
	if resolvedDB == "" {
		resolvedDB, err = privacy.DefaultDBPath(*repoPath)
		if err != nil {
			fmt.Fprintf(os.Stderr, "status: resolve db path: %v\n", err)
			return 1
		}
	}
	status, err := collectStatusJSON(*repoPath, resolvedDB)
	if err != nil {
		fmt.Fprintf(os.Stderr, "status: %v\n", err)
		return 1
	}
	if *jsonOut {
		return writeJSON(status)
	}
	fmt.Printf("aih-graph status %s\n", *repoPath)
	fmt.Printf("  db: %s\n", resolvedDB)
	printStatusState(status.State, status.StaleSince, status.Marker)
	if !status.IndexBuilt {
		fmt.Println("  index: not built")
		return 0
	}
	fmt.Printf("  nodes: %d\n", status.NodesTotal)
	for _, t := range keysSorted(status.NodeCounts) {
		fmt.Printf("    %s: %d\n", t, status.NodeCounts[t])
	}
	fmt.Printf("  bm25_rows: %d\n", status.BM25Rows)
	fmt.Printf("  embedding_rows: %d\n", status.EmbeddingRows)
	for _, model := range keysSorted(status.EmbeddingModels) {
		fmt.Printf("    %s: %d\n", model, status.EmbeddingModels[model])
	}
	return 0
}

func runMarkStale(args []string) int {
	fs := flag.NewFlagSet("mark-stale", flag.ExitOnError)
	repoPath := fs.String("repo", ".", "repository path")
	reason := fs.String("reason", "repository changed", "staleness reason")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if fs.NArg() > 0 {
		*reason = strings.Join(fs.Args(), " ")
	}
	*repoPath = resolveRepoPath(*repoPath)
	path, err := staleMarkerPath(*repoPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "mark-stale: resolve marker: %v\n", err)
		return 1
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		fmt.Fprintf(os.Stderr, "mark-stale: create marker dir: %v\n", err)
		return 1
	}
	body := fmt.Sprintf("stale_since=%s\nreason=%s\n", time.Now().UTC().Format(time.RFC3339), *reason)
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "mark-stale: write marker: %v\n", err)
		return 1
	}
	fmt.Printf("aih-graph marked stale: %s\n", path)
	return 0
}

func staleMarkerPath(repoPath string) (string, error) {
	abs, err := filepath.Abs(repoPath)
	if err != nil {
		return "", err
	}
	return filepath.Join(abs, ".aihaus", "state", "aih-graph.stale"), nil
}

func staleMarkerPaths(repoPath string) ([]string, error) {
	abs, err := filepath.Abs(repoPath)
	if err != nil {
		return nil, err
	}
	return []string{
		filepath.Join(abs, ".aihaus", "state", "aih-graph.stale"),
		filepath.Join(abs, ".claude", "audit", "aih-graph.stale"),
	}, nil
}

func firstExistingStaleMarker(repoPath string) (string, os.FileInfo, bool) {
	paths, err := staleMarkerPaths(repoPath)
	if err != nil {
		return "", nil, false
	}
	for _, path := range paths {
		info, err := os.Stat(path)
		if err == nil {
			return path, info, true
		}
	}
	return "", nil, false
}

func clearStaleMarker(repoPath string) {
	paths, err := staleMarkerPaths(repoPath)
	if err != nil {
		return
	}
	for _, path := range paths {
		_ = os.Remove(path)
	}
}

// runUninstall implements the M036 uninstall subcommand. Modes:
//
//	--purge        delete ALL aih-graph state (entire XDG state root)
//	--user         delete the user-scope graph (~/.aihaus/state/user-graph.db)
//	               + its consent marker (M050/S04, ADR-260611-E own purge path)
//	<repo-path>    delete the .db for that specific repo only
//	(no args)      print where state lives + exit 0
func runUninstall(args []string) int {
	fs := flag.NewFlagSet("uninstall", flag.ExitOnError)
	purgeAll := fs.Bool("purge", false, "delete ALL aih-graph state (every repo)")
	userScope := fs.Bool("user", false, "delete the user-scope graph + its consent marker")
	if err := fs.Parse(args); err != nil {
		return 2
	}

	if *userScope {
		removed, err := privacy.PurgeUser()
		if err != nil {
			fmt.Fprintf(os.Stderr, "uninstall: %v\n", err)
			return 1
		}
		if len(removed) == 0 {
			fmt.Println("uninstall: no user-scope state to remove")
			return 0
		}
		for _, p := range removed {
			fmt.Printf("uninstall: removed %s\n", p)
		}
		return 0
	}

	if *purgeAll {
		removed, err := privacy.PurgeAll()
		if err != nil {
			fmt.Fprintf(os.Stderr, "uninstall: %v\n", err)
			return 1
		}
		if removed == "" {
			fmt.Println("uninstall: no aih-graph state to remove")
		} else {
			fmt.Printf("uninstall: removed all state at %s\n", removed)
		}
		return 0
	}

	if fs.NArg() >= 1 {
		repoPath := fs.Arg(0)
		removed, err := privacy.PurgeRepo(repoPath)
		if err != nil {
			fmt.Fprintf(os.Stderr, "uninstall: %v\n", err)
			return 1
		}
		if removed == "" {
			fmt.Printf("uninstall: no .db found for %s (nothing to remove)\n", repoPath)
		} else {
			fmt.Printf("uninstall: removed %s\n", removed)
		}
		return 0
	}

	// No args: print state location.
	root, err := privacy.XDGStateRoot()
	if err != nil {
		fmt.Fprintf(os.Stderr, "uninstall: %v\n", err)
		return 1
	}
	fmt.Printf("aih-graph state root: %s\n", root)
	fmt.Println("usage:")
	fmt.Println("  aih-graph uninstall --purge          # delete ALL state")
	fmt.Println("  aih-graph uninstall <repo-path>      # delete one repo's .db")
	return 0
}

// runHybridBM25 executes --hybrid via FTS5 BM25 ranking + 1-hop edge
// expansion per match. Mirrors runHybrid's vector path but sources matches
// from FTS5 instead of vector KNN. Same edge-expansion logic.
func runHybridBM25(db *storage.DB, queryText string, typeFilters []string, topK int) int {
	matches, err := db.QueryFTS5(buildFTS5Query(queryText), topK, typeFilters)
	if err != nil {
		fmt.Fprintf(os.Stderr, "query: bm25 hybrid: %v\n", err)
		return 1
	}
	if len(matches) == 0 {
		fmt.Fprintln(os.Stderr, "query: no BM25 matches (try less specific terms)")
		return 1
	}
	eng := query.New(db.SQL())
	for _, m := range matches {
		node, err := eng.GetByIdentifier(m.Type, m.Identifier)
		title := ""
		if err == nil {
			title = titleFromProperties(node.Properties)
		}
		if len(title) > 70 {
			title = title[:67] + "..."
		}
		// SQLite returns negative BM25; flip sign for human-readable "higher = better".
		fmt.Printf("[s=%.2f] %-10s %-40s %s\n", -m.Score, m.Type, m.Identifier, title)
		neighbors, err := eng.LoadNeighbors(m.NodeID, 5)
		if err != nil {
			continue
		}
		for _, n := range neighbors {
			nTitle := titleFromProperties(n.Properties)
			if len(nTitle) > 60 {
				nTitle = nTitle[:57] + "..."
			}
			fmt.Printf("         → %-10s %-40s %s\n", n.Type, n.Identifier, nTitle)
		}
	}
	return 0
}

// runSemanticBM25 executes --semantic via FTS5 BM25 lexical ranking.
// Query syntax follows SQLite FTS5: phrases, OR/AND, prefix*. We pre-process
// the user query to make it FTS5-safe (escape stray quotes, OR-join terms).
func runSemanticBM25(db *storage.DB, queryText string, typeFilters []string, topK int) int {
	fts5Query := buildFTS5Query(queryText)
	matches, err := db.QueryFTS5(fts5Query, topK, typeFilters)
	if err != nil {
		fmt.Fprintf(os.Stderr, "query: bm25: %v\n", err)
		return 1
	}
	if len(matches) == 0 {
		fmt.Fprintln(os.Stderr, "query: no BM25 matches (try less specific terms or --bfs)")
		return 1
	}
	eng := query.New(db.SQL())
	for _, m := range matches {
		node, err := eng.GetByIdentifier(m.Type, m.Identifier)
		title := ""
		if err == nil {
			title = titleFromProperties(node.Properties)
		}
		if len(title) > 80 {
			title = title[:77] + "..."
		}
		// SQLite returns negative BM25; flip sign for human-readable "higher = better".
		fmt.Printf("[s=%.2f] %-10s %-40s %s\n", -m.Score, m.Type, m.Identifier, title)
	}
	return 0
}

// buildFTS5Query converts free-text user input into a safe FTS5 MATCH expression.
// Strategy: tokenize on whitespace, drop punctuation-only tokens, join with OR.
// This is forgiving (no syntax errors) and matches what most search UIs expect.
func buildFTS5Query(raw string) string {
	// Strip FTS5 control chars that would cause syntax errors.
	out := make([]byte, 0, len(raw))
	for i := 0; i < len(raw); i++ {
		c := raw[i]
		switch c {
		case '"', '\'', '(', ')', ':', '*', '+', '-':
			out = append(out, ' ')
		default:
			out = append(out, c)
		}
	}
	// Split on whitespace, OR-join.
	var tokens []string
	current := make([]byte, 0, 32)
	for _, c := range out {
		if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
			if len(current) > 0 {
				tokens = append(tokens, string(current))
				current = current[:0]
			}
			continue
		}
		current = append(current, c)
	}
	if len(current) > 0 {
		tokens = append(tokens, string(current))
	}
	if len(tokens) == 0 {
		return ""
	}
	if len(tokens) == 1 {
		return tokens[0]
	}
	result := tokens[0]
	for _, t := range tokens[1:] {
		result += " OR " + t
	}
	return result
}

// runHybrid executes a --hybrid query: rank top-K by stored Ollama embeddings,
// then expand 1-hop edges per match. It falls back to BM25 when no embeddings
// are stored yet.
func runHybrid(db *storage.DB, queryText string, typeFilters []string, topK int) int {
	rows, err := db.IterateEmbeddings(typeFilters)
	if err != nil {
		fmt.Fprintf(os.Stderr, "query: scan embeddings: %v\n", err)
		return 1
	}
	if len(rows) == 0 {
		return runHybridBM25(db, queryText, typeFilters, topK)
	}
	embedder, err := resolveEmbedder()
	if err != nil {
		fmt.Fprintf(os.Stderr, "query: %v\n", err)
		return runHybridBM25(db, queryText, typeFilters, topK)
	}
	queryVec, err := embedder.Embed(embedInputText(queryText))
	if err != nil {
		fmt.Fprintf(os.Stderr, "query: embed: %v\n", err)
		return runHybridBM25(db, queryText, typeFilters, topK)
	}
	candidates := make([]embed.Candidate, 0, len(rows))
	idMap := map[int64]struct{ typ, identifier string }{}
	for _, r := range rows {
		candidates = append(candidates, embed.Candidate{
			NodeID:    r.NodeID,
			Embedding: embed.DecodeVector(r.Embedding),
		})
		idMap[r.NodeID] = struct{ typ, identifier string }{r.Type, r.Identifier}
	}
	matches := embed.TopK(queryVec, candidates, topK)
	if len(matches) == 0 {
		fmt.Fprintln(os.Stderr, "query: no matches")
		return 1
	}
	eng := query.New(db.SQL())
	for _, m := range matches {
		meta := idMap[m.NodeID]
		node, err := eng.GetByIdentifier(meta.typ, meta.identifier)
		title := ""
		if err == nil {
			title = titleFromProperties(node.Properties)
		}
		if len(title) > 70 {
			title = title[:67] + "..."
		}
		fmt.Printf("[s=%.3f] %-10s %-40s %s\n", m.Score, meta.typ, meta.identifier, title)
		neighbors, err := eng.LoadNeighbors(m.NodeID, 5)
		if err != nil {
			continue
		}
		for _, n := range neighbors {
			nTitle := titleFromProperties(n.Properties)
			if len(nTitle) > 60 {
				nTitle = nTitle[:57] + "..."
			}
			fmt.Printf("         → %-10s %-40s %s\n", n.Type, n.Identifier, nTitle)
		}
	}
	return 0
}

func resolveEmbedder() (embed.Embedder, error) {
	return embed.NewOllamaEmbedder(embed.OllamaOptions{})
}

type jsonNode struct {
	Type       string         `json:"type"`
	Identifier string         `json:"identifier"`
	Title      string         `json:"title,omitempty"`
	Properties map[string]any `json:"properties,omitempty"`
}

type jsonBFSResult struct {
	Distance int      `json:"distance"`
	Node     jsonNode `json:"node"`
	Path     []string `json:"path,omitempty"`
}

type bm25MatchJSON struct {
	Score     float64    `json:"score"`
	Node      jsonNode   `json:"node"`
	Neighbors []jsonNode `json:"neighbors,omitempty"`
}

type memoryFreshness struct {
	Repo       string `json:"repo"`
	State      string `json:"state"`
	StaleSince string `json:"stale_since,omitempty"`
	Marker     string `json:"marker,omitempty"`
}

type contextJSON struct {
	Query                 string          `json:"query"`
	TypeFilter            string          `json:"type_filter,omitempty"`
	Mode                  string          `json:"mode"`
	Target                *jsonNode       `json:"target,omitempty"`
	Freshness             memoryFreshness `json:"freshness"`
	Neighborhood          []jsonBFSResult `json:"neighborhood,omitempty"`
	NeighborhoodTotal     int             `json:"neighborhood_total"`
	NeighborhoodReturned  int             `json:"neighborhood_returned"`
	NeighborhoodTruncated bool            `json:"neighborhood_truncated"`
	Matches               []bm25MatchJSON `json:"matches,omitempty"`
}

type callSiteJSON struct {
	CallerIdentifier string   `json:"caller_identifier"`
	CalleeIdentifier string   `json:"callee_identifier,omitempty"`
	CalleeName       string   `json:"callee_name,omitempty"`
	FilePath         string   `json:"file_path,omitempty"`
	Line             int      `json:"line,omitempty"`
	Call             jsonNode `json:"call"`
}

type callersJSON struct {
	Query     string         `json:"query"`
	CallSites []callSiteJSON `json:"call_sites"`
}

type searchJSON struct {
	Command     string          `json:"command"`
	Query       string          `json:"query"`
	Mode        string          `json:"mode,omitempty"`
	TypeFilter  string          `json:"type_filter,omitempty"`
	ResultCount int             `json:"result_count"`
	Matches     []bm25MatchJSON `json:"matches"`
}

type queryJSON struct {
	Command          string          `json:"command"`
	Query            string          `json:"query"`
	Mode             string          `json:"mode"`
	TypeFilter       string          `json:"type_filter,omitempty"`
	Depth            int             `json:"depth,omitempty"`
	Freshness        memoryFreshness `json:"freshness"`
	ResultCount      int             `json:"result_count"`
	Results          []jsonBFSResult `json:"results,omitempty"`
	ResultsTotal     int             `json:"results_total,omitempty"`
	ResultsReturned  int             `json:"results_returned,omitempty"`
	ResultsTruncated bool            `json:"results_truncated,omitempty"`
	Matches          []bm25MatchJSON `json:"matches,omitempty"`
}

type impactJSON struct {
	Query                 string          `json:"query"`
	TypeFilter            string          `json:"type_filter,omitempty"`
	Depth                 int             `json:"depth"`
	Target                jsonNode        `json:"target"`
	Freshness             memoryFreshness `json:"freshness"`
	RelatedTests          []jsonBFSResult `json:"related_tests,omitempty"`
	RecentCommits         []jsonBFSResult `json:"recent_commits,omitempty"`
	Neighborhood          []jsonBFSResult `json:"neighborhood"`
	NeighborhoodTotal     int             `json:"neighborhood_total"`
	NeighborhoodReturned  int             `json:"neighborhood_returned"`
	NeighborhoodTruncated bool            `json:"neighborhood_truncated"`
}

type statusJSON struct {
	Repo            string         `json:"repo"`
	DB              string         `json:"db"`
	State           string         `json:"state"`
	StaleSince      string         `json:"stale_since,omitempty"`
	Marker          string         `json:"marker,omitempty"`
	IndexBuilt      bool           `json:"index_built"`
	NodesTotal      int            `json:"nodes_total"`
	NodeCounts      map[string]int `json:"node_counts"`
	BM25Rows        int            `json:"bm25_rows"`
	EmbeddingRows   int            `json:"embedding_rows"`
	EmbeddingModels map[string]int `json:"embedding_models"`
}

type refreshJSON struct {
	Command string     `json:"command"`
	Status  statusJSON `json:"status"`
}

func writeJSON(v any) int {
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	if err := enc.Encode(v); err != nil {
		fmt.Fprintf(os.Stderr, "json: encode: %v\n", err)
		return 1
	}
	return 0
}

func runBM25SearchJSON(db *storage.DB, command, queryText string, typeFilters []string, topK int) int {
	eng := query.New(db.SQL())
	matches, err := bm25MatchesForJSON(db, eng, queryText, typeFilters, topK)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s: bm25 json: %v\n", command, err)
		return 1
	}
	if len(matches) == 0 {
		fmt.Fprintf(os.Stderr, "%s: no BM25 matches for %q\n", command, queryText)
		return 1
	}
	return writeJSON(searchJSON{
		Command:     command,
		Query:       queryText,
		TypeFilter:  strings.Join(typeFilters, ","),
		ResultCount: len(matches),
		Matches:     matches,
	})
}

func nodeForJSON(n query.Node) jsonNode {
	return jsonNode{
		Type:       n.Type,
		Identifier: n.Identifier,
		Title:      titleFromProperties(n.Properties),
		Properties: propertiesForJSON(n.Properties),
	}
}

func propertiesForJSON(props map[string]any) map[string]any {
	if len(props) == 0 {
		return nil
	}
	out := make(map[string]any, len(props))
	for k, v := range props {
		s, ok := v.(string)
		if !ok || len(s) <= jsonPropertyStringLimit {
			out[k] = v
			continue
		}
		out[k] = truncateJSONString(s, jsonPropertyStringLimit)
		out[k+"_truncated"] = true
		out[k+"_original_bytes"] = len(s)
	}
	return out
}

func truncateJSONString(s string, maxBytes int) string {
	if maxBytes <= 0 {
		return ""
	}
	if len(s) <= maxBytes {
		return s
	}
	cut := 0
	for i := range s {
		if i > maxBytes {
			break
		}
		cut = i
	}
	if cut == 0 {
		return ""
	}
	return s[:cut]
}

func bfsForJSON(results []query.BFSResult, limit int) ([]jsonBFSResult, bool) {
	truncated := limit > 0 && len(results) > limit
	if truncated {
		results = results[:limit]
	}
	out := make([]jsonBFSResult, 0, len(results))
	for _, r := range results {
		out = append(out, jsonBFSResult{
			Distance: r.Distance,
			Node:     nodeForJSON(r.Node),
			Path:     r.Path,
		})
	}
	return out, truncated
}

func bfsByTypeForJSON(results []query.BFSResult, typ string, limit int) []jsonBFSResult {
	out := []jsonBFSResult{}
	for _, r := range results {
		if r.Node.Type != typ {
			continue
		}
		out = append(out, jsonBFSResult{
			Distance: r.Distance,
			Node:     nodeForJSON(r.Node),
			Path:     r.Path,
		})
		if limit > 0 && len(out) >= limit {
			return out
		}
	}
	return out
}

func bm25MatchesForJSON(db *storage.DB, eng *query.Engine, queryText string, typeFilters []string, topK int) ([]bm25MatchJSON, error) {
	matches, err := db.QueryFTS5(buildFTS5Query(queryText), topK, typeFilters)
	if err != nil {
		return nil, err
	}
	out := make([]bm25MatchJSON, 0, len(matches))
	for _, m := range matches {
		node := query.Node{
			ID:         m.NodeID,
			Type:       m.Type,
			Identifier: m.Identifier,
		}
		if loaded, err := eng.GetByIdentifier(m.Type, m.Identifier); err == nil {
			node = *loaded
		}
		neighbors, err := eng.LoadNeighbors(m.NodeID, 5)
		if err != nil {
			neighbors = nil
		}
		jsonNeighbors := make([]jsonNode, 0, len(neighbors))
		for _, n := range neighbors {
			jsonNeighbors = append(jsonNeighbors, nodeForJSON(n))
		}
		out = append(out, bm25MatchJSON{
			// SQLite BM25 returns negative numbers; JSON follows the human CLI:
			// higher positive score means a stronger lexical match.
			Score:     -m.Score,
			Node:      nodeForJSON(node),
			Neighbors: jsonNeighbors,
		})
	}
	return out, nil
}

func titleFromProperties(p map[string]any) string {
	if t, ok := p["title"].(string); ok && t != "" {
		return t
	}
	if d, ok := p["description"].(string); ok && d != "" {
		return d
	}
	if d, ok := p["purpose"].(string); ok && d != "" {
		return d
	}
	if d, ok := p["summary"].(string); ok && d != "" {
		return d
	}
	if sig, ok := p["signature"].(string); ok && sig != "" {
		return sig
	}
	if callee, ok := p["callee_name"].(string); ok && callee != "" {
		if line, ok := p["line"].(float64); ok {
			return fmt.Sprintf("%s at line %d", callee, int(line))
		}
		return callee
	}
	if heading, ok := p["heading"].(string); ok && heading != "" {
		return heading
	}
	if subject, ok := p["subject"].(string); ok && subject != "" {
		return subject
	}
	if name, ok := p["name"].(string); ok && name != "" {
		return name
	}
	if path, ok := p["path"].(string); ok && path != "" {
		return path
	}
	if path, ok := p["file_path"].(string); ok && path != "" {
		if start, ok := p["start_line"].(float64); ok {
			if end, ok := p["end_line"].(float64); ok {
				return fmt.Sprintf("%s:%d-%d", path, int(start), int(end))
			}
		}
		return path
	}
	return ""
}

func resolveNode(eng *query.Engine, target, typ string) (*query.Node, error) {
	if typ != "" {
		return eng.GetByIdentifier(typ, target)
	}
	if node, err := eng.GetByIdentifier("", target); err == nil {
		return node, nil
	}
	symbols, err := eng.ListByType("Symbol")
	if err == nil {
		var match *query.Node
		for i := range symbols {
			if propString(symbols[i].Properties, "name") == target {
				if match != nil {
					return &symbols[i], nil
				}
				match = &symbols[i]
			}
		}
		if match != nil {
			return match, nil
		}
	}
	return eng.GetByIdentifier("", target)
}

func printNodeSummary(n query.Node) {
	title := titleFromProperties(n.Properties)
	if len(title) > 90 {
		title = title[:87] + "..."
	}
	fmt.Printf("%-8s %-55s %s\n", n.Type, n.Identifier, title)
}

func propString(props map[string]any, key string) string {
	if v, ok := props[key].(string); ok {
		return v
	}
	return ""
}

func propFloat(props map[string]any, key string) float64 {
	switch v := props[key].(type) {
	case float64:
		return v
	case int:
		return float64(v)
	default:
		return 0
	}
}

// agentProps reshapes a types.Agent into a properties map for storage.
// M046: memory_path + memory_excerpt are populated when .claude/agent-memory/
// <name>/MEMORY.md exists (native CC memory: project field accumulation). The
// excerpt becomes part of the Agent node's properties JSON → BM25/FTS5 +
// semantic queries search across what each agent has learned across sessions.
// ruleProps converts a business Rule into node properties. Scenarios + link
// lists are stored so query consumers can render the rule and traverse bindings.
func ruleProps(r types.Rule) map[string]any {
	return map[string]any{
		"title":         r.Title,
		"domain":        r.Domain,
		"statement":     r.Statement,
		"scenarios":     r.Scenarios,
		"status":        r.Status,
		"source":        r.Source,
		"rationale":     r.Rationale,
		"implements":    r.Implements,
		"relates":       r.Relates,
		"decided_by":    r.DecidedBy,
		"last_reviewed": r.LastReviewed,
		"body":          r.Body,
	}
}

// lookupCodeRef resolves a rule's implements: reference to a node id, trying
// Symbol ("<relpath>:<name>"), then File ("<relpath>"), then Test. Returns
// false when the ref matches no indexed code node.
func lookupCodeRef(db *storage.DB, ref string) (int64, bool) {
	for _, typ := range []string{"Symbol", "File", "Test"} {
		if id, err := db.LookupNodeID(typ, ref); err == nil {
			return id, true
		}
	}
	return 0, false
}

func agentProps(a types.Agent) map[string]any {
	props := map[string]any{
		"tools":                  a.Tools,
		"model":                  a.Model,
		"effort":                 a.Effort,
		"color":                  a.Color,
		"memory":                 a.Memory,
		"resumable":              a.Resumable,
		"checkpoint_granularity": a.CheckpointGranularity,
		"description":            a.Description,
	}
	if a.MemoryPath != "" {
		props["memory_path"] = a.MemoryPath
		props["memory_excerpt"] = a.MemoryExcerpt
	}
	return props
}

func repoFileProps(f types.RepoFile) map[string]any {
	return map[string]any{
		"path":        f.Path,
		"extension":   f.Extension,
		"language":    f.Language,
		"size_bytes":  f.SizeBytes,
		"line_count":  f.LineCount,
		"chunk_count": f.ChunkCount,
		"sha256":      f.SHA256,
	}
}

func repoChunkProps(c types.RepoChunk) map[string]any {
	return map[string]any{
		"file_path":  c.FilePath,
		"index":      c.Index,
		"start_line": c.StartLine,
		"end_line":   c.EndLine,
		"text":       c.Text,
		"sha256":     c.SHA256,
	}
}

func repoSymbolProps(s types.RepoSymbol) map[string]any {
	return map[string]any{
		"name":       s.Name,
		"kind":       s.Kind,
		"language":   s.Language,
		"file_path":  s.FilePath,
		"start_line": s.StartLine,
		"end_line":   s.EndLine,
		"signature":  s.Signature,
	}
}

func repoCallProps(c types.RepoCall) map[string]any {
	return map[string]any{
		"caller_identifier": c.CallerIdentifier,
		"callee_identifier": c.CalleeIdentifier,
		"callee_name":       c.CalleeName,
		"callee_qualifier":  c.CalleeQualifier,
		"language":          c.Language,
		"file_path":         c.FilePath,
		"line":              c.Line,
		"column":            c.Column,
	}
}

func repoTestProps(t types.RepoTest) map[string]any {
	return map[string]any{
		"name":                     t.Name,
		"kind":                     t.Kind,
		"language":                 t.Language,
		"file_path":                t.FilePath,
		"start_line":               t.StartLine,
		"end_line":                 t.EndLine,
		"target_file_path":         t.TargetFilePath,
		"target_symbol_identifier": t.TargetSymbolIdentifier,
	}
}

func memoryProps(m types.MarkdownMemory) map[string]any {
	return map[string]any{
		"category":   m.Category,
		"file_path":  m.FilePath,
		"heading":    m.Heading,
		"body":       m.Body,
		"start_line": m.StartLine,
		"end_line":   m.EndLine,
	}
}

func commitProps(c types.RepoCommit) map[string]any {
	return map[string]any{
		"short_hash":  c.ShortHash,
		"author_date": c.AuthorDate,
		"subject":     c.Subject,
		"files":       c.Files,
	}
}

type obsidianExportNode struct {
	ID         int64
	Type       string
	Identifier string
	Properties map[string]any
}

func runObsidianExport(args []string) int {
	fs := flag.NewFlagSet("obsidian-export", flag.ExitOnError)
	dbPath := fs.String("db", "", "path to SQLite database (default: privacy.DefaultDBPath for repo)")
	repoPath := fs.String("repo", ".", "repository path for DB default and export metadata")
	outDir := fs.String("out", "", "output Obsidian vault/folder root (default: .aihaus/state/obsidian-export)")
	includeChunks := fs.Bool("include-chunks", false, "include Chunk nodes (can generate many notes)")
	includeCalls := fs.Bool("include-calls", false, "include Call nodes (can generate many notes)")
	limit := fs.Int("limit", 5000, "maximum exported graph nodes (0 = no limit)")
	userMemoryPath := fs.String("user-memory", "", "optional user memory directory to project into user-brain (default: ~/.aihaus/memory/user if present)")
	if err := fs.Parse(args); err != nil {
		return 2
	}

	*repoPath = resolveRepoPath(*repoPath)
	if absRepoPath, err := filepath.Abs(*repoPath); err == nil {
		*repoPath = absRepoPath
	}
	if *outDir == "" {
		*outDir = filepath.Join(*repoPath, ".aihaus", "state", "obsidian-export")
	}
	db, err := openQueryDBForRepo(*dbPath, *repoPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "obsidian-export: open db: %v\n", err)
		return 1
	}
	defer db.Close()

	nodes, skipped, err := loadObsidianExportNodes(db.SQL(), *includeChunks, *includeCalls, *limit)
	if err != nil {
		fmt.Fprintf(os.Stderr, "obsidian-export: load nodes: %v\n", err)
		return 1
	}

	repoName := filepath.Base(*repoPath)
	if repoName == "." || repoName == string(filepath.Separator) || repoName == "" {
		repoName = "repo"
	}
	exportRoot := filepath.Join(*outDir, obsidianSafeName(repoName))
	if err := os.MkdirAll(exportRoot, 0o755); err != nil {
		fmt.Fprintf(os.Stderr, "obsidian-export: create output dir: %v\n", err)
		return 1
	}

	counts := map[string]int{}
	for _, n := range nodes {
		category := obsidianCategoryForType(n.Type)
		if category == "" {
			category = "repo-memory"
		}
		dir := filepath.Join(exportRoot, category, obsidianSafeName(n.Type))
		if err := os.MkdirAll(dir, 0o755); err != nil {
			fmt.Fprintf(os.Stderr, "obsidian-export: create note dir: %v\n", err)
			return 1
		}
		notePath := filepath.Join(dir, obsidianSafeName(n.Identifier)+".md")
		body := formatObsidianNodeNote(repoName, n)
		if err := os.WriteFile(notePath, []byte(body), 0o644); err != nil {
			fmt.Fprintf(os.Stderr, "obsidian-export: write note: %v\n", err)
			return 1
		}
		counts[category]++
	}

	userCount, err := exportUserMemoryProjection(exportRoot, *userMemoryPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "obsidian-export: user memory export: %v\n", err)
		return 1
	}
	counts["user-brain"] += userCount

	if err := writeObsidianIndex(exportRoot, repoName, *repoPath, *dbPath, counts, skipped); err != nil {
		fmt.Fprintf(os.Stderr, "obsidian-export: write index: %v\n", err)
		return 1
	}

	fmt.Printf("obsidian-export: wrote %d graph note(s) to %s\n", len(nodes), exportRoot)
	if skipped > 0 {
		fmt.Printf("obsidian-export: skipped %d high-volume node(s); use --include-chunks/--include-calls or --limit 0 if needed\n", skipped)
	}
	return 0
}

func loadObsidianExportNodes(sqlDB *sql.DB, includeChunks, includeCalls bool, limit int) ([]obsidianExportNode, int, error) {
	rows, err := sqlDB.Query(`
		SELECT id, type, identifier, properties
		FROM nodes
		ORDER BY CASE type
			WHEN 'Symbol' THEN 1
			WHEN 'File' THEN 2
			WHEN 'Test' THEN 3
			WHEN 'Memory' THEN 4
			WHEN 'Rule' THEN 5
			WHEN 'Decision' THEN 6
			WHEN 'Milestone' THEN 7
			WHEN 'Story' THEN 8
			WHEN 'Commit' THEN 9
			WHEN 'Agent' THEN 10
			WHEN 'Skill' THEN 11
			WHEN 'Hook' THEN 12
			WHEN 'Chunk' THEN 90
			WHEN 'Call' THEN 91
			ELSE 99
		END, type, identifier`)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var out []obsidianExportNode
	skipped := 0
	for rows.Next() {
		var n obsidianExportNode
		var propsRaw string
		if err := rows.Scan(&n.ID, &n.Type, &n.Identifier, &propsRaw); err != nil {
			return nil, skipped, err
		}
		if n.Type == "Chunk" && !includeChunks {
			skipped++
			continue
		}
		if n.Type == "Call" && !includeCalls {
			skipped++
			continue
		}
		if limit > 0 && len(out) >= limit {
			skipped++
			continue
		}
		n.Properties = map[string]any{}
		if strings.TrimSpace(propsRaw) != "" {
			_ = json.Unmarshal([]byte(propsRaw), &n.Properties)
		}
		out = append(out, n)
	}
	if err := rows.Err(); err != nil {
		return nil, skipped, err
	}
	return out, skipped, nil
}

func obsidianCategoryForType(typ string) string {
	switch typ {
	case "File", "Chunk", "Symbol", "Call", "Test":
		return "code-brain"
	case "Decision", "Milestone", "Story", "Rule", "Memory", "Commit", "Agent", "Hook", "Skill":
		return "repo-memory"
	default:
		return "repo-memory"
	}
}

func obsidianSafeName(s string) string {
	s = strings.TrimSpace(s)
	if s == "" {
		s = "untitled"
	}
	sum := sha1.Sum([]byte(s))
	suffix := hex.EncodeToString(sum[:])[:8]
	var b strings.Builder
	lastDash := false
	for _, r := range strings.ToLower(s) {
		ok := (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9')
		if ok {
			b.WriteRune(r)
			lastDash = false
			continue
		}
		if !lastDash {
			b.WriteByte('-')
			lastDash = true
		}
		if b.Len() >= 72 {
			break
		}
	}
	base := strings.Trim(b.String(), "-")
	if base == "" {
		base = "note"
	}
	if len(base) > 72 {
		base = strings.Trim(base[:72], "-")
	}
	return base + "-" + suffix
}

func formatObsidianNodeNote(repoName string, n obsidianExportNode) string {
	title := titleFromProperties(n.Properties)
	if title == "" {
		title = n.Identifier
	}
	var b strings.Builder
	b.WriteString("---\n")
	writeYAMLString(&b, "aih_id", n.Type+":"+n.Identifier)
	writeYAMLString(&b, "aih_repo", repoName)
	writeYAMLString(&b, "aih_type", n.Type)
	writeYAMLString(&b, "aih_sync", "export-only")
	writeYAMLString(&b, "title", title)
	b.WriteString("---\n\n")
	b.WriteString("# ")
	b.WriteString(obsidianHeading(title))
	b.WriteString("\n\n")
	b.WriteString("> Generated from aihaus memory. Treat this note as a read-only projection; edit aihaus source memory or code, then export again.\n\n")
	b.WriteString("## Identity\n\n")
	b.WriteString("| Field | Value |\n|---|---|\n")
	b.WriteString("| Type | `")
	b.WriteString(n.Type)
	b.WriteString("` |\n")
	b.WriteString("| Identifier | `")
	b.WriteString(escapeMarkdownTable(n.Identifier))
	b.WriteString("` |\n")
	if path := propString(n.Properties, "file_path"); path != "" {
		b.WriteString("| File | `")
		b.WriteString(escapeMarkdownTable(path))
		b.WriteString("` |\n")
	}
	if name := propString(n.Properties, "name"); name != "" {
		b.WriteString("| Name | `")
		b.WriteString(escapeMarkdownTable(name))
		b.WriteString("` |\n")
	}
	b.WriteString("\n## Properties\n\n")
	b.WriteString("| Key | Value |\n|---|---|\n")
	keys := make([]string, 0, len(n.Properties))
	for k := range n.Properties {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		v := obsidianPropertyValue(n.Properties[k])
		if v == "" {
			continue
		}
		b.WriteString("| `")
		b.WriteString(escapeMarkdownTable(k))
		b.WriteString("` | ")
		b.WriteString(escapeMarkdownTable(v))
		b.WriteString(" |\n")
	}
	if body := firstStringProperty(n.Properties, "body", "text", "content", "description", "summary"); body != "" {
		b.WriteString("\n## Source Text\n\n")
		b.WriteString("```text\n")
		b.WriteString(capString(body, 4000))
		if len(body) > 4000 {
			b.WriteString("\n... [truncated by obsidian-export]\n")
		}
		b.WriteString("\n```\n")
	}
	b.WriteString("\n## aihaus Lookup\n\n")
	b.WriteString("```bash\n")
	b.WriteString("aihaus memory context --repo . --type ")
	b.WriteString(shellQuote(n.Type))
	b.WriteString(" --json ")
	b.WriteString(shellQuote(n.Identifier))
	b.WriteString("\n```\n")
	return b.String()
}

func writeYAMLString(b *strings.Builder, key, value string) {
	encoded, _ := json.Marshal(value)
	b.WriteString(key)
	b.WriteString(": ")
	b.Write(encoded)
	b.WriteByte('\n')
}

func obsidianHeading(s string) string {
	s = strings.ReplaceAll(s, "\r", " ")
	s = strings.ReplaceAll(s, "\n", " ")
	s = strings.TrimSpace(s)
	if s == "" {
		return "Untitled"
	}
	return s
}

func obsidianPropertyValue(v any) string {
	switch x := v.(type) {
	case string:
		return capString(x, 600)
	case float64, bool:
		return fmt.Sprint(x)
	case []any:
		parts := make([]string, 0, len(x))
		for _, item := range x {
			parts = append(parts, capString(fmt.Sprint(item), 120))
			if len(parts) >= 12 {
				parts = append(parts, "...")
				break
			}
		}
		return strings.Join(parts, ", ")
	default:
		if x == nil {
			return ""
		}
		raw, err := json.Marshal(x)
		if err != nil {
			return capString(fmt.Sprint(x), 600)
		}
		return capString(string(raw), 600)
	}
}

func firstStringProperty(props map[string]any, keys ...string) string {
	for _, key := range keys {
		if v, ok := props[key].(string); ok && strings.TrimSpace(v) != "" {
			return v
		}
	}
	return ""
}

func capString(s string, max int) string {
	if max <= 0 || len(s) <= max {
		return s
	}
	for max > 0 && (s[max]&0xc0) == 0x80 {
		max--
	}
	return s[:max]
}

func escapeMarkdownTable(s string) string {
	s = strings.ReplaceAll(s, "\r", " ")
	s = strings.ReplaceAll(s, "\n", "<br>")
	s = strings.ReplaceAll(s, "|", "\\|")
	return s
}

func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", "'\"'\"'") + "'"
}

func exportUserMemoryProjection(exportRoot, userMemoryPath string) (int, error) {
	if userMemoryPath == "" {
		if home, err := os.UserHomeDir(); err == nil && home != "" {
			userMemoryPath = filepath.Join(home, ".aihaus", "memory", "user")
		}
	}
	userDir := filepath.Join(exportRoot, "user-brain")
	if err := os.MkdirAll(userDir, 0o755); err != nil {
		return 0, err
	}
	if userMemoryPath == "" {
		return 0, writeUserMemoryReadme(userDir, "", 0)
	}
	info, err := os.Stat(userMemoryPath)
	if err != nil || !info.IsDir() {
		return 0, writeUserMemoryReadme(userDir, userMemoryPath, 0)
	}
	count := 0
	err = filepath.WalkDir(userMemoryPath, func(path string, entry os.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.IsDir() || strings.ToLower(filepath.Ext(path)) != ".md" {
			return nil
		}
		rel, err := filepath.Rel(userMemoryPath, path)
		if err != nil {
			return err
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		dst := filepath.Join(userDir, filepath.ToSlash(rel))
		if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
			return err
		}
		header := strings.Builder{}
		header.WriteString("---\n")
		writeYAMLString(&header, "aih_source", "user-memory")
		writeYAMLString(&header, "aih_sync", "export-only")
		writeYAMLString(&header, "aih_source_path", path)
		header.WriteString("---\n\n")
		if err := os.WriteFile(dst, append([]byte(header.String()), data...), 0o644); err != nil {
			return err
		}
		count++
		return nil
	})
	if err != nil {
		return count, err
	}
	return count, writeUserMemoryReadme(userDir, userMemoryPath, count)
}

func writeUserMemoryReadme(userDir, source string, count int) error {
	var b strings.Builder
	b.WriteString("# User Brain\n\n")
	b.WriteString("This folder is the optional Obsidian projection for aihaus global user memory.\n")
	b.WriteString("It is export-only; aihaus does not read this Obsidian folder as an authority.\n\n")
	if source == "" {
		b.WriteString("No user memory directory was configured.\n")
	} else {
		b.WriteString("Source: `")
		b.WriteString(escapeMarkdownTable(source))
		b.WriteString("`\n\n")
	}
	b.WriteString(fmt.Sprintf("Projected notes: %d\n", count))
	return os.WriteFile(filepath.Join(userDir, "README.md"), []byte(b.String()), 0o644)
}

func writeObsidianIndex(exportRoot, repoName, repoPath, dbPath string, counts map[string]int, skipped int) error {
	var b strings.Builder
	b.WriteString("# aihaus Memory Export\n\n")
	b.WriteString("This is an Obsidian-compatible, read-only projection of aihaus memory.\n")
	b.WriteString("SQLite/aih-graph remains the operational source of truth.\n\n")
	b.WriteString("## Sources\n\n")
	b.WriteString("- Repo: `")
	b.WriteString(escapeMarkdownTable(repoPath))
	b.WriteString("`\n")
	if dbPath != "" {
		b.WriteString("- DB: `")
		b.WriteString(escapeMarkdownTable(dbPath))
		b.WriteString("`\n")
	}
	b.WriteString("- Generated: `")
	b.WriteString(time.Now().UTC().Format(time.RFC3339))
	b.WriteString("`\n\n")
	b.WriteString("## Brains\n\n")
	b.WriteString("| Brain | Notes |\n|---|---:|\n")
	for _, key := range []string{"code-brain", "repo-memory", "user-brain"} {
		b.WriteString("| [[")
		b.WriteString(key)
		b.WriteString("]] | ")
		b.WriteString(fmt.Sprintf("%d", counts[key]))
		b.WriteString(" |\n")
	}
	if skipped > 0 {
		b.WriteString("\n")
		b.WriteString(fmt.Sprintf("> Skipped %d high-volume graph nodes. Re-run with `--include-chunks`, `--include-calls`, or `--limit 0` when you need a full projection.\n", skipped))
	}
	b.WriteString("\n## Refresh\n\n")
	b.WriteString("```bash\n")
	b.WriteString("aihaus memory refresh --repo .\n")
	b.WriteString("aihaus memory obsidian-export --repo . --out <vault-or-folder>\n")
	b.WriteString("```\n")
	if repoName != "" {
		b.WriteString("\n")
	}
	return os.WriteFile(filepath.Join(exportRoot, "README.md"), []byte(b.String()), 0o644)
}

func keysSorted(m map[string]int) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

func main() {
	flag.Usage = usage

	// Custom dispatch (avoiding cobra dep — stdlib only per M032 scaffold).
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}

	cmd := os.Args[1]
	args := os.Args[2:]
	switch cmd {
	case "version", "--version", "-v":
		fmt.Println(version)
	case "help", "--help", "-h":
		usage()
	case "build":
		os.Exit(runBuild(args))
	case "refresh":
		os.Exit(runRefresh(args))
	case "query":
		os.Exit(runQuery(args))
	case "context":
		os.Exit(runContext(args))
	case "callers":
		os.Exit(runCallers(args))
	case "impact":
		os.Exit(runImpact(args))
	case "gotchas":
		os.Exit(runGotchas(args))
	case "milestone":
		os.Exit(runMilestone(args))
	case "status":
		os.Exit(runStatus(args))
	case "obsidian-export", "export-obsidian":
		os.Exit(runObsidianExport(args))
	case "rule-drift":
		os.Exit(runRuleDrift(args))
	case "rule":
		os.Exit(runRule(args))
	case "why":
		os.Exit(runWhy(args))
	case "mark-stale":
		os.Exit(runMarkStale(args))
	case "uninstall":
		os.Exit(runUninstall(args))
	default:
		fmt.Fprintf(os.Stderr, "aih-graph: unknown command %q\n\n", cmd)
		usage()
		os.Exit(2)
	}
}
