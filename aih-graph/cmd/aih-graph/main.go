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
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"sort"

	"github.com/overdrive-dev/aihaus-flow/aih-graph/internal/extract"
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
		fmt.Println("(dry-run: nothing persisted; M034 wires modernc/sqlite storage)")
	} else {
		fmt.Println("note: M034 not yet implemented — persistence skipped. Pass --dry-run to suppress this warning.")
	}

	_ = decisions
	_ = agents
	_ = skills
	_ = hooks
	_ = milestones
	_ = stories

	return 0
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
	case "query", "save-result", "uninstall":
		os.Exit(runStub(cmd))
	default:
		fmt.Fprintf(os.Stderr, "aih-graph: unknown command %q\n\n", cmd)
		usage()
		os.Exit(2)
	}
}
