# S00 Noise-floor Verdict

noise_floor: 100.0%
verdict: fuzzy-match-fallback

## Analysis

- Fixture rows: 100
- Clusters analysed: 20 (5 paraphrases each)
- Noisy clusters (>1 distinct hash per cluster): 20
- Hash function: sha256(category | summary | source_agent)[:16]
- Generation model: claude-opus-4-7
- Generated at: 2026-04-23T22:17:33Z

## S03 Dispatch Implication

S03 must implement Jaccard-similarity clustering (threshold 0.8) as fallback grouping strategy instead of pure sha256 hash composition.

## Provenance

- Fixture: tools/.out/s00-fixture.jsonl
- Prompt SHA256: dae652022127a784d2b7b42132b415b05c20ce4930c9cb6876cef425ebdf4e04
- Output SHA256: ff9dc439689218d8e7791da3ff73013d5cc6d99b5b42012c30794a8a564c5493
- Story: S00 -- Synthetic-fixture noise-floor pre-check (M015)
