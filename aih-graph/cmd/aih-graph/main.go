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
// modernc.org/sqlite storage + BM25/FTS5 lexical search (default; pure-Go,
// no API key) + optional opt-in external embedding providers + Go-native
// KNN + 3-mode query (BFS / semantic / hybrid) + 6 typed accessor structs.
// See PRD.md for full spec.
package main

import (
	"database/sql"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
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
var version = "0.1.4-dev"

// usage prints the top-level CLI help.
func usage() {
	fmt.Fprintf(os.Stderr, `aih-graph %s — aihaus standalone memory engine

Usage:
  aih-graph <command> [flags]

Commands:
  build <repo-path>       Extract aihaus graph from repo
    --dry-run             Print extraction summary without persisting
    --embed-provider P    bm25 (default) | ollama | fake | none
    --accept-all-repos    Bypass consent gate (auto-creates marker)
  query "<question>"      Query the graph (default: hybrid)
    --bfs                 Structural BFS only (no embeddings needed)
    --semantic            Vector similarity (cosine) ranking
    --budget N            Token cap on returned context
  context <node-or-topic> Show exact-node neighborhood or hybrid retrieval
  callers <symbol>        List call sites that target a symbol/name
  impact <node>           Show graph neighborhood for impact analysis
  gotchas [topic]         Search markdown memory for gotchas/learnings
  milestone <target>      Search milestone, decision, commit, and memory links
  status [--repo PATH]    Show memory index freshness and counts
  mark-stale [--reason R] Mark derived memory stale after repo changes
  uninstall [--purge]     Remove aih-graph state (single .db file delete)
  version                 Print version
  help                    Show this help

Specs:
  pkg/.aihaus/decisions.md  — ADR-260515-A through -E (+ amendments), ADR-260516-A
  aih-graph/PRD.md          — v0.1 forever-scope
`, version)
}

func openQueryDB(dbPath string) (*storage.DB, error) {
	if dbPath == "" {
		if resolved, err := privacy.DefaultDBPath("."); err == nil {
			dbPath = resolved
		} else {
			dbPath = "aih-graph.db"
		}
	}
	return storage.Open(dbPath)
}

func resetDerivedIndex(db *storage.DB) error {
	_, err := db.SQL().Exec(`
		DELETE FROM edges;
		DELETE FROM nodes_fts;
		DELETE FROM nodes;
	`)
	return err
}

// runBuild implements the M033 build subcommand. Extracts Decision / Agent /
// Skill / Hook nodes; Milestone + Story parsers land in follow-on commits.
func runBuild(args []string) int {
	fs := flag.NewFlagSet("build", flag.ExitOnError)
	dryRun := fs.Bool("dry-run", false, "print extraction summary without persisting")
	dbPath := fs.String("db", "", "path to SQLite database file (default: XDG state dir, per-repo isolated)")
	embedProvider := fs.String("embed-provider", "bm25", "search provider: bm25|ollama|fake|none (default bm25 — pure-Go offline lexical via FTS5)")
	acceptAll := fs.Bool("accept-all-repos", false, "bypass consent gate (auto-creates .aih-graph-consent marker)")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if fs.NArg() < 1 {
		fmt.Fprintln(os.Stderr, "build: <repo-path> required")
		fmt.Fprintln(os.Stderr, "usage: aih-graph build [--db PATH] [--embed-provider P] [--accept-all-repos] [--dry-run] <repo-path>")
		return 2
	}

	repoPath := fs.Arg(0)
	decisionsPath := filepath.Join(repoPath, "pkg", ".aihaus", "decisions.md")
	if _, err := os.Stat(decisionsPath); err != nil {
		fmt.Fprintf(os.Stderr, "build: %s not found\n", decisionsPath)
		return 1
	}

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
		if err := privacy.CreateConsent(repoPath); err != nil {
			fmt.Fprintf(os.Stderr, "build: create consent marker: %v\n", err)
			return 1
		}
		fmt.Fprintf(os.Stderr, "build: created consent marker (--accept-all-repos)\n")
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

	// Search pipeline.
	switch *embedProvider {
	case "", "none":
		// Skip — structural BFS still works without any search index.
	case "bm25":
		if err := runBM25Pipeline(db, decisions, agents, skills, hooks, milestones, stories, repoFiles, repoChunks, repoSymbols, repoCalls, memories, commits); err != nil {
			fmt.Fprintf(os.Stderr, "build: bm25: %v\n", err)
			return 1
		}
	case "voyage", "ollama", "fake":
		provider, err := buildEmbedProvider(*embedProvider)
		if err != nil {
			fmt.Fprintf(os.Stderr, "build: embed provider: %v\n", err)
			return 1
		}
		if err := runEmbedPipeline(db, provider, decisions, agents, skills, hooks, milestones, stories, repoFiles, repoChunks, repoSymbols, repoCalls, memories, commits); err != nil {
			fmt.Fprintf(os.Stderr, "build: embed: %v\n", err)
			return 1
		}
	default:
		fmt.Fprintf(os.Stderr, "build: unknown --embed-provider %q (want bm25|voyage|ollama|fake|none)\n", *embedProvider)
		return 2
	}
	clearStaleMarker(repoPath)
	return 0
}

// runBM25Pipeline writes one FTS5 row per node. Per-node text is the same
// text used for vector embedding providers (same embedTextFor* helpers), so
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
	memories []types.MarkdownMemory,
	commits []types.RepoCommit,
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
	for _, m := range memories {
		units = append(units, unit{"Memory", m.Identifier, embedTextForMemory(m)})
	}
	for _, c := range commits {
		units = append(units, unit{"Commit", c.Hash, embedTextForCommit(c)})
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

// buildEmbedProvider returns a configured embed.Provider by name.
func buildEmbedProvider(name string) (embed.Provider, error) {
	switch name {
	case "voyage":
		return embed.NewVoyageProvider(embed.VoyageOptions{})
	case "ollama":
		return embed.NewOllamaProvider(embed.OllamaOptions{})
	case "fake":
		return embed.NewFakeProvider(1024), nil
	default:
		return nil, fmt.Errorf("unknown provider %q (want voyage|ollama|fake|none)", name)
	}
}

// embedTextForDecision returns the text aih-graph embeds for each Decision
// node. We include the title + status + body so vector queries can match
// against the actual decision narrative.
func embedTextForDecision(d types.Decision) string {
	return d.Identifier + "\n" + d.Title + "\n" + d.Status + "\n" + d.Body
}

func embedTextForAgent(a types.Agent) string {
	return a.Name + "\n" + a.Description
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

func embedTextForMemory(m types.MarkdownMemory) string {
	return m.Identifier + "\n" + m.Category + "\n" + m.FilePath + "\n" + m.Heading + "\n" + m.Body
}

func embedTextForCommit(c types.RepoCommit) string {
	return c.ShortHash + "\n" + c.AuthorDate + "\n" + c.Subject + "\n" + strings.Join(c.Files, "\n")
}

// runEmbedPipeline iterates extracted nodes and writes embeddings + content
// SHAs onto the persisted rows. SHA-based change detection skips nodes whose
// stored content_sha already matches the current text.
func runEmbedPipeline(
	db *storage.DB,
	provider embed.Provider,
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
	memories []types.MarkdownMemory,
	commits []types.RepoCommit,
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
	for _, m := range memories {
		units = append(units, unit{"Memory", m.Identifier, embedTextForMemory(m)})
	}
	for _, c := range commits {
		units = append(units, unit{"Commit", c.Hash, embedTextForCommit(c)})
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
		vec, err := provider.Embed(u.text)
		if err != nil {
			fmt.Fprintf(os.Stderr, "  embed: skip %s %s: %v\n", u.typ, u.identifier, err)
			errs++
			continue
		}
		if err := db.UpdateEmbedding(nodeID, embed.EncodeVector(vec), provider.Model(), sha); err != nil {
			errs++
			continue
		}
		embedded++
	}
	fmt.Printf("Embedded %d nodes (%s; %d skipped — SHA match; %d errors)\n",
		embedded, provider.Model(), skipped, errs)
	return nil
}

// runQuery implements the M035 query subcommand. BFS (structural) and
// --semantic (vector similarity) supported. Hybrid query (SQL pre-filter +
// vector ranking + edge expansion) lands in subsequent M035 commit.
func runQuery(args []string) int {
	fs := flag.NewFlagSet("query", flag.ExitOnError)
	dbPath := fs.String("db", "", "path to SQLite database (default: privacy.DefaultDBPath for cwd, matching `build`)")
	bfs := fs.Bool("bfs", false, "structural BFS query (default if no other mode set)")
	semantic := fs.Bool("semantic", false, "vector similarity (cosine) ranking — pure KNN")
	hybrid := fs.Bool("hybrid", false, "hybrid mode: KNN top-K + 1-hop edge expansion per match")
	depth := fs.Int("depth", 1, "BFS depth (hops outward from root)")
	typ := fs.String("type", "", "restrict root match (BFS) or candidate type (semantic/hybrid) to a node type")
	topK := fs.Int("top", 10, "semantic/hybrid: number of top matches to return")
	provider := fs.String("embed-provider", "", "semantic/hybrid: embedding provider (voyage|ollama|fake; default: derive from stored embedding_model)")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if fs.NArg() < 1 {
		fmt.Fprintln(os.Stderr, "query: <identifier-or-text> required")
		fmt.Fprintln(os.Stderr, "usage: aih-graph query [--bfs|--semantic|--hybrid] [--type T] [--depth N] [--top K] [--db PATH] <identifier-or-text>")
		return 2
	}
	// Default mode: bfs unless --semantic or --hybrid explicitly set.
	if !*semantic && !*bfs && !*hybrid {
		*bfs = true
	}

	// Resolve --db default: match build's default (XDG path keyed by cwd hash).
	// Mirrors install.sh / /aih-init expectation: build and query agree on
	// where the repo's graph lives without the user passing --db each time.
	if *dbPath == "" {
		if resolved, err := privacy.DefaultDBPath("."); err == nil {
			*dbPath = resolved
		} else {
			*dbPath = "aih-graph.db"
		}
	}

	db, err := storage.Open(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "query: open db: %v\n", err)
		return 1
	}
	defer db.Close()

	if *hybrid {
		return runHybrid(db, fs.Arg(0), *typ, *topK, *provider)
	}
	if *semantic {
		return runSemantic(db, fs.Arg(0), *typ, *topK, *provider)
	}

	// BFS mode.
	identifier := fs.Arg(0)
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
		title := titleFromProperties(r.Node.Properties)
		if len(title) > 80 {
			title = title[:77] + "..."
		}
		fmt.Printf("[d=%d] %-10s %-40s %s\n", r.Distance, r.Node.Type, r.Node.Identifier, title)
	}
	return 0
}

// runSemantic executes a --semantic query: routes to BM25/FTS5 lexical
// search when provider=bm25 (or auto-detected as default); otherwise embeds
// the query and KNN-ranks stored vector embeddings by cosine similarity.
func runSemantic(db *storage.DB, queryText, typeFilter string, topK int, providerName string) int {
	// Auto-detect: prefer BM25 if FTS5 has rows; else fall back to vector providers.
	if providerName == "" {
		if n, _ := db.CountFTS(); n > 0 {
			providerName = "bm25"
		}
	}
	if providerName == "bm25" {
		return runSemanticBM25(db, queryText, typeFilter, topK)
	}
	// Determine provider. If --embed-provider not passed, detect from stored
	// rows (first row's embedding_model). Falls back to "fake" if nothing stored.
	if providerName == "" {
		rows, err := db.IterateEmbeddings("")
		if err == nil && len(rows) > 0 {
			// Re-look up the model name (IterateEmbeddings doesn't return it
			// in the row struct; query directly).
			var model sql.NullString
			_ = db.SQL().QueryRow(
				"SELECT embedding_model FROM nodes WHERE id = ?", rows[0].NodeID,
			).Scan(&model)
			if model.String == "fake-sha256" {
				providerName = "fake"
			} else if strings.HasPrefix(model.String, "ollama:") {
				providerName = "ollama"
			} else if model.String != "" {
				providerName = "voyage"
			} else {
				providerName = "fake"
			}
		} else {
			providerName = "fake"
		}
	}
	provider, err := buildEmbedProvider(providerName)
	if err != nil {
		fmt.Fprintf(os.Stderr, "query: %v\n", err)
		return 1
	}

	queryVec, err := provider.Embed(queryText)
	if err != nil {
		fmt.Fprintf(os.Stderr, "query: embed query: %v\n", err)
		return 1
	}

	rows, err := db.IterateEmbeddings(typeFilter)
	if err != nil {
		fmt.Fprintf(os.Stderr, "query: scan embeddings: %v\n", err)
		return 1
	}
	if len(rows) == 0 {
		fmt.Fprintln(os.Stderr, "query: no embeddings stored (run `aih-graph build --embed-provider ollama|fake|voyage` first)")
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

func runContext(args []string) int {
	fs := flag.NewFlagSet("context", flag.ExitOnError)
	dbPath := fs.String("db", "", "path to SQLite database")
	typ := fs.String("type", "", "optional exact type filter")
	depth := fs.Int("depth", 1, "exact-node graph depth")
	topK := fs.Int("top", 8, "hybrid fallback result count")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if fs.NArg() < 1 {
		fmt.Fprintln(os.Stderr, "usage: aih-graph context [--db PATH] [--type T] <node-or-topic>")
		return 2
	}
	db, err := openQueryDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "context: open db: %v\n", err)
		return 1
	}
	defer db.Close()

	target := fs.Arg(0)
	eng := query.New(db.SQL())
	node, err := resolveNode(eng, target, *typ)
	if err != nil {
		fmt.Printf("No exact node for %q; showing hybrid memory matches.\n", target)
		return runHybrid(db, target, *typ, *topK, "bm25")
	}
	fmt.Println("Exact memory context:")
	printNodeSummary(*node)
	results, err := eng.BFS(node.Type, node.Identifier, *depth)
	if err != nil {
		fmt.Fprintf(os.Stderr, "context: bfs: %v\n", err)
		return 1
	}
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
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if fs.NArg() < 1 {
		fmt.Fprintln(os.Stderr, "usage: aih-graph callers [--db PATH] <symbol-name-or-identifier>")
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
		fmt.Printf("%-55s %s:%d calls %s\n", caller, file, line, calleeName)
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
	typ := fs.String("type", "", "optional exact type filter")
	depth := fs.Int("depth", 2, "graph depth")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if fs.NArg() < 1 {
		fmt.Fprintln(os.Stderr, "usage: aih-graph impact [--db PATH] [--type T] <node>")
		return 2
	}
	db, err := openQueryDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "impact: open db: %v\n", err)
		return 1
	}
	defer db.Close()
	eng := query.New(db.SQL())
	target := fs.Arg(0)
	node, err := resolveNode(eng, target, *typ)
	if err != nil {
		fmt.Fprintf(os.Stderr, "impact: no exact node found for %q; use `query --hybrid` to discover identifiers\n", target)
		return 1
	}
	fmt.Println("Impact neighborhood:")
	printNodeSummary(*node)
	results, err := eng.BFS(node.Type, node.Identifier, *depth)
	if err != nil {
		fmt.Fprintf(os.Stderr, "impact: bfs: %v\n", err)
		return 1
	}
	for _, r := range results {
		if r.Distance == 0 {
			continue
		}
		fmt.Printf("[d=%d] ", r.Distance)
		printNodeSummary(r.Node)
	}
	return 0
}

func runGotchas(args []string) int {
	fs := flag.NewFlagSet("gotchas", flag.ExitOnError)
	dbPath := fs.String("db", "", "path to SQLite database")
	topK := fs.Int("top", 8, "result count")
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
	return runHybrid(db, queryText, "Memory", *topK, "bm25")
}

func runMilestone(args []string) int {
	fs := flag.NewFlagSet("milestone", flag.ExitOnError)
	dbPath := fs.String("db", "", "path to SQLite database")
	topK := fs.Int("top", 10, "result count")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if fs.NArg() < 1 {
		fmt.Fprintln(os.Stderr, "usage: aih-graph milestone [--db PATH] <file|symbol|commit|milestone-topic>")
		return 2
	}
	db, err := openQueryDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "milestone: open db: %v\n", err)
		return 1
	}
	defer db.Close()
	return runHybrid(db, strings.Join(fs.Args(), " "), "", *topK, "bm25")
}

func runStatus(args []string) int {
	fs := flag.NewFlagSet("status", flag.ExitOnError)
	dbPath := fs.String("db", "", "path to SQLite database")
	repoPath := fs.String("repo", ".", "repository path for default DB and stale marker")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if fs.NArg() > 0 {
		*repoPath = fs.Arg(0)
	}
	resolvedDB := *dbPath
	var err error
	if resolvedDB == "" {
		resolvedDB, err = privacy.DefaultDBPath(*repoPath)
		if err != nil {
			fmt.Fprintf(os.Stderr, "status: resolve db path: %v\n", err)
			return 1
		}
	}
	fmt.Printf("aih-graph status %s\n", *repoPath)
	fmt.Printf("  db: %s\n", resolvedDB)

	stalePath, staleErr := staleMarkerPath(*repoPath)
	staleInfo, staleStatErr := os.Stat(stalePath)
	if staleErr == nil && staleStatErr == nil {
		fmt.Printf("  state: stale (since %s)\n", staleInfo.ModTime().Format(time.RFC3339))
		fmt.Printf("  marker: %s\n", stalePath)
	} else {
		fmt.Println("  state: fresh")
	}

	if _, err := os.Stat(resolvedDB); err != nil {
		if os.IsNotExist(err) {
			fmt.Println("  index: not built")
			return 0
		}
		fmt.Fprintf(os.Stderr, "status: stat db: %v\n", err)
		return 1
	}
	db, err := storage.Open(resolvedDB)
	if err != nil {
		fmt.Fprintf(os.Stderr, "status: open db: %v\n", err)
		return 1
	}
	defer db.Close()

	counts, err := db.CountByType()
	if err != nil {
		fmt.Fprintf(os.Stderr, "status: count nodes: %v\n", err)
		return 1
	}
	total := 0
	for _, n := range counts {
		total += n
	}
	ftsRows, _ := db.CountFTS()
	embeddingRows := 0
	_ = db.SQL().QueryRow("SELECT COUNT(*) FROM nodes WHERE embedding IS NOT NULL").Scan(&embeddingRows)
	fmt.Printf("  nodes: %d\n", total)
	for _, t := range keysSorted(counts) {
		fmt.Printf("    %s: %d\n", t, counts[t])
	}
	fmt.Printf("  bm25_rows: %d\n", ftsRows)
	fmt.Printf("  embedding_rows: %d\n", embeddingRows)
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
	return filepath.Join(abs, ".claude", "audit", "aih-graph.stale"), nil
}

func clearStaleMarker(repoPath string) {
	path, err := staleMarkerPath(repoPath)
	if err != nil {
		return
	}
	_ = os.Remove(path)
}

// runUninstall implements the M036 uninstall subcommand. Modes:
//
//	--purge        delete ALL aih-graph state (entire XDG state root)
//	<repo-path>    delete the .db for that specific repo only
//	(no args)      print where state lives + exit 0
func runUninstall(args []string) int {
	fs := flag.NewFlagSet("uninstall", flag.ExitOnError)
	purgeAll := fs.Bool("purge", false, "delete ALL aih-graph state (every repo)")
	if err := fs.Parse(args); err != nil {
		return 2
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
func runHybridBM25(db *storage.DB, queryText, typeFilter string, topK int) int {
	matches, err := db.QueryFTS5(buildFTS5Query(queryText), topK, typeFilter)
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
func runSemanticBM25(db *storage.DB, queryText, typeFilter string, topK int) int {
	fts5Query := buildFTS5Query(queryText)
	matches, err := db.QueryFTS5(fts5Query, topK, typeFilter)
	if err != nil {
		fmt.Fprintf(os.Stderr, "query: bm25: %v\n", err)
		return 1
	}
	if len(matches) == 0 {
		fmt.Fprintln(os.Stderr, "query: no BM25 matches (try less specific terms or --bfs/--semantic with vector provider)")
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

// runHybrid executes a --hybrid query: rank top-K by similarity, then expand
// 1-hop edges per match. Routes to BM25 (FTS5) when no vector embeddings are
// stored but FTS5 has rows (default post-M041); otherwise vector KNN path.
func runHybrid(db *storage.DB, queryText, typeFilter string, topK int, providerName string) int {
	// Auto-route to BM25 hybrid when FTS5 has rows and (a) no provider
	// specified, or (b) provider explicitly bm25, or (c) no embeddings stored.
	if providerName == "" || providerName == "bm25" {
		ftsRows, _ := db.CountFTS()
		embRows, _ := db.IterateEmbeddings("")
		if ftsRows > 0 && (providerName == "bm25" || len(embRows) == 0) {
			return runHybridBM25(db, queryText, typeFilter, topK)
		}
	}
	provider, err := resolveProvider(db, providerName)
	if err != nil {
		fmt.Fprintf(os.Stderr, "query: %v\n", err)
		return 1
	}
	queryVec, err := provider.Embed(queryText)
	if err != nil {
		fmt.Fprintf(os.Stderr, "query: embed: %v\n", err)
		return 1
	}
	rows, err := db.IterateEmbeddings(typeFilter)
	if err != nil {
		fmt.Fprintf(os.Stderr, "query: scan embeddings: %v\n", err)
		return 1
	}
	if len(rows) == 0 {
		fmt.Fprintln(os.Stderr, "query: no embeddings stored (run `aih-graph build --embed-provider P` first)")
		return 1
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

// resolveProvider picks an embed.Provider: explicit name wins; else detect
// from stored embedding_model (first non-empty row); else default to fake.
func resolveProvider(db *storage.DB, providerName string) (embed.Provider, error) {
	if providerName == "" {
		rows, err := db.IterateEmbeddings("")
		if err == nil && len(rows) > 0 {
			var model sql.NullString
			_ = db.SQL().QueryRow(
				"SELECT embedding_model FROM nodes WHERE id = ?", rows[0].NodeID,
			).Scan(&model)
			if model.String == "fake-sha256" {
				providerName = "fake"
			} else if strings.HasPrefix(model.String, "ollama:") {
				providerName = "ollama"
			} else if model.String != "" {
				providerName = "voyage"
			} else {
				providerName = "fake"
			}
		} else {
			providerName = "fake"
		}
	}
	return buildEmbedProvider(providerName)
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
