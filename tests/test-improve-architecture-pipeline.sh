#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2016,SC2329
set -euo pipefail

# test-improve-architecture-pipeline.sh — Tests for the resolved-report archival
# behaviour of scripts/improve-architecture-pipeline.sh: fully-resolved reports
# (every '## ' finding carries a RESOLVED marker) are swept out of the live
# reports/ dir into reports/done/ at the gate, instead of lingering as clutter.
# Given/When/Then style, no external framework. claude/gh are stubbed (the
# archival paths exercised here never invoke them — run_scan SKIPs because
# reports already exist, and the gate exits before stage 2).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/improve-architecture-pipeline.sh"

PASS=0
FAIL=0
TEST_TMPDIR=""
STUB_BIN=""

# A throwaway git repo with an origin remote (validate_env refuses without one)
# and stubbed claude/gh on PATH (validate_env checks they exist).
setup() {
  TEST_TMPDIR="$(mktemp -d)"
  mkdir -p "$TEST_TMPDIR/repo/reports"
  (cd "$TEST_TMPDIR/repo" \
    && git init -q \
    && git config user.email t@t.t \
    && git config user.name t \
    && git remote add origin https://example.com/repo.git)
  STUB_BIN="$TEST_TMPDIR/bin"
  mkdir -p "$STUB_BIN"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$STUB_BIN/claude"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$STUB_BIN/gh"
  chmod +x "$STUB_BIN/claude" "$STUB_BIN/gh"
}

teardown() {
  cd "$REPO_ROOT"
  rm -rf "$TEST_TMPDIR"
}

run_test() {
  local name="$1"; shift
  setup
  if "$@"; then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name"; FAIL=$((FAIL + 1))
  fi
  teardown
}

assert_file() {
  [[ -f "$1" ]] && return 0
  echo "  ASSERT FAILED: expected file to exist: $1" >&2
  return 1
}

assert_no_file() {
  [[ ! -e "$1" ]] && return 0
  echo "  ASSERT FAILED: expected file to be gone: $1" >&2
  return 1
}

# Write a report whose every '## ' finding carries a RESOLVED marker.
write_resolved_report() {
  local path="$1"
  cat >"$path" <<'EOF'
# Findings: `foo`

**Date**: 2026-06-30
**Scope**: `foo`

---

## [architecture] Shallow seam — RESOLVED (2026-06-30, #1)

**Severity**: Medium
EOF
}

# Write a report with at least one still-open '## ' finding.
write_open_report() {
  local path="$1"
  cat >"$path" <<'EOF'
# Findings: `bar`

**Date**: 2026-06-30
**Scope**: `bar`

---

## [architecture] Leaky boundary

**Severity**: High
EOF
}

# Run the pipeline against the temp repo (no --yes) with stubs on PATH.
run_pipeline() {
  PATH="$STUB_BIN:$PATH" bash "$SCRIPT" "$TEST_TMPDIR/repo" >/dev/null 2>&1 || true
}

# --- Tests ---------------------------------------------------------------

# A fully-resolved report is swept to reports/done/; an open one stays put.
test_archives_resolved_keeps_open() {
  local rdir="$TEST_TMPDIR/repo/reports"
  write_resolved_report "$rdir/architecture-foo.md"
  write_open_report "$rdir/architecture-bar.md"

  run_pipeline

  assert_no_file "$rdir/architecture-foo.md" || return 1
  assert_file "$rdir/done/architecture-foo.md" || return 1
  assert_file "$rdir/architecture-bar.md" || return 1
  assert_no_file "$rdir/done/architecture-bar.md" || return 1
}

# An all-resolved repo (gate-zero path) archives everything and exits clean.
test_gate_zero_archives_all() {
  local rdir="$TEST_TMPDIR/repo/reports"
  write_resolved_report "$rdir/architecture-foo.md"

  run_pipeline

  assert_no_file "$rdir/architecture-foo.md" || return 1
  assert_file "$rdir/done/architecture-foo.md" || return 1
}

# Idempotent: a second run with the resolved report already archived and only an
# open report left moves nothing further.
test_idempotent() {
  local rdir="$TEST_TMPDIR/repo/reports"
  write_resolved_report "$rdir/architecture-foo.md"
  write_open_report "$rdir/architecture-bar.md"

  run_pipeline
  run_pipeline

  assert_file "$rdir/done/architecture-foo.md" || return 1
  assert_file "$rdir/architecture-bar.md" || return 1
  # No stamped duplicate created on the second pass.
  local extra
  extra="$(find "$rdir/done" -name 'architecture-foo.*.md' 2>/dev/null | wc -l | tr -d ' ')"
  assert_eq_num 0 "$extra" "no stamped duplicate on idempotent re-run" || return 1
}

# Collision: a done/<base> already exists, a new resolved report of the same base
# is archived under a stamped name instead of clobbering the prior archive.
test_collision_stamps() {
  local rdir="$TEST_TMPDIR/repo/reports"
  mkdir -p "$rdir/done"
  printf 'prior archive\n' >"$rdir/done/architecture-foo.md"
  write_resolved_report "$rdir/architecture-foo.md"

  run_pipeline

  # Prior archive preserved verbatim.
  assert_file "$rdir/done/architecture-foo.md" || return 1
  grep -q 'prior archive' "$rdir/done/architecture-foo.md" || {
    echo "  ASSERT FAILED: prior archive was clobbered" >&2; return 1; }
  # New one landed under a UTC-stamped name.
  local stamped
  stamped="$(find "$rdir/done" -name 'architecture-foo.*.md' 2>/dev/null | wc -l | tr -d ' ')"
  assert_eq_num 1 "$stamped" "exactly one stamped archive created" || return 1
  assert_no_file "$rdir/architecture-foo.md" || return 1
}

assert_eq_num() {
  local expected="$1" actual="$2" msg="${3:-}"
  [[ "$expected" == "$actual" ]] && return 0
  echo "  ASSERT FAILED${msg:+: $msg}: expected $expected, got $actual" >&2
  return 1
}

echo "test-improve-architecture-pipeline.sh"
run_test "archives resolved report, keeps open one" test_archives_resolved_keeps_open
run_test "gate-zero archives all resolved reports"  test_gate_zero_archives_all
run_test "idempotent re-run moves nothing further"  test_idempotent
run_test "collision archives under a stamped name"  test_collision_stamps

echo
echo "  $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
