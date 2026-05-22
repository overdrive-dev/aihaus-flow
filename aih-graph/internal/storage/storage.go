// Package storage implements aih-graph's persistence layer using
// modernc.org/sqlite (pure-Go SQLite, no CGO) per ADR-260515-B-amend-02.
//
// Schema is applied idempotently via Open(). The schema definition lives in
// schema.sql (embedded). Nodes are upserted by (type, identifier); edges are
// inserted with deduplication on (from_id, to_id, type).
package storage

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"time"

	_ "modernc.org/sqlite"
)

// DB wraps the *sql.DB handle with aih-graph schema-aware helpers.
type DB struct {
	sql *sql.DB
}

// schemaSQL is applied at Open() time. Idempotent via IF NOT EXISTS.
//
// Diverges from ADR-260515-B-amend-02 schema block in two cosmetic ways:
//  1. embedding stored as BLOB (LE-encoded []float32) per amendment;
//     decoding helpers live in internal/embed/ (M035).
//  2. content_sha is TEXT (SHA-256 hex string).
const schemaSQL = `
CREATE TABLE IF NOT EXISTS nodes (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    type            TEXT NOT NULL,
    identifier      TEXT NOT NULL,
    properties      TEXT NOT NULL,            -- JSON object
    embedding       BLOB,                     -- []float32 LE; NULL until M035 pipeline
    embedding_model TEXT,                     -- 'ollama:nomic-embed-text' | NULL
    content_sha     TEXT,                     -- SHA-256 hex of source content
    created_at      INTEGER NOT NULL,         -- unix epoch seconds
    updated_at      INTEGER NOT NULL,
    UNIQUE(type, identifier)
);

CREATE INDEX IF NOT EXISTS idx_nodes_type ON nodes(type);
CREATE INDEX IF NOT EXISTS idx_nodes_identifier ON nodes(identifier);
CREATE INDEX IF NOT EXISTS idx_nodes_embedding_present ON nodes(id) WHERE embedding IS NOT NULL;

CREATE TABLE IF NOT EXISTS edges (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    from_id     INTEGER NOT NULL REFERENCES nodes(id),
    to_id       INTEGER NOT NULL REFERENCES nodes(id),
    type        TEXT NOT NULL,
    properties  TEXT,                          -- JSON object
    created_at  INTEGER NOT NULL,
    UNIQUE(from_id, to_id, type)
);

CREATE INDEX IF NOT EXISTS idx_edges_from ON edges(from_id);
CREATE INDEX IF NOT EXISTS idx_edges_to ON edges(to_id);

CREATE TABLE IF NOT EXISTS schema_meta (
    version     INTEGER PRIMARY KEY,
    applied_at  INTEGER NOT NULL
);

-- FTS5 contentless virtual table for BM25 lexical search (M041 / ADR-260515-E-amend-04).
-- rowid is the same int as nodes.id; SaveFTS keeps them in sync explicitly.
-- BM25 ranking comes free via SQLite's built-in bm25() function.
CREATE VIRTUAL TABLE IF NOT EXISTS nodes_fts USING fts5(text);
`

const currentSchemaVersion = 1

// Open returns a DB connected to path. Creates the file + applies the schema
// idempotently. dsn (data source name) follows modernc/sqlite conventions:
// the path is taken verbatim; `?_pragma=...` can be appended for tuning.
func Open(path string) (*DB, error) {
	dsn := path + "?_pragma=journal_mode(WAL)&_pragma=foreign_keys(1)"
	sqlDB, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, fmt.Errorf("open sqlite %s: %w", path, err)
	}
	if err := sqlDB.Ping(); err != nil {
		return nil, fmt.Errorf("ping sqlite %s: %w", path, err)
	}

	db := &DB{sql: sqlDB}
	if err := db.applySchema(); err != nil {
		_ = sqlDB.Close()
		return nil, err
	}
	return db, nil
}

// Close releases the underlying *sql.DB handle.
func (d *DB) Close() error {
	return d.sql.Close()
}

// SQL exposes the underlying *sql.DB for read-side packages (internal/query/)
// that need to issue arbitrary read queries without re-establishing a
// connection. Avoids import cycle between storage and query packages.
func (d *DB) SQL() *sql.DB {
	return d.sql
}

func (d *DB) applySchema() error {
	if _, err := d.sql.Exec(schemaSQL); err != nil {
		return fmt.Errorf("apply schema: %w", err)
	}
	_, err := d.sql.Exec(
		"INSERT OR IGNORE INTO schema_meta(version, applied_at) VALUES (?, ?)",
		currentSchemaVersion, time.Now().Unix(),
	)
	if err != nil {
		return fmt.Errorf("record schema_meta: %w", err)
	}
	return nil
}

// UpsertNode inserts-or-updates a node by (type, identifier). Returns the
// row id. Properties is JSON-marshaled.
func (d *DB) UpsertNode(typ, identifier string, properties map[string]any) (int64, error) {
	propsJSON, err := json.Marshal(properties)
	if err != nil {
		return 0, fmt.Errorf("marshal properties: %w", err)
	}
	now := time.Now().Unix()

	// Upsert with ON CONFLICT(type, identifier) — keep created_at intact.
	res, err := d.sql.Exec(`
		INSERT INTO nodes(type, identifier, properties, created_at, updated_at)
		VALUES(?, ?, ?, ?, ?)
		ON CONFLICT(type, identifier) DO UPDATE SET
			properties = excluded.properties,
			updated_at = excluded.updated_at
		`, typ, identifier, string(propsJSON), now, now)
	if err != nil {
		return 0, fmt.Errorf("upsert node (%s, %s): %w", typ, identifier, err)
	}
	// LastInsertId reflects the row affected by ON CONFLICT update OR insert.
	id, err := res.LastInsertId()
	if err != nil {
		return 0, err
	}
	if id == 0 {
		// ON CONFLICT update path — fetch existing id.
		err = d.sql.QueryRow(
			"SELECT id FROM nodes WHERE type=? AND identifier=?", typ, identifier,
		).Scan(&id)
		if err != nil {
			return 0, fmt.Errorf("lookup id for (%s, %s): %w", typ, identifier, err)
		}
	}
	return id, nil
}

// CountByType returns the row count of nodes by type. Convenience helper for
// post-build summary.
func (d *DB) CountByType() (map[string]int, error) {
	rows, err := d.sql.Query("SELECT type, COUNT(*) FROM nodes GROUP BY type ORDER BY type")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string]int{}
	for rows.Next() {
		var t string
		var n int
		if err := rows.Scan(&t, &n); err != nil {
			return nil, err
		}
		out[t] = n
	}
	return out, rows.Err()
}
