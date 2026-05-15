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
// M032 status: foundation scaffold only. Subcommand bodies are stubs that
// return "not implemented in M032 — see ADR-260515-* for milestone-by-feature
// breakdown". Real implementations land in M033–M038.
package main

import (
	"flag"
	"fmt"
	"os"
)

const version = "0.1.0-dev"

// usage prints the top-level CLI help.
func usage() {
	fmt.Fprintf(os.Stderr, `aih-graph %s — aihaus standalone memory engine (foundation scaffold)

Usage:
  aih-graph <command> [flags]

Commands:
  build <path>            Build/refresh graph (AST + embed)               (impl: M033–M035)
  query "<question>"      Hybrid SQL+vec query over graph                 (impl: M035)
    --bfs                 Structural BFS only (no embeddings needed)
    --semantic            Vector similarity (cosine) ranking
    --budget N            Token cap on returned context
  save-result             Persist Q&A to per-repo graph memory            (impl: M035)
  uninstall [--purge]     Remove aih-graph state (single .db file delete) (impl: M036)
  version                 Print version
  help                    Show this help

Flags vary per command — run "aih-graph <command> --help" once implemented.

Specs:
  pkg/.aihaus/decisions.md  — ADR-260515-A through -E (+ C-amend-01)
  aih-graph/PRD.md          — v0.1 forever-scope

M032: foundation scaffold only. All subcommands currently return
"not implemented" — see milestone trail in aihaus's decisions.md.
`, version)
}

// runStub is the not-yet-implemented placeholder for M033–M036 commands.
func runStub(cmd string) int {
	fmt.Fprintf(os.Stderr, "aih-graph %s: not implemented in M032 foundation scaffold.\n", cmd)
	fmt.Fprintf(os.Stderr, "See pkg/.aihaus/decisions.md ADR-260515-* for milestone-by-feature breakdown.\n")
	return 1
}

func main() {
	flag.Usage = usage

	// Custom dispatch (avoiding cobra dep — stdlib only per M032 scaffold).
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}

	cmd := os.Args[1]
	switch cmd {
	case "version", "--version", "-v":
		fmt.Println(version)
	case "help", "--help", "-h":
		usage()
	case "build", "query", "save-result", "uninstall":
		os.Exit(runStub(cmd))
	default:
		fmt.Fprintf(os.Stderr, "aih-graph: unknown command %q\n\n", cmd)
		usage()
		os.Exit(2)
	}
}
