#!/usr/bin/env bash
set -euo pipefail

# test-task-manager-monitor.sh — Tests for task-manager.sh monitoring instrumentation.
# Verifies that task_transition events are emitted via monitor.sh.
# Uses Given/When/Then structure. No external test framework.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASK_MANAGER="$REPO_ROOT/scripts/task-manager.sh"

PASS=0
FAIL=0
TEST_TMPDIR=""

setup() {
  TEST_TMPDIR="$(mktemp -d)"
  mkdir -p "$TEST_TMPDIR/specs/test-feature/tasks"

  # Copy scripts so task-manager.sh can source monitor.sh from SCRIPT_DIR
  mkdir -p "$TEST_TMPDIR/scripts"
  cp "$REPO_ROOT/scripts/task-manager.sh" "$TEST_TMPDIR/scripts/"
  cp "$REPO_ROOT/scripts/monitor.sh" "$TEST_TMPDIR/scripts/"
  chmod +x "$TEST_TMPDIR/scripts/"*.sh

  cd "$TEST_TMPDIR"
}

teardown() {
  cd "$REPO_ROOT"
  rm -rf "$TEST_TMPDIR"
}

assert_eq() {
  local expected="$1" actual="$2" msg="${3:-}"
  if [[ "$expected" == "$actual" ]]; then
    return 0
  fi
  echo "  ASSERT FAILED${msg:+: $msg}" >&2
  echo "    expected: $expected" >&2
  echo "    actual:   $actual" >&2
  return 1
}

run_test() {
  local name="$1"
  shift
  setup
  if "$@"; then
    echo "  PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name"
    FAIL=$((FAIL + 1))
  fi
  teardown
}

# Helper: create a minimal valid task file
create_task_file() {
  local file="$1" id="$2" status="$3"
  local blocked_by="${4:-[]}"
  cat > "$file" <<EOF
---
id: "$id"
name: "Test task $id"
status: $status
max_files: 1
ground_rules: []
test_cases: []
blocked_by: $blocked_by
estimated_files:
  - test.sh
---

## Description

Test task.
EOF
}

# Helper: set up .monitor-context
set_monitor_context() {
  printf 'feature=%s\ntask=%s\n' "$1" "$2" > "$TEST_TMPDIR/.monitor-context"
}

# === Test Cases ===

test_set_status_logs_task_transition_event() {
  # Given a task file at status "todo" and an active .monitor-context
  create_task_file "specs/test-feature/tasks/001-test.md" "001" "todo"
  set_monitor_context "test-feature" "001"

  # When set-status transitions the task to "in-progress"
  "$TEST_TMPDIR/scripts/task-manager.sh" set-status \
    "specs/test-feature/tasks/001-test.md" "in-progress" > /dev/null

  # Then a task_transition event is logged to .monitor.jsonl
  local monitor_file="specs/test-feature/.monitor.jsonl"
  [[ -f "$monitor_file" ]] || { echo "  monitor file not created" >&2; return 1; }
  grep -q '"category":"task_transition"' "$monitor_file"
}

test_set_status_no_event_on_failed_transition() {
  # Given a task at status "todo" and an active .monitor-context
  create_task_file "specs/test-feature/tasks/001-test.md" "001" "todo"
  set_monitor_context "test-feature" "001"

  # When set-status attempts an invalid transition (todo -> done)
  "$TEST_TMPDIR/scripts/task-manager.sh" set-status \
    "specs/test-feature/tasks/001-test.md" "done" 2>/dev/null && true

  # Then no event is logged (monitor file should not exist)
  local monitor_file="specs/test-feature/.monitor.jsonl"
  [[ ! -f "$monitor_file" ]]
}

test_unblock_logs_task_transition_event() {
  # Given two tasks: 001 is done, 002 is blocked by 001
  create_task_file "specs/test-feature/tasks/001-setup.md" "001" "done"
  create_task_file "specs/test-feature/tasks/002-impl.md" "002" "blocked" '["001"]'
  set_monitor_context "test-feature" "001"

  # When unblock is run
  "$TEST_TMPDIR/scripts/task-manager.sh" unblock \
    "specs/test-feature/tasks/" > /dev/null

  # Then a task_transition event is logged for the unblocked task
  local monitor_file="specs/test-feature/.monitor.jsonl"
  [[ -f "$monitor_file" ]] || { echo "  monitor file not created" >&2; return 1; }
  grep -q '"category":"task_transition"' "$monitor_file"
  grep -q '"from_status":"blocked"' "$monitor_file"
  grep -q '"to_status":"todo"' "$monitor_file"
}

test_no_logging_without_monitor_context() {
  # Given a task file at status "todo" and NO .monitor-context
  create_task_file "specs/test-feature/tasks/001-test.md" "001" "todo"
  # (no .monitor-context created)

  # When set-status transitions the task
  "$TEST_TMPDIR/scripts/task-manager.sh" set-status \
    "specs/test-feature/tasks/001-test.md" "in-progress" > /dev/null

  # Then no event is logged (monitor file should not exist)
  local monitor_file="specs/test-feature/.monitor.jsonl"
  [[ ! -f "$monitor_file" ]]
}

test_logged_event_includes_from_and_to_status() {
  # Given a task at "todo" with active monitoring
  create_task_file "specs/test-feature/tasks/001-test.md" "001" "todo"
  set_monitor_context "test-feature" "001"

  # When set-status transitions to "in-progress"
  "$TEST_TMPDIR/scripts/task-manager.sh" set-status \
    "specs/test-feature/tasks/001-test.md" "in-progress" > /dev/null

  # Then the logged event includes from_status and to_status
  local monitor_file="specs/test-feature/.monitor.jsonl"
  local line
  line="$(cat "$monitor_file")"
  [[ "$line" == *'"from_status":"todo"'* ]] || { echo "  missing from_status" >&2; return 1; }
  [[ "$line" == *'"to_status":"in-progress"'* ]] || { echo "  missing to_status" >&2; return 1; }
}

test_logged_event_includes_task_file_path() {
  # Given a task at "todo" with active monitoring
  create_task_file "specs/test-feature/tasks/001-test.md" "001" "todo"
  set_monitor_context "test-feature" "001"

  # When set-status transitions the task
  "$TEST_TMPDIR/scripts/task-manager.sh" set-status \
    "specs/test-feature/tasks/001-test.md" "in-progress" > /dev/null

  # Then the logged event includes the task_file path
  local monitor_file="specs/test-feature/.monitor.jsonl"
  local line
  line="$(cat "$monitor_file")"
  [[ "$line" == *'"task_file":"specs/test-feature/tasks/001-test.md"'* ]]
}

# === Runner ===

echo "Running task-manager.sh monitoring instrumentation tests..."
echo ""

run_test "set-status logs task_transition event on successful transition" test_set_status_logs_task_transition_event
run_test "set-status does not log event when transition fails" test_set_status_no_event_on_failed_transition
run_test "unblock logs task_transition event for each unblocked task" test_unblock_logs_task_transition_event
run_test "no logging occurs when .monitor-context does not exist" test_no_logging_without_monitor_context
run_test "logged event includes from_status and to_status" test_logged_event_includes_from_and_to_status
run_test "logged event includes task_file path" test_logged_event_includes_task_file_path

echo ""
echo "Results: $PASS passed, $FAIL failed out of $((PASS + FAIL)) tests"

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
