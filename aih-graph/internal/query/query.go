// Package query implements aih-graph's read-side over the storage substrate.
//
// v0.1 query modes per ADR-260515-B-amend-02:
//
//	BFS       — recursive CTE over edges; structural-only, no embeddings.
//	Semantic  — vector KNN over embeddings (M035 wires embed pipeline).
//	Hybrid    — SQL pre-filter + vector ranking + edge traversal (M035).
//
// This first cut implements BFS only (semantic + hybrid land alongside the
// embedding pipeline in subsequent M035 commits).
package query

import (
	"database/sql"
	"encoding/json"
	"fmt"
)

// Engine wraps the storage *sql.DB for read-side queries. Caller is responsible
// for opening the storage.DB and passing its underlying *sql.DB here. (We
// accept the raw handle to avoid an import cycle with internal/storage.)
type Engine struct {
	sql *sql.DB
}

// New returns a query Engine bound to the provided *sql.DB.
func New(sqlDB *sql.DB) *Engine {
	return &Engine{sql: sqlDB}
}

// Node is the query-side projection of a graph node. Properties is decoded
// from the stored JSON; Body/Title/etc are accessed via Properties keys.
type Node struct {
	ID         int64
	Type       string
	Identifier string
	Properties map[string]any
}

// GetByIdentifier returns the node matching (type, identifier), or
// sql.ErrNoRows if not found. Pass "" for typ to match any type.
func (e *Engine) GetByIdentifier(typ, identifier string) (*Node, error) {
	var (
		id         int64
		t, ident   string
		propsBytes []byte
	)
	var err error
	if typ == "" {
		err = e.sql.QueryRow(
			"SELECT id, type, identifier, properties FROM nodes WHERE identifier=? LIMIT 1",
			identifier,
		).Scan(&id, &t, &ident, &propsBytes)
	} else {
		err = e.sql.QueryRow(
			"SELECT id, type, identifier, properties FROM nodes WHERE type=? AND identifier=? LIMIT 1",
			typ, identifier,
		).Scan(&id, &t, &ident, &propsBytes)
	}
	if err != nil {
		return nil, err
	}
	n := &Node{ID: id, Type: t, Identifier: ident}
	if len(propsBytes) > 0 {
		if err := json.Unmarshal(propsBytes, &n.Properties); err != nil {
			return nil, fmt.Errorf("decode properties for node %d: %w", id, err)
		}
	}
	return n, nil
}

// ListByType returns all nodes of the given type, ordered by identifier.
func (e *Engine) ListByType(typ string) ([]Node, error) {
	rows, err := e.sql.Query(
		"SELECT id, type, identifier, properties FROM nodes WHERE type=? ORDER BY identifier",
		typ,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []Node
	for rows.Next() {
		var (
			n          Node
			propsBytes []byte
		)
		if err := rows.Scan(&n.ID, &n.Type, &n.Identifier, &propsBytes); err != nil {
			return nil, err
		}
		if len(propsBytes) > 0 {
			if err := json.Unmarshal(propsBytes, &n.Properties); err != nil {
				return nil, fmt.Errorf("decode properties for node %d: %w", n.ID, err)
			}
		}
		out = append(out, n)
	}
	return out, rows.Err()
}

// BFSResult is a node returned by BFS expansion with the path that reached it.
type BFSResult struct {
	Node     Node
	Distance int      // 0 = root; 1 = direct neighbor; ...
	Path     []string // identifiers traversed from root (inclusive)
}

// BFS expands from root identifier outward up to maxDepth hops, following
// edges in either direction. Returns nodes ordered by (distance, type,
// identifier).
//
// maxDepth=0 returns only the root.
// maxDepth<0 is treated as 1 (defensive default).
func (e *Engine) BFS(rootType, rootIdentifier string, maxDepth int) ([]BFSResult, error) {
	if maxDepth < 0 {
		maxDepth = 1
	}
	root, err := e.GetByIdentifier(rootType, rootIdentifier)
	if err != nil {
		return nil, err
	}

	results := []BFSResult{{Node: *root, Distance: 0, Path: []string{root.Identifier}}}
	visited := map[int64]bool{root.ID: true}
	frontier := []int64{root.ID}
	paths := map[int64][]string{root.ID: {root.Identifier}}

	for depth := 1; depth <= maxDepth && len(frontier) > 0; depth++ {
		nextFrontier := []int64{}
		for _, fromID := range frontier {
			// Both directions: from_id=X or to_id=X
			rows, err := e.sql.Query(`
				SELECT n.id, n.type, n.identifier, n.properties
				FROM edges e
				JOIN nodes n ON (
					(e.from_id = ? AND n.id = e.to_id) OR
					(e.to_id   = ? AND n.id = e.from_id)
				)
				WHERE n.id != ?
			`, fromID, fromID, fromID)
			if err != nil {
				return nil, fmt.Errorf("bfs neighbors of %d: %w", fromID, err)
			}
			for rows.Next() {
				var (
					n          Node
					propsBytes []byte
				)
				if err := rows.Scan(&n.ID, &n.Type, &n.Identifier, &propsBytes); err != nil {
					rows.Close()
					return nil, err
				}
				if visited[n.ID] {
					continue
				}
				visited[n.ID] = true
				if len(propsBytes) > 0 {
					_ = json.Unmarshal(propsBytes, &n.Properties)
				}
				newPath := append([]string{}, paths[fromID]...)
				newPath = append(newPath, n.Identifier)
				paths[n.ID] = newPath
				results = append(results, BFSResult{Node: n, Distance: depth, Path: newPath})
				nextFrontier = append(nextFrontier, n.ID)
			}
			rows.Close()
		}
		frontier = nextFrontier
	}
	return results, nil
}
