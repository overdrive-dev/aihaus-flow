package extract

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/overdrive-dev/aihaus-flow/aih-graph/internal/types"
)

// bashFuncRe matches a bash function declaration line.
// Examples:
//
//	my_func() {
//	function my_func() {
//	function my_func {
var bashFuncRe = regexp.MustCompile(`^(?:function\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*\)\s*\{?\s*$`)

// ParseHooksDir walks pkg/.aihaus/hooks/*.sh and returns one Hook per file.
// Per-file extraction:
//   - Purpose: the contiguous comment block at the top of the file (skipping
//     the shebang line). Blank lines terminate the block.
//   - Functions: every line matching bashFuncRe.
//   - SizeBytes: file size from stat.
func ParseHooksDir(repoRoot string) ([]types.Hook, error) {
	matches, err := globUnique(filepath.Join(repoRoot, ".aihaus", "hooks", "*.sh"))
	if err == nil && len(matches) == 0 {
		matches, err = globUnique(filepath.Join(repoRoot, "pkg", ".aihaus", "hooks", "*.sh"))
	}
	if err != nil {
		return nil, fmt.Errorf("glob hooks: %w", err)
	}

	hooks := make([]types.Hook, 0, len(matches))
	for _, path := range matches {
		h, err := parseHookFile(repoRoot, path)
		if err != nil {
			return nil, err
		}
		hooks = append(hooks, h)
	}
	return hooks, nil
}

func parseHookFile(repoRoot, path string) (types.Hook, error) {
	st, err := os.Stat(path)
	if err != nil {
		return types.Hook{}, fmt.Errorf("stat %s: %w", path, err)
	}
	f, err := os.Open(path)
	if err != nil {
		return types.Hook{}, fmt.Errorf("open %s: %w", path, err)
	}
	defer f.Close()

	relPath, _ := filepath.Rel(repoRoot, path)
	// Normalize to forward-slash for portability across Unix/Windows.
	relPath = filepath.ToSlash(relPath)

	h := types.Hook{
		Name:      filepath.Base(path),
		Path:      relPath,
		SizeBytes: st.Size(),
	}

	scanner := bufio.NewScanner(f)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)

	var (
		seenShebang   bool
		inHeaderBlock = true
		headerBuf     strings.Builder
		functions     []string
		seenFuncs     = map[string]struct{}{}
	)

	for scanner.Scan() {
		line := scanner.Text()
		trimmed := strings.TrimSpace(line)

		// Skip the shebang line for header-block purposes.
		if !seenShebang && strings.HasPrefix(trimmed, "#!") {
			seenShebang = true
			continue
		}

		// Build the header comment block from the contiguous run of `#` lines
		// at the top of the file. A blank line OR a non-comment line ends it.
		if inHeaderBlock {
			switch {
			case strings.HasPrefix(trimmed, "#"):
				clean := strings.TrimSpace(strings.TrimPrefix(trimmed, "#"))
				if headerBuf.Len() > 0 {
					headerBuf.WriteByte(' ')
				}
				headerBuf.WriteString(clean)
				continue
			case trimmed == "":
				// First blank line after the comment block closes it.
				if headerBuf.Len() > 0 {
					inHeaderBlock = false
				}
				continue
			default:
				inHeaderBlock = false
			}
		}

		// Function declarations can appear anywhere; collect distinct ones.
		if m := bashFuncRe.FindStringSubmatch(line); m != nil {
			name := m[1]
			if _, seen := seenFuncs[name]; !seen {
				seenFuncs[name] = struct{}{}
				functions = append(functions, name)
			}
		}
	}
	if err := scanner.Err(); err != nil {
		return types.Hook{}, fmt.Errorf("scan %s: %w", path, err)
	}

	h.Purpose = strings.TrimSpace(headerBuf.String())
	h.Functions = functions
	return h, nil
}
