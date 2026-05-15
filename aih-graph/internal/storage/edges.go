package storage

import (
	"encoding/json"
	"fmt"
	"time"
)

// UpsertEdge inserts an edge by (from_id, to_id, type). Duplicate inserts are
// silent no-ops via the UNIQUE(from_id, to_id, type) constraint.
func (d *DB) UpsertEdge(fromID, toID int64, typ string, properties map[string]any) error {
	if fromID == toID {
		return nil // skip self-loops; not meaningful for aihaus types
	}
	var propsStr *string
	if len(properties) > 0 {
		b, err := json.Marshal(properties)
		if err != nil {
			return fmt.Errorf("marshal edge props: %w", err)
		}
		s := string(b)
		propsStr = &s
	}
	_, err := d.sql.Exec(`
		INSERT INTO edges(from_id, to_id, type, properties, created_at)
		VALUES(?, ?, ?, ?, ?)
		ON CONFLICT(from_id, to_id, type) DO NOTHING
	`, fromID, toID, typ, propsStr, time.Now().Unix())
	if err != nil {
		return fmt.Errorf("upsert edge %d-[%s]->%d: %w", fromID, typ, toID, err)
	}
	return nil
}

// LookupNodeID returns the row id for (type, identifier) or 0 + ErrNotFound.
func (d *DB) LookupNodeID(typ, identifier string) (int64, error) {
	var id int64
	err := d.sql.QueryRow(
		"SELECT id FROM nodes WHERE type=? AND identifier=?", typ, identifier,
	).Scan(&id)
	if err != nil {
		return 0, err
	}
	return id, nil
}

// CountEdges returns total edge count grouped by type.
func (d *DB) CountEdges() (map[string]int, error) {
	rows, err := d.sql.Query("SELECT type, COUNT(*) FROM edges GROUP BY type ORDER BY type")
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
