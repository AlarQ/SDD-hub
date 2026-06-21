#!/usr/bin/env bash
# test-select-agents.sh — Tests for scripts/select-agents.sh.
# Deterministic keyword -> flag mapping. Given/When/Then; no framework.
# shellcheck disable=SC1090,SC1091
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SUT="$REPO_ROOT/scripts/select-agents.sh"

PASS=0; FAIL=0; TMP=""

setup() { TMP="$(mktemp -d)"; }
teardown() { [[ -n "$TMP" && -d "$TMP" ]] && rm -rf "$TMP"; TMP=""; }

# write_corpus <text> -> echoes path to a file holding <text>
write_corpus() { local p="$TMP/corpus.md"; printf '%s\n' "$1" >"$p"; printf '%s' "$p"; }

# assert_flag <output> <KEY> <expected>
assert_flag() {
  local out="$1" key="$2" want="$3" got
  got="$(printf '%s\n' "$out" | grep -E "^$key=" | head -1 | cut -d= -f2-)"
  if [[ "$got" == "$want" ]]; then return 0; fi
  echo "    expected $key=$want got $key=$got" >&2; return 1
}

run_test() {
  local name="$1"; shift
  setup
  if ( set +e; "$@" ); then echo "  PASS: $name"; PASS=$((PASS + 1));
  else echo "  FAIL: $name"; FAIL=$((FAIL + 1)); fi
  teardown
}

t_backend_only() {
  local f out; f="$(write_corpus 'The service uses a server queue and cache backend.')"
  out="$(bash "$SUT" "$f")"
  assert_flag "$out" WF_SPAWN_BACKEND 1 || return 1
  assert_flag "$out" WF_SPAWN_UX 0 || return 1
  assert_flag "$out" WF_SPAWN_AI 0 || return 1
  assert_flag "$out" WF_TIER_FORCED '' || return 1
}

t_ui_pairs_ux() {
  local f out; f="$(write_corpus 'A responsive dashboard with a modal component.')"
  out="$(bash "$SUT" "$f")"
  assert_flag "$out" WF_SPAWN_UX 1 || return 1
  assert_flag "$out" WF_SPAWN_UI 1 || return 1
  assert_flag "$out" WF_SPAWN_BACKEND 0 || return 1
}

t_ai() {
  local f out; f="$(write_corpus 'Run LLM inference over the dataset.')"
  out="$(bash "$SUT" "$f")"
  assert_flag "$out" WF_SPAWN_AI 1 || return 1
}

t_tier_force() {
  local f out; f="$(write_corpus 'Adds auth and crypto handling.')"
  out="$(bash "$SUT" "$f")"
  assert_flag "$out" WF_TIER_FORCED medium || return 1
}

t_none() {
  local f out; f="$(write_corpus 'Tweak the copy in the welcome message.')"
  out="$(bash "$SUT" "$f")"
  assert_flag "$out" WF_SPAWN_BACKEND 0 || return 1
  assert_flag "$out" WF_SPAWN_UX 0 || return 1
  assert_flag "$out" WF_SPAWN_AI 0 || return 1
  assert_flag "$out" WF_TIER_FORCED '' || return 1
}

t_word_boundary() {
  # 'rapidly' contains 'api', 'adblock' contains 'db' — must NOT match.
  local f out; f="$(write_corpus 'We move rapidly past the adblock notice.')"
  out="$(bash "$SUT" "$f")"
  assert_flag "$out" WF_SPAWN_BACKEND 0 || return 1
  assert_flag "$out" WF_TIER_FORCED '' || return 1
}

t_multi() {
  # 'API' is in both the backend table and the tier-force table.
  local f out; f="$(write_corpus 'A REST API backed by a database, a frontend form, and an LLM.')"
  out="$(bash "$SUT" "$f")"
  assert_flag "$out" WF_SPAWN_BACKEND 1 || return 1
  assert_flag "$out" WF_SPAWN_UX 1 || return 1
  assert_flag "$out" WF_SPAWN_UI 1 || return 1   # mirrors UX
  assert_flag "$out" WF_SPAWN_AI 1 || return 1
  assert_flag "$out" WF_TIER_FORCED medium || return 1
}

t_plurals() {
  # Common plurals must still match (prior freehand grep caught them).
  local f out; f="$(write_corpus 'Adds REST APIs, new endpoints, and dashboards.')"
  out="$(bash "$SUT" "$f")"
  assert_flag "$out" WF_SPAWN_BACKEND 1 || return 1
  assert_flag "$out" WF_SPAWN_UX 1 || return 1
}

t_missing_file_ok() {
  local out; out="$(bash "$SUT" "$TMP/nope.md" 2>/dev/null)"
  assert_flag "$out" WF_SPAWN_BACKEND 0 || return 1
  assert_flag "$out" WF_TIER_FORCED '' || return 1
}

echo "select-agents.sh tests"
run_test "backend-only keywords" t_backend_only
run_test "UI keyword pairs UX+UI" t_ui_pairs_ux
run_test "AI keywords" t_ai
run_test "tier-force keywords" t_tier_force
run_test "no keywords" t_none
run_test "word boundary (no substring match)" t_word_boundary
run_test "multiple tables" t_multi
run_test "common plurals match" t_plurals
run_test "missing file tolerated" t_missing_file_ok

echo "-----"
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
