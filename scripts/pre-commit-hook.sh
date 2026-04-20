#!/usr/bin/env bash
# Pre-commit hook for target projects.
# Validates any changed task files via task-manager.sh.
# Install: copy to .git/hooks/pre-commit and chmod +x

set -euo pipefail

# Find repo root so the hook works from any subdir (e.g. git -C subdir commit)
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

TASK_MANAGER="$HOME/.claude/scripts/task-manager.sh"

# Load WF_* config variables (exports spec_storage path and peers).
# WF_* vars consumed downstream: WF_REPO_ROOT, WF_SPEC_STORAGE.
# Only required when .workflow.yml is present; skip silently otherwise.
for _loader in "$REPO_ROOT/scripts/config-loader.sh" "$HOME/.claude/scripts/config-loader.sh"; do
  if [[ -x "$_loader" ]]; then
    if [[ ! -f "$REPO_ROOT/.workflow.yml" ]]; then break; fi
    _loader_out="$("$_loader" export 2>&1)" || {
      echo "WARN: config-loader.sh failed: $_loader_out" >&2
      break
    }
    eval "$_loader_out" || echo "WARN: config-loader.sh output malformed — WF_* vars not set" >&2
    break
  fi
done
unset _loader _loader_out

if [ ! -x "$TASK_MANAGER" ]; then
  echo "WARNING: task-manager.sh not found at $TASK_MANAGER — skipping task validation"
  exit 0
fi

# Find changed task files (specs/*/tasks/*.md) relative to repo root
mapfile -t changed_tasks < <(
  git diff --cached --name-only -z --diff-filter=ACM \
  | tr '\0' '\n' | grep -E '^specs/.*/tasks/.*\.md$' || true
)
[[ ${#changed_tasks[@]} -eq 0 ]] && exit 0

errors=0
for task_file in "${changed_tasks[@]}"; do
  abs_task="$REPO_ROOT/$task_file"
  if ! "$TASK_MANAGER" validate "$abs_task"; then
    echo "ERROR: Invalid task file: $task_file"
    echo "Task files must be updated via task-manager.sh"
    errors=$((errors + 1))
  fi
done

if [ "$errors" -gt 0 ]; then
  exit 1
fi
