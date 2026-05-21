package extract

import "testing"

func TestParseGitLogExtractsCommitsAndFiles(t *testing.T) {
	log := "--AIH-COMMIT--abcdef\x00abc123\x002026-05-21T12:00:00Z\x00feat: one\n" +
		"b.go\n" +
		"a.go\n" +
		"--AIH-COMMIT--123456\x00123456\x002026-05-20T12:00:00Z\x00fix: two\n" +
		"README.md\n"

	commits := parseGitLog(log)
	if len(commits) != 2 {
		t.Fatalf("expected 2 commits, got %d: %#v", len(commits), commits)
	}
	if commits[0].ShortHash != "abc123" || commits[0].Subject != "feat: one" {
		t.Fatalf("unexpected first commit: %#v", commits[0])
	}
	if len(commits[0].Files) != 2 || commits[0].Files[0] != "a.go" || commits[0].Files[1] != "b.go" {
		t.Fatalf("unexpected sorted files: %#v", commits[0].Files)
	}
}
