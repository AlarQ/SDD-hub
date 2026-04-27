#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091
set -euo pipefail

# test-validate-impl.sh — T014 tests for scripts/validate-impl.sh helpers
# and the spec_audit_* monitor categories. No real Karen spawn — Karen is
# invoked by the slash command via the Agent tool, not by these helpers.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURE="$REPO_ROOT/tests/fixtures/spec-audit/sample-spec"

PASS=0; FAIL=0
TMPDIR_T=""

setup() {
  TMPDIR_T="$(mktemp -d)"
  mkdir -p "$TMPDIR_T/specs"
  cp -R "$FIXTURE" "$TMPDIR_T/specs/sample-spec"
  printf 'spec_storage: specs/\ngate_pool: knowledge-base/gates.yml\nagent_pool: agents/\nvalidate_scope: per-task\n' > "$TMPDIR_T/.workflow.yml"
  cd "$TMPDIR_T"
  # source helpers fresh
  unset WF_VALIDATE_IMPL_LOADED
  # shellcheck disable=SC1091
  source "$REPO_ROOT/scripts/validate-impl.sh"
}
teardown() { cd "$REPO_ROOT"; rm -rf "$TMPDIR_T"; }

run_test() {
  local name="$1"; shift
  setup
  if ( "$@" ); then echo "  PASS: $name"; PASS=$((PASS+1));
  else echo "  FAIL: $name"; FAIL=$((FAIL+1)); fi
  teardown
}

assert_eq()       { [[ "$1" == "$2" ]] || { echo "  exp:$1 got:$2"; return 1; }; }
assert_contains() { [[ "$1" == *"$2"* ]] || { echo "  missing:$2 in:$1"; return 1; }; }

# === Given: fixture spec.md with FR-1..FR-3 ===
test_parse_frs_extracts_three_ids() {
  # When/Then
  local out; out="$(wf_vi_parse_frs "$TMPDIR_T/specs/sample-spec/spec.md")"
  assert_eq "FR-1
FR-2
FR-3" "$out"
}

test_build_prompt_contains_all_inputs() {
  local out; out="$(wf_vi_build_prompt sample-spec "$TMPDIR_T/specs/sample-spec")"
  assert_contains "$out" "FR-1" || return 1
  assert_contains "$out" "FR-3" || return 1
  assert_contains "$out" "IN Scope" || return 1
  assert_contains "$out" "001-alpha.md" || return 1
  assert_contains "$out" "Git Diff Range" || return 1
  assert_contains "$out" "FR × Status Matrix" || return 1
  assert_contains "$out" "implemented, partial, missing" || return 1
}

test_build_prompt_includes_extra_evidence() {
  local extra; extra="$(mktemp)"
  printf 'GATE FAIL: shellcheck barfed line 42\n' > "$extra"
  local out; out="$(wf_vi_build_prompt sample-spec "$TMPDIR_T/specs/sample-spec" "$extra")"
  assert_contains "$out" "Failing Gate Output" || return 1
  assert_contains "$out" "shellcheck barfed line 42" || return 1
  rm -f "$extra"
}

test_write_report_writes_iso8601_with_frontmatter() {
  local body; body="$(mktemp)"
  printf '## FR × Status Matrix\n\n| FR | status |\n|----|--------|\n| FR-1 | implemented |\n' > "$body"
  local path; path="$(wf_vi_write_report sample-spec "$TMPDIR_T/specs/sample-spec" complete "$body")"
  [[ -f "$path" ]] || return 1
  assert_contains "$path" "spec-audit-" || return 1
  local content; content="$(cat "$path")"
  assert_contains "$content" "feature: sample-spec" || return 1
  assert_contains "$content" "verdict: complete" || return 1
  assert_contains "$content" "FR × Status Matrix" || return 1
}

test_write_report_rejects_invalid_verdict() {
  local body; body="$(mktemp)"
  if wf_vi_write_report sample-spec "$TMPDIR_T/specs/sample-spec" bogus "$body" 2>/dev/null; then
    return 1
  fi
}

test_emit_start_and_done_in_order() {
  wf_vi_emit_start sample-spec
  wf_vi_emit_done sample-spec complete "/tmp/x.md"
  local jsonl="$TMPDIR_T/specs/sample-spec/.monitor.jsonl"
  [[ -f "$jsonl" ]] || return 1
  local cats; cats="$(awk -F'"category":"' 'NF>1{split($2,a,"\""); print a[1]}' "$jsonl" | tr '\n' ' ')"
  assert_eq "spec_audit_start spec_audit_done " "$cats"
}

test_set_spec_shipped_flips_status() {
  wf_vi_set_spec_shipped "$TMPDIR_T/specs/sample-spec"
  local s; s="$(yq --front-matter=extract e '.status' "$TMPDIR_T/specs/sample-spec/spec.md")"
  assert_eq "shipped" "$s"
}

test_emit_complete_and_reopen_in_allowlist() {
  wf_vi_emit_complete sample-spec
  wf_vi_emit_reopen   sample-spec
  local jsonl="$TMPDIR_T/specs/sample-spec/.monitor.jsonl"
  grep -q '"category":"spec_complete"'  "$jsonl" || return 1
  grep -q '"category":"spec_reopened"' "$jsonl" || return 1
}

echo "=== test-validate-impl.sh ==="
run_test "parse_frs extracts FR-1..FR-3"                  test_parse_frs_extracts_three_ids
run_test "build_prompt contains FRs / scope / tasks / FR matrix instructions" test_build_prompt_contains_all_inputs
run_test "build_prompt embeds failing-gate output"        test_build_prompt_includes_extra_evidence
run_test "write_report writes frontmatter + body"         test_write_report_writes_iso8601_with_frontmatter
run_test "write_report rejects invalid verdict"           test_write_report_rejects_invalid_verdict
run_test "emit_start then emit_done appended in order"    test_emit_start_and_done_in_order
run_test "set_spec_shipped flips frontmatter status"      test_set_spec_shipped_flips_status
run_test "emit_complete + emit_reopen pass allowlist"     test_emit_complete_and_reopen_in_allowlist

echo "=== $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
