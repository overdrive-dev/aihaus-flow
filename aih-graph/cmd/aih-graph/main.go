// Package main implements the aih-graph CLI.
//
// aih-graph is aihaus's standalone Go binary memory engine. It builds and
// queries a knowledge graph of aihaus-managed repositories with first-class
// ontological types (Decision, Milestone, Story, Agent, Hook, Skill).
//
// v0.1 forever-scope (per ADR-260515-B-amend-02 + C-amend-02 + E-amend-03):
// Pure-Go (zero CGO) + markdown-only extraction for 6 aihaus typed nodes +
// modernc.org/sqlite storage + vector embeddings (Voyage / local ONNX) +
// Go-native KNN + 3-mode query (BFS / semantic / hybrid) + 6 typed accessor
// structs. See PRD.md for full spec.
//
// M033 in progress: ADR extraction implemented; remaining 5 type parsers
// (Milestone, Story, Agent, Hook, Skill) + modernc/sqlite storage land in
// follow-on commits within M033-M034.
package main

import (
	"database/sql"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"sort"

	"github.com/overdrive-dev/aihaus-flow/aih-graph/internal/extract"
	"github.com/overdrive-dev/aihaus-flow/aih-graph/internal/query"
	"github.com/overdrive-dev/aihaus-flow/aih-graph/internal/storage"
	"github.com/overdrive-dev/aihaus-flow/aih-graph/internal/types"
)

const version = "0.1.0-dev"

// usage prints the top-level CLI help.
func usage() {
	fmt.Fprintf(os.Stderr, `aih-graph %s — aihaus standalone memory engine (M033 in progress)

Usage:
  aih-graph <command> [flags]

Commands:
  build <repo-path>       Extract aihaus graph from repo                  (M033 partial: ADRs only)
    --dry-run             Print extraction summary without persisting
  query "<question>"      Hybrid SQL+vec query over graph                 (impl: M035)
    --bfs                 Structural BFS only (no embeddings needed)
    --semantic            Vector similarity (cosine) ranking
    --budget N            Token cap on returned context
  save-result             Persist Q&A to per-repo graph memory            (impl: M035)
  uninstall [--purge]     Remove aih-graph state (single .db file delete) (impl: M036)
  version                 Print version
  help                    Show this help

Specs:
  pkg/.aihaus/decisions.md  — ADR-260515-A through -E (+ amendments)
  aih-graph/PRD.md          — v0.1 forever-scope
`, version)
}

// runStub is the not-yet-implemented placeholder for unimplemented commands.
func runStub(cmd string) int {
	fmt.Fprintf(os.Stderr, "aih-graph %s: not implemented yet.\n", cmd)
	fmt.Fprintf(os.Stderr, "See pkg/.aihaus/decisions.md ADR-260515-* for milestone-by-feature breakdown.\n")
	return 1
}

// runBuild implements the M033 build subcommand. Extracts Decision / Agent /
// Skill / Hook nodes; Milestone + Story parsers land in follow-on commits.
func runBuild(args []string) int {
	fs := flag.NewFlagSet("build", flag.ExitOnError)
	dryRun := fs.Bool("dry-run", false, "print extraction summary without persisting")
	dbPath := fs.String("db", "aih-graph.db", "path to SQLite database file (created if missing)")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if fs.NArg() < 1 {
		fmt.Fprintln(os.Stderr, "build: <repo-path> required")
		fmt.Fprintln(os.Stderr, "usage: aih-graph build <repo-path> [--dry-run]")
		return 2
	}

	repoPath := fs.Arg(0)
	decisionsPath := filepath.Join(repoPath, "pkg", ".aihaus", "decisions.md")
	if _, err := os.Stat(decisionsPath); err != nil {
		fmt.Fprintf(os.Stderr, "build: %s not found\n", decisionsPath)
		return 1
	}

	fmt.Printf("aih-graph build %s\n", repoPath)

	// Decision (ADR) extraction.
	decisions, err := extract.ParseDecisionsFile(decisionsPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "build: parse decisions.md: %v\n", err)
		return 1
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

	// Agent extraction.
	agents, err := extract.ParseAgentsDir(repoPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "build: parse agents: %v\n", err)
		return 1
	}
	modelCounts := map[string]int{}
	for _, a := range agents {
		modelCounts[a.Model]++
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
	return 0
}

// runQuery implements the M035 query subcommand. Initial release supports
// BFS (structural) mode only; --semantic / hybrid require embedding pipeline
// (deferred to subsequent M035 commit).
func runQuery(args []string) int {
	fs := flag.NewFlagSet("query", flag.ExitOnError)
	dbPath := fs.String("db", "aih-graph.db", "path to SQLite database")
	bfs := fs.Bool("bfs", true, "structural BFS query (default; only mode implemented)")
	semantic := fs.Bool("semantic", false, "vector similarity (NOT YET IMPLEMENTED)")
	depth := fs.Int("depth", 1, "BFS depth (hops outward from root)")
	typ := fs.String("type", "", "restrict root match to a node type (Decision|Milestone|Story|Agent|Hook|Skill)")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *semantic {
		fmt.Fprintln(os.Stderr, "query: --semantic not yet implemented (M035 embedding pipeline pending)")
		return 1
	}
	_ = bfs
	if fs.NArg() < 1 {
		fmt.Fprintln(os.Stderr, "query: <identifier> required")
		fmt.Fprintln(os.Stderr, "usage: aih-graph query [--type T] [--depth N] [--db PATH] <identifier>")
		return 2
	}
	identifier := fs.Arg(0)

	db, err := storage.Open(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "query: open db: %v\n", err)
		return 1
	}
	defer db.Close()

	eng := query.New(db.SQL())
	results, err := eng.BFS(*typ, identifier, *depth)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			fmt.Fprintf(os.Stderr, "query: no node matches identifier %q (type filter=%q)\n", identifier, *typ)
			return 1
		}
		fmt.Fprintf(os.Stderr, "query: %v\n", err)
		return 1
	}

	for _, r := range results {
		title := ""
		if t, ok := r.Node.Properties["title"].(string); ok {
			title = t
		} else if d, ok := r.Node.Properties["description"].(string); ok {
			title = d
		}
		if len(title) > 80 {
			title = title[:77] + "..."
		}
		fmt.Printf("[d=%d] %-10s %-40s %s\n", r.Distance, r.Node.Type, r.Node.Identifier, title)
	}
	return 0
}

// agentProps reshapes a types.Agent into a properties map for storage.
func agentProps(a types.Agent) map[string]any {
	return map[string]any{
		"tools":                  a.Tools,
		"model":                  a.Model,
		"effort":                 a.Effort,
		"color":                  a.Color,
		"memory":                 a.Memory,
		"resumable":              a.Resumable,
		"checkpoint_granularity": a.CheckpointGranularity,
		"description":            a.Description,
	}
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
	case "query":
		os.Exit(runQuery(args))
	case "save-result", "uninstall":
		os.Exit(runStub(cmd))
	default:
		fmt.Fprintf(os.Stderr, "aih-graph: unknown command %q\n\n", cmd)
		usage()
		os.Exit(2)
	}
}
