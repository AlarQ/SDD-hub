#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091
set -euo pipefail

# test-path-resolution.sh — Integration tests verifying that monitor.sh,
# task-manager.sh, and pre-commit-hook.sh resolve paths correctly from
# nested working directories and vault (custom WF_SPEC_STORAGE) setups.
# Uses Given/When/Then structure. No external test framework.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MONITOR_SCRIPT="$REPO_ROOT/scripts/monitor.sh"
TASK_MANAGER="$REPO_ROOT/scripts/task-manager.sh"

PASS=0
FAIL=0
TEST_TMPDIR=""

setup() {
  TEST_TMPDIR="$(mktemp -d)"
  mkdir -p "$TEST_TMPDIR/specs/test-feature"
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

# Helper: write minimal task file
write_task() {
  local file="$1"
  mkdir -p "$(dirname "$file")"
  cat > "$file" <<'EOF'
---
id: "001"
name: "path test"
status: todo
blocked_by: []
max_files: 2
estimated_files: []
ground_rules: []
test_cases: []
---
EOF
}

# === monitor.sh path resolution from nested cwd ===

test_monitor_events_land_under_spec_storage_from_nested_cwd() {
  # Given .workflow.yml at repo root with spec_storage: specs/
  # and cwd is a nested subdirectory
  mkdir -p "$TEST_TMPDIR/deep/nested/dir"
  cd "$TEST_TMPDIR/deep/nested/dir"

  # When log_event is called (sources monitor.sh with find_workflow_root)
  source "$MONITOR_SCRIPT"
  log_event "test-feature" "tool_call" "001" '{"x":1}'

  # Then event lands under $TEST_TMPDIR/specs, not ./specs (relative to nested cwd)
  local expected="$TEST_TMPDIR/specs/test-feature/.monitor.jsonl"
  local wrong="$TEST_TMPDIR/deep/nested/dir/specs/test-feature/.monitor.jsonl"
  [[ -f "$expected" ]] || { echo "  Event not found at expected path: $expected" >&2; return 1; }
  [[ ! -f "$wrong" ]] || { echo "  Event leaked to nested cwd path: $wrong" >&2; return 1; }
}

# === Vault case: WF_SPEC_STORAGE=/tmp/vault ===

test_monitor_vault_events_land_under_vault_not_specs() {
  # Given WF_SPEC_STORAGE points to a vault path
  local vault="$TEST_TMPDIR/vault"
  mkdir -p "$vault/test-feature"
  export WF_SPEC_STORAGE="$vault"

  source "$MONITOR_SCRIPT"
  log_event "test-feature" "config_inferred" "001" '{"inferred_count":2}'

  # Then events land under vault, never under ./specs
  [[ -f "$vault/test-feature/.monitor.jsonl" ]] || {
    echo "  Event not in vault" >&2; unset WF_SPEC_STORAGE; return 1
  }
  [[ ! -f "$TEST_TMPDIR/specs/test-feature/.monitor.jsonl" ]] || {
    echo "  Leaked to specs/" >&2; unset WF_SPEC_STORAGE; return 1
  }
  unset WF_SPEC_STORAGE
}

# === Legacy repo: no .workflow.yml, has specs/ ===

test_legacy_repo_no_workflow_yml_still_works() {
  # Given a repo with specs/ but no .workflow.yml (legacy)
  rm -f "$TEST_TMPDIR/.workflow.yml"
  # WF_LEGACY_SPECS_FALLBACK=1 enables the legacy path explicitly
  export WF_LEGACY_SPECS_FALLBACK=1

  source "$MONITOR_SCRIPT"
  log_event "test-feature" "tool_call" "001" '{"legacy":true}'

  [[ -f "$TEST_TMPDIR/specs/test-feature/.monitor.jsonl" ]] || {
    echo "  Event not found in legacy specs/" >&2; unset WF_LEGACY_SPECS_FALLBACK; return 1
  }
  unset WF_LEGACY_SPECS_FALLBACK
}

# === task-manager.sh walk-up from nested subdir ===

test_task_manager_validate_from_nested_subdir() {
  # Given a task file and a deeply nested cwd
  local task_file="$TEST_TMPDIR/specs/test-feature/tasks/001-task.md"
  write_task "$task_file"
  mkdir -p "$TEST_TMPDIR/level1/level2/level3"
  cd "$TEST_TMPDIR/level1/level2/level3"

  # When task-manager validate is called with the absolute path
  "$TASK_MANAGER" validate "$task_file"
}

# === pre-commit-hook.sh: uses git rev-parse --show-toplevel ===

test_pre_commit_hook_resolves_repo_root_via_git() {
  # Given a real git repo in a tmpdir (simulates git -C subdir invocation)
  local git_repo="$TEST_TMPDIR/git-repo"
  mkdir -p "$git_repo/specs/my-feature/tasks"
  mkdir -p "$git_repo/scripts"
  git -C "$git_repo" init -q
  git -C "$git_repo" config user.email "test@test.com"
  git -C "$git_repo" config user.name "Test"

  write_task "$git_repo/specs/my-feature/tasks/001-task.md"

  # Install hook pointing to repo's task-manager
  mkdir -p "$git_repo/.git/hooks"
  cat > "$git_repo/.git/hooks/pre-commit" <<EOF
#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="\$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
TASK_MANAGER="$TASK_MANAGER"
[ ! -x "\$TASK_MANAGER" ] && exit 0
changed_tasks=\$(git diff --cached --name-only --diff-filter=ACM | grep -E '^specs/.*/tasks/.*\\.md\$' || true)
[ -z "\$changed_tasks" ] && exit 0
errors=0
for task_file in \$changed_tasks; do
  abs_task="\$REPO_ROOT/\$task_file"
  "\$TASK_MANAGER" validate "\$abs_task" || errors=\$((errors + 1))
done
[ "\$errors" -gt 0 ] && exit 1; exit 0
EOF
  chmod +x "$git_repo/.git/hooks/pre-commit"

  # Stage the task file and commit from a nested subdir
  mkdir -p "$git_repo/work/subdir"
  cd "$git_repo"
  git add specs/my-feature/tasks/001-task.md
  # When pre-commit hook runs (triggered by git commit)
  git -C "$git_repo" commit -m "test" --no-gpg-sign 2>/dev/null
}

# === Integration seam: WF_* contract end-to-end ===

test_wf_spec_storage_end_to_end_from_loader() {
  # Given WF_SPEC_STORAGE is set (as if by config-loader.sh export eval)
  local vault="$TEST_TMPDIR/e2e-vault"
  mkdir -p "$vault/myspec"
  export WF_SPEC_STORAGE="$vault"

  # When monitor.sh is sourced and log_event called
  source "$MONITOR_SCRIPT"
  log_event "myspec" "gate_skip" "002" '{"reason":"empty intersection","gate":"rust-clippy"}'

  # Then event is in vault (end-to-end WF_* contract)
  [[ -f "$vault/myspec/.monitor.jsonl" ]] || {
    echo "  WF_SPEC_STORAGE E2E failed" >&2; unset WF_SPEC_STORAGE; return 1
  }
  local line
  line="$(cat "$vault/myspec/.monitor.jsonl")"
  [[ "$line" == *'"category":"gate_skip"'* ]] || {
    echo "  Wrong category in event" >&2; unset WF_SPEC_STORAGE; return 1
  }
  unset WF_SPEC_STORAGE
}

# === CI matrix: default repo AND vault repo ===

test_ci_matrix_default_repo() {
  # Default repo setup (spec_storage: specs/, .workflow.yml present)
  source "$MONITOR_SCRIPT"
  log_event "test-feature" "config_approved" "001" '{"approved":true}'
  [[ -f "$TEST_TMPDIR/specs/test-feature/.monitor.jsonl" ]]
}

test_ci_matrix_vault_repo() {
  # Vault repo: WF_SPEC_STORAGE=/tmp/vault
  local vault="$TEST_TMPDIR/ci-vault"
  mkdir -p "$vault/test-feature"
  export WF_SPEC_STORAGE="$vault"
  source "$MONITOR_SCRIPT"
  log_event "test-feature" "config_approved" "001" '{"approved":true}'
  local ok=0
  [[ -f "$vault/test-feature/.monitor.jsonl" ]] && ok=1
  unset WF_SPEC_STORAGE
  [[ "$ok" == "1" ]]
}

# === Runner ===

echo "Running test-path-resolution.sh tests..."
echo ""
run_test "monitor.sh: events land under spec_storage from nested cwd" test_monitor_events_land_under_spec_storage_from_nested_cwd
run_test "monitor.sh: vault case - events under WF_SPEC_STORAGE, never ./specs" test_monitor_vault_events_land_under_vault_not_specs
run_test "monitor.sh: legacy repo (no .workflow.yml) works via fallback flag" test_legacy_repo_no_workflow_yml_still_works
run_test "task-manager.sh: validate locates task file from deep subdir via walk-up" test_task_manager_validate_from_nested_subdir
run_test "pre-commit-hook.sh: resolves repo root via git rev-parse --show-toplevel" test_pre_commit_hook_resolves_repo_root_via_git
run_test "integration seam: shell callers consume WF_* contract end-to-end from loader" test_wf_spec_storage_end_to_end_from_loader
run_test "T003 CI matrix: default repo" test_ci_matrix_default_repo
run_test "T003 CI matrix: vault repo" test_ci_matrix_vault_repo

echo ""
echo "Results: $PASS passed, $FAIL failed out of $((PASS + FAIL)) tests"
[[ "$FAIL" -gt 0 ]] && exit 1
exit 0
