package privacy

import (
	"os"
	"path/filepath"
	"testing"
)

func TestPurgeRepoRemovesOnlyGeneratedDatabaseAndSidecars(t *testing.T) {
	temp := t.TempDir()
	stateRoot := filepath.Join(temp, "state")
	repo := filepath.Join(temp, "repo")
	t.Setenv("AIH_GRAPH_HOME", stateRoot)

	if err := os.MkdirAll(repo, 0o700); err != nil {
		t.Fatal(err)
	}
	source := filepath.Join(repo, "source.go")
	if err := os.WriteFile(source, []byte("package sample\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	dbPath, err := DefaultDBPath(repo)
	if err != nil {
		t.Fatal(err)
	}
	for _, suffix := range []string{"", "-wal", "-shm", "-journal"} {
		if err := os.WriteFile(dbPath+suffix, []byte("generated"), 0o600); err != nil {
			t.Fatal(err)
		}
	}

	removed, err := PurgeRepo(repo)
	if err != nil {
		t.Fatal(err)
	}
	if removed != dbPath {
		t.Fatalf("removed path = %q, want %q", removed, dbPath)
	}
	for _, suffix := range []string{"", "-wal", "-shm", "-journal"} {
		if _, err := os.Stat(dbPath + suffix); !os.IsNotExist(err) {
			t.Fatalf("generated sidecar still exists: %s", dbPath+suffix)
		}
	}
	if _, err := os.Stat(source); err != nil {
		t.Fatalf("source file was touched by purge: %v", err)
	}
}

func TestPurgeAllStaysInsideConfiguredStateRoot(t *testing.T) {
	temp := t.TempDir()
	stateRoot := filepath.Join(temp, "state", "aih-graph")
	outside := filepath.Join(temp, "keep.txt")
	t.Setenv("AIH_GRAPH_HOME", stateRoot)

	if err := os.MkdirAll(filepath.Join(stateRoot, "repo-hash"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(stateRoot, "repo-hash", "graph.db"), []byte("generated"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(outside, []byte("durable"), 0o600); err != nil {
		t.Fatal(err)
	}

	removed, err := PurgeAll()
	if err != nil {
		t.Fatal(err)
	}
	if removed != stateRoot {
		t.Fatalf("removed root = %q, want %q", removed, stateRoot)
	}
	if _, err := os.Stat(stateRoot); !os.IsNotExist(err) {
		t.Fatalf("state root still exists after purge: %v", err)
	}
	if _, err := os.Stat(outside); err != nil {
		t.Fatalf("file outside state root was touched: %v", err)
	}
}
