# Initialize project memory

This is the provider-neutral initialization routine for repository-local
aihaus. It works with Codex, Grok, Claude Code, and other coding agents that can
read files and run Node.js 22+. It does not use slash commands, global hooks,
provider settings, network access, or the optional graph index.

## Phase 1: deterministic local discovery

From the Git repository root, preview discovery:

    node .aihaus/tools/init.mjs --repo . --dry-run --json

Create or refresh the ignored discovery packet:

    node .aihaus/tools/init.mjs --repo . --json

The command writes only .aihaus/state/bootstrap/discovery.json. It records
repository-relative source paths, hashes, Git/worktree provenance, safe
manifest facts, layout facts, memory targets, exclusions, and conflicts.
Sensitive paths are excluded before file content is read. The packet is
rebuildable state, not canonical memory.

## Phase 2: agent synthesis

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
6. Attach repository-relative source provenance and the reviewed commit when
   practical. Use worktree or untracked when the packet says a source is not
   represented by the reviewed commit.
7. Do not read excluded paths or record secret values. Environment memory may
   name credential locations and access expectations, never credentials.
8. Report conflicting evidence instead of silently choosing a side. Do not
   create .aih-graph-consent, run graph indexing, access the network, start a
   service, or perform a deployment as part of initialization.
9. Rerun the discovery command. With unchanged repository inputs it must report
   packet.action as unchanged. Then run:

    node .aihaus/tools/init.mjs --repo . --status --json

Completion requires status.initialized true, status.stale false, reviewed
changes to canonical Markdown, and a report of preserved files, conflicts, and
unresolved gaps.

## Copy-paste prompt for any coding agent

    Read .aihaus/MAP.md, .aihaus/contracts/harness.md,
    .aihaus/contracts/project-bootstrap.md, and .aihaus/INIT.md. Run the local
    bootstrap discovery command. Then populate .aihaus/memory/project/ using
    only verified repository evidence. Preserve existing content, cite source
    paths and the reviewed commit, keep inferences and conflicts explicit, and
    do not read or record secrets. Do not use slash commands, global aihaus
    state, network access, or graph indexing.
