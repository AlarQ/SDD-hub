#!/usr/bin/env bash
# test-decide.sh — Tests for scripts/decide.sh.
# Deterministic env -> named verdict + reason. Given/When/Then; no framework.
# shellcheck disable=SC1090,SC1091
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SUT="$REPO_ROOT/scripts/decide.sh"

PASS=0; FAIL=0

# assert_field <output> <KEY> <expected>
assert_field() {
  local out="$1" key="$2" want="$3" got
  got="$(printf '%s\n' "$out" | grep -E "^$key=" | head -1 | cut -d= -f2-)"
  if [[ "$got" == "$want" ]]; then return 0; fi
  echo "    expected $key=$want got $key=$got" >&2; return 1
}

run_test() {
  local name="$1"; shift
  if ( set +e; "$@" ); then echo "  PASS: $name"; PASS=$((PASS + 1));
  else echo "  FAIL: $name"; FAIL=$((FAIL + 1)); fi
}

# --- coverage-skip ---------------------------------------------------------

t_cov_tier_small_wins() {
  # tier=small is first in the priority chain — wins even when later predicates
  # would also skip.
  local out
  out="$(WF_SPEC_TIER=small WF_COVERAGE_AUDIT=false WF_VALIDATE_SCOPE=per-spec \
    bash "$SUT" coverage-skip)"
  assert_field "$out" VERDICT skip || return 1
  assert_field "$out" REASON tier_small || return 1
}

t_cov_config_off() {
  local out
  out="$(WF_SPEC_TIER=medium WF_COVERAGE_AUDIT=false WF_VALIDATE_SCOPE=per-task \
    bash "$SUT" coverage-skip)"
  assert_field "$out" VERDICT skip || return 1
  assert_field "$out" REASON config_off || return 1
}

t_cov_config_off_beats_scope() {
  # config_off precedes scope=per-spec in the chain.
  local out
  out="$(WF_SPEC_TIER=medium WF_COVERAGE_AUDIT=false WF_VALIDATE_SCOPE=per-spec \
    bash "$SUT" coverage-skip)"
  assert_field "$out" REASON config_off || return 1
}

t_cov_scope_per_spec() {
  local out
  out="$(WF_SPEC_TIER=large WF_COVERAGE_AUDIT=true WF_VALIDATE_SCOPE=per-spec \
    bash "$SUT" coverage-skip)"
  assert_field "$out" VERDICT skip || return 1
  assert_field "$out" REASON scope=per-spec || return 1
}

t_cov_run() {
  local out
  out="$(WF_SPEC_TIER=medium WF_COVERAGE_AUDIT=true WF_VALIDATE_SCOPE=per-task \
    bash "$SUT" coverage-skip)"
  assert_field "$out" VERDICT run || return 1
  assert_field "$out" REASON '' || return 1
}

t_cov_defaults_run() {
  # Absent WF_COVERAGE_AUDIT defaults to true; absent scope defaults to per-task.
  local out
  out="$(WF_SPEC_TIER=medium bash "$SUT" coverage-skip)"
  assert_field "$out" VERDICT run || return 1
}

# --- validate-impl-skip ----------------------------------------------------

t_vi_tier_small_skip() {
  local out
  out="$(WF_SPEC_TIER=small bash "$SUT" validate-impl-skip)"
  assert_field "$out" VERDICT skip || return 1
  assert_field "$out" REASON tier_small || return 1
}

t_vi_run() {
  local out
  out="$(WF_SPEC_TIER=large bash "$SUT" validate-impl-skip)"
  assert_field "$out" VERDICT run || return 1
  assert_field "$out" REASON '' || return 1
}

# --- impl-context ----------------------------------------------------------

t_ctx_technical() {
  local out
  out="$(WF_SPEC_TRACK=technical bash "$SUT" impl-context)"
  assert_field "$out" VERDICT technical || return 1
  assert_field "$out" REASON 'docs/adr/+CONTEXT.md' || return 1
}

t_ctx_feature() {
  local out
  out="$(WF_SPEC_TRACK=feature bash "$SUT" impl-context)"
  assert_field "$out" VERDICT feature || return 1
  assert_field "$out" REASON 'spec.md+design.md' || return 1
}

t_ctx_defaults_feature() {
  # Absent WF_SPEC_TRACK defaults to feature.
  local out
  out="$(bash "$SUT" impl-context)"
  assert_field "$out" VERDICT feature || return 1
}

# --- errors ----------------------------------------------------------------

t_unknown_decision() {
  bash "$SUT" bogus-decision >/dev/null 2>&1 && return 1
  return 0
}

t_missing_arg() {
  bash "$SUT" >/dev/null 2>&1 && return 1
  return 0
}

echo "decide.sh tests"
run_test "coverage-skip: tier=small wins priority" t_cov_tier_small_wins
run_test "coverage-skip: config_off" t_cov_config_off
run_test "coverage-skip: config_off beats scope" t_cov_config_off_beats_scope
run_test "coverage-skip: scope=per-spec" t_cov_scope_per_spec
run_test "coverage-skip: run (no skip)" t_cov_run
run_test "coverage-skip: defaults -> run" t_cov_defaults_run
run_test "validate-impl-skip: tier=small skip" t_vi_tier_small_skip
run_test "validate-impl-skip: run" t_vi_run
run_test "impl-context: technical" t_ctx_technical
run_test "impl-context: feature" t_ctx_feature
run_test "impl-context: defaults -> feature" t_ctx_defaults_feature
run_test "unknown decision -> nonzero" t_unknown_decision
run_test "missing arg -> nonzero" t_missing_arg

echo "-----"
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
