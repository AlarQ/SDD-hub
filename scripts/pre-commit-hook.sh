#!/usr/bin/env bash
# Pre-commit hook for target projects.
# Validates any changed task files via task-manager.sh.
# Install: copy to .git/hooks/pre-commit and chmod +x

set -euo pipefail

TASK_MANAGER="$HOME/.claude/scripts/task-manager.sh"

if [ ! -x "$TASK_MANAGER" ]; then
  echo "WARNING: task-manager.sh not found at $TASK_MANAGER — skipping task validation"
  exit 0
fi

# Find changed task files (specs/*/tasks/*.md)
changed_tasks=$(git diff --cached --name-only --diff-filter=ACM | grep -E '^specs/.*/tasks/.*\.md$' || true)

if [ -z "$changed_tasks" ]; then
  exit 0
fi

errors=0
for task_file in $changed_tasks; do
  if ! "$TASK_MANAGER" validate "$task_file"; then
    echo "ERROR: Invalid task file: $task_file"
    echo "Task files must be updated via task-manager.sh"
    errors=$((errors + 1))
  fi
done

if [ "$errors" -gt 0 ]; then
  exit 1
fi
