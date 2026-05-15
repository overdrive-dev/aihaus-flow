package storage

import (
	"database/sql"
	"fmt"
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
// typeFilter argument restricts to a single node type (e.g. "Decision"); pass
// "" to scan all.
func (d *DB) IterateEmbeddings(typeFilter string) ([]EmbeddingRow, error) {
	var (
		rows *sql.Rows
		err  error
	)
	if typeFilter == "" {
		rows, err = d.sql.Query(`
			SELECT id, type, identifier, embedding, COALESCE(content_sha, '')
			FROM nodes
			WHERE embedding IS NOT NULL
		`)
	} else {
		rows, err = d.sql.Query(`
			SELECT id, type, identifier, embedding, COALESCE(content_sha, '')
			FROM nodes
			WHERE embedding IS NOT NULL AND type = ?
		`, typeFilter)
	}
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
