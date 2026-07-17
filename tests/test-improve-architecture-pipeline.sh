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

# --- Stage-1 scan: runtime selection + usage parsing ----------------------

# Stub claude for run_scan: record argv, emit a canned stream-json result line
# (cumulative usage), and write a fake report so the post-scan tally sees it.
make_claude_scan_stub() {
  local argvfile="$1"
  cat >"$STUB_BIN/claude" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$argvfile"
printf '%s\n' '{"type":"result","usage":{"input_tokens":100,"output_tokens":20,"cache_read_input_tokens":5,"cache_creation_input_tokens":3},"total_cost_usd":0.0123}'
mkdir -p reports
cat >reports/architecture-foo.md <<'MD'
# Findings: foo

**Date**: 2026-07-14
**Scope**: foo

---

## [architecture] Leaky seam

**Severity**: High
MD
exit 0
STUB
  chmod +x "$STUB_BIN/claude"
}

# Stub pi for run_scan: record argv, emit canned --mode json turn_end events
# (two turns, summed by extract_usage_pi), and write a fake report.
make_pi_scan_stub() {
  local argvfile="$1"
  cat >"$STUB_BIN/pi" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$argvfile"
printf '%s\n' '{"type":"turn_end","message":{"role":"assistant","usage":{"input":100,"output":20,"cacheRead":5,"cacheWrite":3,"cost":{"input":0.01,"output":0.002,"cacheRead":0.0005,"cacheWrite":0.0003,"total":0.0128}}},"toolResults":[]}'
printf '%s\n' '{"type":"turn_end","message":{"role":"assistant","usage":{"input":50,"output":40,"cacheRead":5,"cacheWrite":3,"cost":{"input":0.005,"output":0.004,"cacheRead":0.0005,"cacheWrite":0.0003,"total":0.0098}}},"toolResults":[]}'
mkdir -p reports
cat >reports/architecture-foo.md <<'MD'
# Findings: foo

**Date**: 2026-07-14
**Scope**: foo

---

## [architecture] Leaky seam

**Severity**: High
MD
exit 0
STUB
  chmod +x "$STUB_BIN/pi"
}

# WF_RUNTIME=claude: run_scan emits the Claude invocation (bypassPermissions +
# stream-json) and extract_usage parses the canned result line. Proves the Claude
# path is unchanged and that auto-detect routes a Claude-shaped log to
# extract_usage_claude.
test_scan_claude_invocation_and_usage() {
  local argv="$TEST_TMPDIR/claude-argv.txt"
  make_claude_scan_stub "$argv"
  PATH="$STUB_BIN:$PATH" WF_RUNTIME=claude bash "$SCRIPT" "$TEST_TMPDIR/repo" >/dev/null 2>&1 || true
  [[ -f "$argv" ]] || { echo "  claude never invoked by run_scan" >&2; return 1; }
  local args; args="$(cat "$argv")"
  grep -q -- '--permission-mode bypassPermissions' <<<"$args" || { echo "  missing --permission-mode bypassPermissions" >&2; return 1; }
  grep -q -- '--output-format stream-json' <<<"$args" || { echo "  missing --output-format stream-json" >&2; return 1; }
  grep -q -- '--model' <<<"$args" || { echo "  missing --model" >&2; return 1; }
  ! grep -q -- '--exclude-tools' <<<"$args" || { echo "  pi flag leaked into claude path" >&2; return 1; }
  grep -qF 'USAGE scan in=100 out=20 cache_read=5 cache_creation=3 cost=$0.0123' "$TEST_TMPDIR/repo/reports/.pipeline.log" \
    || { echo "  claude usage not parsed from result line" >&2; cat "$TEST_TMPDIR/repo/reports/.pipeline.log" >&2; return 1; }
}

# WF_RUNTIME=pi: run_scan emits the pi invocation (--mode json --approve
# --exclude-tools ask_question --skill improve-codebase-architecture) and
# extract_usage auto-detects the Pi log and SUMS two turn_end events.
test_scan_pi_invocation_and_usage() {
  local argv="$TEST_TMPDIR/pi-argv.txt"
  make_pi_scan_stub "$argv"
  PATH="$STUB_BIN:$PATH" WF_RUNTIME=pi bash "$SCRIPT" "$TEST_TMPDIR/repo" >/dev/null 2>&1 || true
  [[ -f "$argv" ]] || { echo "  pi never invoked by run_scan" >&2; return 1; }
  local args; args="$(cat "$argv")"
  grep -q -- '-p' <<<"$args" || { echo "  missing -p" >&2; return 1; }
  grep -q -- '--mode json' <<<"$args" || { echo "  missing --mode json" >&2; return 1; }
  grep -q -- '--approve' <<<"$args" || { echo "  missing --approve" >&2; return 1; }
  grep -q -- '--exclude-tools ask_question' <<<"$args" || { echo "  missing --exclude-tools ask_question" >&2; return 1; }
  grep -q -- '--skill' <<<"$args" || { echo "  missing --skill" >&2; return 1; }
  grep -q -- 'improve-codebase-architecture' <<<"$args" || { echo "  --skill not improve-codebase-architecture" >&2; return 1; }
  ! grep -q -- 'bypassPermissions' <<<"$args" || { echo "  claude flag leaked into pi path" >&2; return 1; }
  # Two turn_end events summed: 100+50=150 in, 20+40=60 out, 5+5=10 cache_read,
  # 3+3=6 cache_creation, 0.0128+0.0098=0.0226 cost (extract_usage_pi %.4f).
  grep -qF 'USAGE scan in=150 out=60 cache_read=10 cache_creation=6 cost=$0.0226' "$TEST_TMPDIR/repo/reports/.pipeline.log" \
    || { echo "  pi usage not summed from turn_end events" >&2; cat "$TEST_TMPDIR/repo/reports/.pipeline.log" >&2; return 1; }
}

# WF_RUNTIME unset → claude (no regression). No pi stub on PATH: if the default
# were pi, validate_env would die "pi CLI not found". Claude being invoked proves
# the default is claude.
test_runtime_defaults_to_claude() {
  local argv="$TEST_TMPDIR/claude-argv.txt"
  make_claude_scan_stub "$argv"
  PATH="$STUB_BIN:$PATH" env -u WF_RUNTIME bash "$SCRIPT" "$TEST_TMPDIR/repo" >/dev/null 2>&1 || true
  [[ -f "$argv" ]] || { echo "  default runtime did not invoke claude" >&2; return 1; }
}

echo "test-improve-architecture-pipeline.sh"
run_test "archives resolved report, keeps open one" test_archives_resolved_keeps_open
run_test "gate-zero archives all resolved reports"  test_gate_zero_archives_all
run_test "idempotent re-run moves nothing further"  test_idempotent
run_test "collision archives under a stamped name"  test_collision_stamps
run_test "claude scan invocation + usage parsing"    test_scan_claude_invocation_and_usage
run_test "pi scan invocation + turn_end usage sum"    test_scan_pi_invocation_and_usage
run_test "WF_RUNTIME unset defaults to claude"        test_runtime_defaults_to_claude

echo
echo "  $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
