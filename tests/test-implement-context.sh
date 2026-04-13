#!/usr/bin/env bash
set -euo pipefail

# test-implement-context.sh — Structural tests for set_context wiring in commands/implement.md
# Uses Given/When/Then structure. Asserts relative ordering, not absolute step numbers.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
IMPLEMENT_MD="$REPO_ROOT/commands/implement.md"

PASS=0
FAIL=0

run_test() {
  local name="$1"
  shift
  local stderr_out
  stderr_out="$(mktemp)"
  if "$@" 2>"$stderr_out"; then
    echo "  PASS: $name"
    ((PASS++)) || true
  else
    echo "  FAIL: $name"
    [[ -s "$stderr_out" ]] && echo "    stderr: $(cat "$stderr_out")"
    ((FAIL++)) || true
  fi
  rm -f "$stderr_out"
}

# Given implement.md exists
# When we search for set_context call
# Then it must reference monitor.sh set_context with feature and task_id args
test_contains_set_context_call() {
  grep -qE 'monitor\.sh set_context[[:space:]]+\$ARGUMENTS[[:space:]]+\S' "$IMPLEMENT_MD"
}

# Given implement.md exists
# When we check the monitor.sh path in the set_context call
# Then the literal string ~/.claude/scripts/monitor.sh set_context must appear in the markdown
# (This checks the literal string in the markdown, not that the path resolves at runtime)
test_set_context_references_claude_scripts_path() {
  grep -qF '~/.claude/scripts/monitor.sh set_context' "$IMPLEMENT_MD"
}

# Given implement.md has set-status in-progress and a branch creation step
# When we find line numbers for each
# Then set_context must appear between them (after set-status, before branch creation)
test_set_context_positioned_before_branch_creation() {
  local line_set_status line_set_context line_branch_create
  line_set_status=$(grep -n 'set-status.*in-progress' "$IMPLEMENT_MD" | grep -v '^#' | head -1 | cut -d: -f1)
  line_set_context=$(grep -n 'monitor\.sh set_context' "$IMPLEMENT_MD" | head -1 | cut -d: -f1)
  line_branch_create=$(grep -n 'Ensure the feature integration branch exists' "$IMPLEMENT_MD" | head -1 | cut -d: -f1)

  [[ -n "$line_set_status" && -n "$line_set_context" && -n "$line_branch_create" ]] || return 1
  [[ "$line_set_status" -lt "$line_set_context" ]] || return 1
  [[ "$line_set_context" -lt "$line_branch_create" ]] || return 1
}

# Given implement.md Steps section exists
# When we extract numbered steps from the ## Steps section only
# Then they must be sequential with no gaps
test_step_numbering_sequential() {
  # Extract lines in the ## Steps section (up to next ## heading or EOF)
  local in_steps=0
  local prev=0
  while IFS= read -r line; do
    if [[ "$line" == "## Steps" ]]; then
      in_steps=1
      continue
    fi
    if [[ "$in_steps" -eq 1 && "$line" =~ ^## ]]; then
      break
    fi
    if [[ "$in_steps" -eq 1 && "$line" =~ ^([0-9]+)\. ]]; then
      local num="${BASH_REMATCH[1]}"
      if [[ "$num" -ne $((prev + 1)) ]]; then
        return 1
      fi
      prev="$num"
    fi
  done < "$IMPLEMENT_MD"
  [[ "$prev" -gt 0 ]]
}

echo "=== test-implement-context.sh ==="
run_test "implement.md contains set_context call after task status change" test_contains_set_context_call
run_test "set_context uses full path ~/.claude/scripts/monitor.sh" test_set_context_references_claude_scripts_path
run_test "set_context is positioned before branch creation step" test_set_context_positioned_before_branch_creation
run_test "step numbering is consistent after insertion" test_step_numbering_sequential

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ "$FAIL" -eq 0 ]]; then echo "PASS"; else echo "FAIL"; fi
[[ "$FAIL" -eq 0 ]]
