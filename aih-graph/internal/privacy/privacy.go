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
//     --accept-all-repos for the current run.
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

// UserConsentMarker is the filename aih-graph looks for under ~/.aihaus to
// confirm the user has opted in to indexing global user memory
// (~/.aihaus/memory/user/**) into the user-scope graph (M050/S04,
// ADR-260611-E §3). The user scope has its OWN consent marker and its OWN
// purge path — user memory is NEVER indexed into per-repo DBs
// (ADR-260515-A preserved).
const UserConsentMarker = ".aih-graph-user-consent"

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
// short documentation comment. The normal aihaus install/init flow avoids
// creating this repo-root file and uses --accept-all-repos for one run instead.
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

// --- User scope (M050/S04, ADR-260611-A tier C / ADR-260611-E §3) ---------
//
// The user-scope graph indexes ~/.aihaus/memory/user/** into a SEPARATE
// ~/.aihaus/state/user-graph.db. Its consent marker, DB path, and purge path
// are all distinct from the per-repo machinery above so the two scopes can
// never bleed into each other.

// UserAihausRoot returns the aihaus-owned user namespace (~/.aihaus). Honors
// AIH_GRAPH_USER_HOME for explicit override (tests + advanced users) —
// mirroring the AIH_GRAPH_HOME override on XDGStateRoot.
func UserAihausRoot() (string, error) {
	if override := strings.TrimSpace(os.Getenv("AIH_GRAPH_USER_HOME")); override != "" {
		return override, nil
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, ".aihaus"), nil
}

// UserConsentMarkerPath returns the absolute path of the user-scope consent
// marker (~/.aihaus/.aih-graph-user-consent).
func UserConsentMarkerPath() (string, error) {
	root, err := UserAihausRoot()
	if err != nil {
		return "", err
	}
	return filepath.Join(root, UserConsentMarker), nil
}

// HasUserConsent returns true if the user-scope consent marker exists.
// Empty files count.
func HasUserConsent() (bool, error) {
	p, err := UserConsentMarkerPath()
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

// CreateUserConsent writes the user-scope consent marker with a short
// documentation comment. Created by `aih-graph build --user --accept`.
func CreateUserConsent() error {
	p, err := UserConsentMarkerPath()
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(p), 0o700); err != nil {
		return fmt.Errorf("create user root %s: %w", filepath.Dir(p), err)
	}
	body := []byte(`# aih-graph user-scope consent marker
#
# This file marks global user memory (~/.aihaus/memory/user/**) as opted-in
# for aih-graph indexing into the SEPARATE user-scope graph at
# ~/.aihaus/state/user-graph.db. User memory is never indexed into per-repo
# DBs. Remove this file to deny future user-scope builds.
#
# Created by 'aih-graph build --user --accept' or manual touch.
# See ADR-260611-E in pkg/.aihaus/decisions.md (extends ADR-260515-A).
`)
	return os.WriteFile(p, body, 0o644)
}

// UserMemoryRoot returns the user-scope memory source directory
// (~/.aihaus/memory/user).
func UserMemoryRoot() (string, error) {
	root, err := UserAihausRoot()
	if err != nil {
		return "", err
	}
	return filepath.Join(root, "memory", "user"), nil
}

// UserDBPath returns the canonical user-scope graph DB path
// (~/.aihaus/state/user-graph.db). Creates the state directory if missing.
func UserDBPath() (string, error) {
	root, err := UserAihausRoot()
	if err != nil {
		return "", err
	}
	dir := filepath.Join(root, "state")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", fmt.Errorf("create user state dir %s: %w", dir, err)
	}
	return filepath.Join(dir, "user-graph.db"), nil
}

// PurgeUser removes the user-scope graph DB (+ WAL/SHM/journal sidecars) and
// the user-scope consent marker. Returns the paths that were removed.
// This is the `aih-graph uninstall --user` arm (own purge path per
// ADR-260611-E §3).
func PurgeUser() ([]string, error) {
	var removed []string
	root, err := UserAihausRoot()
	if err != nil {
		return nil, err
	}
	dbPath := filepath.Join(root, "state", "user-graph.db")
	for _, suffix := range []string{"", "-wal", "-shm", "-journal"} {
		p := dbPath + suffix
		if _, err := os.Stat(p); err != nil {
			if os.IsNotExist(err) {
				continue
			}
			return removed, err
		}
		if err := os.Remove(p); err != nil && !os.IsNotExist(err) {
			return removed, fmt.Errorf("remove %s: %w", p, err)
		}
		removed = append(removed, p)
	}
	marker := filepath.Join(root, UserConsentMarker)
	if _, err := os.Stat(marker); err == nil {
		if err := os.Remove(marker); err != nil && !os.IsNotExist(err) {
			return removed, fmt.Errorf("remove %s: %w", marker, err)
		}
		removed = append(removed, marker)
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
