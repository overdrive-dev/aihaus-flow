#!/usr/bin/env bash
# Shared online-action (promotion / deploy) command patterns.
#
# Sourced by flow-guard.sh — the sole online-boundary gate (ADR-260612-A) —
# so the deploy-detection list has a SINGLE definition. This is the M030 drift
# lesson applied: one canonical source, never two copies that silently diverge.
#
# Project-specific patterns extend the base set via
# .aihaus/online-actions.conf (one ERE per line; populated by aih-init
# env-detection). Intentionally conservative — a missed pattern fails open (a
# command is allowed), never destructively.

# aihaus_online_action_regex <project-root> — prints the combined ERE (base
# patterns + any project .conf), pipe-joined, ready for `grep -iE`.
aihaus_online_action_regex() {
  local root="${1:-.}"
  local patterns=(
    'kubectl\s+.*(apply|delete|rollout|scale|set\s+image)'
    'helm\s+(install|upgrade|uninstall|rollback)'
    'terraform\s+(apply|destroy)'
    'gh\s+workflow\s+run'
    'gh\s+release\s+create'
    'docker\s+push'
    'docker\s+compose\s+.*-f\s+[^ ]*(staging|stg|homolog|hml|prod|production)'
    'aws\s+(ecs|lambda|cloudformation|elasticbeanstalk|amplify)\s'
    '(flyctl|fly)\s+deploy'
    'vercel\s+(deploy|--prod)'
    'netlify\s+deploy'
    '(serverless|sls)\s+deploy'
    'git\s+push\s+(origin\s+)?(staging|homolog|hml|production|prod|release)\b'
    '\b(deploy|subir|subida)[-_]?(staging|stg|homolog|hml|prod|production)\b'
  )
  local conf="${root}/.aihaus/online-actions.conf"
  if [ -f "$conf" ]; then
    while IFS= read -r line; do
      case "$line" in ''|\#*) continue ;; esac
      patterns+=("$line")
    done < "$conf"
  fi
  local IFS='|'
  printf '%s\n' "${patterns[*]}"
}
