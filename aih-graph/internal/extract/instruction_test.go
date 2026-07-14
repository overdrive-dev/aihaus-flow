package extract

import "testing"

func TestInstalledAihausLayoutExtractsPortableInstructionsAndMemory(t *testing.T) {
	root := t.TempDir()
	writeFile(t, root, ".aihaus/MAP.md", "# aihaus Map\n\nRoute narrowly.\n")
	writeFile(t, root, ".aihaus/conventions.md", "# Conventions\n\nFiles are truth.\n")
	writeFile(t, root, ".aihaus/roles/planner.md", "# Role: planner\n\nPlan the smallest coherent path.\n")
	writeFile(t, root, ".aihaus/rooms/feature/CONTEXT.md", "# Room: feature\n\nDeliver behavior.\n")
	writeFile(t, root, ".aihaus/contracts/evidence.md", "# Contract: evidence\n\nRequire executable proof.\n")
	writeFile(t, root, ".aihaus/tools/check.mjs", "#!/usr/bin/env node\n// deterministic check\n")
	writeFile(t, root, ".aihaus/memory/project/knowledge.md", "# Knowledge\n\n## K-001\n\nUse file tasks.\n")

	instructions, err := ParseInstructionsDir(root)
	if err != nil {
		t.Fatalf("ParseInstructionsDir returned error: %v", err)
	}
	if len(instructions) != 6 {
		t.Fatalf("expected six portable instructions, got %#v", instructions)
	}
	want := map[string]string{
		"Contract/evidence":      "Contract: evidence",
		"Convention/conventions": "Conventions",
		"Map/MAP":                "aihaus Map",
		"Role/planner":           "Role: planner",
		"Room/feature":           "Room: feature",
		"Tool/check":             "check",
	}
	for _, instruction := range instructions {
		key := instruction.Type + "/" + instruction.Identifier
		if title, ok := want[key]; !ok || instruction.Title != title {
			t.Fatalf("unexpected instruction: %#v", instruction)
		}
		delete(want, key)
	}
	if len(want) != 0 {
		t.Fatalf("missing instructions: %#v", want)
	}

	memories, err := ParseMarkdownMemory(root)
	if err != nil {
		t.Fatalf("ParseMarkdownMemory returned error: %v", err)
	}
	found := false
	for _, memory := range memories {
		if memory.FilePath == ".aihaus/memory/project/knowledge.md" && memory.Category == "project" {
			found = true
		}
	}
	if !found {
		t.Fatalf("expected typed project memory to be indexed: %#v", memories)
	}
}
