#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091
set -euo pipefail

# test-monitor.sh — Tests for scripts/monitor.sh
# Uses Given/When/Then structure. No external test framework.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MONITOR_SCRIPT="$REPO_ROOT/scripts/monitor.sh"

PASS=0
FAIL=0
TEST_TMPDIR=""

setup() {
  TEST_TMPDIR="$(mktemp -d)"
  mkdir -p "$TEST_TMPDIR/specs/test-feature/tasks"
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

# === Test Cases ===

test_log_event_appends_valid_jsonl() {
  # Given a project with specs/test-feature/
  # When log_event is called with valid arguments
  source "$MONITOR_SCRIPT"
  log_event "test-feature" "tool_call" "001" '{"tool_name":"Edit"}'

  # Then a valid JSONL line is appended to .monitor.jsonl
  local file="$TEST_TMPDIR/specs/test-feature/.monitor.jsonl"
  [[ -f "$file" ]] || return 1
  local line_count
  line_count="$(wc -l < "$file" | tr -d ' ')"
  assert_eq "1" "$line_count" "expected exactly 1 line"
}

test_log_event_creates_monitor_file() {
  # Given .monitor.jsonl does not exist
  source "$MONITOR_SCRIPT"
  local file="$TEST_TMPDIR/specs/test-feature/.monitor.jsonl"
  [[ ! -f "$file" ]] || return 1

  # When log_event is called
  log_event "test-feature" "context_read" "001" '{"file":"src/main.rs"}'

  # Then .monitor.jsonl is created
  [[ -f "$file" ]]
}

test_start_phase_prints_correlation_id() {
  # Given a project with specs/test-feature/
  source "$MONITOR_SCRIPT"

  # When start_phase is called
  local cid
  cid="$(start_phase "test-feature" "003" "impl")"

  # Then it prints a correlation_id to stdout matching <phase>-<task>-<epoch>
  [[ "$cid" =~ ^impl-003-[0-9]+$ ]]
}

test_end_phase_logs_matching_correlation_id() {
  # Given a start_phase was called and returned a correlation_id
  source "$MONITOR_SCRIPT"
  local cid
  cid="$(start_phase "test-feature" "003" "impl")"

  # When end_phase is called with that correlation_id and phase name
  end_phase "test-feature" "$cid" "impl"

  # Then the end event has the matching correlation_id
  local file="$TEST_TMPDIR/specs/test-feature/.monitor.jsonl"
  local last_line
  last_line="$(tail -1 "$file")"
  [[ "$last_line" == *"\"correlation_id\":\"$cid\""* ]]
}

test_set_context_writes_file() {
  # Given a project root
  source "$MONITOR_SCRIPT"

  # When set_context is called
  set_context "my-feature" "002"

  # Then .monitor-context contains feature and task
  local ctx="$TEST_TMPDIR/.monitor-context"
  [[ -f "$ctx" ]] || return 1
  grep -q "^feature=my-feature$" "$ctx" || return 1
  grep -q "^task=002$" "$ctx"
}

test_clear_context_removes_file() {
  # Given .monitor-context exists
  source "$MONITOR_SCRIPT"
  set_context "my-feature" "002"
  [[ -f "$TEST_TMPDIR/.monitor-context" ]] || return 1

  # When clear_context is called
  clear_context

  # Then .monitor-context is removed
  [[ ! -f "$TEST_TMPDIR/.monitor-context" ]]
}

test_log_event_empty_task_omits_field() {
  # Given a project with specs/test-feature/
  source "$MONITOR_SCRIPT"

  # When log_event is called with empty task_id
  log_event "test-feature" "kb_rule" "" '{"rule_path":"security/general.md"}'

  # Then the JSON line does not contain a "task" field
  local file="$TEST_TMPDIR/specs/test-feature/.monitor.jsonl"
  local line
  line="$(cat "$file")"
  [[ "$line" != *'"task"'* ]]
}

test_json_output_valid_single_line() {
  command -v python3 >/dev/null 2>&1 || { echo "  SKIP: python3 not available"; return 0; }
  # Given a project with specs/test-feature/
  source "$MONITOR_SCRIPT"

  # When multiple events are logged
  log_event "test-feature" "tool_call" "001" '{"tool_name":"Bash"}'
  log_event "test-feature" "context_read" "001" '{"file":"src/lib.rs"}'
  log_event "test-feature" "task_transition" "001" '{"from_status":"todo","to_status":"in-progress"}'

  # Then each line is valid single-line JSON (no embedded newlines)
  local file="$TEST_TMPDIR/specs/test-feature/.monitor.jsonl"
  local line_count
  line_count="$(wc -l < "$file" | tr -d ' ')"
  assert_eq "3" "$line_count" "expected exactly 3 lines for 3 events"

  # Verify each line parses as JSON (using python as a portable validator)
  while IFS= read -r line; do
    printf '%s' "$line" | python3 -c "import sys,json; json.loads(sys.stdin.read())" 2>/dev/null || {
      echo "Invalid JSON: $line" >&2
      return 1
    }
  done < "$file"
}

test_timestamps_iso8601_utc() {
  # Given a project with specs/test-feature/
  source "$MONITOR_SCRIPT"

  # When an event is logged
  log_event "test-feature" "tool_call" "001" '{"tool_name":"Read"}'

  # Then the timestamp is ISO 8601 UTC format
  local file="$TEST_TMPDIR/specs/test-feature/.monitor.jsonl"
  local line
  line="$(cat "$file")"
  # Match pattern: YYYY-MM-DDTHH:MM:SS.000Z
  [[ "$line" =~ \"ts\":\"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.000Z\" ]]
}

# === Feature Validation Tests (Task 001) ===

test_set_context_valid_feature_succeeds() {
  # Given a valid feature name matching ^[a-zA-Z0-9_-]+$
  # When set_context is called via CLI mode
  "$MONITOR_SCRIPT" set_context "my-feature" "001"

  # Then the context file is created successfully
  [[ -f "$TEST_TMPDIR/.monitor-context" ]]
}

test_set_context_path_traversal_rejected() {
  # Given a feature name containing path traversal
  # When set_context is called via CLI
  local err
  err="$("$MONITOR_SCRIPT" set_context "../../etc" "001" 2>&1)" && return 1

  # Then exit code is non-zero and an error is printed to stderr
  [[ "$err" == *"Invalid feature"* ]] || return 1
  [[ ! -f "$TEST_TMPDIR/.monitor-context" ]] || return 1
}

test_set_context_spaces_rejected() {
  # Given a feature name with spaces
  # When set_context is called
  "$MONITOR_SCRIPT" set_context "my feature" "001" 2>/dev/null && return 1

  # Then context file is not created
  [[ ! -f "$TEST_TMPDIR/.monitor-context" ]]
}

test_set_context_empty_feature_fails() {
  # Given an empty feature name
  # When set_context is called with empty first arg
  # Then bash :? guard fires with non-zero exit
  "$MONITOR_SCRIPT" set_context "" "001" 2>/dev/null && return 1
  return 0
}

test_get_monitor_file_slashes_rejected() {
  # Given a feature name containing a slash
  # When get_monitor_file is called (via log_event which flows through it)
  source "$MONITOR_SCRIPT"
  get_monitor_file "my/feature" 2>/dev/null && return 1

  # Then it returns exit 1
  return 0
}

test_log_event_malicious_feature_blocked() {
  # Given a malicious feature value with path separators
  source "$MONITOR_SCRIPT"
  local before after
  before="$(find "$TEST_TMPDIR" -name '.monitor.jsonl' | wc -l | tr -d ' ')"

  # When log_event is called with a malicious feature value
  log_event "../../etc" "tool_call" "001" '{"tool_name":"Bash"}' 2>/dev/null && return 1

  # Then get_monitor_file rejects it and no new monitor file is written
  after="$(find "$TEST_TMPDIR" -name '.monitor.jsonl' | wc -l | tr -d ' ')"
  [[ "$before" -eq "$after" ]] || return 1
}

test_poisoned_context_rejected() {
  # Given .monitor-context was somehow written with a poisoned feature value
  source "$MONITOR_SCRIPT"
  printf 'feature=../../etc\ntask=001\n' > "$TEST_TMPDIR/.monitor-context"

  # When read_context is called it should reject the poisoned value at the read boundary
  read_context 2>/dev/null && return 1

  # Then read_context returns non-zero — poisoned value never leaves the function
  return 0
}

test_set_context_overwrites_previous() {
  # Given .monitor-context exists with one task
  "$MONITOR_SCRIPT" set_context "feature-a" "001"
  [[ -f "$TEST_TMPDIR/.monitor-context" ]] || return 1

  # When set_context is called with different values
  "$MONITOR_SCRIPT" set_context "feature-b" "002"

  # Then the file contains the new values
  grep -q "^feature=feature-b$" "$TEST_TMPDIR/.monitor-context" || return 1
  grep -q "^task=002$" "$TEST_TMPDIR/.monitor-context" || return 1
}

test_set_context_writes_only_feature_and_task() {
  # Given no prior context file
  # When set_context is called
  "$MONITOR_SCRIPT" set_context "my-feature" "003"

  # Then the file contains exactly 2 lines: feature and task
  local line_count
  line_count="$(wc -l < "$TEST_TMPDIR/.monitor-context" | tr -d ' ')"
  assert_eq "2" "$line_count" "expected exactly 2 lines"
  grep -q "^feature=my-feature$" "$TEST_TMPDIR/.monitor-context" || return 1
  grep -q "^task=003$" "$TEST_TMPDIR/.monitor-context" || return 1
}

test_set_context_read_context_roundtrip() {
  # Given set_context is called with known values
  source "$MONITOR_SCRIPT"
  set_context "round-trip" "042"

  # When read_context is called
  local output
  output="$(read_context)"
  local feature task
  feature="$(printf '%s' "$output" | head -1)"
  task="$(printf '%s' "$output" | tail -1)"

  # Then the values match what was written
  assert_eq "round-trip" "$feature" "feature mismatch" || return 1
  assert_eq "042" "$task" "task mismatch"
}

test_task_id_path_chars_rejected() {
  # Given a task ID containing path characters
  # When set_context is called via CLI
  "$MONITOR_SCRIPT" set_context "valid-feature" "../task" 2>/dev/null && return 1

  # Then context file is not created
  [[ ! -f "$TEST_TMPDIR/.monitor-context" ]] || return 1
}

test_gitignore_matches_monitor_context() {
  # Given the repo root .gitignore
  local gitignore="$REPO_ROOT/.gitignore"
  [[ -f "$gitignore" ]] || return 1

  # When we check for .monitor-context pattern
  grep -q "\.monitor-context" "$gitignore"
}

# === Runner ===

echo "Running monitor.sh tests..."
echo ""

run_test "log_event appends valid JSONL line to .monitor.jsonl" test_log_event_appends_valid_jsonl
run_test "log_event creates .monitor.jsonl if it does not exist" test_log_event_creates_monitor_file
run_test "start_phase prints correlation_id to stdout" test_start_phase_prints_correlation_id
run_test "end_phase logs event with matching correlation_id" test_end_phase_logs_matching_correlation_id
run_test "set_context writes feature and task to .monitor-context" test_set_context_writes_file
run_test "clear_context removes .monitor-context file" test_clear_context_removes_file
run_test "log_event with empty task_id omits task field" test_log_event_empty_task_omits_field
run_test "JSON output is valid single-line JSON per event" test_json_output_valid_single_line
run_test "timestamps are ISO 8601 UTC format" test_timestamps_iso8601_utc
run_test "set_context with valid feature name succeeds" test_set_context_valid_feature_succeeds
run_test "set_context with path traversal feature rejects with exit 1" test_set_context_path_traversal_rejected
run_test "set_context with spaces in feature rejects with exit 1" test_set_context_spaces_rejected
run_test "set_context with empty feature fails via bash guard" test_set_context_empty_feature_fails
run_test "get_monitor_file with slashes in feature rejects with exit 1" test_get_monitor_file_slashes_rejected
run_test "log_event with malicious feature is blocked by get_monitor_file" test_log_event_malicious_feature_blocked
run_test "poisoned context file values are rejected by read_context" test_poisoned_context_rejected
run_test "set_context with different values overwrites previous context" test_set_context_overwrites_previous
run_test "set_context writes exactly feature and task lines, nothing else" test_set_context_writes_only_feature_and_task
run_test "set_context + read_context round-trip returns correct values" test_set_context_read_context_roundtrip
run_test "task ID with path characters is rejected by existing validate_id" test_task_id_path_chars_rejected
run_test ".gitignore matches .monitor-context pattern" test_gitignore_matches_monitor_context

echo ""
echo "Results: $PASS passed, $FAIL failed out of $((PASS + FAIL)) tests"

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
