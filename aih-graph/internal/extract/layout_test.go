package extract

import "testing"

func TestInstalledAihausLayoutExtractsAgentsSkillsHooksAndMemory(t *testing.T) {
	root := t.TempDir()
	writeFile(t, root, ".aihaus/agents/workflow-planning-gate.md", `---
name: workflow-planning-gate
tools: Read, Bash
model: sonnet
effort: high
color: blue
memory: project
resumable: true
checkpoint_granularity: story
description: Planning gate
---

Plans workflow gates.
`)
	writeFile(t, root, ".claude/agent-memory/workflow-planning-gate/MEMORY.md", `# Memory

## Repo preference

Ask business questions before TDD.
`)
	writeFile(t, root, ".aihaus/skills/aih-workflow/SKILL.md", `---
name: aih-workflow
description: Manage workflow state
---
`)
	writeFile(t, root, ".aihaus/hooks/aih-graph-refresh.sh", "#!/usr/bin/env bash\nrefresh_memory() {\n  :\n}\n")
	writeFile(t, root, ".aihaus/knowledge.md", "# Knowledge\n\n## K-001\n\nUse planning gates.\n")

	agents, err := ParseAgentsDir(root)
	if err != nil {
		t.Fatalf("ParseAgentsDir returned error: %v", err)
	}
	if len(agents) != 1 || agents[0].Name != "workflow-planning-gate" {
		t.Fatalf("unexpected agents: %#v", agents)
	}
	if agents[0].MemoryPath == "" || agents[0].MemoryExcerpt == "" {
		t.Fatalf("expected agent memory to be attached: %#v", agents[0])
	}

	skills, err := ParseSkillsDir(root)
	if err != nil {
		t.Fatalf("ParseSkillsDir returned error: %v", err)
	}
	if len(skills) != 1 || skills[0].Name != "aih-workflow" {
		t.Fatalf("unexpected skills: %#v", skills)
	}

	hooks, err := ParseHooksDir(root)
	if err != nil {
		t.Fatalf("ParseHooksDir returned error: %v", err)
	}
	if len(hooks) != 1 || hooks[0].Path != ".aihaus/hooks/aih-graph-refresh.sh" {
		t.Fatalf("unexpected hooks: %#v", hooks)
	}

	memories, err := ParseMarkdownMemory(root)
	if err != nil {
		t.Fatalf("ParseMarkdownMemory returned error: %v", err)
	}
	foundKnowledge := false
	foundAgentMemory := false
	for _, memory := range memories {
		if memory.FilePath == ".aihaus/knowledge.md" && memory.Category == "knowledge" {
			foundKnowledge = true
		}
		if memory.FilePath == ".claude/agent-memory/workflow-planning-gate/MEMORY.md" && memory.Category == "agent" {
			foundAgentMemory = true
		}
	}
	if !foundKnowledge || !foundAgentMemory {
		t.Fatalf("expected installed memory files to be indexed: %#v", memories)
	}
}
