package extract

import (
	"bytes"
	"crypto/sha256"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"unicode/utf8"

	"github.com/overdrive-dev/aihaus-flow/aih-graph/internal/types"
)

const (
	maxRepoFileBytes  = 512 * 1024
	maxRepoChunkChars = 6000
)

// neverIndexRepoDirs is the explicit safety boundary applied even when Git
// says a path is tracked. Managed instructions and memory are indexed by their
// typed extractors rather than duplicated as generic repository text.
var neverIndexRepoDirs = map[string]struct{}{
	".git":             {},
	".aihaus-download": {},
	".aihaus-lab":      {},
}

var genericExcludedRepoDirs = map[string]struct{}{
	".aihaus": {},
	".claude": {},
}

// fallbackSkippedRepoDirs is used only outside a Git worktree, where there is
// no authoritative .gitignore evaluation.
var fallbackSkippedRepoDirs = map[string]struct{}{
	".venv":        {},
	"venv":         {},
	"__pycache__":  {},
	"node_modules": {},
	"vendor":       {},
	"dist":         {},
	"build":        {},
	"bin":          {},
	"coverage":     {},
	"target":       {},
	"tmp":          {},
}

var neverIndexRepoArtifacts = map[string]struct{}{
	".aih-graph-consent": {},
	"aih-graph.stale":    {},
}

var textExtensions = map[string]string{
	".go":            "go",
	".sh":            "bash",
	".bash":          "bash",
	".ps1":           "powershell",
	".md":            "markdown",
	".txt":           "text",
	".json":          "json",
	".jsonl":         "jsonl",
	".yml":           "yaml",
	".yaml":          "yaml",
	".toml":          "toml",
	".js":            "javascript",
	".jsx":           "javascript",
	".ts":            "typescript",
	".tsx":           "typescript",
	".css":           "css",
	".html":          "html",
	".cmd":           "batch",
	".bat":           "batch",
	".gitignore":     "gitignore",
	".gitattributes": "gitattributes",
}

// ParseRepositoryText returns repository text files plus bounded chunks. Git
// worktrees are enumerated with `git ls-files --cached --others
// --exclude-standard`, so nested ignore rules and negations are honored.
// Explicit safety exclusions remain authoritative even for tracked files.
func ParseRepositoryText(repoRoot string) ([]types.RepoFile, []types.RepoChunk, error) {
	var files []types.RepoFile
	var chunks []types.RepoChunk

	paths, err := repositoryTextPaths(repoRoot)
	if err != nil {
		return nil, nil, err
	}
	for _, rel := range paths {
		lang := languageForPath(rel)
		if lang == "" {
			continue
		}

		path := filepath.Join(repoRoot, filepath.FromSlash(rel))
		info, err := os.Lstat(path)
		if err != nil || !info.Mode().IsRegular() || info.Size() > maxRepoFileBytes {
			continue
		}
		data, err := os.ReadFile(path)
		if err != nil || looksBinary(data) || !utf8.Valid(data) {
			continue
		}

		text := string(data)
		fileChunks := chunkText(rel, text)
		file := types.RepoFile{
			Path:       rel,
			Extension:  strings.ToLower(filepath.Ext(rel)),
			Language:   lang,
			SizeBytes:  info.Size(),
			LineCount:  countLines(text),
			ChunkCount: len(fileChunks),
			SHA256:     sha256Hex(data),
		}
		files = append(files, file)
		chunks = append(chunks, fileChunks...)
	}

	sort.Slice(files, func(i, j int) bool { return files[i].Path < files[j].Path })
	sort.Slice(chunks, func(i, j int) bool { return chunks[i].Identifier < chunks[j].Identifier })
	return files, chunks, nil
}

func repositoryTextPaths(repoRoot string) ([]string, error) {
	cmd := exec.Command("git", "-C", repoRoot, "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--")
	out, err := cmd.Output()
	if err == nil {
		return filterRepositoryPaths(out), nil
	}

	// A failed enumeration inside an apparent worktree is an error: silently
	// walking it would ignore .gitignore and could index excluded artifacts.
	probe := exec.Command("git", "-C", repoRoot, "rev-parse", "--is-inside-work-tree")
	probeOut, probeErr := probe.Output()
	_, markerErr := os.Lstat(filepath.Join(repoRoot, ".git"))
	if (probeErr == nil && strings.TrimSpace(string(probeOut)) == "true") || markerErr == nil {
		return nil, fmt.Errorf("enumerate repository files with git ls-files: %w", err)
	}
	return walkRepositoryPaths(repoRoot)
}

func filterRepositoryPaths(output []byte) []string {
	var paths []string
	for _, raw := range bytes.Split(output, []byte{0}) {
		if len(raw) == 0 {
			continue
		}
		rel := filepath.ToSlash(filepath.Clean(filepath.FromSlash(string(raw))))
		if !validRepositoryRelativePath(rel) || neverIndexRepositoryPath(rel) {
			continue
		}
		paths = append(paths, rel)
	}
	sort.Strings(paths)
	return paths
}

func walkRepositoryPaths(repoRoot string) ([]string, error) {
	var paths []string
	err := filepath.WalkDir(repoRoot, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return nil
		}
		rel, err := filepath.Rel(repoRoot, path)
		if err != nil {
			return nil
		}
		rel = filepath.ToSlash(rel)
		if rel == "." {
			return nil
		}
		if entry.IsDir() {
			name := strings.ToLower(entry.Name())
			if neverIndexRepositoryPath(rel) {
				return filepath.SkipDir
			}
			if _, skip := fallbackSkippedRepoDirs[name]; skip {
				return filepath.SkipDir
			}
			return nil
		}
		if entry.Type()&fs.ModeType != 0 || neverIndexRepositoryPath(rel) {
			return nil
		}
		paths = append(paths, rel)
		return nil
	})
	if err != nil {
		return nil, fmt.Errorf("walk repository text: %w", err)
	}
	sort.Strings(paths)
	return paths, nil
}

func validRepositoryRelativePath(rel string) bool {
	return rel != "" && rel != "." && !filepath.IsAbs(rel) && rel != ".." && !strings.HasPrefix(rel, "../")
}

func neverIndexRepositoryPath(rel string) bool {
	normalized := strings.ToLower(strings.TrimPrefix(filepath.ToSlash(rel), "./"))
	parts := strings.Split(normalized, "/")
	for i, part := range parts {
		if part == ".aihaus" && i+1 < len(parts) && parts[i+1] == "state" {
			return true
		}
		if _, excluded := neverIndexRepoDirs[part]; excluded {
			return true
		}
		if _, excluded := genericExcludedRepoDirs[part]; excluded {
			return true
		}
	}
	base := parts[len(parts)-1]
	if _, excluded := neverIndexRepoArtifacts[base]; excluded {
		return true
	}
	return isDatabaseArtifact(base)
}

func isDatabaseArtifact(base string) bool {
	for _, suffix := range []string{".db", ".sqlite", ".sqlite3"} {
		if strings.HasSuffix(base, suffix) {
			return true
		}
		for _, sidecar := range []string{"-journal", "-shm", "-wal"} {
			if strings.HasSuffix(base, suffix+sidecar) {
				return true
			}
		}
	}
	return false
}

func languageForPath(rel string) string {
	base := strings.ToLower(filepath.Base(rel))
	if lang, ok := textExtensions[base]; ok {
		return lang
	}
	ext := strings.ToLower(filepath.Ext(rel))
	return textExtensions[ext]
}

func looksBinary(data []byte) bool {
	for _, b := range data {
		if b == 0 {
			return true
		}
	}
	return false
}

func countLines(text string) int {
	if text == "" {
		return 0
	}
	n := strings.Count(text, "\n")
	if !strings.HasSuffix(text, "\n") {
		n++
	}
	return n
}

func chunkText(rel, text string) []types.RepoChunk {
	lines := strings.SplitAfter(text, "\n")
	if len(lines) == 0 {
		return nil
	}

	var out []types.RepoChunk
	var b strings.Builder
	startLine := 1
	lineNo := 1
	chunkIndex := 1

	flush := func(endLine int) {
		if b.Len() == 0 {
			return
		}
		chunkText := b.String()
		out = append(out, types.RepoChunk{
			Identifier: fmt.Sprintf("%s#chunk-%04d", rel, chunkIndex),
			FilePath:   rel,
			Index:      chunkIndex,
			StartLine:  startLine,
			EndLine:    endLine,
			Text:       chunkText,
			SHA256:     sha256Hex([]byte(chunkText)),
		})
		chunkIndex++
		b.Reset()
	}

	for _, line := range lines {
		if b.Len() > 0 && b.Len()+len(line) > maxRepoChunkChars {
			flush(lineNo - 1)
			startLine = lineNo
		}
		b.WriteString(line)
		lineNo++
	}
	flush(lineNo - 1)
	return out
}

func sha256Hex(data []byte) string {
	sum := sha256.Sum256(data)
	const hex = "0123456789abcdef"
	out := make([]byte, 64)
	for i, b := range sum {
		out[i*2] = hex[b>>4]
		out[i*2+1] = hex[b&0x0f]
	}
	return string(out)
}
