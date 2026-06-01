#!/usr/bin/env bash
# test-agents-install.sh — Tests for install_claude_code in agents/scripts/install.sh.
#
# Bug under test: install_claude_code flattens per-category agent files into a
# single ~/.claude/agents/ dir via `cp "$f" "$dest/"`. Two categories holding a
# same-named agent (design/analyst.md, engineering/analyst.md) both resolve to
# $dest/analyst.md — the later category silently OVERWRITES the earlier file
# (data loss), and `count` increments on the clobbering copy too, over-reporting
# the number of surviving agents. The fix is a collision guard: skip + `err` on a
# repeated destination basename, and only count first-writes.
#
# Isolation approach: install.sh has NO source guard — it ends with `main "$@"`,
# so sourcing it would trigger a full install. Following the repo idiom in
# test-pre-commit-hook.sh (sed-extract the code under test into a sourceable
# snippet), we extract ONLY the install_claude_code function definition into a
# tmp snippet, then source it in a subshell where REPO_ROOT/HOME point at
# fixtures and `ok`/`err` are stubbed to append their messages to log files. This
# drives the EXACT function body in isolation without running main or the other
# installers.
#
# Given/When/Then per testing/principles.md. No external test framework.
#
# SC1090/SC1091: the extracted function snippet is sourced from a runtime path.
# SC2329: the ok()/err() stubs are invoked INDIRECTLY by the sourced
# install_claude_code, so shellcheck cannot see the call sites.
# shellcheck disable=SC1090,SC1091,SC2329

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_SH="$REPO_ROOT/agents/scripts/install.sh"

PASS=0; FAIL=0; TEST_TMPDIR=""

setup() {
  TEST_TMPDIR="$(mktemp -d)"
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

# Extract just the install_claude_code function definition (from its opening
# `install_claude_code() {` line to the first line that is a lone `}` at column 0)
# into a sourceable snippet — the EXACT code under test, no main, no siblings.
extract_install_fn() {
  local out="$1"
  sed -n '/^install_claude_code() {/,/^}/p' "$INSTALL_SH" > "$out"
}

# Build a fake REPO_ROOT with two category dirs sharing a same-named agent plus a
# unique agent. Bodies differ so we can tell which file survived. Echoes the
# fixture repo path.
#   design/analyst.md        -> body "DESIGN-ANALYST"  (first category in loop)
#   engineering/analyst.md   -> body "ENGINEERING-ANALYST" (later -> would clobber)
#   engineering/architect.md -> body "ENGINEERING-ARCHITECT" (unique)
mk_repo() {
  local repo="$TEST_TMPDIR/repo"
  mkdir -p "$repo/design" "$repo/engineering"
  printf -- '---\nname: analyst\n---\nDESIGN-ANALYST\n'        > "$repo/design/analyst.md"
  printf -- '---\nname: analyst\n---\nENGINEERING-ANALYST\n'   > "$repo/engineering/analyst.md"
  printf -- '---\nname: architect\n---\nENGINEERING-ARCHITECT\n' > "$repo/engineering/architect.md"
  printf '%s' "$repo"
}

# Run install_claude_code against a fixture repo in an isolated subshell.
# HOME is pointed at a tmp dir so $dest == $HOME/.claude/agents. `ok`/`err` are
# stubbed to append their messages to $TEST_TMPDIR/ok.log / err.log so the test
# can assert on reported count and on conflict reporting. Echoes nothing; side
# effects land under $TEST_TMPDIR.
run_install() {
  local repo="$1"
  local snippet="$TEST_TMPDIR/fn.sh"
  extract_install_fn "$snippet"
  (
    set -uo pipefail
    REPO_ROOT="$repo"
    HOME="$TEST_TMPDIR/home"
    ok()  { printf '%s\n' "$*" >> "$TEST_TMPDIR/ok.log"; }
    err() { printf '%s\n' "$*" >> "$TEST_TMPDIR/err.log"; }
    # shellcheck source=/dev/null
    source "$snippet"
    install_claude_code
  )
}

DEST() { printf '%s' "$TEST_TMPDIR/home/.claude/agents"; }

# --- collision guard behavior (RED against current code) ---

# The first category's file (design/analyst.md) must be PRESERVED — the later
# engineering/analyst.md must NOT overwrite it. Current code clobbers -> RED.
test_first_seen_basename_is_preserved() {
  local repo dest body
  repo="$(mk_repo)"
  run_install "$repo"
  dest="$(DEST)"
  [[ -f "$dest/analyst.md" ]] || { echo "    analyst.md missing entirely" >&2; return 1; }
  body="$(cat "$dest/analyst.md")"
  [[ "$body" == *"DESIGN-ANALYST"* ]] || {
    echo "    expected first-category (DESIGN) body preserved, got: $body" >&2; return 1; }
}

# A conflict must be surfaced loudly via `err`, naming the colliding incoming
# path. Current code emits nothing -> RED.
test_conflict_emits_err() {
  local repo
  repo="$(mk_repo)"
  run_install "$repo"
  [[ -f "$TEST_TMPDIR/err.log" ]] || { echo "    no err emitted for collision" >&2; return 1; }
  grep -q "analyst.md" "$TEST_TMPDIR/err.log" || {
    echo "    err did not name the colliding basename:" >&2
    cat "$TEST_TMPDIR/err.log" >&2; return 1; }
}

# Reported count must equal the number of UNIQUE agents actually installed
# (analyst + architect = 2), NOT the number of copies attempted (3).
# Current code reports 3 -> RED.
test_count_reflects_unique_agents() {
  local repo
  repo="$(mk_repo)"
  run_install "$repo"
  grep -Eq "Claude Code: 2 agents" "$TEST_TMPDIR/ok.log" || {
    echo "    expected reported count 2 (unique), got:" >&2
    cat "$TEST_TMPDIR/ok.log" >&2; return 1; }
}

# --- GREEN sanity: the unique agent is still installed regardless ---

test_unique_agent_still_installed() {
  local repo dest
  repo="$(mk_repo)"
  run_install "$repo"
  dest="$(DEST)"
  [[ -f "$dest/architect.md" ]] || { echo "    unique architect.md not installed" >&2; return 1; }
}

echo "=== test-agents-install.sh ==="
run_test "first-seen colliding basename is preserved (no silent overwrite)" test_first_seen_basename_is_preserved
run_test "conflicting agent basename emits err"                             test_conflict_emits_err
run_test "reported count reflects unique agents (not copy attempts)"        test_count_reflects_unique_agents
run_test "unique agent is still installed"                                  test_unique_agent_still_installed

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
