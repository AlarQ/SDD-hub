#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091
set -euo pipefail

# test-validate-impl.sh — T014 tests for scripts/validate-impl.sh helpers
# and the spec_audit_* monitor categories. No real Odium spawn — Odium is
# invoked by the slash command via the Agent tool, not by these helpers.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURE="$REPO_ROOT/tests/fixtures/spec-audit/sample-spec"
COV_FEAT="$REPO_ROOT/tests/fixtures/coverage/feature-task.md"
COV_TECH="$REPO_ROOT/tests/fixtures/coverage/technical-task.md"

PASS=0; FAIL=0
TMPDIR_T=""

setup() {
  TMPDIR_T="$(mktemp -d)"
  mkdir -p "$TMPDIR_T/specs"
  cp -R "$FIXTURE" "$TMPDIR_T/specs/sample-spec"
  printf 'spec_storage: specs/\nagent_pool: agents/\nvalidate_scope: per-task\ngate_pool:\n  - id: rust-clippy\n    command: "cargo clippy -- -D warnings"\n    applies_to: [rust]\n    category: lint\n    blocking: true\n' > "$TMPDIR_T/.workflow.yml"
  cd "$TMPDIR_T"
  # Init a minimal git repo with main + feat/sample-spec so wf_vi_diff_range
  # can resolve a real merge-base (T6 — no silent HEAD~1 fallback).
  git init -q -b main . 2>/dev/null || git init -q .
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  git checkout -q -b feat/sample-spec 2>/dev/null || true
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m work
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

test_diff_range_fails_loud_when_no_branch() {
  # When neither `merge-base main feat/<feature>` nor feat/<feature>^ resolves,
  # wf_vi_diff_range must return rc 5 instead of silently using HEAD~1.
  local outside; outside="$(mktemp -d)"
  ( cd "$outside" \
    && git init -q -b main . 2>/dev/null \
    && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m base ) || { rm -rf "$outside"; return 1; }
  local rc=0
  ( cd "$outside" && wf_vi_diff_range nonexistent-feature ) >/dev/null 2>&1 || rc=$?
  rm -rf "$outside"
  [[ "$rc" == "5" ]]
}

# ===========================================================================
# Per-task coverage audit (Phase 3 of /validate) — task-scoped helpers.
# ===========================================================================

# === Given: feature-track task fixture with `## Acceptance` GWT table ===
test_task_acceptance_rows_skips_header_and_separator() {
  local out; out="$(wf_vi__task_acceptance_rows "$COV_FEAT")"
  assert_contains "$out" "a logged-out user" || return 1
  assert_contains "$out" "an expired token" || return 1
  [[ "$out" != *"Given"* ]] || { echo "  header row leaked"; return 1; }
  [[ "$out" != *"---"* ]]   || { echo "  separator row leaked"; return 1; }
  local n; n="$(printf '%s\n' "$out" | grep -c .)"
  assert_eq "2" "$n"
}

test_task_fr_refs_extracts_unique_sorted() {
  local out; out="$(wf_vi__task_fr_refs "$COV_FEAT")"
  assert_eq "FR-2
FR-5" "$out"
}

test_build_task_prompt_feature_track() {
  local out
  out="$(WF_SPEC_TRACK=feature wf_vi_build_task_prompt sample-spec "$COV_FEAT" "$TMPDIR_T/specs/sample-spec" "abc..HEAD")"
  assert_contains "$out" "Feature-track task" || return 1
  assert_contains "$out" "a logged-out user" || return 1
  assert_contains "$out" "FR Reference Allowlist" || return 1
  assert_contains "$out" "FR-2" || return 1
  assert_contains "$out" "Acceptance × Coverage Matrix" || return 1
  assert_contains "$out" "abc..HEAD" || return 1
}

test_build_task_prompt_technical_track() {
  local out
  out="$(WF_SPEC_TRACK=technical wf_vi_build_task_prompt sample-spec "$COV_TECH" "$TMPDIR_T/specs/sample-spec" "abc..HEAD")"
  assert_contains "$out" "Technical-track task" || return 1
  assert_contains "$out" "Extract auth middleware" || return 1
  [[ "$out" != *"FR Reference Allowlist"* ]] || { echo "  technical track must not emit FR allowlist"; return 1; }
}

test_task_diff_range_per_task_merge_base() {
  # per-task (no WF_BRANCH_STRATEGY), fixture has no task_base_sha → merge-base feat/<f> HEAD
  local out; out="$(wf_vi_task_diff_range sample-spec "$COV_FEAT")"
  [[ "$out" == *..HEAD ]] || { echo "  exp *..HEAD got:$out"; return 1; }
}

test_task_diff_range_single_branch_uses_base_sha() {
  local base; base="$(git rev-parse HEAD~1)"   # the 'base' commit on feat/sample-spec
  local tf="$TMPDIR_T/sb-task.md"
  printf -- '---\nid: "030"\ntask_base_sha: "%s"\n---\nbody\n' "$base" > "$tf"
  local out; out="$(WF_BRANCH_STRATEGY=single-branch wf_vi_task_diff_range sample-spec "$tf")"
  assert_eq "${base}..HEAD" "$out"
}

test_task_diff_range_loud_fail_rc5() {
  # Neither single-branch sha, nor merge-base feat/<f>, nor wf_vi_diff_range resolves → rc 5.
  local outside; outside="$(mktemp -d)"
  ( cd "$outside" \
    && git init -q -b main . 2>/dev/null \
    && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m base ) || { rm -rf "$outside"; return 1; }
  local rc=0
  ( WF_TASK_REPO_PATH="$outside" wf_vi_task_diff_range nonexistent-feature "$COV_FEAT" ) >/dev/null 2>&1 || rc=$?
  rm -rf "$outside"
  [[ "$rc" == "5" ]]
}

test_write_task_coverage_report_complete_pass() {
  local out; out="$(wf_vi_write_task_coverage_report sample-spec "$TMPDIR_T/specs/sample-spec" 010 complete /dev/null)"
  [[ -f "$out" ]] || return 1
  assert_contains "$out" "010-coverage.yaml" || return 1
  local c; c="$(cat "$out")"
  assert_contains "$c" "gate: coverage" || return 1
  assert_contains "$c" "status: pass" || return 1
  assert_contains "$c" "findings: []" || return 1
}

test_write_task_coverage_report_reopen_findings() {
  local mx; mx="$(mktemp)"
  printf '| point | status | evidence |\n|---|---|---|\n| session starts | covered | diff L1 |\n| token re-auth | missing | none |\n| logout flow | partial | half |\n' > "$mx"
  local out; out="$(wf_vi_write_task_coverage_report sample-spec "$TMPDIR_T/specs/sample-spec" 010 reopen "$mx")"
  local c; c="$(cat "$out")"
  rm -f "$mx"
  assert_contains "$c" "status: findings" || return 1
  assert_contains "$c" "severity: high" || return 1     # missing row
  assert_contains "$c" "severity: medium" || return 1   # partial row
  assert_contains "$c" "source: llm" || return 1
  assert_contains "$c" "token re-auth" || return 1
  assert_contains "$c" "logout flow" || return 1
  [[ "$c" != *"session starts"* ]] || { echo "  covered row must not become a finding"; return 1; }
}

test_emit_coverage_helpers_in_allowlist() {
  wf_vi_emit_coverage_start sample-spec 010
  wf_vi_emit_coverage_done  sample-spec 010 reopen "/tmp/r.yaml"
  local jsonl="$TMPDIR_T/specs/sample-spec/.monitor.jsonl"
  [[ -f "$jsonl" ]] || return 1
  grep -q '"category":"coverage_audit_start"' "$jsonl" || return 1
  grep -q '"category":"coverage_audit_done"'  "$jsonl" || return 1
}

# ===========================================================================
# wf_vi_run_union_gates — `blocking:` normalization (fail-closed hard-block).
# A pool gate may declare a non-boolean `blocking:` value (typo, `yes`, `maybe`,
# `True`). Such values MUST fail closed → treated as blocking=true, so a gate
# FAILURE forces verdict "reopen" AND the emitted JSON stays a valid boolean.
# ===========================================================================

# Builds a one-gate pool with the given `blocking:` literal, a `shell`-scoped
# failing gate command, and runs wf_vi_run_union_gates over sample-spec (whose
# tasks carry languages/shell ground_rules, so the union picks the gate up).
# Echoes the verdict JSON line on stdout.
_run_union_with_blocking() {
  local blocking_literal="$1"
  local pool="$TMPDIR_T/typo-pool.yml"
  printf 'gate_pool:\n  - id: typo-gate\n    command: "exit 1"\n    applies_to: [shell]\n    category: lint\n    blocking: %s\n' \
    "$blocking_literal" > "$pool"
  WF_TASK_GATE_POOL="$pool" WF_SPEC_GATES="typo-gate" \
    wf_vi_run_union_gates sample-spec "$TMPDIR_T/specs/sample-spec" "$TMPDIR_T/gate.log"
}

# BUG 1: non-bool blocking must fail closed → a failing gate forces "reopen".
test_run_union_nonbool_blocking_fails_closed() {
  local out; out="$(_run_union_with_blocking maybe)"
  local verdict; verdict="$(printf '%s' "$out" | jq -r .verdict)"
  assert_eq "reopen" "$verdict"
}

# BUG 2: emitted verdict line is always valid JSON; .blocking is a real boolean
# even when the pool declared a non-bool literal.
test_run_union_nonbool_blocking_emits_valid_json_boolean() {
  local out; out="$(_run_union_with_blocking yes)"
  # whole line must parse
  printf '%s' "$out" | jq -e . >/dev/null || { echo "  invalid JSON: $out"; return 1; }
  local btype; btype="$(printf '%s' "$out" | jq -r '.gate_failures[0].blocking | type')"
  assert_eq "boolean" "$btype"
  local bval; bval="$(printf '%s' "$out" | jq -r '.gate_failures[0].blocking')"
  assert_eq "true" "$bval"
}

# Legitimate blocking:false must be preserved (not over-corrected to true):
# a failing non-blocking gate records blocking=false and does NOT force reopen.
test_run_union_explicit_false_preserved() {
  local out; out="$(_run_union_with_blocking false)"
  local verdict; verdict="$(printf '%s' "$out" | jq -r .verdict)"
  assert_eq "" "$verdict"
  local bval; bval="$(printf '%s' "$out" | jq -r '.gate_failures[0].blocking')"
  assert_eq "false" "$bval"
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
run_test "diff_range fails loud (rc 5) on missing feat branch" test_diff_range_fails_loud_when_no_branch
run_test "task_acceptance_rows skips header + separator"  test_task_acceptance_rows_skips_header_and_separator
run_test "task_fr_refs extracts unique sorted FR ids"     test_task_fr_refs_extracts_unique_sorted
run_test "build_task_prompt feature track: rows + FR allowlist" test_build_task_prompt_feature_track
run_test "build_task_prompt technical track: no FR allowlist"   test_build_task_prompt_technical_track
run_test "task_diff_range per-task → merge-base ..HEAD"   test_task_diff_range_per_task_merge_base
run_test "task_diff_range single-branch → base_sha..HEAD" test_task_diff_range_single_branch_uses_base_sha
run_test "task_diff_range loud-fails (rc 5) when unresolvable"  test_task_diff_range_loud_fail_rc5
run_test "write_task_coverage_report complete → pass"     test_write_task_coverage_report_complete_pass
run_test "write_task_coverage_report reopen → high/medium llm findings" test_write_task_coverage_report_reopen_findings
run_test "emit_coverage_start/done pass category allowlist" test_emit_coverage_helpers_in_allowlist
run_test "run_union: non-bool blocking fails closed → reopen"   test_run_union_nonbool_blocking_fails_closed
run_test "run_union: non-bool blocking emits valid JSON boolean" test_run_union_nonbool_blocking_emits_valid_json_boolean
run_test "run_union: explicit blocking:false preserved"          test_run_union_explicit_false_preserved

echo "=== $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
