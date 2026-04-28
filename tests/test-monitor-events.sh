#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091
set -euo pipefail

# test-monitor-events.sh — Tests for T003 monitor.sh additions:
# category allowlist, HOME redaction, YAML body rejection.
# Uses Given/When/Then structure. No external test framework.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MONITOR_SCRIPT="$REPO_ROOT/scripts/monitor.sh"

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

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  if [[ "$haystack" == *"$needle"* ]]; then return 0; fi
  echo "  ASSERT FAILED${msg:+: $msg}" >&2
  echo "    expected to find: $needle" >&2
  echo "    in: $haystack" >&2
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

# === Category Allowlist Tests ===

test_known_category_accepted() {
  # Given monitor.sh is sourced
  source "$MONITOR_SCRIPT"

  # When log_event is called with each pre-existing category
  local cat
  for cat in task_transition phase tool_call context_read agent_invocation \
             validation_result finding_found finding_accepted finding_rejected task_update; do
    log_event "test-feature" "$cat" "001" '{"ok":true}' || {
      echo "  Category rejected: $cat" >&2; return 1
    }
  done
}

test_new_categories_accepted() {
  # Given monitor.sh is sourced
  source "$MONITOR_SCRIPT"

  # When log_event is called with the four new T003 categories
  log_event "test-feature" "config_inferred" "001" '{"inferred_count":3}' && \
  log_event "test-feature" "config_approved" "001" '{"approved":true}' && \
  log_event "test-feature" "agent_spawn" "001" '{"agent":"security-engineer"}' && \
  log_event "test-feature" "gate_skip" "001" '{"reason":"empty intersection"}'
}

test_unknown_category_rejected() {
  # Given monitor.sh is sourced
  source "$MONITOR_SCRIPT"

  # When log_event is called with an unknown category
  local err
  err="$(log_event "test-feature" "bogus_category" "001" '{"x":1}' 2>&1)" && return 1

  # Then it exits non-zero and no event is written
  [[ "$err" == *"Unknown category"* ]] || return 1
  local file="$TEST_TMPDIR/specs/test-feature/.monitor.jsonl"
  [[ ! -f "$file" ]] || [[ "$(wc -l < "$file" | tr -d ' ')" == "0" ]]
}

test_unknown_category_writes_nothing() {
  # Given monitor.sh is sourced and one valid event already logged
  source "$MONITOR_SCRIPT"
  log_event "test-feature" "tool_call" "001" '{"x":1}'
  local file="$TEST_TMPDIR/specs/test-feature/.monitor.jsonl"
  local before
  before="$(wc -l < "$file" | tr -d ' ')"

  # When an invalid category is attempted
  log_event "test-feature" "not_in_allowlist" "001" '{"x":1}' 2>/dev/null || true

  # Then no new line was written
  local after
  after="$(wc -l < "$file" | tr -d ' ')"
  assert_eq "$before" "$after" "no new event should be written for unknown category"
}

# === HOME Redaction Tests ===

test_home_path_redacted_in_event() {
  # Given monitor.sh is sourced
  source "$MONITOR_SCRIPT"

  # When an event is logged with a path under $HOME
  local path_under_home="$HOME/some/deep/path/file.sh"
  log_event "test-feature" "tool_call" "001" "$(printf '{"file":"%s"}' "$path_under_home")"

  # Then the stored event contains ~ instead of the $HOME expansion
  local file="$TEST_TMPDIR/specs/test-feature/.monitor.jsonl"
  local line
  line="$(cat "$file")"
  [[ "$line" != *"$HOME"* ]] || { echo "  $HOME path leaked into event" >&2; return 1; }
  assert_contains "$line" "~/some/deep/path/file.sh" "~ prefix expected"
}

test_non_home_path_not_altered() {
  # Given monitor.sh is sourced
  source "$MONITOR_SCRIPT"

  # When an event is logged with a path NOT under $HOME
  log_event "test-feature" "tool_call" "001" '{"file":"/tmp/somefile.sh"}'

  # Then the path is preserved as-is
  local file="$TEST_TMPDIR/specs/test-feature/.monitor.jsonl"
  local line
  line="$(cat "$file")"
  assert_contains "$line" '"/tmp/somefile.sh"' "non-home path should be unchanged"
}

# === YAML Body Rejection Tests ===

test_yaml_doc_separator_rejected() {
  # Given monitor.sh is sourced
  source "$MONITOR_SCRIPT"

  # When log_event json_data contains a --- separator
  local bad_data
  bad_data='{"body":"---\nsome: yaml"}'
  log_event "test-feature" "tool_call" "001" "$bad_data" 2>/dev/null && return 1

  # Then it exits non-zero and no file is written
  local file="$TEST_TMPDIR/specs/test-feature/.monitor.jsonl"
  [[ ! -f "$file" ]] || [[ "$(wc -l < "$file" | tr -d ' ')" == "0" ]]
}

test_gates_key_in_payload_rejected() {
  # Given monitor.sh is sourced
  source "$MONITOR_SCRIPT"

  # When log_event json_data contains a "gates": key
  log_event "test-feature" "tool_call" "001" '{"gates":"should-not-be-here"}' 2>/dev/null && return 1

  # Then it exits non-zero
  return 0
}

test_clean_payload_with_event_type_and_sha_accepted() {
  # Given monitor.sh is sourced
  source "$MONITOR_SCRIPT"

  # When log_event is called with only event type, id, and git SHA in payload
  local sha="abc1234def5678"
  log_event "test-feature" "gate_skip" "001" \
    "$(printf '{"event_type":"gate_skip","task_id":"001","git_sha":"%s","reason":"empty intersection"}' "$sha")"

  # Then the event is written successfully
  local file="$TEST_TMPDIR/specs/test-feature/.monitor.jsonl"
  [[ -f "$file" ]] && [[ "$(wc -l < "$file" | tr -d ' ')" == "1" ]]
}

# === WF_SPEC_STORAGE Integration Tests ===

test_wf_spec_storage_overrides_default_path() {
  # Given WF_SPEC_STORAGE points to a custom vault directory
  local vault="$TEST_TMPDIR/vault"
  mkdir -p "$vault/test-feature"
  export WF_SPEC_STORAGE="$vault"

  source "$MONITOR_SCRIPT"

  # When log_event is called
  log_event "test-feature" "tool_call" "001" '{"x":1}'

  # Then the event lands under the vault, not ./specs
  local expected_file="$vault/test-feature/.monitor.jsonl"
  local wrong_file="$TEST_TMPDIR/specs/test-feature/.monitor.jsonl"
  [[ -f "$expected_file" ]] || { echo "  Event not found at vault path" >&2; unset WF_SPEC_STORAGE; return 1; }
  [[ ! -f "$wrong_file" ]] || { echo "  Event leaked to specs/ path" >&2; unset WF_SPEC_STORAGE; return 1; }
  unset WF_SPEC_STORAGE
}

test_wf_spec_storage_no_global_fallback() {
  # Given WF_SPEC_STORAGE is set to a vault path and ./specs also exists
  local vault="$TEST_TMPDIR/custom-vault"
  mkdir -p "$vault/test-feature"
  export WF_SPEC_STORAGE="$vault"

  source "$MONITOR_SCRIPT"
  log_event "test-feature" "agent_spawn" "001" '{"agent":"test"}' 2>/dev/null

  # Then only vault path is written — specs/ never touched
  [[ ! -f "$TEST_TMPDIR/specs/test-feature/.monitor.jsonl" ]] || {
    echo "  Leaked to specs/" >&2; unset WF_SPEC_STORAGE; return 1
  }
  unset WF_SPEC_STORAGE
}

# === Runner ===

echo "Running monitor-events.sh tests..."
echo ""
run_test "pre-existing categories are accepted" test_known_category_accepted
run_test "four new T003 categories accepted: config_inferred, config_approved, agent_spawn, gate_skip" test_new_categories_accepted
run_test "unknown category rejected with non-zero exit" test_unknown_category_rejected
run_test "unknown category writes nothing to JSONL" test_unknown_category_writes_nothing
run_test "path under HOME is redacted to ~ prefix in event" test_home_path_redacted_in_event
run_test "path not under HOME is preserved as-is" test_non_home_path_not_altered
run_test "payload containing --- separator is rejected" test_yaml_doc_separator_rejected
run_test "payload containing gates: key is rejected" test_gates_key_in_payload_rejected
run_test "clean payload with event type + id + git SHA is accepted" test_clean_payload_with_event_type_and_sha_accepted
run_test "WF_SPEC_STORAGE overrides default specs/ path" test_wf_spec_storage_overrides_default_path
run_test "WF_SPEC_STORAGE set: no fallback to global specs/" test_wf_spec_storage_no_global_fallback

echo ""
echo "Results: $PASS passed, $FAIL failed out of $((PASS + FAIL)) tests"
[[ "$FAIL" -gt 0 ]] && exit 1
exit 0
