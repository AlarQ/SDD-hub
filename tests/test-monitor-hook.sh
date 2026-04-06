#!/usr/bin/env bash
set -euo pipefail

# test-monitor-hook.sh — Tests for hooks/monitor-tool-calls.sh
# Uses Given/When/Then structure. No external test framework.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK_SCRIPT="$REPO_ROOT/hooks/monitor-tool-calls.sh"
MONITOR_SCRIPT="$REPO_ROOT/scripts/monitor.sh"

PASS=0
FAIL=0
TEST_TMPDIR=""

setup() {
  TEST_TMPDIR="$(mktemp -d)"
  mkdir -p "$TEST_TMPDIR/specs/test-feature/tasks"
  # Create a fake ~/.claude/scripts/monitor.sh for the hook to source.
  mkdir -p "$TEST_TMPDIR/fake-home/.claude/scripts"
  cp "$MONITOR_SCRIPT" "$TEST_TMPDIR/fake-home/.claude/scripts/monitor.sh"
  chmod +x "$TEST_TMPDIR/fake-home/.claude/scripts/monitor.sh"
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

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  if [[ "$haystack" == *"$needle"* ]]; then
    return 0
  fi
  echo "  ASSERT FAILED${msg:+: $msg}" >&2
  echo "    expected to contain: $needle" >&2
  echo "    actual: $haystack" >&2
  return 1
}

run_hook() {
  # Run the hook in the test project dir with HOME overridden.
  local input="$1"
  cd "$TEST_TMPDIR"
  printf '%s' "$input" | HOME="$TEST_TMPDIR/fake-home" bash "$HOOK_SCRIPT"
}

write_context() {
  local feature="${1:-test-feature}" task="${2:-001}"
  printf 'feature=%s\ntask=%s\n' "$feature" "$task" > "$TEST_TMPDIR/.monitor-context"
}

read_monitor_event() {
  local feature="${1:-test-feature}"
  local monitor_file="$TEST_TMPDIR/specs/$feature/.monitor.jsonl"
  [[ -f "$monitor_file" ]] || return 1
  head -1 "$monitor_file"
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

test_hook_exits_silently_without_context() {
  # Given .monitor-context does not exist
  # (setup creates project dir but no context file)

  # When the hook fires with a Read tool call
  local input='{"tool_name":"Read","tool_input":{"file_path":"src/main.rs"}}'
  run_hook "$input"

  # Then no events are logged (no .monitor.jsonl created)
  ! read_monitor_event &>/dev/null
}

test_hook_logs_context_read_for_read_tool() {
  # Given .monitor-context exists with feature=test-feature, task=001
  write_context

  # When the hook fires for a Read tool call
  local input='{"tool_name":"Read","tool_input":{"file_path":"src/app.rs"}}'
  run_hook "$input"

  # Then a context_read event is logged
  local line
  line="$(read_monitor_event)" || return 1
  assert_contains "$line" '"category":"context_read"' "category should be context_read"
}

test_hook_logs_agent_invocation_for_agent_tool() {
  # Given .monitor-context exists
  write_context

  # When the hook fires for an Agent tool call
  local input='{"tool_name":"Agent","tool_input":{"description":"Review code quality","subagent_type":"code-quality-pragmatist"}}'
  run_hook "$input"

  # Then an agent_invocation event is logged
  local line
  line="$(read_monitor_event)" || return 1
  assert_contains "$line" '"category":"agent_invocation"' "category should be agent_invocation"
}

test_hook_logs_tool_call_for_bash() {
  # Given .monitor-context exists
  write_context

  # When the hook fires for a Bash tool call
  local input='{"tool_name":"Bash","tool_input":{"command":"cargo test"}}'
  run_hook "$input"

  # Then a tool_call event is logged
  local line
  line="$(read_monitor_event)" || return 1
  assert_contains "$line" '"category":"tool_call"' "category should be tool_call"
  assert_contains "$line" '"tool_name":"Bash"' "tool_name should be Bash"
}

test_hook_logs_tool_call_for_edit() {
  # Given .monitor-context exists
  write_context

  # When the hook fires for an Edit tool call
  local input='{"tool_name":"Edit","tool_input":{"file_path":"src/lib.rs","old_string":"foo","new_string":"bar"}}'
  run_hook "$input"

  # Then a tool_call event is logged with tool_name Edit
  local line
  line="$(read_monitor_event)" || return 1
  assert_contains "$line" '"category":"tool_call"' "category should be tool_call"
  assert_contains "$line" '"tool_name":"Edit"' "tool_name should be Edit"
}

test_hook_logs_tool_call_for_write() {
  # Given .monitor-context exists
  write_context

  # When the hook fires for a Write tool call
  local input='{"tool_name":"Write","tool_input":{"file_path":"src/new.rs","content":"fn main() {}"}}'
  run_hook "$input"

  # Then a tool_call event is logged with tool_name Write
  local line
  line="$(read_monitor_event)" || return 1
  assert_contains "$line" '"category":"tool_call"' "category should be tool_call"
  assert_contains "$line" '"tool_name":"Write"' "tool_name should be Write"
}

test_hook_extracts_file_path_from_read() {
  # Given .monitor-context exists
  write_context

  # When the hook fires for a Read tool call with a file path
  local input='{"tool_name":"Read","tool_input":{"file_path":"src/model/event.rs"}}'
  run_hook "$input"

  # Then the event data contains the file path
  local line
  line="$(read_monitor_event)" || return 1
  assert_contains "$line" '"file":"src/model/event.rs"' "data should contain file path"
}

test_hook_extracts_agent_name() {
  # Given .monitor-context exists
  write_context

  # When the hook fires for an Agent tool with description
  local input='{"tool_name":"Agent","tool_input":{"description":"Analyze security","subagent_type":"security-auditor"}}'
  run_hook "$input"

  # Then the event data contains the agent description
  local line
  line="$(read_monitor_event)" || return 1
  assert_contains "$line" '"agent_name":"Analyze security"' "data should contain agent description"
}

test_hook_reads_feature_and_task_from_context() {
  # Given .monitor-context with specific feature and task
  write_context "my-feature" "003"
  mkdir -p "$TEST_TMPDIR/specs/my-feature/tasks"

  # When the hook fires
  local input='{"tool_name":"Bash","tool_input":{"command":"ls"}}'
  run_hook "$input"

  # Then the event uses feature and task from .monitor-context
  local line
  line="$(read_monitor_event "my-feature")" || return 1
  assert_contains "$line" '"feature":"my-feature"' "feature should be from context"
  assert_contains "$line" '"task":"003"' "task should be from context"
}

test_hook_exits_silently_on_empty_stdin() {
  # Given .monitor-context exists
  write_context

  # When the hook fires with empty stdin
  run_hook ""

  # Then no events are logged and hook exits 0
  ! read_monitor_event &>/dev/null
}

test_hook_exits_silently_on_invalid_json() {
  # Given .monitor-context exists
  write_context

  # When the hook fires with completely invalid input
  run_hook "this is not json at all"

  # Then no events are logged and hook exits 0
  ! read_monitor_event &>/dev/null
}

test_hook_exits_silently_on_json_without_tool_name() {
  # Given .monitor-context exists
  write_context

  # When the hook fires with JSON missing tool_name
  run_hook '{"some_key":"some_value"}'

  # Then no events are logged and hook exits 0
  ! read_monitor_event &>/dev/null
}

test_hook_ignores_unrecognized_tool_names() {
  # Given .monitor-context exists
  write_context

  # When the hook fires for an unrecognized tool
  run_hook '{"tool_name":"WebFetch","tool_input":{"url":"https://example.com"}}'

  # Then no events are logged and hook exits 0
  ! read_monitor_event &>/dev/null
}

# === Runner ===

echo "Running monitor-tool-calls.sh hook tests..."
echo ""

run_test "hook exits silently when .monitor-context does not exist" test_hook_exits_silently_without_context
run_test "hook logs context_read event for Read tool calls" test_hook_logs_context_read_for_read_tool
run_test "hook logs agent_invocation event for Agent tool calls" test_hook_logs_agent_invocation_for_agent_tool
run_test "hook logs tool_call event for Bash tool calls" test_hook_logs_tool_call_for_bash
run_test "hook logs tool_call event for Edit tool calls" test_hook_logs_tool_call_for_edit
run_test "hook logs tool_call event for Write tool calls" test_hook_logs_tool_call_for_write
run_test "hook extracts file path from Read tool input" test_hook_extracts_file_path_from_read
run_test "hook extracts agent name from Agent tool input" test_hook_extracts_agent_name
run_test "hook reads feature and task from .monitor-context" test_hook_reads_feature_and_task_from_context
run_test "hook exits silently on empty stdin" test_hook_exits_silently_on_empty_stdin
run_test "hook exits silently on invalid JSON" test_hook_exits_silently_on_invalid_json
run_test "hook exits silently on JSON without tool_name" test_hook_exits_silently_on_json_without_tool_name
run_test "hook ignores unrecognized tool names" test_hook_ignores_unrecognized_tool_names

echo ""
echo "Results: $PASS passed, $FAIL failed out of $((PASS + FAIL)) tests"

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
