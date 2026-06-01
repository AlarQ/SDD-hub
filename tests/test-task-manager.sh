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

# === interaction field tests ===

test_validate_interaction_afk_accepted() {
  local task_file="$TEST_TMPDIR/specs/test-feature/tasks/001-test-task.md"
  write_task "$task_file"
  # Insert an explicit valid interaction field into the frontmatter
  sed -i.bak 's/^status: todo$/status: todo\ninteraction: afk/' "$task_file"
  "$TASK_MANAGER" validate "$task_file"
}

test_validate_interaction_absent_defaults_ok() {
  # write_task emits no interaction field — must still validate (defaults afk)
  local task_file="$TEST_TMPDIR/specs/test-feature/tasks/001-test-task.md"
  write_task "$task_file"
  "$TASK_MANAGER" validate "$task_file"
}

test_validate_interaction_invalid_rejected() {
  local task_file="$TEST_TMPDIR/specs/test-feature/tasks/001-test-task.md"
  write_task "$task_file"
  sed -i.bak 's/^status: todo$/status: todo\ninteraction: bogus/' "$task_file"
  # Expect non-zero exit (die on invalid interaction)
  if "$TASK_MANAGER" validate "$task_file" 2>/dev/null; then
    return 1
  fi
  return 0
}

# === technical_acceptance field tests ===

test_validate_technical_acceptance_absent_ok() {
  # feature-track task omits the field — must still validate
  local task_file="$TEST_TMPDIR/specs/test-feature/tasks/001-test-task.md"
  write_task "$task_file"
  "$TASK_MANAGER" validate "$task_file"
}

test_validate_technical_acceptance_array_accepted() {
  local task_file="$TEST_TMPDIR/specs/test-feature/tasks/001-test-task.md"
  write_task "$task_file"
  sed -i.bak 's/^status: todo$/status: todo\ntechnical_acceptance:\n  - "public API of module X unchanged"\n  - "span checkout.charge emitted"/' "$task_file"
  "$TASK_MANAGER" validate "$task_file"
}

test_validate_technical_acceptance_scalar_rejected() {
  local task_file="$TEST_TMPDIR/specs/test-feature/tasks/001-test-task.md"
  write_task "$task_file"
  sed -i.bak 's/^status: todo$/status: todo\ntechnical_acceptance: not-an-array/' "$task_file"
  if "$TASK_MANAGER" validate "$task_file" 2>/dev/null; then
    return 1
  fi
  return 0
}

# === implementer field tests ===
# Pin the agent pool to this repo's agents/ tree so id resolution is
# deterministic regardless of whether ~/.claude/agents is installed.
export WF_AGENT_POOL="$REPO_ROOT/agents"

test_validate_implementer_generalist_accepted() {
  local task_file="$TEST_TMPDIR/specs/test-feature/tasks/001-test-task.md"
  write_task "$task_file"
  sed -i.bak 's/^status: todo$/status: todo\nimplementer: generalist/' "$task_file"
  "$TASK_MANAGER" validate "$task_file"
}

test_validate_implementer_resolvable_accepted() {
  # engineering/frontend-developer → agents/engineering/engineering-frontend-developer.md
  local task_file="$TEST_TMPDIR/specs/test-feature/tasks/001-test-task.md"
  write_task "$task_file"
  sed -i.bak 's#^status: todo$#status: todo\nimplementer: engineering/frontend-developer#' "$task_file"
  "$TASK_MANAGER" validate "$task_file"
}

test_validate_implementer_unresolvable_rejected() {
  local task_file="$TEST_TMPDIR/specs/test-feature/tasks/001-test-task.md"
  write_task "$task_file"
  sed -i.bak 's#^status: todo$#status: todo\nimplementer: bogus/nope#' "$task_file"
  if "$TASK_MANAGER" validate "$task_file" 2>/dev/null; then
    return 1
  fi
  return 0
}

test_validate_implementer_absent_grace_ok() {
  # write_task emits no implementer field — legacy task must still validate
  local task_file="$TEST_TMPDIR/specs/test-feature/tasks/001-test-task.md"
  write_task "$task_file"
  "$TASK_MANAGER" validate "$task_file"
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

# === update_frontmatter atomicity / empty-output guard ===

# RED: an expression that yq evaluates to empty output must NOT wipe the file.
# Original must be byte-identical and the call must exit non-zero.
test_update_frontmatter_empty_output_preserves_original() {
  local task_file="$TEST_TMPDIR/specs/test-feature/tasks/001-test-task.md"
  write_task "$task_file"
  local before_sum
  before_sum="$(shasum "$task_file" | awk '{print $1}')"

  # `.x | select(. != null)` on a missing key → yq exits 0 with empty stdout,
  # which (in the buggy version) wipes the frontmatter. Call the function
  # directly so we can supply an arbitrary expression.
  local rc=0
  ( source "$TASK_MANAGER"; update_frontmatter "$task_file" '.x | select(. != null)' ) \
    >/dev/null 2>&1 || rc=$?

  local after_sum
  after_sum="$(shasum "$task_file" | awk '{print $1}')"
  assert_eq "$before_sum" "$after_sum" "file must be unchanged on empty yq output" || return 1
  [[ "$rc" -ne 0 ]] || { echo "  ASSERT FAILED: expected non-zero exit, got $rc" >&2; return 1; }
  return 0
}

# Frontmatter-only file (no body after closing ---) must update cleanly,
# exit 0, with no spurious error from the empty-body path.
test_set_status_frontmatter_only_no_body() {
  local task_file="$TEST_TMPDIR/specs/test-feature/tasks/001-nobody.md"
  cat > "$task_file" <<'EOF'
---
id: "001"
name: "no body task"
status: todo
blocked_by: []
max_files: 3
estimated_files:
  - src/main.sh
ground_rules: []
test_cases:
  - "it works"
---
EOF
  # Capture stderr only — set-status prints a normal "Status updated" line to
  # stdout on success; the empty-body path must add no error noise to stderr.
  local err rc=0
  err="$("$TASK_MANAGER" set-status "$task_file" in-progress 2>&1 1>/dev/null)" || rc=$?
  [[ "$rc" -eq 0 ]] || { echo "  ASSERT FAILED: set-status exited $rc; stderr: $err" >&2; return 1; }
  [[ -z "$err" ]] || { echo "  ASSERT FAILED: spurious stderr: $err" >&2; return 1; }
  local new_status
  new_status="$(grep '^status:' "$task_file" | awk '{print $2}')"
  assert_eq "in-progress" "$new_status" "status should be updated on frontmatter-only file"
}

# Regression: a normal set-status updates status AND preserves the body verbatim.
test_set_status_preserves_body_verbatim() {
  local task_file="$TEST_TMPDIR/specs/test-feature/tasks/001-test-task.md"
  write_task "$task_file"
  local body_before
  body_before="$(awk 'f{print} /^---$/{c++} c==2{f=1}' "$task_file")"

  "$TASK_MANAGER" set-status "$task_file" in-progress

  local new_status body_after
  new_status="$(grep '^status:' "$task_file" | awk '{print $2}')"
  body_after="$(awk 'f{print} /^---$/{c++} c==2{f=1}' "$task_file")"
  assert_eq "in-progress" "$new_status" "status should be updated" || return 1
  assert_eq "$body_before" "$body_after" "body must be preserved verbatim"
}

# === Runner ===

test_validate_frontmatter_with_markdown_hr_in_body() {
  # Given: a task whose body contains a markdown horizontal rule (`---`).
  # When: validate parses frontmatter.
  # Then: it must NOT confuse the body HR with the closing frontmatter delim.
  local task_file="$TEST_TMPDIR/specs/test-feature/tasks/001-hr-task.md"
  cat > "$task_file" <<'EOF'
---
id: "001"
name: "task with HR in body"
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

Some intro text.

---

## Section after horizontal rule

The body contains an HR above; frontmatter parser must not stop there.
EOF
  WF_REPO_ROOT="$TEST_TMPDIR" "$TASK_MANAGER" validate "$task_file"
}

# C2 — diamond cycle detection via topological sort.
# T1 → [T2,T3], T2 → [T4], T3 → [T4], T4 → [T1] (T4 closes the cycle).
# Asserts circular_dependency diagnostic appears in `status` output.
test_status_detects_diamond_cycle() {
  # cmd_status uses bash 4+ associative arrays (declare -A) — skip on bash 3.x.
  if (( BASH_VERSINFO[0] < 4 )); then
    echo "    SKIP: bash 3.x lacks associative arrays" >&2
    return 0
  fi
  local td="$TEST_TMPDIR/specs/cycle-feat/tasks"
  mkdir -p "$td"
  _wt() {
    cat > "$td/$1.md" <<EOF
---
id: "$1"
name: "task $1"
status: blocked
blocked_by: [$2]
max_files: 1
estimated_files: []
ground_rules: []
test_cases: []
---
body
EOF
  }
  # blocked_by = predecessors → cycle: T1 needs T4, T4 needs T2 or T3, T2/T3 need T1.
  _wt T1 '"T4"'
  _wt T2 '"T1"'
  _wt T3 '"T1"'
  _wt T4 '"T2", "T3"'
  local out
  out="$(WF_REPO_ROOT="$TEST_TMPDIR" "$TASK_MANAGER" status "$td" 2>&1)" || true
  [[ "$out" == *"circular_dependency"* ]]
}

# --- resolve_ground_rule_path (single-KB model, ADR-0002) ---

test_bare_path_resolves_under_general_kb() {
  local out
  out="$(WF_GENERAL_KB=/gkb bash -c \
         'source "'"$TASK_MANAGER"'"; resolve_ground_rule_path "style/general.md"' 2>/dev/null)"
  assert_eq "/gkb/style/general.md" "$out" "bare path → \$WF_GENERAL_KB"
}

test_bare_path_emits_no_warning() {
  local err
  err="$(WF_GENERAL_KB=/gkb bash -c \
         'source "'"$TASK_MANAGER"'"; resolve_ground_rule_path "style/general.md"' 2>&1 1>/dev/null)"
  [[ -z "$err" ]]
}

test_general_prefix_stripped_and_warned() {
  local out err
  out="$(WF_GENERAL_KB=/gkb bash -c \
         'source "'"$TASK_MANAGER"'"; resolve_ground_rule_path "general:security/general.md" 2>/dev/null')"
  assert_eq "/gkb/security/general.md" "$out" "general: stripped"
  err="$(WF_GENERAL_KB=/gkb bash -c \
         'source "'"$TASK_MANAGER"'"; resolve_ground_rule_path "general:security/general.md"' 2>&1 1>/dev/null)"
  [[ "$err" == *"deprecated"* ]]
}

test_project_prefix_stripped_and_warned() {
  local out err
  out="$(WF_GENERAL_KB=/gkb bash -c \
         'source "'"$TASK_MANAGER"'"; resolve_ground_rule_path "project:languages/ts.md" 2>/dev/null')"
  assert_eq "/gkb/languages/ts.md" "$out" "project: stripped"
  err="$(WF_GENERAL_KB=/gkb bash -c \
         'source "'"$TASK_MANAGER"'"; resolve_ground_rule_path "project:languages/ts.md"' 2>&1 1>/dev/null)"
  [[ "$err" == *"deprecated"* ]]
}

test_repo_named_prefix_stripped_and_warned() {
  local out
  out="$(WF_GENERAL_KB=/gkb bash -c \
         'source "'"$TASK_MANAGER"'"; resolve_ground_rule_path "repo:b:languages/go.md" 2>/dev/null')"
  assert_eq "/gkb/languages/go.md" "$out" "repo:<name>: stripped"
}

test_missing_general_kb_exits_7() {
  local rc=0
  ( unset WF_GENERAL_KB; bash -c \
    'source "'"$TASK_MANAGER"'"; resolve_ground_rule_path "style/general.md"' ) >/dev/null 2>&1 || rc=$?
  [[ "$rc" == "7" ]]
}

test_deprecation_warn_once_per_process() {
  local err
  err="$(WF_GENERAL_KB=/gkb bash -c \
    'source "'"$TASK_MANAGER"'"
     resolve_ground_rule_path "general:a.md" >/dev/null
     resolve_ground_rule_path "project:b.md" >/dev/null' 2>&1 1>/dev/null)"
  local n
  n="$(printf '%s\n' "$err" | grep -c "deprecated")"
  assert_eq "1" "$n" "warn emitted once per process"
}

echo "Running test-task-manager.sh tests..."
echo ""
run_test "validate accepts task file via absolute path from any dir" test_validate_absolute_path_works_from_any_dir
run_test "validate resolves relative path from repo root when WF_REPO_ROOT is set" test_validate_relative_path_resolved_from_repo_root
run_test "validate works when invoked from a nested subdir (WF_REPO_ROOT set)" test_validate_from_nested_subdir
run_test "next returns correct task from explicit tasks directory" test_next_with_explicit_tasks_dir
run_test "vault: tasks under WF_SPEC_STORAGE are accessible to next command" test_vault_spec_storage_task_accessible
run_test "set-status works from a nested subdir with absolute task path" test_set_status_works_from_nested_subdir
run_test "validate parses frontmatter with markdown HR in body" test_validate_frontmatter_with_markdown_hr_in_body
run_test "status detects diamond-shaped dependency cycle (C2)" test_status_detects_diamond_cycle
run_test "resolve: bare path → \$WF_GENERAL_KB" test_bare_path_resolves_under_general_kb
run_test "resolve: bare path emits no warning" test_bare_path_emits_no_warning
run_test "resolve: general: stripped + warned" test_general_prefix_stripped_and_warned
run_test "resolve: project: stripped + warned" test_project_prefix_stripped_and_warned
run_test "resolve: repo:<name>: stripped + warned" test_repo_named_prefix_stripped_and_warned
run_test "resolve: missing WF_GENERAL_KB → exit 7" test_missing_general_kb_exits_7
run_test "resolve: deprecation warn once per process" test_deprecation_warn_once_per_process
run_test "validate accepts technical_acceptance absent" test_validate_technical_acceptance_absent_ok
run_test "validate accepts technical_acceptance array" test_validate_technical_acceptance_array_accepted
run_test "validate rejects technical_acceptance scalar" test_validate_technical_acceptance_scalar_rejected
run_test "validate accepts interaction: afk" test_validate_interaction_afk_accepted
run_test "validate accepts task with no interaction field (defaults afk)" test_validate_interaction_absent_defaults_ok
run_test "validate rejects invalid interaction value" test_validate_interaction_invalid_rejected
run_test "validate accepts implementer: generalist" test_validate_implementer_generalist_accepted
run_test "validate accepts resolvable implementer id" test_validate_implementer_resolvable_accepted
run_test "validate rejects unresolvable implementer id" test_validate_implementer_unresolvable_rejected
run_test "validate accepts task with no implementer field (grace)" test_validate_implementer_absent_grace_ok
run_test "update_frontmatter: empty yq output preserves original + non-zero exit" test_update_frontmatter_empty_output_preserves_original
run_test "set-status: frontmatter-only file (no body) updates cleanly, no spurious error" test_set_status_frontmatter_only_no_body
run_test "set-status: normal update preserves body verbatim (regression)" test_set_status_preserves_body_verbatim

echo ""
echo "Results: $PASS passed, $FAIL failed out of $((PASS + FAIL)) tests"
[[ "$FAIL" -gt 0 ]] && exit 1
exit 0
