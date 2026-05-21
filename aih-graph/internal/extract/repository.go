package extract

import (
	"crypto/sha256"
	"fmt"
	"io/fs"
	"os"
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

var skippedRepoDirs = map[string]struct{}{
	".git":         {},
	".aihaus":      {},
	".claude":      {},
	"node_modules": {},
	"vendor":       {},
	"dist":         {},
	"build":        {},
	"bin":          {},
	"coverage":     {},
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

// ParseRepositoryText walks repoRoot and returns text files plus bounded chunks.
// It is intentionally conservative: binary files, large files, generated
// dependency trees, and runtime state directories are skipped. M048 follow-up
// stories can replace this with .gitignore-aware and parser-backed extraction.
func ParseRepositoryText(repoRoot string) ([]types.RepoFile, []types.RepoChunk, error) {
	var files []types.RepoFile
	var chunks []types.RepoChunk

	err := filepath.WalkDir(repoRoot, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return nil
		}
		name := entry.Name()
		if entry.IsDir() {
			if _, skip := skippedRepoDirs[name]; skip {
				return filepath.SkipDir
			}
			return nil
		}
		if entry.Type()&fs.ModeType != 0 {
			return nil
		}

		rel, err := filepath.Rel(repoRoot, path)
		if err != nil {
			return nil
		}
		rel = filepath.ToSlash(rel)
		lang := languageForPath(rel)
		if lang == "" {
			return nil
		}

		info, err := entry.Info()
		if err != nil || info.Size() > maxRepoFileBytes {
			return nil
		}
		data, err := os.ReadFile(path)
		if err != nil || looksBinary(data) || !utf8.Valid(data) {
			return nil
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
		return nil
	})
	if err != nil {
		return nil, nil, fmt.Errorf("walk repository text: %w", err)
	}

	sort.Slice(files, func(i, j int) bool { return files[i].Path < files[j].Path })
	sort.Slice(chunks, func(i, j int) bool { return chunks[i].Identifier < chunks[j].Identifier })
	return files, chunks, nil
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
