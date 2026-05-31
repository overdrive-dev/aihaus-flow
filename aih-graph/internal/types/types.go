// Package types defines the core domain types for aih-graph.
//
// Per ADR-260521-A, M048 expands aih-graph from aihaus-artifact memory into
// native repository memory. The original 6 aihaus types remain first-class,
// and generic repository types become codebase memory nodes.
//
// Node + Edge are the storage-substrate-shaped generic types; the 6 typed
// structs are property-view structs that consumers of the public API see.
package types

import "time"

// Node is the generic graph node. Properties holds type-specific fields as a
// JSON-serializable map.
type Node struct {
	ID             int64
	Type           string // "Decision" | "Milestone" | "Story" | "Agent" | "Hook" | "Skill" | "Rule" | "File" | "Chunk" | "Symbol" | "Call" | "Test" | "Memory" | "Commit"
	Identifier     string // e.g. "ADR-260514-B", "M030", "aih-milestone"
	Properties     map[string]any
	Embedding      []float32 // optional; nil if not yet embedded
	EmbeddingModel string    // e.g. "ollama:nomic-embed-text" | ""
	ContentSHA     string    // SHA-256 of content used for embedding (change detection)
	CreatedAt      time.Time
	UpdatedAt      time.Time
}

// Edge is a typed relationship between two nodes.
type Edge struct {
	ID         int64
	FromID     int64
	ToID       int64
	Type       string // "contains" | "references" | "amends" | "supersedes" | ...
	Properties map[string]any
	CreatedAt  time.Time
}

// Decision represents an Architecture Decision Record.
// Source: pkg/.aihaus/decisions.md sections beginning with `## ADR-`.
type Decision struct {
	Identifier string // "ADR-260514-B"
	Title      string // header line after the em-dash
	Status     string // "Accepted" | "Proposed" | "Superseded" | etc.
	Date       string // ISO date string
	Milestone  string // milestone tag, e.g. "M030", "M032/S04"
	Amends     string // empty if not an amendment; else the parent ADR identifier
	Body       string // full markdown body of the section
}

// Milestone represents an aihaus execution milestone.
// Source: .aihaus/milestones/<slug>/RUN-MANIFEST.md Metadata section.
type Milestone struct {
	ID          string // "M030"
	Slug        string // "M030-260514-merge-settings-array-aware"
	Status      string // "completed" | "running" | "paused" | "aborted"
	Phase       string // free-text phase label
	PauseClass  string // when status=paused: "external-dep-down" | etc.
	LastUpdated time.Time
}

// Story represents a milestone's atomic work unit.
// Source: RUN-MANIFEST.md Story Records table rows.
type Story struct {
	ID          string // "S01", "S02", ...
	MilestoneID string // parent milestone "M030"
	Summary     string
	Status      string // "completed" | "running" | "draft"
	OwnedFiles  []string
}

// RepoFile represents a text file indexed from the repository itself. It is a
// generic repository-memory node, not an aihaus-only artifact type.
type RepoFile struct {
	Path       string
	Extension  string
	Language   string
	SizeBytes  int64
	LineCount  int
	ChunkCount int
	SHA256     string
}

// RepoChunk represents a bounded text chunk from a RepoFile. Chunk text is
// stored in properties so lexical/vector retrieval can ground answers in code.
type RepoChunk struct {
	Identifier string
	FilePath   string
	Index      int
	StartLine  int
	EndLine    int
	Text       string
	SHA256     string
}

// RepoSymbol represents a code symbol discovered from a source file. M048's
// first extractor supports Go functions/methods plus shell/PowerShell function
// definitions; later stories can add richer language-specific symbols.
type RepoSymbol struct {
	Identifier string
	Name       string
	Kind       string
	Language   string
	FilePath   string
	StartLine  int
	EndLine    int
	Signature  string
}

// RepoCall represents a call expression discovered inside a symbol body. It is
// persisted separately so callers/impact queries can cite call-site evidence.
type RepoCall struct {
	Identifier       string
	CallerIdentifier string
	CalleeIdentifier string
	CalleeName       string
	CalleeQualifier  string
	Language         string
	FilePath         string
	Line             int
	Column           int
}

// RepoTest represents a test file or test function discovered from repository
// code. Target fields are best-effort static links used by impact queries.
type RepoTest struct {
	Identifier             string
	Name                   string
	Kind                   string
	Language               string
	FilePath               string
	StartLine              int
	EndLine                int
	TargetFilePath         string
	TargetSymbolIdentifier string
}

// MarkdownMemory is a human-curated memory section extracted from aihaus
// markdown memory files. The database stores it as a derived Memory node; the
// source-of-truth stays in markdown.
type MarkdownMemory struct {
	Identifier string
	Category   string
	FilePath   string
	Heading    string
	Body       string
	StartLine  int
	EndLine    int
}

// RepoCommit is recent git history captured as temporal repository memory.
type RepoCommit struct {
	Hash       string
	ShortHash  string
	AuthorDate string
	Subject    string
	Files      []string
}

// Agent represents an aihaus agent definition.
// Source: pkg/.aihaus/agents/<name>.md YAML frontmatter + body.
// MemoryPath + MemoryExcerpt populated when .claude/agent-memory/<name>/MEMORY.md
// exists (native CC memory: project field — first 200 lines or 25KB per docs).
type Agent struct {
	Name                  string
	Tools                 []string
	Model                 string // "opus" | "sonnet" | "haiku"
	Effort                string // "medium" | "high" | "xhigh" | "max"
	Color                 string
	Memory                string
	Resumable             bool
	CheckpointGranularity string // "story" | "file" | "step"
	Description           string // first non-frontmatter paragraph
	MemoryPath            string // relative path to .claude/agent-memory/<name>/MEMORY.md if present
	MemoryExcerpt         string // first 200 lines or 25KB of MEMORY.md (matches native CC injection)
}

// Hook represents an aihaus shell hook script.
// Source: pkg/.aihaus/hooks/<name>.sh header comment + bash function declarations.
type Hook struct {
	Name      string   // "bash-guard.sh"
	Path      string   // "pkg/.aihaus/hooks/bash-guard.sh"
	Purpose   string   // from leading comment block
	Functions []string // declared bash function names
	SizeBytes int64
}

// Skill represents an aihaus user-invocable skill.
// Source: pkg/.aihaus/skills/aih-<name>/SKILL.md YAML frontmatter.
type Skill struct {
	Name                   string // "aih-milestone"
	Description            string
	DisableModelInvocation bool
	AllowedTools           []string
	ArgumentHint           string
}

// Rule represents a business rule from the decision-autonomy contract.
// Source: .aihaus/memory/workflows/business-rules.md sections beginning with
// `### BR-`. Per ADR-260531-A. Scenarios are the BDD core (Given/When/Then);
// Implements / Relates / DecidedBy are cross-link fields used to build edges to
// code symbols/files/tests, other rules, and ADRs. The markdown ledger stays the
// source of truth; aih-graph indexes Rule nodes so agents can query rule↔code.
type Rule struct {
	Identifier   string   // "BR-001", "BR-F1"
	Title        string   // header line after the em-dash
	Domain       string   // "software" | "design" | "infra" | "security" | "data" | "compliance"
	Statement    string   // one-line business statement (WHAT must hold)
	Scenarios    []string // Given/When/Then lines
	Status       string   // "proposed" | "accepted" | "deprecated"
	Source       string   // who defined the premise + when
	Rationale    string   // why this rule exists
	Implements   []string // symbol/file/test references (→ code edges)
	Relates      []string // BR-<id> references (→ rule edges)
	DecidedBy    []string // ADR-<id> references (→ ADR edges)
	LastReviewed string   // commit SHA (staleness anchor)
	Body         string   // full markdown body of the section
}
