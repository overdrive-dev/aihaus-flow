package storage

import (
	"fmt"
)

// SaveFTS writes (or replaces) the FTS5 row for a node. Idempotent: delete-
// then-insert by rowid keeps the nodes_fts table in sync with the nodes table.
func (d *DB) SaveFTS(nodeID int64, text string) error {
	if _, err := d.sql.Exec("DELETE FROM nodes_fts WHERE rowid = ?", nodeID); err != nil {
		return fmt.Errorf("fts5 delete %d: %w", nodeID, err)
	}
	if _, err := d.sql.Exec("INSERT INTO nodes_fts(rowid, text) VALUES (?, ?)", nodeID, text); err != nil {
		return fmt.Errorf("fts5 insert %d: %w", nodeID, err)
	}
	return nil
}

// CountFTS returns the number of indexed FTS5 rows.
func (d *DB) CountFTS() (int, error) {
	var n int
	if err := d.sql.QueryRow("SELECT COUNT(*) FROM nodes_fts").Scan(&n); err != nil {
		return 0, err
	}
	return n, nil
}

// FTSMatch is one BM25-ranked match row: node ID + raw BM25 score (negative;
// more-negative = more-similar by SQLite convention).
type FTSMatch struct {
	NodeID int64
	Score  float64
	Type   string
	Identifier string
}

// QueryFTS5 runs an FTS5 MATCH query with BM25 ranking and returns up to k
// nodes ordered by relevance (most relevant first; SQLite returns negative
// BM25 scores by convention — more-negative = more-similar).
//
// query syntax follows SQLite FTS5 query language:
//   "merge-settings"       → phrase match
//   "merge OR settings"    → boolean OR
//   "merge AND arrays"     → boolean AND
//   "merge*"               → prefix match
//
// typeFilter optionally restricts to one node type ("Decision", etc.); pass
// "" to match across all types.
func (d *DB) QueryFTS5(query string, k int, typeFilter string) ([]FTSMatch, error) {
	if query == "" || k <= 0 {
		return nil, nil
	}
	if typeFilter == "" {
		return d.queryFTS5All(query, k)
	}
	return d.queryFTS5Typed(query, k, typeFilter)
}

func (d *DB) queryFTS5All(query string, k int) ([]FTSMatch, error) {
	rows, err := d.sql.Query(`
		SELECT n.id, n.type, n.identifier, bm25(nodes_fts) AS score
		FROM nodes_fts
		JOIN nodes n ON n.id = nodes_fts.rowid
		WHERE nodes_fts MATCH ?
		ORDER BY score
		LIMIT ?
	`, query, k)
	if err != nil {
		return nil, fmt.Errorf("fts5 query: %w", err)
	}
	defer rows.Close()
	var out []FTSMatch
	for rows.Next() {
		var m FTSMatch
		if err := rows.Scan(&m.NodeID, &m.Type, &m.Identifier, &m.Score); err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

func (d *DB) queryFTS5Typed(query string, k int, typeFilter string) ([]FTSMatch, error) {
	rows, err := d.sql.Query(`
		SELECT n.id, n.type, n.identifier, bm25(nodes_fts) AS score
		FROM nodes_fts
		JOIN nodes n ON n.id = nodes_fts.rowid
		WHERE nodes_fts MATCH ? AND n.type = ?
		ORDER BY score
		LIMIT ?
	`, query, typeFilter, k)
	if err != nil {
		return nil, fmt.Errorf("fts5 query (typed): %w", err)
	}
	defer rows.Close()
	var out []FTSMatch
	for rows.Next() {
		var m FTSMatch
		if err := rows.Scan(&m.NodeID, &m.Type, &m.Identifier, &m.Score); err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	return out, rows.Err()
}
