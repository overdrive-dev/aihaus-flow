// Package privacy implements aih-graph's privacy contract per ADR-260515-A
// (privacy) + ADR-260515-B-amend-02 (single .db file per repo as the isolation
// primitive).
//
// Three guarantees:
//
//  1. Per-repo isolation: each repository gets its own SQLite file at an
//     XDG-resolved path keyed by a hash of the repo's absolute path.
//  2. Explicit consent: `aih-graph build` refuses on any repo that does not
//     contain a `.aih-graph-consent` marker, unless the user passes
//     --accept-all-repos.
//  3. Surgical removal: `aih-graph uninstall --purge` deletes ALL aih-graph
//     state (single file delete in the canonical layout; per-repo .db files
//     under the XDG state root removed wholesale).
package privacy

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

// ConsentMarker is the filename aih-graph looks for at the repo root to
// confirm the user has opted in to building a graph for this repo.
const ConsentMarker = ".aih-graph-consent"

// XDGStateRoot returns the canonical aih-graph state directory per platform.
//
//	Linux / *BSD:  $XDG_STATE_HOME/aih-graph  (fallback ~/.local/state/aih-graph)
//	macOS:         ~/Library/Application Support/aih-graph
//	Windows:       %LOCALAPPDATA%/aih-graph
//
// Honors AIH_GRAPH_HOME for explicit override (test + advanced users).
func XDGStateRoot() (string, error) {
	if override := strings.TrimSpace(os.Getenv("AIH_GRAPH_HOME")); override != "" {
		return override, nil
	}
	switch runtime.GOOS {
	case "windows":
		if d := os.Getenv("LOCALAPPDATA"); d != "" {
			return filepath.Join(d, "aih-graph"), nil
		}
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		return filepath.Join(home, "AppData", "Local", "aih-graph"), nil
	case "darwin":
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		return filepath.Join(home, "Library", "Application Support", "aih-graph"), nil
	default: // linux + freebsd + others
		if d := os.Getenv("XDG_STATE_HOME"); d != "" {
			return filepath.Join(d, "aih-graph"), nil
		}
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		return filepath.Join(home, ".local", "state", "aih-graph"), nil
	}
}

// RepoHash returns a stable 16-hex-char identifier for a repo path. We use
// the absolute path of the repo as input; same path always yields same hash.
// This is the isolation primitive — each repo has its own .db file under
// XDGStateRoot()/<hash>/graph.db.
func RepoHash(repoPath string) (string, error) {
	abs, err := filepath.Abs(repoPath)
	if err != nil {
		return "", err
	}
	// Normalize: lowercase on case-insensitive filesystems for stability.
	if runtime.GOOS == "windows" || runtime.GOOS == "darwin" {
		abs = strings.ToLower(abs)
	}
	sum := sha256.Sum256([]byte(abs))
	return hex.EncodeToString(sum[:8]), nil // 16 hex chars; collision risk negligible at aihaus scale
}

// DefaultDBPath returns the canonical .db path for a given repo path.
// Creates intermediate directories if missing.
func DefaultDBPath(repoPath string) (string, error) {
	root, err := XDGStateRoot()
	if err != nil {
		return "", err
	}
	hash, err := RepoHash(repoPath)
	if err != nil {
		return "", err
	}
	dir := filepath.Join(root, hash)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", fmt.Errorf("create state dir %s: %w", dir, err)
	}
	return filepath.Join(dir, "graph.db"), nil
}

// ConsentMarkerPath returns the absolute path of the consent marker file.
func ConsentMarkerPath(repoPath string) (string, error) {
	abs, err := filepath.Abs(repoPath)
	if err != nil {
		return "", err
	}
	return filepath.Join(abs, ConsentMarker), nil
}

// HasConsent returns true if a `.aih-graph-consent` marker file exists at the
// repo root. Empty files count.
func HasConsent(repoPath string) (bool, error) {
	p, err := ConsentMarkerPath(repoPath)
	if err != nil {
		return false, err
	}
	_, err = os.Stat(p)
	if err == nil {
		return true, nil
	}
	if os.IsNotExist(err) {
		return false, nil
	}
	return false, err
}

// CreateConsent writes a `.aih-graph-consent` marker at the repo root with a
// short documentation comment.
func CreateConsent(repoPath string) error {
	p, err := ConsentMarkerPath(repoPath)
	if err != nil {
		return err
	}
	body := []byte(`# aih-graph consent marker
#
# This file marks the repository at this path as opted-in for aih-graph
# memory engine indexing. Remove this file to deny future builds.
#
# Created by 'aih-graph build --accept-all-repos' or manual touch.
# See ADR-260515-A in pkg/.aihaus/decisions.md for the privacy contract.
`)
	return os.WriteFile(p, body, 0o644)
}

// PurgeRepo removes the .db file for repoPath. If the parent (per-repo hash)
// dir is now empty, removes it too. Returns the path that was removed (or
// empty string if nothing existed) and any error.
func PurgeRepo(repoPath string) (string, error) {
	dbPath, err := DefaultDBPath(repoPath)
	if err != nil {
		return "", err
	}
	removed := ""
	if _, err := os.Stat(dbPath); err == nil {
		// Also remove WAL + SHM sidecars.
		for _, suffix := range []string{"", "-wal", "-shm", "-journal"} {
			p := dbPath + suffix
			if err := os.Remove(p); err != nil && !os.IsNotExist(err) {
				return removed, fmt.Errorf("remove %s: %w", p, err)
			}
		}
		removed = dbPath
	} else if !os.IsNotExist(err) {
		return "", err
	}
	// Try to remove the per-repo dir if empty.
	dir := filepath.Dir(dbPath)
	if entries, err := os.ReadDir(dir); err == nil && len(entries) == 0 {
		_ = os.Remove(dir)
	}
	return removed, nil
}

// PurgeAll removes ALL aih-graph state (entire XDG state root). Returns the
// root path that was removed (or empty string if it did not exist).
func PurgeAll() (string, error) {
	root, err := XDGStateRoot()
	if err != nil {
		return "", err
	}
	if _, err := os.Stat(root); err == nil {
		if err := os.RemoveAll(root); err != nil {
			return root, fmt.Errorf("remove %s: %w", root, err)
		}
		return root, nil
	} else if !os.IsNotExist(err) {
		return "", err
	}
	return "", nil
}
