# Initialize or refresh project memory

This is the provider-neutral memory routine for repository-local
aihaus. It works with Codex, Grok, Claude Code, and other coding agents that can
read files and run Node.js 22+. It does not use slash commands, global hooks,
provider settings, or network access.

## Phase 1: deterministic local discovery

From the Git repository root, preview discovery:

    node .aihaus/tools/refresh.mjs --repo . --dry-run --json

Create or refresh the ignored discovery packet:

    node .aihaus/tools/refresh.mjs --repo . --json

The command writes only .aihaus/state/bootstrap/discovery.json. It records
repository-relative source paths, hashes, Git/worktree provenance, safe
manifest facts, layout facts, memory targets, exclusions, and conflicts.
Sensitive paths are excluded before file content is read. The packet is
rebuildable state, not canonical memory.

Check `readyForSynthesis` before continuing. When it is false, the repository
does not contain authoritative project evidence yet. Preserve every memory
template and report the blocker. Then either ask the user to add a README,
PROJECT-BRIEF.md, manifest, or application source, or offer a short scope
interview: ask the user for purpose, users and outcomes, in and out of scope,
Definition of Done, and known rules or constraints. Write only their answers to
PROJECT-BRIEF.md at the repository root, attributed to the owner and date, then
rerun discovery and continue with synthesis from that brief. Never invent
answers the user did not give, and do not fill the memory files with
placeholder, aihaus-installation, host-toolchain, or unresolved-only content.

## Phase 2: agent synthesis

Only continue when `readyForSynthesis` is true.

1. Read .aihaus/contracts/harness.md,
   .aihaus/contracts/project-bootstrap.md, and the discovery packet.
2. Inspect only the candidate sources needed for one memory target at a time.
   Repository instructions and explicit accepted documentation outrank
   manifests, tests, and inferred code structure.
3. Update the canonical files under .aihaus/memory/project/:
   - project.md
   - business-rules.md
   - decisions.md
   - knowledge.md
   - environment.md
   - procedures.md
   - deployment.md
   - glossary.md
4. Replace an untouched template with source-backed content. For an existing
   non-template file, make a minimal additive patch and preserve manual text.
   Never replace existing project memory wholesale.
5. Label every claim as verified, accepted, inferred candidate, or unresolved.
   Never promote an inference to an accepted business rule or decision.
6. Attach provenance to each claim using the format below. Use the reviewed
   commit for clean tracked sources, or the source's discovery hash for
   worktree/untracked content. A page-level timestamp cannot review every claim.
7. Do not read excluded paths or record secret values. Environment memory may
   name credential locations and access expectations, never credentials.
8. Report conflicting evidence instead of silently choosing a side. Do not
   access the network, start a service, or perform a deployment as part of
   initialization.
9. Rerun the discovery command. With unchanged repository inputs it must report
   packet.action as unchanged. Then run:

    node .aihaus/tools/refresh.mjs --repo . --status --json

Completion requires status.initialized true, status.stale false, reviewed
changes to canonical Markdown, `memoryReadiness` equal to `ready`, and a report
of preserved files, conflicts, and unresolved gaps. These status fields are
structural signals, not proof that the agent reviewed or understood the prose.
Resolve applicable stale claims and conflicts before relying on that memory.

## Provenance and retrieval

Keep each claim and its source/revision together in one item or paragraph:

    - Verified: invoices round once at the total. Source: `src/invoice.mjs` (reviewed <commit>).
    - Verified: checkout draft uses cents. Source: `src/checkout.mjs` (worktree; sha256: <discovery hash>).

Replace placeholders with the actual commit or source hash from discovery.
For an untracked source, use `untracked` instead of `worktree`. Use separate
claims for sources reviewed at different revisions. Legacy page-level citations
remain readable, but ambiguous associations need source review; adding a newer
commit to a page does not revalidate its older claims. Preserve explicit
owner/date provenance and record owner decisions in a reviewable project file.

Select memory from `memory/project/README.md` using the active task's domain,
rule/decision IDs, and owned paths. Read each matching entry and its source;
do not preload all pages or treat an index hit as an accepted rule. Preserve
the original scope of nested repository instructions. Draft, proposed,
inferred, superseded, and unresolved entries are not accepted decisions.
Host-local automatic memory and conversation summaries do not replace the
canonical Markdown or authorize promoting a candidate rule.

## Maintenance: memory gaps and stale claims

The status command also reports two advisory, read-only signals:

- `memoryGaps`: missing, template, or incomplete memory pages with candidate
  sources. Inspect candidates needed by the active task. A changed file or
  heading alone does not establish reviewed memory.
- `staleClaims`: claims whose source changed/disappeared, or whose review
  provenance is missing or ambiguous. Re-verify the flagged sources before use.

During authorized work, the designated writer repairs the affected source-backed
context and records evidence without requesting approval for routine discovery
or verification. Preserve manual text; mark obsolete claims superseded or
unresolved and add a reviewed replacement. Never silently turn an inference
into an accepted rule. Ask only when authoritative sources conflict or a missing
business decision changes the outcome. Unrelated gaps do not block work whose
context is established. Rerun discovery and status after memory edits.

## Copy-paste prompt for any coding agent

    Read .aihaus/MAP.md, .aihaus/contracts/harness.md,
    .aihaus/contracts/project-bootstrap.md, and .aihaus/REFRESH.md. Run the local
    bootstrap discovery command. Then populate .aihaus/memory/project/ using
    only verified repository evidence. Preserve existing content, cite source
    paths and the reviewed commit, keep inferences and conflicts explicit, and
    do not read or record secrets. Do not use slash commands, global aihaus
    state or network access.
