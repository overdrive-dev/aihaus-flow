# Workflow Environment Memory

Use this file for repository-specific execution environment notes that should
survive across `/aih-goal` runs.

Record only durable facts, for example:

- default Linear team, project, or view names used for goal intake,
- dev/staging/prod URLs that agents should verify,
- deployment commands, CI jobs, or environment gates,
- credentials or access prerequisites described without secrets,
- recurring environment constraints that affect workflow stage movement.

Do not paste transient logs, tokens, screenshots, or one-off command output.

<!-- AIHAUS:WORKFLOW-ENVIRONMENT-PROMPTS-START -->
## Runtime and Deployment

- **Where code runs:** _local dev / container / CodeBuild / ECS / Lambda / other_
- **Default dev URL:** _fill in if browser validation uses a stable URL_
- **Deploy path:** _command, pipeline, CodeBuild project, or human-owned release path_
- **Promotion gates:** _what must pass before dev, staging, or production_

## Credentials and Test Accounts

- **Credential location:** _Secrets Manager, Parameter Store, .env vault, password manager, or other approved source_
- **Test users/roles:** _named roles only; do not store passwords or tokens_
- **Auth protocol:** _how an agent should authenticate for Playwright or API smoke checks_

## Validation Commands

- **Unit/integration:** _repo command or CI job_
- **Playwright/browser:** _repo command, dev URL, required seed data_
- **CodeBuild/CI:** _project names or commands used to check builds_
- **Smoke evidence:** _screenshots, traces, URLs, logs, or release artifacts expected_

## Source System Hints

- **External kanban:** _Linear team/project/view, Jira project, Notion DB, or none_
- **Stage sync:** _which statuses/views mirror local aihaus stages_
- **Question protocol:** _how business-rule gaps are recorded and answered_
<!-- AIHAUS:WORKFLOW-ENVIRONMENT-PROMPTS-END -->
