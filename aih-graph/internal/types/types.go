// Package types defines the core domain types for aih-graph.
//
// Per ADR-260515-B-amend-02 (pure-Go SQLite) + ADR-260515-C-amend-02
// (markdown-only extraction) + ADR-260515-E-amend-03 (6 aihaus typed nodes only
// in v0.1), the 6 first-class types are Decision, Milestone, Story, Agent,
// Hook, Skill.
//
// Node + Edge are the storage-substrate-shaped generic types; the 6 typed
// structs are property-view structs that consumers of the public API see.
package types

import "time"

// Node is the generic graph node. Properties holds type-specific fields as a
// JSON-serializable map.
type Node struct {
	ID             int64
	Type           string // "Decision" | "Milestone" | "Story" | "Agent" | "Hook" | "Skill"
	Identifier     string // e.g. "ADR-260514-B", "M030", "aih-milestone"
	Properties     map[string]any
	Embedding      []float32 // optional; nil if not yet embedded
	EmbeddingModel string    // e.g. "voyage-3" | "local-minilm" | ""
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
	ID          string    // "M030"
	Slug        string    // "M030-260514-merge-settings-array-aware"
	Status      string    // "completed" | "running" | "paused" | "aborted"
	Phase       string    // free-text phase label
	PauseClass  string    // when status=paused: "external-dep-down" | etc.
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
