#!/usr/bin/env bash
set -euo pipefail

db_path="${1:-.aihaus/state/kanban.db}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
schema_path="${script_dir}/schema.sql"

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "init-kanban-db.sh: sqlite3 not found" >&2
  exit 127
fi

mkdir -p "$(dirname "$db_path")"
sqlite3 "$db_path" < "$schema_path"
