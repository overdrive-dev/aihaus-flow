# Notion Sync Setup Guide

This guide walks you through configuring the AIhaus Notion sync agent for
your project. The agent keeps a Notion Kanban board synchronized with your
milestone execution state.

## Prerequisites

- A Notion account with permission to create integrations
- A Notion workspace where you want the Kanban board
- Your project installed with AIhaus (`/aih-init` completed)

---

## Step 1: Create a Notion Integration

1. Go to [https://www.notion.so/my-integrations](https://www.notion.so/my-integrations)
2. Click **New integration**
3. Give it a name (e.g., "AIhaus Sync")
4. Select the workspace where your Kanban board lives
5. Under **Capabilities**, ensure it has:
   - Read content
   - Update content
   - Insert content
6. Click **Submit** and copy the **Internal Integration Secret** (starts with `ntn_`)

This token is your `NOTION_TOKEN`. Keep it safe.

## Step 2: Create the Notion Database

Create a new database in Notion (full-page or inline) with at least these
properties. You can rename them — just update `card_fields` in your config
to match.

| Property Name | Type     | Purpose                                 |
|---------------|----------|-----------------------------------------|
| Title         | Title    | Card name (auto-generated from template)|
| Status        | Select   | Kanban column (see status options below) |
| Role          | Select   | Which user role this card covers         |
| Device        | Select   | Platform (Web, Mobile, API, etc.)        |
| Version       | Text     | Version or release identifier            |
| Screen        | Text     | UI screen or page name                   |
| Route         | Text     | API route or URL path                    |
| Milestone     | Text     | Which milestone this belongs to          |
| Phase         | Text     | Planning phase or slice                  |
| Requested     | Text     | What was requested                       |
| Delivered     | Text     | What was actually delivered              |
| Notes         | Text     | Additional context or justifications     |

### Status Select Options

Add these options to the **Status** select property (customize names in config):

- Requests
- Backlog
- In Progress
- Testing
- Done
- Rejected
- Archived

After creating the database:
1. Click the **...** menu on the database page
2. Go to **Connections** and add your integration
3. Copy the **database ID** from the URL:
   `https://www.notion.so/<workspace>/<DATABASE_ID>?v=...`

## Step 3: Configure `.aihaus/notion/config.json`

Copy the example config to your project:

```bash
mkdir -p .aihaus/notion
cp .aihaus/templates/notion/config.example.json .aihaus/notion/config.json
```

Edit `.aihaus/notion/config.json`:

1. Replace `YOUR_NOTION_DATABASE_ID` with the database ID from Step 2
2. Update `status_flow` values if you renamed any status options
3. Update `roles` to match your project's user roles
4. Update `card_fields` if you renamed any database properties
5. Update `title_format` to match your preferred card naming convention
6. Update `sync_commands` to match your project's sync script commands

### Sync Commands

The `sync_commands` object tells the agent which CLI commands to run. You need
to set up these scripts in your project. The default config assumes npm scripts,
but you can use any command runner.

Example for a Node.js project (`package.json`):

```json
{
  "scripts": {
    "notion:sync:dry": "node scripts/notion-sync.js --dry-run",
    "notion:sync": "node scripts/notion-sync.js",
    "notion:sync:body:dry": "node scripts/notion-sync.js --body --dry-run",
    "notion:sync:body": "node scripts/notion-sync.js --body",
    "notion:sync:body:force": "node scripts/notion-sync.js --body --force",
    "notion:query": "node scripts/notion-query.js"
  }
}
```

Example for a Python project (`Makefile`):

```makefile
notion-sync-dry:
	python scripts/notion_sync.py --dry-run
notion-sync:
	python scripts/notion_sync.py
notion-query:
	python scripts/notion_query.py
```

Then in your config:

```json
{
  "sync_commands": {
    "dry_run": "make notion-sync-dry",
    "sync": "make notion-sync",
    "query": "make notion-query"
  }
}
```

## Step 4: Set Up Sync Scripts

The AIhaus Notion agent calls your sync commands but does not include the
sync scripts themselves — they are project-specific. You need to implement:

1. **Sync script**: Reads `.aihaus/notion/sync-items.json` and updates Notion
   cards via the Notion API. Should support `--dry-run` to preview changes.
2. **Query script**: Queries the Notion database and outputs card data to
   stdout. Should support `--query-status <STATUS>` and `--role <ROLE>` flags.

The sync script reads from `.aihaus/notion/sync-items.json`, which the agent
maintains. Each item has the fields defined in your `card_fields` config.

Refer to the [Notion API documentation](https://developers.notion.com/) for
details on reading and writing database pages.

## Step 5: Set the NOTION_TOKEN Environment Variable

Add your integration token to your environment. Do NOT commit it to version
control.

```bash
# In your shell profile (.bashrc, .zshrc, etc.)
export NOTION_TOKEN="ntn_your_token_here"

# Or in a .env file (make sure .env is in .gitignore)
NOTION_TOKEN=ntn_your_token_here
```

If using `.env`, your sync scripts need to load it (e.g., via `dotenv` in
Node.js or `python-dotenv` in Python).

## Step 6: Test with a Dry-Run Sync

Run the Notion sync skill with a dry run to verify everything is connected:

```
/aih-sync-notion sync
```

The agent will:
1. Read your config from `.aihaus/notion/config.json`
2. Read the current execution state
3. Run the `dry_run` command from your config
4. Report what would change without writing to Notion

If the dry run succeeds, you can run a real sync. If it fails, check:
- Is `NOTION_TOKEN` set correctly?
- Does the integration have access to the database?
- Are the field names in config matching the actual Notion properties?
- Are the sync scripts working independently?

## Optional: Create a Runbook

For project-specific sync protocols (e.g., custom triage workflows, approval
gates, or multi-board setups), create `.aihaus/notion/runbook.md`. The agent
treats this as the source of truth when present and falls back to its built-in
protocol otherwise.

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "NOTION_TOKEN not set" | Export the token in your shell or .env file |
| "Database not found" | Verify the database ID and that the integration has access |
| "Property not found" | Check that `card_fields` in config matches your Notion database |
| Cards not appearing | Ensure the integration is connected to the database page |
| Wrong status names | Update `status_flow` in config to match your Notion select options |
