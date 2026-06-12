#!/usr/bin/env bash
# lib/global-harness.sh — GLOBAL-HARNESS seed + ~/.aihaus/.targets registry
# (M050/S08, ADR-260611-E §2 / BR-U1 consent triple).
#
# Sourced by install.sh / update.sh / uninstall.sh. PowerShell parity lives
# inline in install.ps1 / update.ps1 / uninstall.ps1 (BR-P3).
#
# Two $HOME writes live here; both satisfy the standing checklist:
#   1. ~/.claude/CLAUDE.md GLOBAL-HARNESS marker block — default-ON; consent
#      triple = --no-global-harness flag + AIHAUS_SKIP_GLOBAL_HARNESS=1 env +
#      uninstall.sh --purge-user-global marker-block removal; named in
#      release notes (BR-U1, all four legs).
#   2. ~/.aihaus/.targets append-dedupe registry (hole 8 / F9) — consumed by
#      `aihaus update --all`; honors the same AIHAUS_SKIP_GLOBAL_HARNESS=1 env.

# Prints the marker block: autonomy-law digest (derived from
# pkg/.aihaus/protocols/harness.md — condensed, NOT the whole file) +
# overlay nudge + tier-C pointer.
aihaus_global_harness_block() {
  cat <<'GLOBAL_HARNESS_EOF'
<!-- AIHAUS:GLOBAL-HARNESS-START -->
## aihaus harness (global digest)

- Decide from the repo's business-rules ledger (`.aihaus/memory/workflows/business-rules.md`): **covered** — decide alone, cite the BR-id when behavior is affected; **gap** — the only TRUE blocker: ask **once**, the answer **becomes a rule**; **conflict** — surface it, ask which wins, record the resolution as a rule; **mechanics** — decide alone, no citation.
- Autonomy = contract coverage. No option menus for covered decisions.
- Memory tiers: A = code/concept graph (`aihaus memory ... --json`, retrieval only); B = project memory (source of truth: ledger apex + decisions.md + knowledge.md + project.md); C = global user preferences at `~/.aihaus/memory/user/preferences.md` (write only via `aihaus prefs add`). Repo overrides global on conflict.
- Stage gates record one verdict — `PASS|SKIPPED|BLOCKED-TO-PLANNING|BLOCKED` — plus warn-only `rules_cited`.
- Repo without an aihaus overlay (no `.aihaus/`)? Run `/aih-install` to enable per-repo memory + enforcement.
- Full harness (canonical when installed): `.aihaus/protocols/harness.md`. Seeded by aihaus install; removed by `uninstall.sh --purge-user-global`.
<!-- AIHAUS:GLOBAL-HARNESS-END -->
GLOBAL_HARNESS_EOF
}

# seed_global_harness — idempotent ensure_block() shape on ~/.claude/CLAUDE.md:
# create file if absent; awk span-replace when markers exist; append otherwise.
# Skips (quiet note) on --no-global-harness (NO_GLOBAL_HARNESS=1) or
# AIHAUS_SKIP_GLOBAL_HARNESS=1.
seed_global_harness() {
  if [[ "${NO_GLOBAL_HARNESS:-0}" == "1" ]] || [[ "${AIHAUS_SKIP_GLOBAL_HARNESS:-0}" == "1" ]]; then
    echo "  global-harness: seed skipped (--no-global-harness / AIHAUS_SKIP_GLOBAL_HARNESS=1)"
    return 0
  fi
  local claude_md="$HOME/.claude/CLAUDE.md"
  local start_marker="AIHAUS:GLOBAL-HARNESS-START"
  local end_marker="AIHAUS:GLOBAL-HARNESS-END"
  local src_tmp
  src_tmp="$(mktemp 2>/dev/null)" || src_tmp="/tmp/.aihaus-global-harness.$$"
  aihaus_global_harness_block > "${src_tmp}" 2>/dev/null || { rm -f "${src_tmp}" 2>/dev/null; return 0; }

  mkdir -p "$HOME/.claude" 2>/dev/null || { rm -f "${src_tmp}" 2>/dev/null; return 0; }

  if [[ ! -f "${claude_md}" ]]; then
    cp "${src_tmp}" "${claude_md}" 2>/dev/null && \
      echo "  global-harness: created ~/.claude/CLAUDE.md (AIHAUS:GLOBAL-HARNESS block)"
  elif grep -Fq "${start_marker}" "${claude_md}" 2>/dev/null && grep -Fq "${end_marker}" "${claude_md}" 2>/dev/null; then
    # Span-replace between markers (ensure_block() awk shape) — idempotent refresh.
    local tmp="${claude_md}.tmp.$$"
    if awk -v start="${start_marker}" -v end="${end_marker}" -v source="${src_tmp}" '
      BEGIN {
        while ((getline line < source) > 0) {
          if (index(line, start) > 0) in_source = 1
          if (in_source) block = block line ORS
          if (in_source && index(line, end) > 0) break
        }
        close(source)
      }
      {
        if (index($0, start) > 0) {
          printf "%s", block
          skipping = 1
          next
        }
        if (skipping) {
          if (index($0, end) > 0) skipping = 0
          next
        }
        print
      }
    ' "${claude_md}" > "${tmp}" 2>/dev/null; then
      if cmp -s "${claude_md}" "${tmp}" 2>/dev/null; then
        rm -f "${tmp}" 2>/dev/null || true
        echo "  global-harness: ~/.claude/CLAUDE.md block up to date (no-op)"
      else
        mv "${tmp}" "${claude_md}" 2>/dev/null && \
          echo "  global-harness: refreshed AIHAUS:GLOBAL-HARNESS block in ~/.claude/CLAUDE.md"
      fi
    else
      rm -f "${tmp}" 2>/dev/null || true
    fi
  else
    { printf '\n\n'; cat "${src_tmp}"; } >> "${claude_md}" 2>/dev/null && \
      echo "  global-harness: appended AIHAUS:GLOBAL-HARNESS block to ~/.claude/CLAUDE.md"
  fi
  rm -f "${src_tmp}" 2>/dev/null || true
  return 0
}

# remove_global_harness — strips ONLY the marker span from ~/.claude/CLAUDE.md
# (never the user's other content). Deletes the file only when nothing but
# whitespace remains (i.e. the seed was the entire file).
remove_global_harness() {
  local claude_md="$HOME/.claude/CLAUDE.md"
  if [[ ! -f "${claude_md}" ]] || ! grep -Fq "AIHAUS:GLOBAL-HARNESS-START" "${claude_md}" 2>/dev/null; then
    echo "  global-harness: nothing to remove"
    return 0
  fi
  local tmp="${claude_md}.tmp.$$"
  if awk '
    index($0, "AIHAUS:GLOBAL-HARNESS-START") > 0 { skipping = 1; next }
    skipping { if (index($0, "AIHAUS:GLOBAL-HARNESS-END") > 0) skipping = 0; next }
    { print }
  ' "${claude_md}" > "${tmp}" 2>/dev/null; then
    if [[ -z "$(tr -d '[:space:]' < "${tmp}" 2>/dev/null)" ]]; then
      rm -f "${tmp}" "${claude_md}" 2>/dev/null || true
      echo "  removed user-global: ~/.claude/CLAUDE.md (file contained only the GLOBAL-HARNESS block)"
    else
      mv "${tmp}" "${claude_md}" 2>/dev/null && \
        echo "  removed user-global: AIHAUS:GLOBAL-HARNESS block from ~/.claude/CLAUDE.md (other content preserved)"
    fi
  else
    rm -f "${tmp}" 2>/dev/null || true
  fi
  return 0
}

# register_aihaus_target <abs-repo-path> — APPEND-dedupe one absolute repo
# path per line to ~/.aihaus/.targets (format consumed by the `aihaus update
# --all` loop). Honors AIHAUS_SKIP_GLOBAL_HARNESS=1 (BR-U1 — same env gates
# both $HOME enrollment surfaces in this slice).
register_aihaus_target() {
  local target="${1:-}"
  [[ -z "${target}" ]] && return 0
  if [[ "${AIHAUS_SKIP_GLOBAL_HARNESS:-0}" == "1" ]]; then
    echo "  targets: enrollment skipped (AIHAUS_SKIP_GLOBAL_HARNESS=1)"
    return 0
  fi
  local reg="$HOME/.aihaus/.targets"
  mkdir -p "$HOME/.aihaus" 2>/dev/null || return 0
  if [[ -f "${reg}" ]] && grep -Fxq "${target}" "${reg}" 2>/dev/null; then
    return 0
  fi
  printf '%s\n' "${target}" >> "${reg}" 2>/dev/null && \
    echo "  targets: registered ${target} in ~/.aihaus/.targets (consumed by 'aihaus update --all')"
  return 0
}
