# migration-reviewer Dispatch — aih-milestone Merge-Back Path (M027/S9)

This annex documents the conditional dispatch of `migration-reviewer` during
the `aih-milestone` worktree merge-back path (Step E6 story loop). It is the
standalone-path complement to the paralelo dispatch defined in
`aih-feature/annexes/agent-routing.md`.

---

## Trigger: post-merge-back diff filter

After `merge-back.sh` writes the story's Owned Files to the milestone branch
(exit 0 confirmed), the orchestrator runs the migration diff filter against
the just-merged-back file set:

```bash
git diff HEAD~1 --name-only | grep -E '(^migrations/|\.sql$)'
```

Alternatively, filter the story's Owned Files list directly if the manifest
contains it:

```bash
printf '%s\n' "${owned_files[@]}" | grep -E '(^migrations/|\.sql$)'
```

**Diff regex (binding — OQ-OPEN-4 lock):**
`^(diff --git.*migrations/|.*\.sql$)`

For `--name-only` output: `grep -E '(^migrations/|\.sql$)'`

---

## Dispatch rule

| Post-merge diff match | Action |
|---|---|
| No match | Skip. Proceed to next story. |
| Match | Spawn `migration-reviewer` standalone (no code-reviewer pair). |

---

## Spawn shape (standalone path)

Spawn `migration-reviewer` with `subagent_type: "migration-reviewer"`. Include
in the spawn prompt:

```
MANIFEST_PATH="<abs>/.aihaus/milestones/M0XX-<slug>/RUN-MANIFEST.md"
Dispatch mode: standalone (aih-milestone merge-back path, no code-reviewer pair)
Story: S<NN>
Migration files to review: <list from diff filter above>
Return a MIGRATION-REVIEW-PAYLOAD-START...END block (see agent definition for schema).
Do NOT write any files.
```

---

## Output contract (ADR-001 single-writer preserved)

`migration-reviewer` returns a `MIGRATION-REVIEW-PAYLOAD-START/END` payload
string. The parent orchestrator (aih-milestone coordinator) is the **sole writer**:

1. Determine output path:
   `.aihaus/milestones/<M0XX>-<slug>/execution/S<NN>/MIGRATION-REVIEW.md`
   (create `S<NN>/` subdirectory if needed).
2. Write the payload verbatim as `MIGRATION-REVIEW.md` using the Write tool
   in the parent skill's context (NOT by the agent).
3. `migration-reviewer` has NO Write and NO Edit tools — payload return only.

**Why standalone (not REVIEW.md section):** In the aih-milestone path there is
no per-story `code-reviewer` run producing a REVIEW.md at the story level.
Appending to a non-existent REVIEW.md would create an orphan section.
A separate `MIGRATION-REVIEW.md` preserves clear artifact ownership and makes
the file discoverable by downstream consumers (verifier, integration-checker,
security-auditor in Step E7). If a per-story code-reviewer is ever wired into
the milestone path, this annex MUST be amended to switch to the append path.

---

## Integration with the story loop (Step E6)

Insert the following check after the merge-back confirmation line in Step E6:

```
After merge-back.sh exits 0 for story S<NN>:
  1. Run migration diff filter (see above).
  2. If match → spawn migration-reviewer (standalone). Write MIGRATION-REVIEW.md
     from payload. Log to RUN-MANIFEST progress:
       manifest-append.sh --field progress-log \
         --payload "S<NN>: migration-reviewer dispatched — MIGRATION-REVIEW.md written"
  3. Append to story task completion note: "migration-reviewer: <N> findings (see execution/S<NN>/MIGRATION-REVIEW.md)"
  4. If CRITICAL or HIGH findings in MIGRATION-REVIEW.md:
     - Surface to the orchestrator as a FAIL verdict.
     - Surface MIGRATION-REVIEW.md path to the user.
     - Do NOT proceed to the next story until findings are resolved.
     - This IS a TRUE blocker per _shared/autonomy-protocol.md.
  5. If no match → proceed silently to next story (no log entry needed).
```

---

## RUN-MANIFEST checkpoint wrapping

When migration-reviewer is dispatched, wrap with manifest checkpoint calls
(per ADR-M014-B / ADR-004 single-writer discipline):

```bash
bash .aihaus/hooks/manifest-append.sh \
  --checkpoint-enter S<NN> migration-reviewer migration-review:S<NN>

# ... spawn migration-reviewer, receive payload, write MIGRATION-REVIEW.md ...

bash .aihaus/hooks/manifest-append.sh \
  --checkpoint-exit S<NN> migration-reviewer migration-review:S<NN> OK <sha>
```

On agent error or timeout, emit `result=ERR` and surface to user.
Do NOT silently swallow the failure.

---

## Rollback

To roll back S9 (remove migration-reviewer from the milestone path):
1. Delete this annex (`migration-reviewer-dispatch.md`).
2. Delete `pkg/.aihaus/agents/migration-reviewer.md`.
3. Revert the diff-aware row in `aih-feature/annexes/agent-routing.md`.
4. Remove the migration-reviewer row from `cohorts.md` membership table.
No schema migrations; no runtime artifacts affected (MIGRATION-REVIEW.md
files are per-invocation; no cleanup needed for past runs).
