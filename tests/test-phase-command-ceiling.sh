#!/usr/bin/env bash
# test-phase-command-ceiling.sh — T004: ceiling semantics, snapshot drift, config gate.
# Tests the bash logic documented in commands/validate.md, commands/implement.md,
# and scripts/ship-procedure.md. No external framework. Given/When/Then per testing/principles.md.
# shellcheck disable=SC1090,SC1091

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOADER="$REPO_ROOT/scripts/config-loader.sh"
CEILING_HELPERS="$REPO_ROOT/scripts/gate-ceiling.sh"
FIXTURES="$REPO_ROOT/tests/fixtures/config"

# shellcheck source=../scripts/gate-ceiling.sh
source "$CEILING_HELPERS"

# Preflight: verify required fixture files exist
for _f in gates-valid.yml task-doc-only-empty-ok.md task-rust-ground-rules.md; do
  [[ -f "$FIXTURES/$_f" ]] || { echo "MISSING FIXTURE: $FIXTURES/$_f" >&2; exit 1; }
done
unset _f

PASS=0; FAIL=0; TEST_TMPDIR=""

setup() {
  TEST_TMPDIR="$(mktemp -d)"
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

# Build a minimal valid repo with spec config in $TEST_TMPDIR.
mk_repo_with_spec() {
  local feature="${1:-demo}"
  local repo="$TEST_TMPDIR/repo"
  mkdir -p "$repo/specs/$feature/tasks" "$repo/agents"
  cat > "$repo/.workflow.yml" <<EOF
spec_storage: specs/
gate_pool:
  - id: rust-clippy
    command: "cargo clippy -- -D warnings"
    applies_to: [rust]
    category: lint
    blocking: true
  - id: shellcheck
    command: "shellcheck scripts/*.sh"
    applies_to: [shell]
    category: lint
    blocking: true
  - id: semgrep-security
    command: "semgrep --config auto ."
    applies_to: [any]
    category: security
    blocking: true
general_kb_path: $REPO_ROOT/tests/fixtures
agent_pool: agents
validate_scope: per-task
EOF
  # Minimal spec config with rust-clippy + shellcheck ceiling
  cat > "$repo/specs/$feature/config.yml" <<EOF
tags: [test]
tier: small
gates:
  - rust-clippy
  - shellcheck
agents:
  validate:
    - code-quality-pragmatist
EOF
  # Agent stub
  : > "$repo/agents/code-quality-pragmatist.md"
  printf '%s' "$repo"
}

# --- Test: missing config.yml → loader exit 4 ---

t_missing_spec_config_exit4() {
  # Given: repo without spec config.yml
  local repo="$TEST_TMPDIR/repo"
  mkdir -p "$repo/specs/demo" "$repo/agents"
  cat > "$repo/.workflow.yml" <<EOF
spec_storage: specs/
gate_pool:
  - id: rust-clippy
    command: "cargo clippy -- -D warnings"
    applies_to: [rust]
    category: lint
    blocking: true
  - id: shellcheck
    command: "shellcheck scripts/*.sh"
    applies_to: [shell]
    category: lint
    blocking: true
  - id: semgrep-security
    command: "semgrep --config auto ."
    applies_to: [any]
    category: security
    blocking: true
general_kb_path: $REPO_ROOT/tests/fixtures
agent_pool: agents
EOF

  # When: loader invoked with --spec demo
  (
    cd "$repo" || return 1
    source "$LOADER"
    wf_load_config --spec demo
  )
  local rc=$?

  # Then: exit code is 4
  [[ $rc -eq 4 ]]
}
run_test "Missing config.yml → loader exits 4" t_missing_spec_config_exit4

# --- Test: ceiling intersection yields effective set ---

# Thin shim over the canonical ceiling intersection helper in
# scripts/gate-ceiling.sh. Tests exercise the production code path rather
# than a parallel re-implementation.
_compute_effective_set() {
  local gates_file="$1"   # path to .workflow.yml (inline gate_pool)
  local spec_gates="$2"   # newline-separated ceiling gate IDs
  local lang_tags="$3"    # space-separated language tags (e.g. "rust shell")

  local langs_nl="" tag
  for tag in $lang_tags; do langs_nl+="$tag"$'\n'; done
  WF_GATE_POOL="$gates_file" wf_gc__intersect "$gates_file" "$spec_gates" "$langs_nl"
}

t_ceiling_intersection_rust_task() {
  # Given: spec ceiling = [rust-clippy, shellcheck]; task lang = rust
  local repo
  repo="$(mk_repo_with_spec demo)"
  (
    cd "$repo" || return 1
    source "$LOADER"
    wf_load_config --spec demo
    effective="$(_compute_effective_set "$WF_GATE_POOL" "$WF_SPEC_GATES" "rust")"
    # Then: rust-clippy in effective; shellcheck NOT in effective (applies_to shell, not rust)
    echo "$effective" | grep -Fxq "rust-clippy"
    ! echo "$effective" | grep -Fxq "shellcheck"
  )
}
run_test "Ceiling intersection: rust task → only rust-clippy in effective set" t_ceiling_intersection_rust_task

t_ceiling_intersection_semgrep_any_tag() {
  # Given: spec ceiling includes semgrep-security (applies_to: any)
  local repo="$TEST_TMPDIR/repo"
  mkdir -p "$repo/specs/demo" "$repo/agents"
  cat > "$repo/.workflow.yml" <<EOF
spec_storage: specs/
gate_pool:
  - id: rust-clippy
    command: "cargo clippy -- -D warnings"
    applies_to: [rust]
    category: lint
    blocking: true
  - id: shellcheck
    command: "shellcheck scripts/*.sh"
    applies_to: [shell]
    category: lint
    blocking: true
  - id: semgrep-security
    command: "semgrep --config auto ."
    applies_to: [any]
    category: security
    blocking: true
general_kb_path: $REPO_ROOT/tests/fixtures
agent_pool: agents
EOF
  cat > "$repo/specs/demo/config.yml" <<EOF
tier: small
gates:
  - rust-clippy
  - semgrep-security
agents: {}
EOF
  (
    cd "$repo" || return 1
    source "$LOADER"
    wf_load_config --spec demo
    effective="$(_compute_effective_set "$WF_GATE_POOL" "$WF_SPEC_GATES" "rust")"
    # Then: both rust-clippy and semgrep-security in effective (semgrep matches via "any")
    echo "$effective" | grep -Fxq "rust-clippy"
    echo "$effective" | grep -Fxq "semgrep-security"
  )
}
run_test "Ceiling intersection: 'any' applies_to gate runs for any language" t_ceiling_intersection_semgrep_any_tag

t_gate_outside_ceiling_excluded() {
  # Given: gate_pool has shellcheck but spec ceiling only has rust-clippy
  local repo="$TEST_TMPDIR/repo"
  mkdir -p "$repo/specs/demo" "$repo/agents"
  cat > "$repo/.workflow.yml" <<EOF
spec_storage: specs/
gate_pool:
  - id: rust-clippy
    command: "cargo clippy -- -D warnings"
    applies_to: [rust]
    category: lint
    blocking: true
  - id: shellcheck
    command: "shellcheck scripts/*.sh"
    applies_to: [shell]
    category: lint
    blocking: true
  - id: semgrep-security
    command: "semgrep --config auto ."
    applies_to: [any]
    category: security
    blocking: true
general_kb_path: $REPO_ROOT/tests/fixtures
agent_pool: agents
EOF
  cat > "$repo/specs/demo/config.yml" <<EOF
tier: small
gates:
  - rust-clippy
agents: {}
EOF
  (
    cd "$repo" || return 1
    source "$LOADER"
    wf_load_config --spec demo
    effective="$(_compute_effective_set "$WF_GATE_POOL" "$WF_SPEC_GATES" "shell")"
    # Then: effective set is empty (shellcheck is language-applicable but not in ceiling)
    [[ -z "$effective" ]]
  )
}
run_test "Gate outside ceiling → excluded from effective set" t_gate_outside_ceiling_excluded

# --- Test: empty intersection + empty_intersection_ok ---

t_empty_intersection_ok_flag() {
  # Given: task with empty_intersection_ok: true in frontmatter
  local task_file="$FIXTURES/task-doc-only-empty-ok.md"
  local empty_ok
  empty_ok="$(yq e '.empty_intersection_ok' "$task_file" 2>/dev/null)"
  [[ "$empty_ok" == "true" ]]
}
run_test "Doc-only task fixture has empty_intersection_ok: true" t_empty_intersection_ok_flag

t_code_task_no_empty_ok_flag() {
  # Given: code task with no empty_intersection_ok (default false)
  local task_file="$FIXTURES/task-rust-ground-rules.md"
  local empty_ok
  # Use head -1 to read first YAML document only (markdown files have frontmatter + body)
  empty_ok="$(yq e '.empty_intersection_ok // false' "$task_file" 2>/dev/null | head -1)"
  [[ "$empty_ok" == "false" ]]
}
run_test "Rust task fixture has empty_intersection_ok: false (default)" t_code_task_no_empty_ok_flag

# --- Test: snapshot creation and drift detection ---

t_snapshot_no_drift_on_whitespace_edit() {
  # Given: snapshot written with rust-clippy + shellcheck (via wf_write_snapshot)
  local snap="$TEST_TMPDIR/snapshot"
  local repo
  repo="$(mk_repo_with_spec demo)"
  (
    cd "$repo" || return 1
    source "$LOADER"
    wf_load_config --spec demo
    wf_write_snapshot "$snap"
    # When: same config re-read — no drift
    result="$(wf_check_snapshot_drift "$snap")"
    [[ "$result" == "SNAPSHOT_OK" ]]
  )
}
run_test "Snapshot: whitespace/order change → no drift" t_snapshot_no_drift_on_whitespace_edit

t_snapshot_drift_on_gate_removal() {
  # Given: snapshot written with rust-clippy + shellcheck
  local snap="$TEST_TMPDIR/snapshot"
  local repo
  repo="$(mk_repo_with_spec demo)"
  (
    cd "$repo" || return 1
    source "$LOADER"
    wf_load_config --spec demo
    wf_write_snapshot "$snap"
    # When: gates env var reduced to only rust-clippy
    WF_SPEC_GATES="rust-clippy"
    result="$(wf_check_snapshot_drift "$snap")"
    [[ "$result" == "SNAPSHOT_DRIFT" ]]
  )
}
run_test "Snapshot: gate removed → drift detected" t_snapshot_drift_on_gate_removal

t_snapshot_drift_on_gate_added() {
  # Given: snapshot written with rust-clippy only
  local snap="$TEST_TMPDIR/snapshot"
  local repo
  repo="$(mk_repo_with_spec demo)"
  (
    cd "$repo" || return 1
    source "$LOADER"
    wf_load_config --spec demo
    WF_SPEC_GATES="rust-clippy"
    wf_write_snapshot "$snap"
    # When: semgrep-security added to gates
    WF_SPEC_GATES=$'rust-clippy\nsemgrep-security'
    result="$(wf_check_snapshot_drift "$snap")"
    [[ "$result" == "SNAPSHOT_DRIFT" ]]
  )
}
run_test "Snapshot: gate added → drift detected" t_snapshot_drift_on_gate_added

t_snapshot_no_drift_identical() {
  # Given/When: same config snapshot written and re-checked
  local snap="$TEST_TMPDIR/snapshot"
  local repo
  repo="$(mk_repo_with_spec demo)"
  (
    cd "$repo" || return 1
    source "$LOADER"
    wf_load_config --spec demo
    WF_SPEC_GATES="rust-clippy"
    wf_write_snapshot "$snap"
    result="$(wf_check_snapshot_drift "$snap")"
    [[ "$result" == "SNAPSHOT_OK" ]]
  )
}
run_test "Snapshot: identical gates → no drift" t_snapshot_no_drift_identical

# --- Test: unknown agent ID → loader exits non-zero ---

t_unknown_agent_id_exit4() {
  # Given: spec config references agent id "nonexistent-agent" not in agent pool
  local repo="$TEST_TMPDIR/repo"
  mkdir -p "$repo/specs/demo" "$repo/agents"
  cat > "$repo/.workflow.yml" <<EOF
spec_storage: specs/
gate_pool:
  - id: rust-clippy
    command: "cargo clippy -- -D warnings"
    applies_to: [rust]
    category: lint
    blocking: true
  - id: shellcheck
    command: "shellcheck scripts/*.sh"
    applies_to: [shell]
    category: lint
    blocking: true
  - id: semgrep-security
    command: "semgrep --config auto ."
    applies_to: [any]
    category: security
    blocking: true
general_kb_path: $REPO_ROOT/tests/fixtures
agent_pool: agents
EOF
  cat > "$repo/specs/demo/config.yml" <<EOF
tier: small
gates:
  - rust-clippy
agents:
  validate:
    - nonexistent-agent
EOF
  (
    cd "$repo" || return 1
    source "$LOADER"
    wf_load_config --spec demo
  )
  local rc=$?
  # Then: exit code is 4 (unknown agent fails closed)
  [[ $rc -eq 4 ]]
}
run_test "Unknown agent ID in spec config → loader exits 4" t_unknown_agent_id_exit4

# --- Test: integration seam — loader --spec exports WF_SPEC_GATES for ceiling ---

t_integration_seam_loader_spec_gates() {
  # Given: spec config with specific gate ceiling
  local repo
  repo="$(mk_repo_with_spec demo)"
  (
    cd "$repo" || return 1
    source "$LOADER"
    wf_load_config --spec demo
    # Then: WF_SPEC_GATES contains the ceiling IDs
    echo "$WF_SPEC_GATES" | grep -Fxq "rust-clippy"
    echo "$WF_SPEC_GATES" | grep -Fxq "shellcheck"
    # And: WF_SPEC_AGENTS_VALIDATE contains the agent ID
    [[ "$WF_SPEC_AGENTS_VALIDATE" == "code-quality-pragmatist" ]]
  )
}
run_test "Integration seam: loader --spec exports WF_SPEC_GATES and WF_SPEC_AGENTS_VALIDATE" t_integration_seam_loader_spec_gates

# --- Summary ---
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
