package storage

import (
	"database/sql"
	"fmt"
	"strings"
	"time"
)

// UpdateEmbedding writes an embedding (LE-encoded bytes) + model name +
// content SHA onto an existing node. Returns sql.ErrNoRows if the node ID
// doesn't exist.
func (d *DB) UpdateEmbedding(nodeID int64, embedding []byte, model, contentSHA string) error {
	res, err := d.sql.Exec(`
		UPDATE nodes
		   SET embedding = ?,
		       embedding_model = ?,
		       content_sha = ?,
		       updated_at = ?
		 WHERE id = ?
	`, embedding, model, contentSHA, time.Now().Unix(), nodeID)
	if err != nil {
		return fmt.Errorf("update embedding for %d: %w", nodeID, err)
	}
	affected, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if affected == 0 {
		return sql.ErrNoRows
	}
	return nil
}

// EmbeddingRow is one (id, embedding bytes, content_sha) row from the nodes
// table, used by KNN scan + change detection.
type EmbeddingRow struct {
	NodeID       int64
	Embedding    []byte
	ContentSHA   string
	Type         string
	Identifier   string
}

// IterateEmbeddings yields all rows with non-NULL embeddings. The optional
// typeFilters argument restricts to the given node types (e.g.
// ["Rule", "Decision"]); pass nil (or an empty slice) to scan all.
//
// F15 (M050/S04): the signature was widened from a single `typeFilter string`
// to `typeFilters []string` — multi-type restriction is expanded into a SQL
// `type IN (...)` clause HERE at the storage layer (not post-filtered by
// callers), so candidate sets stay correct for KNN ranking.
func (d *DB) IterateEmbeddings(typeFilters []string) ([]EmbeddingRow, error) {
	q := `
		SELECT id, type, identifier, embedding, COALESCE(content_sha, '')
		FROM nodes
		WHERE embedding IS NOT NULL`
	var args []any
	if len(typeFilters) > 0 {
		q += " AND type IN (?" + strings.Repeat(",?", len(typeFilters)-1) + ")"
		for _, t := range typeFilters {
			args = append(args, t)
		}
	}
	rows, err := d.sql.Query(q, args...)
	if err != nil {
		return nil, fmt.Errorf("iterate embeddings: %w", err)
	}
	defer rows.Close()

	var out []EmbeddingRow
	for rows.Next() {
		var r EmbeddingRow
		if err := rows.Scan(&r.NodeID, &r.Type, &r.Identifier, &r.Embedding, &r.ContentSHA); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// EmbeddingSHA returns the content_sha currently stored for nodeID, or empty
// string if the node has no embedding yet. Used for change-detection skip.
func (d *DB) EmbeddingSHA(nodeID int64) (string, error) {
	var sha sql.NullString
	err := d.sql.QueryRow(
		"SELECT content_sha FROM nodes WHERE id = ?", nodeID,
	).Scan(&sha)
	if err != nil {
		return "", err
	}
	return sha.String, nil
}
