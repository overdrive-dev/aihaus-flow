# Operational Context Bootstrap

This annex runs after `.aihaus/project.md` is ready and before aih-graph
bootstrap. It turns repository evidence into initial operational context without
inventing values.

1. If `.aihaus/skills/aih-init/scripts/environment-discovery.sh` exists, run:

   ```bash
   bash .aihaus/skills/aih-init/scripts/environment-discovery.sh --target .
   ```

   It writes `.aihaus/init/environment-discovery.md` and updates the managed
   `AIHAUS:ENV-DISCOVERY` block in
   `.aihaus/memory/workflows/environment.md`.

2. If `.aihaus/skills/aih-init/scripts/claude-context-verify.sh` exists, run:

   ```bash
   bash .aihaus/skills/aih-init/scripts/claude-context-verify.sh --target .
   ```

   It writes `.aihaus/audit/claude-context-verify.md` with `PASS` or `WARN`
   plus the exact missing imports/files.

3. Spawn `project-business-interviewer` with:

   > Read project and environment discovery artifacts, then write
   > `.aihaus/init/business-context-questions.md` with one business-rule
   > question per gap. Do not sync these questions to kanban or Linear.

4. If the run is interactive and the questions file contains at least one
   question, ask only Q1 to the human. Record the answer in the same artifact
   under `## Answered During Init`. Do not block init if the answer is absent.

Rules:

- Never read or store plaintext secrets.
- Environment discovery is evidence-based; mark missing facts as gaps.
- Business questions must be rule/criterion questions, not implementation
  trivia or bundled option menus.
