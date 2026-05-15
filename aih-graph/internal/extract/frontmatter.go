package extract

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strings"

	"gopkg.in/yaml.v3"
)

// frontmatterDelim is the canonical YAML frontmatter delimiter line.
const frontmatterDelim = "---"

// readFrontmatter reads a markdown file and returns (yaml bytes, body bytes).
// Returns an empty yaml slice if the file does not begin with `---\n`.
// The body includes everything after the closing delimiter.
func readFrontmatter(path string) ([]byte, []byte, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, nil, fmt.Errorf("open %s: %w", path, err)
	}
	defer f.Close()

	all, err := io.ReadAll(f)
	if err != nil {
		return nil, nil, fmt.Errorf("read %s: %w", path, err)
	}
	return splitFrontmatter(all)
}

// splitFrontmatter splits the leading `---\n…\n---\n` block from the rest.
// Returns (yaml, body, nil). Returns ([]byte{}, body, nil) when no frontmatter
// is present (i.e. file does not start with the delimiter).
//
// UTF-8 BOM (0xEF 0xBB 0xBF) at the start is silently stripped — several
// SKILL.md files in this repo carry it (likely created by a Windows editor).
func splitFrontmatter(b []byte) ([]byte, []byte, error) {
	// Strip UTF-8 BOM if present.
	if len(b) >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF {
		b = b[3:]
	}

	// File must start with `---\n` to have frontmatter.
	if !startsWith(b, []byte(frontmatterDelim+"\n")) && !startsWith(b, []byte(frontmatterDelim+"\r\n")) {
		return nil, b, nil
	}

	// Scan lines after the opening delimiter looking for the closing one.
	r := strings.NewReader(string(b))
	scanner := bufio.NewScanner(r)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)

	var (
		inYAML       bool
		yamlBuf      strings.Builder
		bodyStartIdx int
		offset       int
	)

	for scanner.Scan() {
		line := scanner.Text()
		offset += len(line) + 1 // +1 for the \n consumed by Scanner
		if !inYAML {
			// First line — opening delimiter. Confirmed by startsWith check above.
			inYAML = true
			continue
		}
		if strings.TrimRight(line, "\r") == frontmatterDelim {
			// Closing delimiter found.
			bodyStartIdx = offset
			break
		}
		yamlBuf.WriteString(line)
		yamlBuf.WriteByte('\n')
	}

	if err := scanner.Err(); err != nil {
		return nil, nil, fmt.Errorf("scan frontmatter: %w", err)
	}

	if bodyStartIdx == 0 {
		// Unterminated frontmatter — treat the whole file as body, no frontmatter.
		return nil, b, nil
	}

	body := b[bodyStartIdx:]
	// Trim leading newlines from body — common after `---\n`.
	for len(body) > 0 && (body[0] == '\n' || body[0] == '\r') {
		body = body[1:]
	}
	return []byte(yamlBuf.String()), body, nil
}

func startsWith(b, prefix []byte) bool {
	if len(b) < len(prefix) {
		return false
	}
	for i, c := range prefix {
		if b[i] != c {
			return false
		}
	}
	return true
}

// parseFrontmatterInto decodes the leading YAML frontmatter of path into dst.
// Returns the markdown body bytes (everything after the closing delimiter).
// If the file has no frontmatter, dst is left unchanged and body == file content.
func parseFrontmatterInto(path string, dst any) ([]byte, error) {
	yamlBytes, body, err := readFrontmatter(path)
	if err != nil {
		return nil, err
	}
	if len(yamlBytes) == 0 {
		return body, nil
	}
	if err := yaml.Unmarshal(yamlBytes, dst); err != nil {
		return nil, fmt.Errorf("yaml unmarshal %s: %w", path, err)
	}
	return body, nil
}
