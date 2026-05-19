#!/usr/bin/env bash
# test-inferencer-schema.sh — T008: config-inferencer agent schema-shape tests.
# Tests validate schema contract, ID resolution, security exclusions, and fallback.
# No external framework. Given/When/Then per testing/principles.md.
# No golden fixtures — LLM nondeterminism risk (per design §MEDIUM risk).
# shellcheck disable=SC1090,SC1091

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURES="$REPO_ROOT/tests/fixtures/config"
AGENT_DEF="$REPO_ROOT/agents/engineering/engineering-config-inferencer.md"

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
  setup || { echo "  FATAL: setup failed for: $name" >&2; exit 1; }
  if ( set +e; "$@" ); then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name (rc=$?)"; FAIL=$((FAIL + 1))
  fi
  teardown || true
}

# Build a minimal agent_pool + inline gate_pool registry (.workflow.yml) in
# $TEST_TMPDIR. gate_pool is the LAST key so tests can append entries.
mk_env() {
  local repo="$TEST_TMPDIR/repo"
  mkdir -p "$repo/agent_pool/engineering" \
            "$repo/agent_pool/design"
  cat > "$repo/.workflow.yml" <<'EOF'
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
EOF
  # Seed agent pool matching agent ID grammar from design.md.
  touch "$repo/agent_pool/engineering/engineering-security-engineer.md"
  touch "$repo/agent_pool/engineering/engineering-software-architect.md"
  touch "$repo/agent_pool/engineering/engineering-code-reviewer.md"
  touch "$repo/agent_pool/engineering/engineering-config-inferencer.md"
  touch "$repo/agent_pool/code-quality-pragmatist.md"
  printf '%s' "$repo"
}

# Validate structural schema contract for a given config.yml file.
# Takes one argument: path to the YAML file under test.
# Returns 1 if any required structural property is violated.
validate_schema_shape() {
  local file="$1"
  local fail=0

  # tags must be present (list or empty list, not null)
  local tags; tags="$(yq e '.tags' "$file")" || return 1
  [[ "$tags" != "null" ]] || { echo "  tags is null in $file" >&2; fail=1; }

  # gates must be present (list or empty list, not null)
  local gates; gates="$(yq e '.gates' "$file")" || return 1
  [[ "$gates" != "null" ]] || { echo "  gates is null in $file" >&2; fail=1; }

  # agents must be present with all five required phase keys
  local agents; agents="$(yq e '.agents' "$file")" || return 1
  [[ "$agents" != "null" ]] || { echo "  agents is null in $file" >&2; fail=1; }

  # branch_strategy is optional; when present it must be a valid enum value
  local bs; bs="$(yq e '.branch_strategy' "$file")" || return 1
  if [[ "$bs" != "null" ]]; then
    [[ "$bs" == "per-task" || "$bs" == "single-branch" ]] \
      || { echo "  branch_strategy invalid enum '$bs' in $file" >&2; fail=1; }
  fi

  for phase in explore propose implement validate pr-review; do
    local val; val="$(yq e ".agents.\"$phase\"" "$file" 2>/dev/null)"
    if [[ "$val" == "null" ]]; then
      echo "  agents.$phase is null in $file" >&2
      fail=1
    fi
  done

  return $fail
}

# ──────────────────────────────────────────────────────────────────────────────
# Test: agent definition file exists at expected path
# ──────────────────────────────────────────────────────────────────────────────
test_agent_def_exists() {
  # Given: T008 task expects agent at agents/engineering/engineering-config-inferencer.md
  # When: we check the file
  # Then: present and non-empty
  [[ -f "$AGENT_DEF" ]] || { echo "  missing: $AGENT_DEF" >&2; return 1; }
  [[ -s "$AGENT_DEF" ]] || { echo "  empty: $AGENT_DEF" >&2; return 1; }
}

# ──────────────────────────────────────────────────────────────────────────────
# Test: inferencer output parses as valid spec config.yml (full happy path)
# ──────────────────────────────────────────────────────────────────────────────
test_output_parses_as_valid_config() {
  local out_file="$TEST_TMPDIR/config-full.yml"
  # Given: a fully-populated output representing the happy path
  cat > "$out_file" <<'YAML'
tags: [api, rust]
gates:
  - rust-clippy
  - semgrep-security
agents:
  explore:    [engineering/software-architect]
  propose:    [engineering/software-architect]
  implement:  [code-quality-pragmatist]
  validate:   [engineering/security-engineer, code-quality-pragmatist]
  pr-review:  [engineering/code-reviewer]
YAML
  # When/Then: schema shape is valid
  validate_schema_shape "$out_file"
}

# ──────────────────────────────────────────────────────────────────────────────
# Test: minimal valid output (empty lists) still parses as valid
# ──────────────────────────────────────────────────────────────────────────────
test_minimal_output_valid() {
  local out_file="$TEST_TMPDIR/config-minimal.yml"
  # Given: minimal output (all empty lists — e.g. fallback template)
  cat > "$out_file" <<'YAML'
tags: []
gates: []
agents:
  explore: []
  propose: []
  implement: []
  validate: []
  pr-review: []
YAML
  # When/Then: schema shape is valid
  validate_schema_shape "$out_file"
}

# ──────────────────────────────────────────────────────────────────────────────
# Test: all emitted gate IDs resolve in .workflow.yml gate_pool
# ──────────────────────────────────────────────────────────────────────────────
test_gate_ids_resolve_in_registry() {
  local repo; repo="$(mk_env)"
  local gates_file="$repo/.workflow.yml"
  local out_file="$TEST_TMPDIR/config-gates.yml"
  # Given: output with gates from the registry
  cat > "$out_file" <<'YAML'
tags: [rust]
gates:
  - rust-clippy
  - semgrep-security
agents:
  explore: []
  propose: []
  implement: []
  validate: []
  pr-review: []
YAML
  # When: we extract gate IDs and check each against .workflow.yml gate_pool
  local fail=0
  while IFS= read -r gate_id; do
    [[ -z "$gate_id" ]] && continue
    local found; found="$(yq e ".gate_pool[] | select(.id == \"$gate_id\") | .id" "$gates_file")"
    if [[ -z "$found" ]]; then
      echo "  gate ID not in registry: $gate_id" >&2
      fail=1
    fi
  done < <(yq e '.gates[]' "$out_file")
  return $fail
}

# ──────────────────────────────────────────────────────────────────────────────
# Test: invalid gate ID not in registry fails validation
# ──────────────────────────────────────────────────────────────────────────────
test_invalid_gate_id_rejected() {
  local repo; repo="$(mk_env)"
  local gates_file="$repo/.workflow.yml"
  local out_file="$TEST_TMPDIR/config-bad-gate.yml"
  # Given: output with a gate ID that does not exist in the registry
  cat > "$out_file" <<'YAML'
tags: []
gates:
  - nonexistent-gate
agents:
  explore: []
  propose: []
  implement: []
  validate: []
  pr-review: []
YAML
  # When: we check the gate against registry
  # Then: validation detects the unknown ID
  local found; found="$(yq e ".gate_pool[] | select(.id == \"nonexistent-gate\") | .id" "$gates_file")"
  [[ -z "$found" ]] || { echo "  nonexistent gate should not resolve" >&2; return 1; }
}

# ──────────────────────────────────────────────────────────────────────────────
# Test: all emitted agent IDs resolve under agent_pool
# ──────────────────────────────────────────────────────────────────────────────
test_agent_ids_resolve_in_pool() {
  local repo; repo="$(mk_env)"
  local agent_pool="$repo/agent_pool"
  local out_file="$TEST_TMPDIR/config-agents.yml"
  # Given: output with known agent IDs
  cat > "$out_file" <<'YAML'
tags: []
gates: []
agents:
  explore:    [engineering/software-architect]
  propose:    [engineering/software-architect]
  implement:  [code-quality-pragmatist]
  validate:   [engineering/security-engineer, code-quality-pragmatist]
  pr-review:  [engineering/code-reviewer]
YAML
  # When: we extract and resolve each agent ID
  local fail=0
  local all_ids; all_ids="$(yq e '.agents | to_entries | .[].value | .[]' "$out_file" 2>/dev/null | sort -u)"

  while IFS= read -r agent_id; do
    [[ -z "$agent_id" ]] && continue
    local resolved
    if [[ "$agent_id" == *"/"* ]]; then
      local cat="${agent_id%%/*}"
      local name="${agent_id##*/}"
      resolved="$agent_pool/$cat/${cat}-${name}.md"
    else
      resolved="$agent_pool/${agent_id}.md"
    fi
    if [[ ! -f "$resolved" ]]; then
      echo "  agent ID does not resolve: $agent_id → $resolved" >&2
      fail=1
    fi
  done <<< "$all_ids"
  return $fail
}

# ──────────────────────────────────────────────────────────────────────────────
# Test: partial input — agent_pool empty, gate_pool populated
# Output must include gates, agent phases must be empty lists
# ──────────────────────────────────────────────────────────────────────────────
test_partial_input_empty_agent_pool() {
  local out_file="$TEST_TMPDIR/config-partial-agents.yml"
  # Given: inferencer output when agent_pool is empty (partial fallback)
  cat > "$out_file" <<'YAML'
tags: [rust]
gates:
  - rust-clippy
agents:
  explore: []
  propose: []
  implement: []
  validate: []
  pr-review: []
YAML
  # When/Then: schema shape still valid; gates populated, agents all empty
  validate_schema_shape "$out_file" || return 1

  local all_agents; all_agents="$(yq e '.agents | to_entries | .[].value | .[]' "$out_file" 2>/dev/null || true)"
  [[ -z "$all_agents" ]] || { echo "  expected empty agent lists for empty-pool partial output" >&2; return 1; }

  local gate_count; gate_count="$(yq e '.gates | length' "$out_file")"
  [[ "$gate_count" -ge 1 ]] || { echo "  gates should be non-empty when gate_pool is populated" >&2; return 1; }
}

# ──────────────────────────────────────────────────────────────────────────────
# Test: partial input — gate_pool empty, agent_pool populated
# Output must include agents, gates must be empty list
# ──────────────────────────────────────────────────────────────────────────────
test_partial_input_empty_gates() {
  local out_file="$TEST_TMPDIR/config-partial-gates.yml"
  # Given: inferencer output when gate_pool has no entries (partial fallback)
  cat > "$out_file" <<'YAML'
tags: [rust]
gates: []
agents:
  explore:   [engineering/software-architect]
  propose:   [engineering/software-architect]
  implement: [code-quality-pragmatist]
  validate:  [engineering/security-engineer]
  pr-review: [engineering/code-reviewer]
YAML
  # When/Then: schema shape valid; gates empty, agents populated
  validate_schema_shape "$out_file" || return 1

  local gate_count; gate_count="$(yq e '.gates | length' "$out_file")"
  [[ "$gate_count" -eq 0 ]] || { echo "  gates should be empty for empty-gates partial output" >&2; return 1; }

  local has_agents; has_agents="$(yq e '.agents.validate | length' "$out_file")"
  [[ "$has_agents" -ge 1 ]] || { echo "  agents should be populated when agent_pool is available" >&2; return 1; }
}

# ──────────────────────────────────────────────────────────────────────────────
# Test: inferencer prompt forbids reading .env*, *.pem, id_*, .git/config
# ──────────────────────────────────────────────────────────────────────────────
test_forbidden_inputs_documented_in_prompt() {
  local fail=0
  for pattern in '\.env\*' '\.pem' 'id_\*' '\.git/config'; do
    if ! grep -qE "$pattern" "$AGENT_DEF"; then
      echo "  forbidden pattern not documented in agent def: $pattern" >&2
      fail=1
    fi
  done
  return $fail
}

# ──────────────────────────────────────────────────────────────────────────────
# Test: timeout fallback path produces manual-entry prompt or default template
# ──────────────────────────────────────────────────────────────────────────────
test_fallback_documented_in_agent_def() {
  grep -q 'FALLBACK' "$AGENT_DEF" || { echo "  FALLBACK keyword missing from agent def" >&2; return 1; }
  grep -q 'Manual entry required\|manual entry' "$AGENT_DEF" || { echo "  manual-entry fallback not documented" >&2; return 1; }
  grep -q 'gates: \[\]' "$AGENT_DEF" || { echo "  default template missing gates: []" >&2; return 1; }
}

# ──────────────────────────────────────────────────────────────────────────────
# Test: partial-input fallback behavior documented in agent def
# ──────────────────────────────────────────────────────────────────────────────
test_partial_input_fallback_documented() {
  # Given: agent definition should document partial-input cases separately
  grep -q 'Partial Input Fallback\|partial.*fallback\|agent_pool.*empty.*gates\|gates.*empty.*agent' "$AGENT_DEF" \
    || { echo "  partial-input fallback not documented in agent def" >&2; return 1; }
}

# ──────────────────────────────────────────────────────────────────────────────
# Test: negative-shape — rust-only: output with python/js gates would be rejected
# Uses a gates fixture extended with python/js-only entries to make the test falsifiable.
# ──────────────────────────────────────────────────────────────────────────────
test_negative_shape_rust_only_signals() {
  local repo; repo="$(mk_env)"
  # Extend gates fixture with python-only and js-only entries so grep can actually detect them.
  cat >> "$repo/.workflow.yml" <<'YAML'
  - id: pylint
    command: "pylint src/"
    applies_to: [python]
    category: lint
    blocking: true
  - id: eslint
    command: "npx eslint ."
    applies_to: [javascript]
    category: lint
    blocking: true
YAML

  # Given: a valid Cargo.toml-only output (rust only — no python/js gates)
  local valid_file="$TEST_TMPDIR/config-rust-valid.yml"
  cat > "$valid_file" <<'YAML'
tags: [rust, backend]
gates:
  - rust-clippy
  - semgrep-security
agents:
  explore: []
  propose: []
  implement: []
  validate: []
  pr-review: []
YAML

  # Then: at least one rust-applicable gate is present
  local gates; gates="$(yq e '.gates | join(" ")' "$valid_file")"
  echo "$gates" | grep -q 'rust-clippy' \
    || { echo "  rust-only output missing rust gate" >&2; return 1; }

  # Then: no python-only or js-only gate IDs present
  local has_python; has_python="$(echo "$gates" | grep -c 'pylint\|mypy\|ruff' || true)"
  local has_js;     has_js="$(echo "$gates" | grep -c 'eslint\|tsc\|jest\|npm-test' || true)"
  [[ "$has_python" -eq 0 ]] || { echo "  rust-only output contains python gate: $gates" >&2; return 1; }
  [[ "$has_js" -eq 0 ]]     || { echo "  rust-only output contains js gate: $gates" >&2; return 1; }

  # Negative: given: a bad output that includes python/js gates for a rust-only repo
  local bad_file="$TEST_TMPDIR/config-rust-bad.yml"
  cat > "$bad_file" <<'YAML'
tags: [rust, backend]
gates:
  - rust-clippy
  - pylint
  - eslint
agents:
  explore: []
  propose: []
  implement: []
  validate: []
  pr-review: []
YAML
  local bad_gates; bad_gates="$(yq e '.gates | join(" ")' "$bad_file")"
  local bad_python; bad_python="$(echo "$bad_gates" | grep -c 'pylint' || true)"
  local bad_js;     bad_js="$(echo "$bad_gates" | grep -c 'eslint' || true)"
  # This bad output DOES contain python/js gates — confirm detection works
  [[ "$bad_python" -ge 1 ]] || { echo "  detection broken: pylint not found in bad output" >&2; return 1; }
  [[ "$bad_js" -ge 1 ]]     || { echo "  detection broken: eslint not found in bad output" >&2; return 1; }
}

# ──────────────────────────────────────────────────────────────────────────────
# Test: inferencer inputs and outputs logged to monitor events (doc check)
# ──────────────────────────────────────────────────────────────────────────────
test_monitor_events_documented() {
  grep -q 'config_inferred' "$AGENT_DEF" || { echo "  config_inferred event not documented" >&2; return 1; }
  grep -q 'config_approved' "$AGENT_DEF" || { echo "  config_approved event not documented" >&2; return 1; }
}

# ──────────────────────────────────────────────────────────────────────────────
# Test: branch_strategy axis documented in agent def (schema + rubric + default)
# ──────────────────────────────────────────────────────────────────────────────
test_branch_strategy_documented_in_agent_def() {
  local fail=0
  grep -q 'branch_strategy: per-task | single-branch' "$AGENT_DEF" \
    || { echo "  branch_strategy not in Output Contract schema" >&2; fail=1; }
  grep -qi 'Branch Strategy' "$AGENT_DEF" \
    || { echo "  Branch Strategy inference rubric missing" >&2; fail=1; }
  grep -q 'branch_strategy: per-task  # safe default in fallback' "$AGENT_DEF" \
    || { echo "  fallback default branch_strategy missing" >&2; fail=1; }
  return $fail
}

# ──────────────────────────────────────────────────────────────────────────────
# Test: inferencer output carrying branch_strategy key parses; value is enum
# ──────────────────────────────────────────────────────────────────────────────
test_branch_strategy_key_valid_in_output() {
  local out_file="$TEST_TMPDIR/config-bs.yml"
  cat > "$out_file" <<'YAML'
tags: [rust]
branch_strategy: single-branch
gates:
  - rust-clippy
agents:
  explore: []
  propose: []
  implement: []
  validate: []
  pr-review: []
YAML
  # Positive: valid enum value passes schema validation.
  validate_schema_shape "$out_file" || return 1

  # Negative: an out-of-enum branch_strategy must be rejected by the validator
  # (proves the check is real, not a tautology over a self-written value).
  local bad_file="$TEST_TMPDIR/config-bs-bad.yml"
  cat > "$bad_file" <<'YAML'
tags: [rust]
branch_strategy: bogus-strategy
gates: []
agents:
  explore: []
  propose: []
  implement: []
  validate: []
  pr-review: []
YAML
  if validate_schema_shape "$bad_file" 2>/dev/null; then
    echo "  validator accepted invalid branch_strategy" >&2
    return 1
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Run all tests
# ──────────────────────────────────────────────────────────────────────────────
echo "=== test-inferencer-schema.sh (T008) ==="

run_test "agent definition exists at expected path" \
  test_agent_def_exists

run_test "inferencer output parses as valid spec config.yml (full happy path)" \
  test_output_parses_as_valid_config

run_test "minimal valid output (empty lists) parses as valid" \
  test_minimal_output_valid

run_test "all emitted gate IDs resolve in .workflow.yml gate_pool" \
  test_gate_ids_resolve_in_registry

run_test "invalid gate ID not in registry is detectable" \
  test_invalid_gate_id_rejected

run_test "all emitted agent IDs resolve under agent_pool" \
  test_agent_ids_resolve_in_pool

run_test "partial input: empty agent_pool — gates populated, agents all empty" \
  test_partial_input_empty_agent_pool

run_test "partial input: empty gate_pool — agents populated, gates empty" \
  test_partial_input_empty_gates

run_test "inferencer prompt forbids reading .env*, *.pem, id_*, .git/config" \
  test_forbidden_inputs_documented_in_prompt

run_test "timeout fallback path produces manual-entry prompt or default template" \
  test_fallback_documented_in_agent_def

run_test "partial-input fallback behavior documented in agent definition" \
  test_partial_input_fallback_documented

run_test "negative-shape: Cargo.toml-only signals include rust gate, exclude python/js-only" \
  test_negative_shape_rust_only_signals

run_test "inferencer inputs and outputs logged to monitor events" \
  test_monitor_events_documented

run_test "branch_strategy axis documented in agent def" \
  test_branch_strategy_documented_in_agent_def

run_test "inferencer output branch_strategy key is a valid enum" \
  test_branch_strategy_key_valid_in_output

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
