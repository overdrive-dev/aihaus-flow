# memory/frontend/ — Frontend-Specific Patterns

## Purpose

This bucket holds UI/UX and client-side knowledge accumulated across
milestones: patterns, gotchas, and conventions that apply specifically
to the frontend layer of the target project. It is written by the
frontend-dev and implementer agents during and after frontend work.

## What goes here

- Component-level patterns (naming, file layout, prop conventions)
- State-management conventions (store shapes, action naming, side-effect
  boundaries)
- Styling conventions (class naming, token usage, responsive rules)
- Frontend-specific gotchas (build tool quirks, SSR edge cases,
  hydration issues, browser-compatibility traps)
- Testing conventions for UI components (what to render, what to mock,
  accessibility assertions)

## What does NOT go here

- Cross-cutting patterns that apply to all layers → use `memory/global/`
- Backend-specific patterns → use `memory/backend/`
- Reviewer output / common findings → use `memory/reviews/`

## Ownership

Files in this bucket are **frontend-dev-written and implementer-written**.
The reviewer may propose additions via the evolution pass (ADR-M013-A).
Per ADR-M009-A, `/aih-update` never overwrites this directory.

## Cross-references

- ADR-M013-A (to be written in S04) locks the full ownership contract.
- `memory/global/` holds cross-cutting patterns that also apply here.
- `MEMORY.md` (index at `memory/MEMORY.md`) lists active frontend memory
  files and their one-line hooks for fast agent context loading.
