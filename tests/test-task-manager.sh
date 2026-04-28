#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091
set -euo pipefail

# test-task-manager.sh — Tests for task-manager.sh walk-up and WF_SPEC_STORAGE behavior.
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
  mkdir -p "$TEST_TMPDIR/knowledge-base"
  printf 'spec_storage: specs/\n' > "$TEST_TMPDIR/.workflow.yml"
  cd "$TEST_TMPDIR"
}

teardown() {
  cd "$REPO_ROOT"
  rm -rf "$TEST_TMPDIR"
}

assert_eq() {
  local expected="$1" actual="$2" msg="${3:-}"
  if [[ "$expected" == "$actual" ]]; then return 0; fi
  echo "  ASSERT FAILED${msg:+: $msg}" >&2
  echo "    expected: $expected" >&2
  echo "    actual:   $actual" >&2
  return 1
}

run_test() {
  local name="$1"; shift
  setup
  if "$@"; then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name"; FAIL=$((FAIL + 1))
  fi
  teardown
}

# Helper: write a minimal valid task file
write_task() {
  local file="$1"
  cat > "$file" <<'EOF'
---
id: "001"
name: "test task"
status: todo
blocked_by: []
max_files: 3
estimated_files:
  - src/main.sh
ground_rules: []
test_cases:
  - "it works"
---

## Description
Test task.
EOF
}

# === Walk-up tests ===

test_validate_from_nested_subdir() {
  # Given a task file at repo root and a deeply nested working directory
  local task_file="$TEST_TMPDIR/specs/test-feature/tasks/001-test-task.md"
  write_task "$task_file"
  mkdir -p "$TEST_TMPDIR/deep/nested/subdir"
  cd "$TEST_TMPDIR/deep/nested/subdir"

  # When task-manager.sh validate is called with a path relative to repo root
  # (WF_REPO_ROOT set to emulate walk-up finding the root)
  WF_REPO_ROOT="$TEST_TMPDIR" "$TASK_MANAGER" validate "$task_file"
}

test_validate_absolute_path_works_from_any_dir() {
  # Given a task file with an absolute path
  local task_file="$TEST_TMPDIR/specs/test-feature/tasks/001-test-task.md"
  write_task "$task_file"
  mkdir -p "$TEST_TMPDIR/some/other/dir"
  cd "$TEST_TMPDIR/some/other/dir"

  # When validate is called with an absolute path from a different dir
  "$TASK_MANAGER" validate "$task_file"
}

test_validate_relative_path_resolved_from_repo_root() {
  # Given a task file and WF_REPO_ROOT set
  local task_file="$TEST_TMPDIR/specs/test-feature/tasks/001-test-task.md"
  write_task "$task_file"
  mkdir -p "$TEST_TMPDIR/subdir"
  cd "$TEST_TMPDIR/subdir"

  # When validate is called with a relative path (relative to repo root, not cwd)
  local rel_path="specs/test-feature/tasks/001-test-task.md"
  WF_REPO_ROOT="$TEST_TMPDIR" "$TASK_MANAGER" validate "$rel_path"
}

# === Status / next tests with WF_SPEC_STORAGE ===

test_next_with_explicit_tasks_dir() {
  # Given a task file in the standard location
  local task_file="$TEST_TMPDIR/specs/test-feature/tasks/001-test-task.md"
  write_task "$task_file"

  # When next is called with explicit tasks directory
  local result
  result="$("$TASK_MANAGER" next "$TEST_TMPDIR/specs/test-feature/tasks/")"
  [[ "$result" == *"001-test-task.md"* ]]
}

test_vault_spec_storage_task_accessible() {
  # Given WF_SPEC_STORAGE points to a vault outside the repo
  local vault="$TEST_TMPDIR/vault"
  mkdir -p "$vault/my-feature/tasks"
  write_task "$vault/my-feature/tasks/001-test-task.md"

  # When next is called with vault tasks directory
  local result
  result="$("$TASK_MANAGER" next "$vault/my-feature/tasks/")"
  [[ "$result" == *"001-test-task.md"* ]]
}

test_set_status_works_from_nested_subdir() {
  # Given a task file and a nested subdir as cwd
  local task_file="$TEST_TMPDIR/specs/test-feature/tasks/001-test-task.md"
  write_task "$task_file"
  mkdir -p "$TEST_TMPDIR/a/b/c"
  cd "$TEST_TMPDIR/a/b/c"

  # When set-status is called with the absolute task file path
  "$TASK_MANAGER" set-status "$task_file" in-progress

  # Then status is updated
  local new_status
  new_status="$(grep '^status:' "$task_file" | awk '{print $2}')"
  assert_eq "in-progress" "$new_status" "status should be updated"
}

# === Runner ===

echo "Running test-task-manager.sh tests..."
echo ""
run_test "validate accepts task file via absolute path from any dir" test_validate_absolute_path_works_from_any_dir
run_test "validate resolves relative path from repo root when WF_REPO_ROOT is set" test_validate_relative_path_resolved_from_repo_root
run_test "validate works when invoked from a nested subdir (WF_REPO_ROOT set)" test_validate_from_nested_subdir
run_test "next returns correct task from explicit tasks directory" test_next_with_explicit_tasks_dir
run_test "vault: tasks under WF_SPEC_STORAGE are accessible to next command" test_vault_spec_storage_task_accessible
run_test "set-status works from a nested subdir with absolute task path" test_set_status_works_from_nested_subdir

echo ""
echo "Results: $PASS passed, $FAIL failed out of $((PASS + FAIL)) tests"
[[ "$FAIL" -gt 0 ]] && exit 1
exit 0
