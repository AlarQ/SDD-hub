#!/usr/bin/env bash
# test-block-git-hook-bypass.sh — Tests for hooks/block-git-hook-bypass.sh
#
# The hook is a Claude Code PreToolUse hook. It reads a JSON event on stdin,
# extracts .tool_input.command, and emits a deny-decision JSON when the command
# tries to bypass git hooks. We drive it by piping {"tool_input":{"command":...}}
# and assert on whether the output contains a deny decision.
#
# Given/When/Then per testing/principles.md. No external test framework.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/hooks/block-git-hook-bypass.sh"

PASS=0
FAIL=0

# Feed a command string to the hook as a PreToolUse JSON event; echo the hook's
# stdout. Uses jq to build the JSON so arbitrary quoting in the command is safe.
run_hook() {
  local cmd="$1"
  jq -n --arg c "$cmd" '{tool_input:{command:$c}}' | bash "$HOOK"
}

# Like run_hook but for a raw JSON event (used for the empty/missing-command case).
run_hook_raw() {
  local json="$1"
  printf '%s' "$json" | bash "$HOOK"
}

deny_present() {
  [[ "$1" == *'"permissionDecision":"deny"'* ]]
}

# Assert the hook DENIES the given command.
assert_deny() {
  local cmd="$1"
  local out
  out="$(run_hook "$cmd")"
  if deny_present "$out"; then
    return 0
  fi
  echo "    expected DENY for command: $cmd" >&2
  echo "    actual output: ${out:-<empty>}" >&2
  return 1
}

# Assert the hook ALLOWS the given command (no deny decision emitted).
assert_allow() {
  local cmd="$1"
  local out
  out="$(run_hook "$cmd")"
  if deny_present "$out"; then
    echo "    expected ALLOW for command: $cmd" >&2
    echo "    actual output: $out" >&2
    return 1
  fi
  return 0
}

run_test() {
  local name="$1"
  shift
  if ( set +e; "$@" ); then
    echo "  PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name (rc=$?)"
    FAIL=$((FAIL + 1))
  fi
}

# --- DENY: bypass-detection cases ---

test_deny_short_no_verify() {
  # Given a commit using the short -n form of --no-verify
  # When/Then the hook denies it
  assert_deny 'git commit -n'
}

test_deny_bundled_nm_cluster() {
  # Given a bundled short-flag cluster -nm on commit
  assert_deny 'git commit -nm "x"'
}

test_deny_bundled_vn_cluster() {
  # Given a bundled short-flag cluster -vn on commit
  assert_deny 'git commit -vn'
}

test_deny_hookspath_dev_null() {
  # Given an explicit -c core.hooksPath override to /dev/null
  assert_deny 'git -c core.hooksPath=/dev/null commit -m x'
}

test_deny_hookspath_empty() {
  # Given an explicit -c core.hooksPath override to an empty value
  assert_deny "git -c core.hooksPath='' commit"
}

test_deny_short_no_verify_on_merge() {
  # Given -n on a merge (which honors --no-verify)
  assert_deny 'git merge --no-ff -n topic'
}

test_deny_short_no_verify_on_rebase() {
  # Given -n on a rebase (which honors --no-verify)
  assert_deny 'git rebase -n main'
}

# --- GREEN / regression: long-form must still deny ---

test_deny_long_no_verify() {
  assert_deny 'git commit --no-verify'
}

test_deny_long_no_gpg_sign() {
  assert_deny 'git commit --no-gpg-sign'
}

# --- ALLOW: false-positive safety ---

test_allow_plain_commit_message() {
  # -m with a message, no -n anywhere
  assert_allow 'git commit -m "msg"'
}

test_allow_git_log_n_count() {
  # -n here means "number of commits", NOT no-verify; must be allowed
  assert_allow 'git log -n 5'
}

test_allow_grep_n() {
  assert_allow 'grep -n foo file'
}

test_allow_echo_n() {
  assert_allow 'echo -n hi'
}

test_allow_git_show() {
  assert_allow 'git show'
}

test_allow_empty_command() {
  # Empty command — jq yields "" ; must not crash and must allow.
  local out
  out="$(run_hook '')"
  ! deny_present "$out"
}

test_allow_missing_command_field() {
  # No .tool_input.command at all — jq yields null; must not crash, must allow.
  local out
  out="$(run_hook_raw '{"tool_input":{}}')"
  ! deny_present "$out"
}

# === Runner ===

echo "=== test-block-git-hook-bypass.sh ==="
run_test "deny: git commit -n (short no-verify)"              test_deny_short_no_verify
run_test "deny: git commit -nm (bundled cluster)"             test_deny_bundled_nm_cluster
run_test "deny: git commit -vn (bundled cluster)"             test_deny_bundled_vn_cluster
run_test "deny: -c core.hooksPath=/dev/null"                  test_deny_hookspath_dev_null
run_test "deny: -c core.hooksPath='' (empty value)"           test_deny_hookspath_empty
run_test "deny: git merge ... -n (short no-verify)"           test_deny_short_no_verify_on_merge
run_test "deny: git rebase -n (short no-verify)"              test_deny_short_no_verify_on_rebase
run_test "deny: git commit --no-verify (long form)"           test_deny_long_no_verify
run_test "deny: git commit --no-gpg-sign (long form)"         test_deny_long_no_gpg_sign
run_test "allow: git commit -m \"msg\" (no -n)"               test_allow_plain_commit_message
run_test "allow: git log -n 5 (count, not no-verify)"         test_allow_git_log_n_count
run_test "allow: grep -n foo file"                            test_allow_grep_n
run_test "allow: echo -n hi"                                  test_allow_echo_n
run_test "allow: git show"                                    test_allow_git_show
run_test "allow: empty command (no crash)"                    test_allow_empty_command
run_test "allow: missing command field (no crash)"            test_allow_missing_command_field

echo ""
echo "Results: $PASS passed, $FAIL failed out of $((PASS + FAIL)) tests"
[[ "$FAIL" -eq 0 ]]
