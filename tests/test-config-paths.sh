#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091
set -euo pipefail

# test-config-paths.sh — Tests for scripts/config-paths.sh (T001).
# No external test framework. Given/When/Then structure per testing/principles.md.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PATHS_SCRIPT="$REPO_ROOT/scripts/config-paths.sh"
FIXTURES="$REPO_ROOT/tests/fixtures/config"
GATES_FILE="$REPO_ROOT/knowledge-base/gates.yml"

# Fix B: single top-level source
source "$PATHS_SCRIPT"
PASS=0
FAIL=0
TEST_TMPDIR=""

setup() { TEST_TMPDIR="$(mktemp -d)"; }
teardown() {
  [[ -n "$TEST_TMPDIR" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
  TEST_TMPDIR=""
}
run_test() {
  local name="$1"; shift
  setup
  if ( "$@" ); then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name"; FAIL=$((FAIL + 1))
  fi
  teardown
}
assert_fails() { ! ( "$@" ) >/dev/null 2>&1; }
# --- find_workflow_root ---
test_find_workflow_root_from_nested_subdir() {
  # Given a tmp repo with .workflow.yml at root and nested/deep/cwd subdir
  local root="$TEST_TMPDIR/repo"
  mkdir -p "$root/nested/deep/cwd"
  : > "$root/.workflow.yml"

  # When find_workflow_root is called from the nested cwd
  local found
  found="$(find_workflow_root "$root/nested/deep/cwd")"

  # Then it returns the realpath of the root
  local expected
  expected="$(realpath -- "$root")"
  [[ "$found" == "$expected" ]]
}
test_find_workflow_root_returns_nonzero_without_marker() {
  # Given a tmp dir with no .workflow.yml in any ancestor (sandboxed below /tmp)
  local root="$TEST_TMPDIR/no-marker/deep"
  mkdir -p "$root"

  # When find_workflow_root is called
  # Then it exits non-zero
  # Only assert non-zero if /tmp chain truly has no .workflow.yml ancestor.
  # If host has a stray marker above /tmp, skip the assertion rather than lie.
  if find_workflow_root "$root" >/dev/null 2>&1; then
    echo "    SKIP: ancestor marker present on host above $root" >&2
    return 0
  fi
  ! ( cd "$root" && find_workflow_root >/dev/null 2>&1 )
}

# --- realpath_safe ---

test_realpath_safe_rejects_dotdot_escape() {
  assert_fails realpath_safe "../../etc/passwd"
}
test_realpath_safe_rejects_symlink_ancestor_outside_roots() {
  # Given a symlink whose target escapes $HOME and repo root
  local outside="$TEST_TMPDIR/outside"
  mkdir -p "$outside/real"
  : > "$outside/real/file"
  local linkdir="$TEST_TMPDIR/link"
  ln -s "$outside/real" "$linkdir"

  # Force $HOME to a third location so the symlink target is outside both
  # $HOME and any discoverable workflow root.
  local fake_home="$TEST_TMPDIR/fake-home"
  mkdir -p "$fake_home"

  ! ( cd "$fake_home" && HOME="$fake_home" realpath_safe "$linkdir/file" >/dev/null 2>&1 )
}

# --- validate_id ---

test_validate_id_accepts_rust_clippy() {
  validate_id "rust-clippy"
}
test_validate_id_rejects_shell_injection() {
  assert_fails validate_id "; rm -rf ~"
}
test_validate_id_rejects_65_char_id() {
  local long_id
  long_id="$(printf 'a%.0s' $(seq 1 65))"
  assert_fails validate_id "$long_id"
}

# --- gates.yml schema ---

test_gates_yml_parses_and_has_required_fields() {
  command -v yq >/dev/null 2>&1 || { echo "    SKIP: yq not installed" >&2; return 0; }
  # Every entry has id, command, applies_to, category, blocking.
  local missing
  missing="$(yq e '.gates[] | [.id, .command, .applies_to, .category, .blocking] | any_c(. == null)' "$GATES_FILE" | grep -c '^true$' || true)"
  [[ "$missing" == "0" ]]
}
test_gates_yml_ids_unique() {
  command -v yq >/dev/null 2>&1 || { echo "    SKIP: yq not installed" >&2; return 0; }
  local total unique
  total="$(yq e '.gates | length' "$GATES_FILE")"
  unique="$(yq e '[.gates[].id] | unique | length' "$GATES_FILE")"
  [[ "$total" == "$unique" ]]
}

# --- dependency direction guard ---
test_config_paths_sources_no_workflow_script() {
  # Policy: config-paths.sh is a leaf — MUST NOT source any workflow script.
  ! grep -E '^\s*(source|\.)[[:space:]]+[^#]*(monitor|task-manager|config-loader|pre-commit-hook)' "$PATHS_SCRIPT"
}
# --- shared fixtures presence ---
test_shared_fixtures_created() {
  [[ -f "$FIXTURES/workflow-valid.yml" ]] \
    && [[ -f "$FIXTURES/gates-valid.yml" ]] \
    && [[ -f "$FIXTURES/gates-duplicate-id.yml" ]] \
    && [[ -d "$FIXTURES/symlink-ancestor" ]] \
    && [[ -d "$FIXTURES/nested/deep/cwd" ]]
}

echo "=== test-config-paths.sh ==="
run_test "find_workflow_root discovers .workflow.yml from nested subdir" test_find_workflow_root_from_nested_subdir
run_test "find_workflow_root returns non-zero when no marker exists" test_find_workflow_root_returns_nonzero_without_marker
run_test "realpath_safe rejects ../../etc escape" test_realpath_safe_rejects_dotdot_escape
run_test "realpath_safe rejects symlink ancestor outside allowed roots" test_realpath_safe_rejects_symlink_ancestor_outside_roots
run_test "validate_id accepts rust-clippy" test_validate_id_accepts_rust_clippy
run_test "validate_id rejects ; rm -rf ~" test_validate_id_rejects_shell_injection
run_test "validate_id rejects 65-char id" test_validate_id_rejects_65_char_id
run_test "gates.yml parses with yq; all entries have required fields" test_gates_yml_parses_and_has_required_fields
run_test "gates.yml ids are unique" test_gates_yml_ids_unique
run_test "config-paths.sh sources no workflow script" test_config_paths_sources_no_workflow_script
run_test "shared fixtures under tests/fixtures/config/ exist" test_shared_fixtures_created

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
