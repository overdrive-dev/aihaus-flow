package embed

import (
	"math"
	"sort"
)

// Match is a single KNN result: the matched node ID + cosine similarity score.
type Match struct {
	NodeID int64
	Score  float32 // cosine in [-1, 1]; higher is more similar
}

// Candidate is one row of (id, embedding) supplied to TopK.
type Candidate struct {
	NodeID    int64
	Embedding []float32
}

// TopK returns the top-k candidates by cosine similarity to query, sorted
// descending by Score. Brute force O(N*d) per ADR-260515-B-amend-02; adequate
// for aihaus target scale (<500k nodes).
//
// If query is empty, returns nil. Candidates whose Embedding length differs
// from query are skipped (defensive — caller should pre-filter by Dim).
// Candidates without an Embedding are skipped.
func TopK(query []float32, candidates []Candidate, k int) []Match {
	if len(query) == 0 || k <= 0 {
		return nil
	}
	qNorm := norm(query)
	if qNorm == 0 {
		return nil
	}
	matches := make([]Match, 0, len(candidates))
	for _, c := range candidates {
		if len(c.Embedding) != len(query) {
			continue
		}
		cNorm := norm(c.Embedding)
		if cNorm == 0 {
			continue
		}
		score := dot(query, c.Embedding) / (qNorm * cNorm)
		matches = append(matches, Match{NodeID: c.NodeID, Score: score})
	}
	sort.Slice(matches, func(i, j int) bool {
		return matches[i].Score > matches[j].Score
	})
	if k < len(matches) {
		matches = matches[:k]
	}
	return matches
}

func dot(a, b []float32) float32 {
	var s float32
	for i := range a {
		s += a[i] * b[i]
	}
	return s
}

func norm(v []float32) float32 {
	var s float64
	for _, x := range v {
		s += float64(x) * float64(x)
	}
	return float32(math.Sqrt(s))
}
