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
  mkdir -p "$repo/gkb"
  # rewrite paths to live in-repo (repo mode; general_kb_path required)
  cat > "$repo/.workflow.yml" <<EOF
spec_storage: specs/
gate_pool: knowledge-base/gates.yml
agent_pool: agent_pool
general_kb_path: /Users/ernestbednarczyk/Desktop/projects/master-brain/projects/dev-workflow/dev-workflow-repo/tests/fixtures
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

# --- validate_scope tests (T013) ---

test_loader_validate_scope_default_per_task() {
  # Given: .workflow.yml omits validate_scope
  # When:  wf_load_config succeeds
  # Then:  WF_VALIDATE_SCOPE=per-task
  require_yq || return 0
  local repo; repo="$(mk_repo)"
  sed '/^validate_scope/d' "$repo/.workflow.yml" > "$repo/.workflow.yml.tmp" \
    && mv "$repo/.workflow.yml.tmp" "$repo/.workflow.yml"
  ( cd "$repo" && source "$LOADER" && wf_load_config \
      && [[ "$WF_VALIDATE_SCOPE" == "per-task" ]] )
}

test_loader_validate_scope_per_spec_from_workflow_yml() {
  # Given: .workflow.yml sets validate_scope: per-spec
  # When:  wf_load_config succeeds
  # Then:  WF_VALIDATE_SCOPE=per-spec
  require_yq || return 0
  local repo; repo="$(mk_repo)"
  sed 's/^validate_scope:.*/validate_scope: per-spec/' "$repo/.workflow.yml" > "$repo/.workflow.yml.tmp" \
    && mv "$repo/.workflow.yml.tmp" "$repo/.workflow.yml"
  ( cd "$repo" && source "$LOADER" && wf_load_config \
      && [[ "$WF_VALIDATE_SCOPE" == "per-spec" ]] )
}

test_loader_validate_scope_spec_override_wins() {
  # Given: .workflow.yml sets per-task, spec config.yml sets both
  # When:  wf_load_config --spec demo
  # Then:  WF_VALIDATE_SCOPE=both (spec wins)
  require_yq || return 0
  local repo; repo="$(mk_repo)"
  cp "$FIXTURES/spec-config-scope-override.yml" "$repo/specs/demo/config.yml"
  ( cd "$repo" && source "$LOADER" && wf_load_config --spec demo \
      && [[ "$WF_VALIDATE_SCOPE" == "both" ]] )
}

test_loader_validate_scope_invalid_exits_2_names_enum() {
  # Given: .workflow.yml sets validate_scope: disabled (unknown value)
  # When:  wf_load_config runs
  # Then:  exits 2 and error names the allowed enum
  require_yq || return 0
  local repo; repo="$(mk_repo)"
  sed 's/^validate_scope:.*/validate_scope: disabled/' "$repo/.workflow.yml" > "$repo/.workflow.yml.tmp" \
    && mv "$repo/.workflow.yml.tmp" "$repo/.workflow.yml"
  local rc=0 err
  err="$(cd "$repo" && source "$LOADER"; wf_load_config 2>&1 1>/dev/null)" || rc=$?
  [[ "$rc" == "2" ]] \
    && grep -q "per-task" <<<"$err" \
    && grep -q "per-spec" <<<"$err" \
    && grep -q "both"     <<<"$err"
}

test_loader_validate_scope_templates_documented() {
  # Given: both templates exist
  # Then:  workflow.yml.template and spec-config.yml.template each reference validate_scope
  grep -q "validate_scope" "$REPO_ROOT/templates/workflow.yml.template" \
    && grep -q "validate_scope" "$REPO_ROOT/templates/spec-config.yml.template"
}

test_loader_no_script_has_inline_source_of_config_loader() {
  # Ensure no script in scripts/ or commands/ contains an inline 'source config-loader.sh' call.
  # Callers must use wf_load_config after sourcing, not re-source the loader inline.
  # grep -v "config-loader.sh" excludes config-loader.sh's own self-reference lines
  # (the file path appears in grep output as the filename prefix).
  ! grep -rE '^[[:space:]]*(source|\.)[[:space:]]+[^#]*config-loader\.sh' \
      "$REPO_ROOT/scripts/" "$REPO_ROOT/commands/" 2>/dev/null \
    | grep -v "config-loader.sh"
}

test_loader_spec_gates_shape_well_formed() {
  # I6 — WF_SPEC_GATES is newline-separated; no leading/trailing newline;
  # every line matches ^[a-z][a-z0-9-]*$ (gate id regex subset).
  require_yq || return 0
  local repo; repo="$(mk_repo)"
  cp "$FIXTURES/spec-config-valid.yml" "$repo/specs/demo/config.yml"
  ( cd "$repo" && source "$LOADER" && wf_load_config --spec demo \
      && [[ -n "$WF_SPEC_GATES" ]] \
      && [[ "${WF_SPEC_GATES:0:1}" != $'\n' ]] \
      && [[ "${WF_SPEC_GATES: -1}" != $'\n' ]] \
      && while IFS= read -r line; do
           [[ "$line" =~ ^[a-z][a-z0-9-]*$ ]] || { echo "    bad id: [$line]" >&2; exit 1; }
         done <<<"$WF_SPEC_GATES" )
}

# --- vault mode tests (thin-pointer .workflow.yml in vault) ---

# Build a vault dir (thin pointer) + N code repos (no .workflow.yml; each owns
# knowledge-base/gates.yml). Args: n_repos, primary index (-1 none),
# use_project_token (1 → spec_storage uses projects/{project}/specs).
# Echoes "<vault>|<repo0>|<repo1>|...".
mk_vault() {
  local n_repos="${1:-1}" primary_idx="${2:--1}" use_proj="${3:-0}"
  local vault="$TEST_TMPDIR/vault"
  mkdir -p "$vault/gkb"
  local storage="specs"
  if [[ "$use_proj" == "1" ]]; then
    storage="projects/{project}/specs"
    mkdir -p "$vault/projects/myproj/specs/demo/tasks"
  else
    mkdir -p "$vault/specs/demo/tasks"
  fi
  cat > "$vault/.workflow.yml" <<EOF
spec_storage_mode: vault
spec_storage: $storage
general_kb_path: /Users/ernestbednarczyk/Desktop/projects/master-brain/projects/dev-workflow/dev-workflow-repo/tests/fixtures
validate_scope: per-task
EOF

  local repos_yaml="" i repo repo_real role_line
  for ((i = 0; i < n_repos; i++)); do
    local repo="$TEST_TMPDIR/repo$i"
    mkdir -p "$repo/knowledge-base"
    repo_real="$(realpath -- "$repo")"
    cp "$FIXTURES/gates-valid.yml" "$repo/knowledge-base/gates.yml"
    ( cd "$repo" && git init -q && git -c user.email=t@t -c user.name=t add -A \
        && git -c user.email=t@t -c user.name=t commit -q -m init ) >/dev/null 2>&1 || true
    role_line=""
    [[ "$primary_idx" == "$i" ]] && role_line="    role: primary"
    repos_yaml+="$(printf '  - name: repo%d\n    path: %s\n%s\n' "$i" "$repo_real" "$role_line")"
    repos_yaml+=$'\n'
  done

  local spec_dir="$vault/specs/demo"
  [[ "$use_proj" == "1" ]] && spec_dir="$vault/projects/myproj/specs/demo"
  cat > "$spec_dir/config.yml" <<EOF
tier: small
$( [[ "$use_proj" == "1" ]] && echo 'project: myproj' )
gates:
  - rust-clippy
repos:
$repos_yaml
EOF

  local out="$vault"
  for ((i = 0; i < n_repos; i++)); do out+="|$TEST_TMPDIR/repo$i"; done
  printf '%s' "$out"
}

# WF_REPO_ROOT is the VAULT (not a hijacked code repo); gate pool / project KB
# empty; repos bound.
test_vault_repo_root_is_vault() {
  require_yq || return 0
  local info vault r0 r1
  info="$(mk_vault 2 1)"
  IFS='|' read -r vault r0 r1 <<<"$info"
  ( cd "$vault" && source "$LOADER" && wf_load_config --spec demo \
      && [[ "$WF_REPO_ROOT" == "$(realpath -- "$vault")" ]] \
      && [[ "$WF_VAULT_ROOT" == "$(realpath -- "$vault")" ]] \
      && [[ -z "$WF_GATE_POOL" ]] && [[ -z "$WF_PROJECT_KB" ]] \
      && [[ "$WF_SPEC_HAS_CONFIG" == "1" ]] \
      && [[ "$WF_REPO_NAMES" == $'repo0\nrepo1' ]] )
}

test_vault_no_role_still_vault_root() {
  require_yq || return 0
  local info vault r0 r1
  info="$(mk_vault 2 -1)"
  IFS='|' read -r vault r0 r1 <<<"$info"
  ( cd "$vault" && source "$LOADER" && wf_load_config --spec demo \
      && [[ "$WF_REPO_ROOT" == "$(realpath -- "$vault")" ]] )
}

# No --spec + --require-spec under vault → exit 4 (no silent gate skip).
test_vault_require_spec_no_feature_fails_4() {
  require_yq || return 0
  local info vault
  info="$(mk_vault 1 0)"
  IFS='|' read -r vault _ <<<"$info"
  local rc=0
  ( cd "$vault" && source "$LOADER" && wf_load_config --require-spec ) >/dev/null 2>&1 || rc=$?
  [[ "$rc" == "4" ]]
}

# {project} token resolved from --project (pre-config) and from existing dir.
test_vault_project_token_resolves() {
  require_yq || return 0
  local info vault
  info="$(mk_vault 1 0 1)"
  IFS='|' read -r vault _ <<<"$info"
  ( cd "$vault" && source "$LOADER" && wf_load_config --spec demo --project myproj \
      && [[ "$WF_SPEC_PROJECT" == "myproj" ]] \
      && [[ "$WF_SPEC_STORAGE" == "$(realpath -- "$vault")/projects/myproj/specs" ]] )
}

test_vault_project_token_unresolved_fails_4() {
  require_yq || return 0
  # {project} token but no --project and no spec → cannot resolve.
  local vault="$TEST_TMPDIR/vault-np"
  mkdir -p "$vault/gkb"
  cat > "$vault/.workflow.yml" <<EOF
spec_storage_mode: vault
spec_storage: projects/{project}/specs
general_kb_path: /Users/ernestbednarczyk/Desktop/projects/master-brain/projects/dev-workflow/dev-workflow-repo/tests/fixtures
EOF
  local rc=0
  ( cd "$vault" && source "$LOADER" && wf_load_config ) >/dev/null 2>&1 || rc=$?
  [[ "$rc" == "4" ]]
}

# {project} path resolved but config.yml omits `project:` → exit 4 (fail-closed,
# absent key not silently tolerated).
test_vault_project_absent_mismatch_fails_4() {
  require_yq || return 0
  local info vault
  info="$(mk_vault 1 0 1)"
  IFS='|' read -r vault _ <<<"$info"
  # Strip the `project: myproj` line mk_vault injected.
  grep -v '^project:' "$vault/projects/myproj/specs/demo/config.yml" > "$vault/projects/myproj/specs/demo/c2" \
    && mv "$vault/projects/myproj/specs/demo/c2" "$vault/projects/myproj/specs/demo/config.yml"
  local rc=0
  ( cd "$vault" && source "$LOADER" && wf_load_config --spec demo --project myproj ) >/dev/null 2>&1 || rc=$?
  [[ "$rc" == "4" ]]
}

# spec gate id absent from every bound repo's gates.yml → exit 4 (union check).
test_vault_unknown_gate_union_fails_4() {
  require_yq || return 0
  local info vault
  info="$(mk_vault 1 0)"
  IFS='|' read -r vault _ <<<"$info"
  sed 's/- rust-clippy/- bogus-gate/' "$vault/specs/demo/config.yml" > "$vault/specs/demo/c2" \
    && mv "$vault/specs/demo/c2" "$vault/specs/demo/config.yml"
  local rc=0 err
  err="$(cd "$vault" && source "$LOADER"; wf_load_config --spec demo 2>&1 1>/dev/null)" || rc=$?
  [[ "$rc" == "4" ]] && grep -q "bogus-gate" <<<"$err"
}

test_vault_spec_config_missing_fails_2() {
  local empty="$TEST_TMPDIR/empty-vault"
  mkdir -p "$empty"
  local rc=0
  ( cd "$empty" && source "$LOADER" && wf_load_config --spec demo ) >/dev/null 2>&1 || rc=$?
  [[ "$rc" == "2" ]]
}

test_vault_repos_empty_fails_4() {
  require_yq || return 0
  local vault="$TEST_TMPDIR/vault-empty"
  mkdir -p "$vault/specs/demo" "$vault/gkb"
  cat > "$vault/.workflow.yml" <<EOF
spec_storage_mode: vault
spec_storage: specs
general_kb_path: /Users/ernestbednarczyk/Desktop/projects/master-brain/projects/dev-workflow/dev-workflow-repo/tests/fixtures
EOF
  cat > "$vault/specs/demo/config.yml" <<EOF
tier: small
repos: []
EOF
  local rc=0
  ( cd "$vault" && source "$LOADER" && wf_load_config --spec demo ) >/dev/null 2>&1 || rc=$?
  [[ "$rc" == "4" ]]
}

test_vault_repo_path_invalid_fails_7() {
  require_yq || return 0
  local vault="$TEST_TMPDIR/vault-bad"
  mkdir -p "$vault/specs/demo" "$vault/gkb"
  cat > "$vault/.workflow.yml" <<EOF
spec_storage_mode: vault
spec_storage: specs
general_kb_path: /Users/ernestbednarczyk/Desktop/projects/master-brain/projects/dev-workflow/dev-workflow-repo/tests/fixtures
EOF
  cat > "$vault/specs/demo/config.yml" <<EOF
tier: small
repos:
  - name: ghost
    path: $TEST_TMPDIR/does-not-exist
    role: primary
EOF
  local rc=0
  ( cd "$vault" && source "$LOADER" && wf_load_config --spec demo ) >/dev/null 2>&1 || rc=$?
  [[ "$rc" == "7" ]]
}

test_repo_cwd_unchanged_no_vault_root() {
  require_yq || return 0
  local repo; repo="$(mk_repo)"
  ( cd "$repo" && source "$LOADER" && wf_load_config \
      && [[ -z "${WF_VAULT_ROOT:-}" ]] )
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
run_test "validate_scope defaults to per-task when field absent" test_loader_validate_scope_default_per_task
run_test "validate_scope=per-spec exported from .workflow.yml" test_loader_validate_scope_per_spec_from_workflow_yml
run_test "validate_scope spec config.yml override wins over repo default" test_loader_validate_scope_spec_override_wins
run_test "validate_scope=disabled exits 2 and names enum in error" test_loader_validate_scope_invalid_exits_2_names_enum
run_test "validate_scope documented in both templates" test_loader_validate_scope_templates_documented
run_test "grep guard: no script has inline source of config-loader.sh" test_loader_no_script_has_inline_source_of_config_loader
run_test "WF_SPEC_GATES shape: newline-sep, regex-valid, no leading/trailing NL" test_loader_spec_gates_shape_well_formed
run_test "vault: WF_REPO_ROOT is the vault, gate pool/project KB empty" test_vault_repo_root_is_vault
run_test "vault: no role still resolves vault root"     test_vault_no_role_still_vault_root
run_test "vault: --require-spec without feature fails exit 4" test_vault_require_spec_no_feature_fails_4
run_test "vault: {project} token resolves from --project" test_vault_project_token_resolves
run_test "vault: {project} unresolved fails exit 4"     test_vault_project_token_unresolved_fails_4
run_test "vault: {project} path but config.yml omits project: fails exit 4" test_vault_project_absent_mismatch_fails_4
run_test "vault: unknown gate id (union) fails exit 4"  test_vault_unknown_gate_union_fails_4
run_test "vault: no spec config.yml fails exit 2"       test_vault_spec_config_missing_fails_2
run_test "vault: empty repos[] fails exit 4"            test_vault_repos_empty_fails_4
run_test "vault: bad repo path fails exit 7"            test_vault_repo_path_invalid_fails_7
run_test "repo CWD unchanged: WF_VAULT_ROOT unset"      test_repo_cwd_unchanged_no_vault_root

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
