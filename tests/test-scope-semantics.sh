#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091
set -euo pipefail

# T016 — scope semantics + union gate execution helpers.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0; FAIL=0
TMPDIR_T=""

setup() {
  TMPDIR_T="$(mktemp -d)"
  mkdir -p "$TMPDIR_T/specs/demo/tasks"
  cat > "$TMPDIR_T/.workflow.yml" <<'EOF'
spec_storage: specs/
agent_pool: agents/
validate_scope: per-spec
gate_pool:
  - id: shellcheck
    command: "true"
    applies_to: [shell]
    category: lint
    blocking: true
  - id: shell-syntax
    command: "true"
    applies_to: [shell]
    category: lint
    blocking: true
  - id: rust-clippy
    command: "true"
    applies_to: [rust]
    category: lint
    blocking: true
  - id: docs-only
    command: "true"
    applies_to: [any]
    category: docs
    blocking: false
  - id: failing-blocker
    command: "false"
    applies_to: [shell]
    category: test
    blocking: true
  - id: failing-nonblocker
    command: "false"
    applies_to: [shell]
    category: lint
    blocking: false
EOF
  cat > "$TMPDIR_T/specs/demo/tasks/001-a.md" <<'EOF'
---
id: "001"
status: implemented
ground_rules:
  - languages/shell/_index.md
---
EOF
  cat > "$TMPDIR_T/specs/demo/tasks/002-b.md" <<'EOF'
---
id: "002"
status: implemented
ground_rules:
  - languages/shell/_index.md
  - architecture/general.md
---
EOF
  cd "$TMPDIR_T"
  unset WF_VALIDATE_IMPL_LOADED WF_CONFIG_LOADED
  # shellcheck disable=SC1091
  source "$REPO_ROOT/scripts/validate-impl.sh"
  export WF_GATE_POOL="$TMPDIR_T/.workflow.yml"
}
teardown() { cd "$REPO_ROOT"; rm -rf "$TMPDIR_T"; }

run_test() {
  local name="$1"; shift
  setup
  if ( "$@" ); then echo "  PASS: $name"; PASS=$((PASS+1));
  else echo "  FAIL: $name"; FAIL=$((FAIL+1)); fi
  teardown
}

assert_eq()       { [[ "$1" == "$2" ]] || { echo "    exp:[$1] got:[$2]"; return 1; }; }
assert_contains() { [[ "$1" == *"$2"* ]] || { echo "    missing:[$2] in:[$1]"; return 1; }; }

# === Helpers ===

test_task_languages_extracts_shell() {
  local out; out="$(wf_gc_task_languages "$TMPDIR_T/specs/demo/tasks/001-a.md")"
  assert_eq "shell" "$out"
}

test_union_languages_merges_across_tasks() {
  local out; out="$(wf_gc_union_languages "$TMPDIR_T/specs/demo/tasks")"
  assert_eq "shell" "$out"
}

test_compute_union_intersects_ceiling_with_languages() {
  local ceiling; ceiling=$'shellcheck\nshell-syntax\nrust-clippy\ndocs-only'
  local langs; langs=$'shell'
  local out; out="$(wf_gc__intersect "$WF_GATE_POOL" "$ceiling" "$langs")"
  # rust-clippy excluded (lang mismatch), docs-only included via `any`
  assert_eq $'docs-only\nshell-syntax\nshellcheck' "$out"
}

test_compute_union_dedupes_each_gate_once() {
  # Even though shell appears in two tasks, gate-id appears only once in union.
  local ceiling; ceiling=$'shellcheck\nshellcheck'
  local langs; langs=$'shell\nshell'
  local out; out="$(wf_gc__intersect "$WF_GATE_POOL" "$ceiling" "$langs")"
  assert_eq "shellcheck" "$out"
}

# === Union execution ===

# Helper: parse the "verdict" field from the JSON line emitted on stdout.
_extract_verdict() {
  # crude JSON extract — sufficient for fixed-shape stdout from wf_vi_run_union_gates
  local s="$1"
  [[ "$s" =~ \"verdict\":\"([^\"]*)\" ]] && printf '%s' "${BASH_REMATCH[1]}"
}

test_run_union_passes_when_all_gates_succeed() {
  export WF_SPEC_GATES=$'shellcheck\nshell-syntax'
  local log; log="$(mktemp)"
  local out; out="$(wf_vi_run_union_gates demo "$TMPDIR_T/specs/demo" "$log")"
  assert_eq "" "$(_extract_verdict "$out")" || return 1
  grep -q 'gate: shellcheck' "$log" || return 1
  grep -q 'gate: shell-syntax' "$log" || return 1
}

test_run_union_blocking_failure_forces_reopen() {
  export WF_SPEC_GATES=$'shellcheck\nfailing-blocker'
  local log; log="$(mktemp)"
  local out; out="$(wf_vi_run_union_gates demo "$TMPDIR_T/specs/demo" "$log")"
  assert_eq "reopen" "$(_extract_verdict "$out")" || return 1
  assert_contains "$out" '"id":"failing-blocker"' || return 1
  assert_contains "$(cat "$log")" "failing-blocker" || return 1
}

test_run_union_nonblocking_failure_does_not_force_reopen() {
  export WF_SPEC_GATES=$'shellcheck\nfailing-nonblocker'
  local log; log="$(mktemp)"
  local out; out="$(wf_vi_run_union_gates demo "$TMPDIR_T/specs/demo" "$log")"
  assert_eq "" "$(_extract_verdict "$out")" || return 1
  assert_contains "$out" '"id":"failing-nonblocker"' || return 1
  assert_contains "$(cat "$log")" "failing-nonblocker" || return 1
}

test_run_union_empty_on_code_bearing_returns_3() {
  export WF_SPEC_GATES=$'rust-clippy'  # shell tasks ⇒ empty intersection
  local log; log="$(mktemp)"
  local rc=0
  wf_vi_run_union_gates demo "$TMPDIR_T/specs/demo" "$log" >/dev/null || rc=$?
  assert_eq "3" "$rc" || return 1
  assert_contains "$(cat "$log")" "EMPTY_UNION_FAIL_CLOSED" || return 1
}

test_run_union_doc_only_spec_passes_with_empty_union() {
  # No language tags → not code-bearing → empty union ok
  rm -rf "$TMPDIR_T/specs/demo/tasks"
  mkdir -p "$TMPDIR_T/specs/demo/tasks"
  cat > "$TMPDIR_T/specs/demo/tasks/001-doc.md" <<'EOF'
---
id: "001"
status: implemented
ground_rules:
  - architecture/general.md
---
EOF
  export WF_SPEC_GATES=$'shellcheck'
  local log; log="$(mktemp)"
  local rc=0
  wf_vi_run_union_gates demo "$TMPDIR_T/specs/demo" "$log" >/dev/null || rc=$?
  assert_eq "0" "$rc"
}

# === Monitor: scope=per-spec is a valid gate_skip reason ===

test_monitor_accepts_scope_per_spec_reason() {
  # shellcheck disable=SC1091
  source "$REPO_ROOT/scripts/monitor.sh"
  log_event demo gate_skip 001 \
    '{"gate":"shellcheck","reason":"scope=per-spec","scope":"per-spec"}'
  local jsonl="$TMPDIR_T/specs/demo/.monitor.jsonl"
  [[ -f "$jsonl" ]] || return 1
  grep -q '"reason":"scope=per-spec"' "$jsonl" || return 1
  grep -q '"category":"gate_skip"'    "$jsonl" || return 1
}

# === Doc assertions: validate.md scope short-circuit + validate-impl.md wiring ===

test_validate_md_documents_scope_per_spec_short_circuit() {
  local md="$REPO_ROOT/commands/validate.md"
  grep -q 'scope=per-spec' "$md" || return 1
  grep -q 'WF_VALIDATE_SCOPE' "$md" || return 1
}

test_validate_impl_md_wires_union_runner() {
  local md="$REPO_ROOT/commands/validate-impl.md"
  grep -q 'wf_vi_run_union_gates' "$md" || return 1
}

echo "=== test-scope-semantics.sh ==="
run_test "task_languages extracts shell tag"                 test_task_languages_extracts_shell
run_test "union_languages merges across tasks"               test_union_languages_merges_across_tasks
run_test "compute_union intersects ceiling ∩ langs (+any)"   test_compute_union_intersects_ceiling_with_languages
run_test "compute_union dedupes each gate once"              test_compute_union_dedupes_each_gate_once
run_test "run_union passes when all gates succeed"           test_run_union_passes_when_all_gates_succeed
run_test "run_union blocking failure → forced=reopen"        test_run_union_blocking_failure_forces_reopen
run_test "run_union non-blocking failure → not forced"       test_run_union_nonblocking_failure_does_not_force_reopen
run_test "run_union empty on code-bearing spec → rc 3"       test_run_union_empty_on_code_bearing_returns_3
run_test "run_union doc-only spec passes empty union"        test_run_union_doc_only_spec_passes_with_empty_union
run_test "monitor accepts gate_skip reason=scope=per-spec"   test_monitor_accepts_scope_per_spec_reason
run_test "validate.md documents scope=per-spec short-circuit" test_validate_md_documents_scope_per_spec_short_circuit
run_test "validate-impl.md wires wf_vi_run_union_gates"      test_validate_impl_md_wires_union_runner

echo "=== $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
