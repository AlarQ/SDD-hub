#!/usr/bin/env bash
# test-pre-commit-hook.sh — Tests for the config-load block in scripts/pre-commit-hook.sh.
# Security focus: the loader output must NOT be eval'd as arbitrary code (RCE at
# commit time). Only allowlisted `WF_<NAME>=` lines may be applied.
# No external framework. Given/When/Then per testing/principles.md.
#
# SC2016: probe expressions are intentionally single-quoted — they are deferred
# and `eval`'d by run_load_block AFTER the load block is sourced, so they must
# observe the post-source shell, not expand at the call site.
# shellcheck disable=SC1090,SC1091,SC2016

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/scripts/pre-commit-hook.sh"

PASS=0; FAIL=0; TEST_TMPDIR=""

setup() {
  TEST_TMPDIR="$(mktemp -d)"
  # Unset WF_* so each test starts clean.
  while IFS= read -r v; do unset "$v"; done < <(compgen -v | grep '^WF_' || true)
}
teardown() {
  [[ -n "$TEST_TMPDIR" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
  TEST_TMPDIR=""
}
run_test() {
  local name="$1"; shift
  setup
  if ( set +e; "$@" ); then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name (rc=$?)"; FAIL=$((FAIL + 1))
  fi
  teardown
}

# Extract the loader-load block (the lines between `for _loader in ...` and
# `unset _loader _loader_out`, inclusive) into a sourceable snippet. This drives
# the EXACT code under test while letting the test shell observe the resulting
# environment (vars applied, sentinel side effects).
extract_load_block() {
  local out="$1"
  sed -n '/^for _loader in /,/^unset _loader _loader_out/p' "$HOOK" > "$out"
}

# Build a fixture repo whose repo-local scripts/config-loader.sh is a stub
# emitting $1 on `export`. Echoes the fixture repo path. The repo-local loader
# is tried FIRST by the hook, which is exactly the poisoning vector.
mk_fixture() {
  local export_stdout="$1"
  local repo="$TEST_TMPDIR/repo"
  mkdir -p "$repo/scripts"
  : > "$repo/.workflow.yml"   # presence gates the load block
  cat > "$repo/scripts/config-loader.sh" <<STUB
#!/usr/bin/env bash
if [[ "\${1:-}" == "export" ]]; then
$export_stdout
fi
STUB
  chmod +x "$repo/scripts/config-loader.sh"
  printf '%s' "$repo"
}

# Run the extracted load block against a fixture repo, then evaluate a probe
# expression IN THE SAME SHELL so it observes vars the block applied (eval'd
# vars are not exported, so a child process would not see them). REPO_ROOT is
# pointed at the fixture; HOME is forced to a non-existent dir so only the
# repo-local stub loader is exercised (the poisoning vector tried FIRST).
# $1 = repo, $2 = probe expression (bash test/command run via `eval`).
run_load_block() {
  local repo="$1" probe="$2"
  local snippet="$TEST_TMPDIR/block.sh"
  extract_load_block "$snippet"
  (
    set -uo pipefail
    REPO_ROOT="$repo"
    HOME="$TEST_TMPDIR/nohome"
    # shellcheck source=/dev/null
    source "$snippet"
    eval "$probe"
  )
}

# --- RED: RCE / injection guard ---

# A poisoned repo-local loader emits a shell command plus a non-WF assignment.
# The hook MUST NOT execute the command (no sentinel) and MUST NOT apply the
# non-WF var.
test_poisoned_loader_does_not_execute_injected_command() {
  local sentinel="$TEST_TMPDIR/pwned"
  local repo
  # Stub PRINTS the poison to stdout (the loader-output vector). Only the hook's
  # eval could turn it into the touch — if the sentinel appears, that is RCE.
  repo="$(mk_fixture "  printf '%s\n' \"touch '$sentinel'; echo INJECTED=1\"")"
  run_load_block "$repo" '[[ ! -e "'"$sentinel"'" ]]'
  local rc=$?
  [[ "$rc" == "0" ]] || { echo "    sentinel was created — RCE!" >&2; return 1; }
}

test_poisoned_loader_does_not_set_non_wf_var() {
  local repo
  repo="$(mk_fixture "  echo INJECTED=1")"
  # Probe: INJECTED must be unset after the block runs.
  run_load_block "$repo" '[[ -z "${INJECTED:-}" ]]'
}

test_poisoned_non_wf_export_line_skipped() {
  # A line that looks like an env assignment but is not WF_-prefixed must be
  # skipped (not eval'd), even without an explicit command.
  local repo
  repo="$(mk_fixture "  printf '%s\n' \"PATH=/evil\" \"WF_SPEC_STORAGE='specs'\"")"
  # WF_SPEC_STORAGE still applied; PATH not clobbered to /evil.
  run_load_block "$repo" '[[ "${WF_SPEC_STORAGE:-}" == "specs" && "$PATH" != "/evil" ]]'
}

# --- GREEN: valid contract still works ---

test_valid_export_applies_wf_var() {
  local repo
  repo="$(mk_fixture "  printf '%s\n' \"WF_SPEC_STORAGE='specs'\"")"
  run_load_block "$repo" '[[ "${WF_SPEC_STORAGE:-}" == "specs" ]]'
}

test_valid_dynamic_wf_agents_line_accepted() {
  local repo
  repo="$(mk_fixture "  printf '%s\n' \"WF_SPEC_AGENTS_FOO='bar'\"")"
  run_load_block "$repo" '[[ "${WF_SPEC_AGENTS_FOO:-}" == "bar" ]]'
}

test_loader_failure_does_not_set_vars() {
  # Loader exits non-zero (with a diagnostic on stderr); block must break and
  # apply nothing — no WF_ var leaks into the env.
  local repo
  repo="$(mk_fixture "  echo 'boom' >&2; exit 1")"
  run_load_block "$repo" '[[ -z "${WF_SPEC_STORAGE:-}" ]]'
}

test_stderr_warning_not_eval_d() {
  # Drop-2>&1 guarantee: a stderr diagnostic from a SUCCEEDING loader must never
  # reach eval. Stub writes a poison command to stderr, a valid WF line to stdout.
  local sentinel="$TEST_TMPDIR/stderr_pwned"
  local repo
  repo="$(mk_fixture "  echo \"touch '$sentinel'\" >&2; printf '%s\n' \"WF_SPEC_STORAGE='specs'\"")"
  run_load_block "$repo" '[[ ! -e "'"$sentinel"'" && "${WF_SPEC_STORAGE:-}" == "specs" ]]'
}

echo "=== test-pre-commit-hook.sh ==="
run_test "poisoned loader command is NOT executed (no RCE sentinel)" test_poisoned_loader_does_not_execute_injected_command
run_test "poisoned non-WF var is NOT applied"                        test_poisoned_loader_does_not_set_non_wf_var
run_test "non-WF assignment line skipped, valid WF line still applied" test_poisoned_non_wf_export_line_skipped
run_test "valid WF_SPEC_STORAGE export is applied"                   test_valid_export_applies_wf_var
run_test "dynamic WF_SPEC_AGENTS_* line accepted"                    test_valid_dynamic_wf_agents_line_accepted
run_test "loader failure applies no WF_ vars"                        test_loader_failure_does_not_set_vars
run_test "stderr diagnostic from succeeding loader never eval'd"     test_stderr_warning_not_eval_d

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
