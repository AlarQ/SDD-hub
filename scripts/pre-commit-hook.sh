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
    # Capture stdout ONLY — stderr stays on the terminal so warnings/diagnostics
    # can never be folded into the text we eval (would otherwise be RCE input).
    _loader_out="$("$_loader" export)" || {
      echo "WARN: config-loader.sh failed" >&2
      break
    }
    # Defense-in-depth: a poisoned/older repo-local loader (tried first) could
    # emit arbitrary text. eval ONLY allowlisted WF_<NAME>=... lines; anything
    # else is warned about and skipped, never executed.
    while IFS= read -r _loader_line; do
      [[ -z "$_loader_line" ]] && continue
      if [[ "$_loader_line" =~ ^WF_[A-Z0-9_]+= ]]; then
        eval "$_loader_line" || echo "WARN: config-loader.sh line rejected: ${_loader_line%%=*}" >&2
      else
        echo "WARN: config-loader.sh emitted non-WF line — skipped" >&2
      fi
    done <<< "$_loader_out"
    break
  fi
done
unset _loader _loader_out _loader_line

if [ ! -x "$TASK_MANAGER" ]; then
  echo "WARNING: task-manager.sh not found at $TASK_MANAGER — skipping task validation"
  exit 0
fi

# Derive spec storage prefix for task file path matching.
# WF_SPEC_STORAGE is set by config-loader when .workflow.yml is present.
# Without .workflow.yml workflow is unconfigured — skip task validation.
if [[ -z "${WF_SPEC_STORAGE:-}" ]]; then
  exit 0
fi
_spec_prefix="${WF_SPEC_STORAGE#"$REPO_ROOT/"}"
# Escape ERE metacharacters so a path like "my.specs" matches literally
_spec_prefix_esc="$(printf '%s' "$_spec_prefix" | sed 's/[.[\*^$()+?{|]/\\&/g')"

# Find changed task files under spec storage relative to repo root
mapfile -t changed_tasks < <(
  git diff --cached --name-only -z --diff-filter=ACM \
  | tr '\0' '\n' | grep -E "^${_spec_prefix_esc}/.*/tasks/.*\\.md\$" || true
)
unset _spec_prefix _spec_prefix_esc
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
