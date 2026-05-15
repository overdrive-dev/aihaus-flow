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

// runBuild implements the M033 build subcommand. Currently extracts ADRs only;
// remaining 5 types land in follow-on commits within M033.
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

	decisions, err := extract.ParseDecisionsFile(decisionsPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "build: parse decisions.md: %v\n", err)
		return 1
	}

	// Summary by status + milestone.
	statusCounts := map[string]int{}
	milestoneCounts := map[string]int{}
	amendCount := 0
	for _, d := range decisions {
		statusCounts[d.Status]++
		if d.Milestone != "" {
			milestoneCounts[d.Milestone]++
		}
		if d.Amends != "" {
			amendCount++
		}
	}

	fmt.Printf("aih-graph build %s\n", repoPath)
	fmt.Printf("  decisions.md: %s\n", decisionsPath)
	fmt.Printf("  ADRs extracted: %d (%d are amendments)\n", len(decisions), amendCount)

	fmt.Println("  by status:")
	statuses := keysSorted(statusCounts)
	for _, s := range statuses {
		label := s
		if label == "" {
			label = "(no Status field)"
		}
		fmt.Printf("    %-30s %d\n", label, statusCounts[s])
	}

	if *dryRun {
		fmt.Println()
		fmt.Println("(dry-run: nothing persisted; M034 wires modernc/sqlite storage)")
	} else {
		fmt.Println()
		fmt.Println("note: M034 not yet implemented — persistence skipped. Use --dry-run to suppress this warning.")
	}

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
