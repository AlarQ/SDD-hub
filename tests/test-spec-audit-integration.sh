#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091
set -euo pipefail

# test-spec-audit-integration.sh — T017 tests:
# create-followup command, FR allowlist fail-closed, reaudit guard logic,
# spec_reaudit_requested allowlist entry.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TM="$REPO_ROOT/scripts/task-manager.sh"
MON_VAL="$REPO_ROOT/scripts/monitor-validators.sh"

PASS=0
FAIL=0
TEST_TMPDIR=""

setup_fixture() {
  TEST_TMPDIR="$(mktemp -d)"
  export WF_REPO_ROOT="$TEST_TMPDIR"
  mkdir -p "$TEST_TMPDIR/specs/demo/tasks" "$TEST_TMPDIR/specs/demo/reports"
  printf 'spec_storage: specs/\n' > "$TEST_TMPDIR/.workflow.yml"
  cat > "$TEST_TMPDIR/specs/demo/spec.md" <<'EOF'
# Demo Spec

## Functional Requirements

### FR-1: First requirement
Body.

### FR-2: Second requirement
Body.

## Applicable Ground Rules

- `general:security/general.md` — input validation
- `general:testing/principles.md` — Given/When/Then
EOF
  # Seed an existing task so next id resolves to 002
  cat > "$TEST_TMPDIR/specs/demo/tasks/001-seed.md" <<'EOF'
---
id: "001"
name: "Seed"
status: done
blocked_by: []
max_files: 1
estimated_files: []
test_cases: []
ground_rules:
  - general:security/general.md
---

## Description
Seed.
EOF
}

teardown_fixture() {
  unset WF_REPO_ROOT
  rm -rf "$TEST_TMPDIR"
}

assert_eq() {
  local expected="$1" actual="$2" msg="${3:-}"
  if [[ "$expected" == "$actual" ]]; then PASS=$((PASS+1)); echo "  PASS: $msg"; return 0; fi
  FAIL=$((FAIL+1))
  echo "  FAIL: $msg" >&2
  echo "    expected: $expected" >&2
  echo "    actual:   $actual" >&2
  return 1
}

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  if [[ "$haystack" == *"$needle"* ]]; then PASS=$((PASS+1)); echo "  PASS: $msg"; return 0; fi
  FAIL=$((FAIL+1))
  echo "  FAIL: $msg" >&2
  echo "    needle missing: $needle" >&2
  return 1
}

# === Tests ===

test_unknown_fr_fails_closed() {
  echo "[test] unknown FR id fails closed, lists known FRs"
  setup_fixture
  local out rc=0
  out="$(bash "$TM" create-followup demo FR-99 "should not create" 2>&1)" || rc=$?
  assert_eq 1 "$rc" "exit non-zero on unknown FR"
  assert_contains "$out" "Unknown FR id 'FR-99'" "error names unknown FR id"
  assert_contains "$out" "FR-1" "error lists known FRs"
  assert_contains "$out" "FR-2" "error lists known FRs"
  # No new task file created
  local count
  count=$(ls "$TEST_TMPDIR/specs/demo/tasks/" | wc -l | tr -d ' ')
  assert_eq 1 "$count" "no follow-up task created on rejection"
  teardown_fixture
}

test_create_followup_happy_path() {
  echo "[test] create-followup writes valid task with inherited ground_rules"
  setup_fixture
  local task_path
  task_path="$(bash "$TM" create-followup demo FR-2 "Add validation for FR-2 contract")"
  [[ -f "$task_path" ]] || { echo "  FAIL: task file not created"; FAIL=$((FAIL+1)); teardown_fixture; return; }
  assert_contains "$task_path" "002-fr-2-" "filename uses next sequential id 002 and references FR id"
  local body
  body="$(cat "$task_path")"
  assert_contains "$body" 'status: todo' "status is todo"
  assert_contains "$body" 'general:security/general.md' "inherits security ground_rule from spec"
  assert_contains "$body" 'general:testing/principles.md' "inherits testing ground_rule from spec"
  assert_contains "$body" 'FR-2' "name references FR id"
  # Validate the generated task passes task-manager validate
  local rc=0
  bash "$TM" validate "$task_path" >/dev/null 2>&1 || rc=$?
  assert_eq 0 "$rc" "generated task passes structural validation"
  teardown_fixture
}

test_spec_reaudit_in_allowlist() {
  echo "[test] spec_reaudit_requested in monitor closed allowlist"
  local content
  content="$(cat "$MON_VAL")"
  assert_contains "$content" "spec_reaudit_requested" "category present in allowlist"
}

test_reaudit_guard_logic() {
  echo "[test] guard: spec_reaudit_requested newer than spec_audit_done clears guard"
  setup_fixture
  local mon="$TEST_TMPDIR/specs/demo/.monitor.jsonl"
  printf '{"category":"spec_audit_done"}\n{"category":"spec_reaudit_requested"}\n' > "$mon"
  # Most recent is spec_reaudit_requested → expect newest != spec_audit_done
  local newest
  newest=$(grep -oE '"category":"(spec_audit_done|spec_reaudit_requested)"' "$mon" | tail -1)
  assert_contains "$newest" "spec_reaudit_requested" "newest event is reaudit sentinel"
  # And reverse case
  printf '{"category":"spec_reaudit_requested"}\n{"category":"spec_audit_done"}\n' > "$mon"
  newest=$(grep -oE '"category":"(spec_audit_done|spec_reaudit_requested)"' "$mon" | tail -1)
  assert_contains "$newest" "spec_audit_done" "newest event is audit_done — guard holds"
  teardown_fixture
}

test_create_followup_via_cli_dispatch() {
  echo "[test] CLI dispatch: create-followup is registered as subcommand"
  setup_fixture
  local help
  help="$(bash "$TM" help 2>&1)"
  assert_contains "$help" "create-followup" "help lists create-followup"
  teardown_fixture
}

# === Run ===

test_unknown_fr_fails_closed
test_create_followup_happy_path
test_spec_reaudit_in_allowlist
test_reaudit_guard_logic
test_create_followup_via_cli_dispatch

echo
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
