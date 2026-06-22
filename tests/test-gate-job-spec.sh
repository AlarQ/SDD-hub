#!/usr/bin/env bash
# test-gate-job-spec.sh — Tests for wf_build_gate_job_spec in scripts/gate-ceiling.sh.
# Deterministic effective-set + gate pool -> JSON job spec. Given/When/Then; no framework.
# shellcheck disable=SC1090,SC1091
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SUT="$REPO_ROOT/scripts/gate-ceiling.sh"

PASS=0; FAIL=0; TMP=""

setup() { TMP="$(mktemp -d)"; }
teardown() { [[ -n "$TMP" && -d "$TMP" ]] && rm -rf "$TMP"; TMP=""; }

# write_pool -> echoes path to a .workflow.yml fixture carrying an inline gate_pool
write_pool() {
  local p="$TMP/.workflow.yml"
  cat >"$p" <<'YAML'
gate_pool:
  - id: rust-check
    command: "cargo check --workspace"
    applies_to: [rust]
    category: code-quality
    blocking: true
  - id: ts-test
    command: "npm test --silent"
    cwd: "frontend"
    applies_to: [ts]
    category: testing
    blocking: true
  - id: quote-gate
    command: "echo \"hi there\" && grep -E 'a|b' ."
    applies_to: [any]
    category: code-quality
    blocking: false
YAML
  printf '%s' "$p"
}

# assert_json <json> <yq-expr> <expected>
assert_json() {
  local json="$1" expr="$2" want="$3" got
  got="$(printf '%s' "$json" | yq e -p=json -r "$expr" - 2>/dev/null)"
  if [[ "$got" == "$want" ]]; then return 0; fi
  echo "    expected [$expr]=$want got=$got" >&2; return 1
}

run_test() {
  local name="$1"; shift
  setup
  if ( set +e; "$@" ); then echo "  PASS: $name"; PASS=$((PASS + 1));
  else echo "  FAIL: $name"; FAIL=$((FAIL + 1)); fi
  teardown
}

# --- single gate ------------------------------------------------------------

t_single_gate_fields() {
  local pool json
  pool="$(write_pool)"
  ( source "$SUT"
    json="$(wf_build_gate_job_spec 'rust-check' "$pool")" || exit 1
    assert_json "$json" 'length' 1 || exit 1
    assert_json "$json" '.[0].gate_id' rust-check || exit 1
    assert_json "$json" '.[0].command' 'cargo check --workspace' || exit 1
    assert_json "$json" '.[0].category' code-quality || exit 1
    # cwd absent when the gate has none
    assert_json "$json" '.[0] | has("cwd")' false || exit 1
  )
}

# --- cwd present when the gate declares one ---------------------------------

t_cwd_present_when_set() {
  local pool json
  pool="$(write_pool)"
  ( source "$SUT"
    json="$(wf_build_gate_job_spec 'ts-test' "$pool")" || exit 1
    assert_json "$json" '.[0].cwd' frontend || exit 1
    assert_json "$json" '.[0].command' 'npm test --silent' || exit 1
  )
}

# --- multiple gates preserve order ------------------------------------------

t_multi_gate_order() {
  local pool json
  pool="$(write_pool)"
  ( source "$SUT"
    json="$(printf 'rust-check\nts-test' | { read -r a; read -r b; wf_build_gate_job_spec "$(printf '%s\n%s' "$a" "$b")" "$pool"; })" || exit 1
    assert_json "$json" 'length' 2 || exit 1
    assert_json "$json" '.[0].gate_id' rust-check || exit 1
    assert_json "$json" '.[1].gate_id' ts-test || exit 1
  )
}

# --- shell metacharacters in command survive as data, not eval --------------

t_quotes_escaped_safely() {
  local pool json
  pool="$(write_pool)"
  ( source "$SUT"
    json="$(wf_build_gate_job_spec 'quote-gate' "$pool")" || exit 1
    assert_json "$json" '.[0].command' 'echo "hi there" && grep -E '"'"'a|b'"'"' .' || exit 1
  )
}

# --- empty effective set -> empty JSON array --------------------------------

t_empty_set() {
  local pool json
  pool="$(write_pool)"
  ( source "$SUT"
    json="$(wf_build_gate_job_spec '' "$pool")" || exit 1
    assert_json "$json" 'length' 0 || exit 1
  )
}

echo "test-gate-job-spec.sh"
run_test "single gate fields, cwd absent when unset" t_single_gate_fields
run_test "cwd present when gate declares one"        t_cwd_present_when_set
run_test "multiple gates preserve order"             t_multi_gate_order
run_test "shell metachars in command kept as data"   t_quotes_escaped_safely
run_test "empty effective set -> empty array"        t_empty_set

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
