# Refactor provenance and deletion ledger

Git history preserves the original bodies. This ledger records behavior that
must be ported, intentionally dropped, or archived before deletion.

## Preserve as deterministic behavior

- online promotion boundary from `flow-guard.sh` and `online-actions.sh`;
- non-vacuous business-rule gate from `calibrate-guard.sh`;
- explicit-file merge and staging protections from `merge-back.sh` and
  `git-add-guard.sh`;
- executable evidence semantics from AIPI `step-result.js`;
- realpath-scoped destructive operations for the local lab.

## Preserve as on-demand review lenses

- security threat-to-code verification;
- migration reversibility, lock impact, and data-loss review;
- goal-backward plan checking and verification;
- integration existence-versus-wiring checks;
- business-rule calibration and complexity deletion pressure.

## Port as workflow contracts

- OKF Map/rooms and six general roles;
- AIPI research ordering: internal context, external evidence, challenge,
  synthesis;
- AIPI ops boundary taxonomy and "not a sandbox" doctrine;
- adversarial criterion mapping and evidence-backed completion;
- planning-question to draft-business-rule flywheel over files/JSONL.

## Audit of the original `aihaus` repository

- `.planning/` and the default Nuxt README describe the retired website, so
  they are not part of the canonical package;
- the useful product idea from `i18n/locales/{pt,en}.json` -- turning business
  intent into verifiable engineering contracts -- is retained in the canonical
  README, without the obsolete specialist-agent framing;
- consulting metrics, contact details, brand copy, and other site-only content
  are deliberately excluded;
- the original repository had unrelated local changes and was inspected
  read-only.

## Removed after replacement gates passed

- archived `plugin/` preview and marketplace entry (no installer/runtime/CI
  consumers; removed after focused contracts and the 104-check legacy smoke);
- superseded architecture, milestone, and proposal snapshots whose live
  contracts now reside in `architecture.md`, `aih-graph/PRD.md`, and this
  ledger;
- duplicate public/package README bodies, replaced by one public contract and
  a short package pointer;
- fresh-install dependence on global Claude settings, hooks, or symlinks;
  `pkg/setup.mjs` installs only the portable core and preserves local memory;
- redundant specialist prompts, manifest/phase/statusline bureaucracy, SQLite
  kanban, core Notion integration, global hooks, and their migration fixtures.

The deletion was applied only after the 104-check legacy baseline and focused
replacement contracts passed locally. Package CI now runs the replacement
install/lab contracts on Windows, Linux, and macOS.
