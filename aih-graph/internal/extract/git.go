package extract

import (
	"fmt"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"

	"github.com/overdrive-dev/aihaus-flow/aih-graph/internal/types"
)

const commitHeaderPrefix = "--AIH-COMMIT--"

// ParseGitCommits extracts recent git history as temporal repository memory.
// Missing git or non-git repositories are treated as an empty history.
func ParseGitCommits(repoRoot string, limit int) ([]types.RepoCommit, error) {
	if limit <= 0 {
		limit = 200
	}
	out, err := exec.Command(
		"git", "-C", repoRoot, "log",
		fmt.Sprintf("--max-count=%d", limit),
		"--name-only",
		"--pretty=format:"+commitHeaderPrefix+"%H%x00%h%x00%aI%x00%s",
	).Output()
	if err != nil {
		return nil, nil
	}
	return parseGitLog(string(out)), nil
}

func parseGitLog(output string) []types.RepoCommit {
	lines := strings.Split(output, "\n")
	var commits []types.RepoCommit
	var current *types.RepoCommit
	for _, raw := range lines {
		line := strings.TrimSpace(raw)
		if line == "" {
			continue
		}
		if strings.HasPrefix(line, commitHeaderPrefix) {
			if current != nil {
				commits = append(commits, *current)
			}
			fields := strings.SplitN(strings.TrimPrefix(line, commitHeaderPrefix), "\x00", 4)
			current = &types.RepoCommit{}
			if len(fields) > 0 {
				current.Hash = fields[0]
			}
			if len(fields) > 1 {
				current.ShortHash = fields[1]
			}
			if len(fields) > 2 {
				current.AuthorDate = fields[2]
			}
			if len(fields) > 3 {
				current.Subject = fields[3]
			}
			continue
		}
		if current == nil {
			continue
		}
		current.Files = append(current.Files, filepath.ToSlash(line))
	}
	if current != nil {
		commits = append(commits, *current)
	}
	for i := range commits {
		sort.Strings(commits[i].Files)
	}
	return commits
}
