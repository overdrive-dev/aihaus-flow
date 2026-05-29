# Role Selection (aih-init)

Establishes the install's **role profile** → `.aihaus/.profile`. Roles are the
capability profiles defined in `.aihaus/workflows/roles.md` (`pm`, `builder`,
`dev`, `qa`, `devops`). Roles are **additive** — a profile may hold several
(e.g. `builder,devops`). The `devops` role is the only one that may cross the
staging→prod "online" boundary; the role-guard PreToolUse hook enforces it.

## Steps

1. **Re-run / already set.** If `.aihaus/.profile` exists, read it and show the
   current roles. Ask whether to keep or change. Keep → done (no write).

2. **Ask (interactive only).** Ask exactly ONE question:
   > "Quais roles este install deve ter? (separe por vírgula)
   >  `pm` · `builder` · `dev` · `qa` · `devops` — veja `.aihaus/workflows/roles.md`"

3. **Validate.** Accept a comma/space-separated subset of
   `{pm,builder,dev,qa,devops}`. Reject any unknown token by re-listing the
   valid set. Lowercase, de-duplicate.

4. **Write.** Write the validated roles to `.aihaus/.profile` as a single line,
   comma-separated, no trailing newline:
   ```bash
   printf '%s' "builder,devops" > .aihaus/.profile
   ```

5. **Non-interactive / no answer.** Do NOT write `.aihaus/.profile`. The
   role-guard stays out of scope (absent sentinel → exit 0). Print:
   > "No role profile set — role-guard stays out of scope. Set roles later by
   >  writing `.aihaus/.profile` (see `.aihaus/workflows/roles.md`)."

## Notes

- `.aihaus/.profile` is **local + gitignored** — a per-machine / per-person
  profile, never committed (Fase 1 enforcement is per-environment).
- This step never blocks `/aih-init`: skip-on-no-answer keeps the run autonomous.
- Downstream, env instructions are scoped by this profile (see
  `operational-context-bootstrap.md`): `devops` gets the online env; others get
  offline-local env only.
