# memory/backend/ — Backend-Specific Patterns

## Purpose

This bucket holds server-side knowledge accumulated across milestones:
patterns, gotchas, and conventions that apply specifically to the backend
layer of the target project. It is written by the implementer and
code-fixer agents during and after backend work.

## What goes here

- `migration-patterns.md` — migration conventions, common pitfalls,
  ordering rules (agents read this before touching migrations)
- `api-patterns.md` — endpoint conventions, serialization rules,
  error-response shapes (agents read this before touching endpoints)
- `test-patterns.md` — integration-test conventions, fixture patterns,
  what must NOT be mocked (agents read this before writing tests)
- Any backend-specific gotcha that is not yet a global pattern
- Stack-specific discovery notes (ORM quirks, framework behavior, etc.)

## What does NOT go here

- Cross-cutting patterns that apply to all layers → use `memory/global/`
- Frontend-specific patterns → use `memory/frontend/`
- Reviewer output / common findings → use `memory/reviews/`

## Ownership

Files in this bucket are **implementer-written and code-fixer-written**.
The reviewer may propose additions via the evolution pass (ADR-M013-A).
Per ADR-M009-A, `/aih-update` never overwrites this directory.

## Cross-references

- ADR-M013-A (to be written in S04) locks the full ownership contract.
- `memory/global/` holds cross-cutting patterns that also apply here.
- `MEMORY.md` (index at `memory/MEMORY.md`) lists active backend memory
  files and their one-line hooks for fast agent context loading.
