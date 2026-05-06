#!/usr/bin/env bash
# tier-check.sh — verify spec stays under tier ceilings (file + task count).
# Called by /implement step 0 after wf_load_config --spec <feature>.
# On breach: prints WF_TIER_BREACH=<actual_tasks>:<actual_files> /
# CEILING=<task_ceiling>:<file_ceiling> and exits 9. On OK: exits 0.
# Counts include tasks/ entries (in spec dir) and unique paths
# referenced by `files:` frontmatter across all task md files.
# shellcheck disable=SC1090,SC1091
set -euo pipefail

usage() { echo "Usage: tier-check.sh <feature>" >&2; exit 2; }
[[ $# -eq 1 ]] || usage
feature="$1"

self_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/config-loader.sh
source "$self_dir/config-loader.sh"
wf_load_config --spec "$feature" || exit $?

spec_dir="$WF_SPEC_STORAGE/$feature"
tasks_dir="$spec_dir/tasks"

task_count=0
if [[ -d "$tasks_dir" ]]; then
  task_count="$(find "$tasks_dir" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')"
fi

# Best-effort file count: union of `files:` lists across task frontmatter.
file_count=0
if [[ -d "$tasks_dir" ]] && command -v yq >/dev/null 2>&1; then
  file_count="$(
    for f in "$tasks_dir"/*.md; do
      [[ -f "$f" ]] || continue
      yq e '.files[]?' "$f" 2>/dev/null || true
    done | sort -u | grep -c . || true
  )"
fi

tc="${WF_TIER_TASK_CEILING:-}"
fc="${WF_TIER_FILE_CEILING:-}"

breach=0
[[ -n "$tc" && "$task_count" -gt "$tc" ]] && breach=1
[[ -n "$fc" && "$file_count" -gt "$fc" ]] && breach=1

if [[ "$breach" == "1" ]]; then
  printf 'WF_TIER_BREACH=%s:%s\n' "$task_count" "$file_count"
  printf 'CEILING=%s:%s\n' "${tc:-unbounded}" "${fc:-unbounded}"
  printf 'TIER=%s\n' "$WF_SPEC_TIER"
  if [[ -f "$HOME/.claude/scripts/monitor.sh" ]]; then
    bash "$HOME/.claude/scripts/monitor.sh" log_event "$feature" tier_breach "" \
      "$(printf '{"tier":"%s","tasks":%s,"files":%s,"ceiling_tasks":"%s","ceiling_files":"%s"}' \
        "$WF_SPEC_TIER" "$task_count" "$file_count" "${tc:-}" "${fc:-}")" \
      >/dev/null 2>&1 || true
  fi
  exit 9
fi

printf 'TIER=%s TASKS=%s/%s FILES=%s/%s\n' \
  "$WF_SPEC_TIER" "$task_count" "${tc:-unbounded}" "$file_count" "${fc:-unbounded}"
exit 0
