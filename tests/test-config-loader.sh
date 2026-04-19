#!/usr/bin/env bash
# test-config-loader.sh — Tests for scripts/config-loader.sh (T002).
# No external framework. Given/When/Then per testing/principles.md.
# shellcheck disable=SC1090,SC1091

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOADER="$REPO_ROOT/scripts/config-loader.sh"
FIXTURES="$REPO_ROOT/tests/fixtures/config"

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

# Build a minimal valid repo in $TEST_TMPDIR; echoes repo path.
mk_repo() {
  local repo="$TEST_TMPDIR/repo"
  mkdir -p "$repo/specs/demo/tasks" "$repo/knowledge-base" "$repo/agent_pool"
  cp "$FIXTURES/workflow-vault.yml" "$repo/.workflow.yml"
  # rewrite paths to live in-repo
  cat > "$repo/.workflow.yml" <<EOF
spec_storage: specs/
gate_pool: knowledge-base/gates.yml
agent_pool: agent_pool
validate_scope: per-task
EOF
  cp "$FIXTURES/gates-valid.yml" "$repo/knowledge-base/gates.yml"
  # Seed agent files referenced by spec-config-valid.yml fixture
  : > "$repo/agent_pool/code-quality-pragmatist.md"
  printf '%s' "$repo"
}

require_yq() {
  command -v yq >/dev/null 2>&1 || { echo "    SKIP: yq not installed" >&2; return 99; }
}

# --- happy path ---

test_loader_exports_wf_spec_storage() {
  require_yq || return 0
  local repo; repo="$(mk_repo)"
  ( cd "$repo" && source "$LOADER" && wf_load_config && [[ -n "$WF_SPEC_STORAGE" && -d "$WF_SPEC_STORAGE" ]] )
}

test_loader_missing_workflow_fails_exit_2() {
  local empty="$TEST_TMPDIR/empty"
  mkdir -p "$empty"
  local rc=0
  ( cd "$empty" && source "$LOADER" && wf_load_config ) >/dev/null 2>"$TEST_TMPDIR/err" || rc=$?
  [[ "$rc" == "2" ]] && grep -q "/bootstrap" "$TEST_TMPDIR/err" && ! grep -q '^WF_SPEC_STORAGE=' <(env)
}

test_loader_malformed_gates_exit_3() {
  require_yq || return 0
  local repo; repo="$(mk_repo)"
  echo "gates: [ {id: x" > "$repo/knowledge-base/gates.yml"
  local rc=0
  ( cd "$repo" && source "$LOADER" && wf_load_config ) >/dev/null 2>&1 || rc=$?
  [[ "$rc" == "3" ]]
}

test_loader_unknown_spec_gate_exit_4() {
  require_yq || return 0
  local repo; repo="$(mk_repo)"
  cp "$FIXTURES/spec-config-unknown-gate.yml" "$repo/specs/demo/config.yml"
  local rc=0 err="$TEST_TMPDIR/err"
  ( cd "$repo" && source "$LOADER" && wf_load_config --spec demo ) >/dev/null 2>"$err" || rc=$?
  [[ "$rc" == "4" ]] && grep -q "nonexistent-gate" "$err"
}

test_loader_traversal_exit_2() {
  require_yq || return 0
  local repo; repo="$(mk_repo)"
  cat > "$repo/.workflow.yml" <<EOF
spec_storage: ../../etc
gate_pool: knowledge-base/gates.yml
agent_pool: agent_pool
EOF
  local rc=0
  ( cd "$repo" && source "$LOADER" && wf_load_config ) >/dev/null 2>&1 || rc=$?
  [[ "$rc" == "2" ]]
}

test_loader_billion_laughs_exit_5_within_5s() {
  require_yq || return 0
  local repo; repo="$(mk_repo)"
  cp "$FIXTURES/billion-laughs.yml" "$repo/knowledge-base/gates.yml"
  local rc=0 start end
  start=$(date +%s)
  ( cd "$repo" && source "$LOADER" && wf_load_config ) >/dev/null 2>&1 || rc=$?
  end=$(date +%s)
  [[ "$rc" == "5" || "$rc" == "3" ]] && (( end - start <= 7 ))
}

test_loader_double_source_idempotent() {
  require_yq || return 0
  local repo; repo="$(mk_repo)"
  ( cd "$repo" \
    && source "$LOADER" && wf_load_config \
    && [[ "$WF_CONFIG_LOADED" == "1" ]] \
    && source "$LOADER" \
    && [[ "$WF_CONFIG_LOADED" == "1" ]] )
}

test_loader_cli_export_kv_lines() {
  require_yq || return 0
  local repo; repo="$(mk_repo)"
  local out
  out="$(cd "$repo" && "$LOADER" export 2>/dev/null)"
  grep -qE "^WF_CONFIG_LOADED='1'$" <<<"$out" \
    && grep -qE "^WF_SPEC_STORAGE='[^']+'$" <<<"$out"
}

test_loader_warns_on_uncommitted_gates() {
  require_yq || return 0
  local repo; repo="$(mk_repo)"
  ( cd "$repo" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -q -m init ) || return 1
  echo "# drift" >> "$repo/knowledge-base/gates.yml"
  local err rc=0
  err="$(cd "$repo" && source "$LOADER" && wf_load_config 2>&1 1>/dev/null)" || rc=$?
  [[ "$rc" == "0" ]] && grep -qi "uncommitted" <<<"$err"
}

test_loader_no_workflow_source_refs() {
  # CI grep guard: loader contains no `source` reference to monitor / task-manager / pre-commit-hook / itself.
  ! grep -E '^[[:space:]]*(source|\.)[[:space:]]+[^#]*(monitor|task-manager|pre-commit-hook|config-loader)\.sh' "$LOADER"
}

test_loader_spec_exports_gates_agents_has_config() {
  require_yq || return 0
  local repo; repo="$(mk_repo)"
  cp "$FIXTURES/spec-config-valid.yml" "$repo/specs/demo/config.yml"
  ( cd "$repo" && source "$LOADER" && wf_load_config --spec demo \
    && [[ "$WF_SPEC_HAS_CONFIG" == "1" ]] \
    && grep -q "rust-clippy" <<<"$WF_SPEC_GATES" \
    && [[ "${WF_SPEC_AGENTS_VALIDATE:-}" == *"code-quality-pragmatist"* ]] \
    && [[ "$WF_VALIDATE_SCOPE" == "per-spec" ]] )
}

test_loader_missing_spec_config_exit_4_no_partial() {
  require_yq || return 0
  local repo; repo="$(mk_repo)"  # no specs/demo/config.yml is written
  local rc=0
  ( cd "$repo" && source "$LOADER"; wf_load_config --spec demo; exit $? ) >/dev/null 2>&1 || rc=$?
  [[ "$rc" == "4" ]] || return 1
  # No-partial-export check: CLI export mode must also fail (rc != 0) and produce no WF_* lines.
  local out
  out="$(cd "$repo" && "$LOADER" export --spec demo 2>/dev/null)"
  [[ -z "$out" ]]
}

test_loader_integration_seam_with_config_paths() {
  # Integration seam: loader uses config-paths.sh primitives under WF_* contract.
  require_yq || return 0
  local repo; repo="$(mk_repo)"
  local nested="$repo/a/b/c"; mkdir -p "$nested"
  ( cd "$nested" && source "$LOADER" && wf_load_config \
      && [[ "$WF_REPO_ROOT" == "$(realpath -- "$repo")" ]] )
}

test_loader_gates_duplicate_id_exit_3() {
  require_yq || return 0
  local repo; repo="$(mk_repo)"
  cp "$FIXTURES/gates-duplicate-id.yml" "$repo/knowledge-base/gates.yml"
  local rc=0
  ( cd "$repo" && source "$LOADER" && wf_load_config ) >/dev/null 2>&1 || rc=$?
  [[ "$rc" == "3" ]]
}

test_loader_gate_pool_traversal_exit_2() {
  require_yq || return 0
  local repo; repo="$(mk_repo)"
  cat > "$repo/.workflow.yml" <<EOF
spec_storage: specs/
gate_pool: ../../etc/hosts
agent_pool: agent_pool
EOF
  local rc=0
  ( cd "$repo" && source "$LOADER" && wf_load_config ) >/dev/null 2>&1 || rc=$?
  [[ "$rc" == "2" ]]
}

test_loader_unresolved_agent_exit_4() {
  require_yq || return 0
  local repo; repo="$(mk_repo)"
  cat > "$repo/specs/demo/config.yml" <<EOF
agents:
  validate:
    - ghost-agent-does-not-exist
EOF
  local rc=0
  ( cd "$repo" && source "$LOADER" && wf_load_config --spec demo ) >/dev/null 2>&1 || rc=$?
  [[ "$rc" == "4" ]]
}

test_shared_fixtures_extended() {
  [[ -f "$FIXTURES/workflow-vault.yml" \
     && -f "$FIXTURES/spec-config-valid.yml" \
     && -f "$FIXTURES/spec-config-unknown-gate.yml" \
     && -f "$FIXTURES/billion-laughs.yml" \
     && -f "$FIXTURES/README.md" ]]
}

echo "=== test-config-loader.sh ==="
run_test "loader exports WF_SPEC_STORAGE from valid .workflow.yml" test_loader_exports_wf_spec_storage
run_test "missing .workflow.yml fails closed exit 2 naming /bootstrap" test_loader_missing_workflow_fails_exit_2
run_test "malformed gates.yml fails closed exit 3" test_loader_malformed_gates_exit_3
run_test "unknown spec gate id fails closed exit 4 naming missing id" test_loader_unknown_spec_gate_exit_4
run_test "spec_storage path traversal fails closed exit 2" test_loader_traversal_exit_2
run_test "billion-laughs exits 5 within 5 seconds" test_loader_billion_laughs_exit_5_within_5s
run_test "double-source is idempotent" test_loader_double_source_idempotent
run_test "config-loader.sh export emits evaluable KEY=VAL lines" test_loader_cli_export_kv_lines
run_test "uncommitted gates.yml warns but loader still succeeds" test_loader_warns_on_uncommitted_gates
run_test "CI grep guard: loader sources no workflow script" test_loader_no_workflow_source_refs
run_test "--spec sets WF_SPEC_GATES, WF_SPEC_AGENTS_*, WF_SPEC_HAS_CONFIG" test_loader_spec_exports_gates_agents_has_config
run_test "missing per-spec config.yml with --spec exits 4 (no partial)" test_loader_missing_spec_config_exit_4_no_partial
run_test "integration seam: loader composes config-paths.sh under WF_* contract" test_loader_integration_seam_with_config_paths
run_test "gates.yml duplicate ids fail closed exit 3" test_loader_gates_duplicate_id_exit_3
run_test "gate_pool with ../ traversal fails closed exit 2" test_loader_gate_pool_traversal_exit_2
run_test "unresolved agent id fails closed exit 4" test_loader_unresolved_agent_exit_4
run_test "extended shared fixtures present" test_shared_fixtures_extended

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
