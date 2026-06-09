#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2016,SC2329
set -euo pipefail

# test-address-reports-triage.sh — Tests for the triage phase of
# scripts/address-reports.sh: clustering, the LLM-judge contract (mocked via
# TRIAGE_VERDICT_FILE), unit collapse, --limit over units, fail-closed on a bad
# verdict, and --resume manifest reuse (no re-judge). Given/When/Then style,
# no external framework. DRY_RUN=1 keeps every test deterministic and offline —
# the only non-determinism (the judge) is injected.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/address-reports.sh"

PASS=0
FAIL=0
TEST_TMPDIR=""

setup() {
  # A throwaway git repo with a writable parent (the script creates a sibling
  # ../.worktrees and refuses to run if the parent is not writable).
  TEST_TMPDIR="$(mktemp -d)"
  mkdir -p "$TEST_TMPDIR/repo/reports"
  (cd "$TEST_TMPDIR/repo" && git init -q && git config user.email t@t.t && git config user.name t)
  cd "$TEST_TMPDIR/repo"
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

assert_eq() {
  local expected="$1" actual="$2" msg="${3:-}"
  if [[ "$expected" == "$actual" ]]; then return 0; fi
  echo "  ASSERT FAILED${msg:+: $msg}" >&2
  echo "    expected: $expected" >&2
  echo "    actual:   $actual" >&2
  return 1
}

# Count "DRY   unit " lines in a dry-run worklist.
count_units() { grep -c 'DRY   unit ' <<<"$1" || true; }

# Run the scheduler in dry mode with an optional canned verdict file.
dry_run() {
  local verdict="${1:-}"; shift
  if [[ -n "$verdict" ]]; then
    NO_COLOR=1 DRY_RUN=1 TRIAGE_VERDICT_FILE="$verdict" bash "$SCRIPT" "$@" 2>&1
  else
    NO_COLOR=1 DRY_RUN=1 bash "$SCRIPT" "$@" 2>&1
  fi
}

# Install a PATH shim dir at $TEST_TMPDIR/shim and prepend it to PATH (mutates
# PATH in the caller's scope). The non-DRY scheduler path requires `claude` and
# `gh` on PATH (validate_env) and will otherwise call the real binaries — these
# stubs keep every test offline and deterministic. Callers overwrite
# $TEST_TMPDIR/shim/claude afterward to record argv / count invocations.
install_path_shims() {
  local shim="$TEST_TMPDIR/shim"
  mkdir -p "$shim"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$shim/claude"; chmod +x "$shim/claude"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$shim/gh";     chmod +x "$shim/gh"
  PATH="$shim:$PATH"
}

# Give the throwaway repo a real `origin/main` so pin_base (git fetch origin
# main + rev-parse origin/main) succeeds and dispatch reaches run_worker. An
# initial commit is required so there is a sha to fetch.
init_origin() {
  git add -A && git commit -qm init
  git init -q --bare "$TEST_TMPDIR/origin.git"
  git remote add origin "$TEST_TMPDIR/origin.git"
  git push -q origin "$(git symbolic-ref --short HEAD):main"
}

write_finding() {
  # write_finding <file> <heading> <severity> <files-bullet>
  local file="$1" heading="$2" sev="$3" files="$4"
  {
    printf '## %s\n\n' "$heading"
    printf '**Severity**: %s\n\n' "$sev"
    printf '**Files**:\n- `%s`\n\n' "$files"
    printf '**Problem**: p.\n\n**Fix**: f.\n\n'
  } >>"$file"
}

# === Tests ===

# Two reports, the SAME underlying finding (shared file) → 1 duplicate unit,
# canonical = the higher-severity member, both members recorded.
test_cross_report_duplicate() {
  printf '# a\n\n' >reports/a.md
  write_finding reports/a.md "[DRY] Dup foo" High "src/foo.rs:10"
  printf '# b\n\n' >reports/b.md
  write_finding reports/b.md "[DRY] foo again" Medium "src/foo.rs:12"
  cat >verdict.json <<'JSON'
{ "units": [ { "type": "duplicate",
    "canonical_ref": "a:dry-dup-foo",
    "member_refs": ["a:dry-dup-foo", "b:dry-foo-again"],
    "reason": "same" } ] }
JSON
  local out; out="$(dry_run "$PWD/verdict.json" reports/a.md reports/b.md)"
  assert_eq 1 "$(count_units "$out")" "one duplicate unit" || { echo "$out" >&2; return 1; }
  grep -q 'type=duplicate canonical=a:dry-dup-foo' <<<"$out" || { echo "$out" >&2; return 1; }
  grep -q 'members=\[a:dry-dup-foo,b:dry-foo-again\]' <<<"$out" || { echo "$out" >&2; return 1; }
}

# When the judge OMITS canonical_ref, the deterministic fallback (_pick_canonical)
# must select the highest-severity member — not the lowest report_idx. The High
# finding lives in the SECOND report (idx 1); a naive "lowest idx wins" pick would
# wrongly choose the Medium one in a.md (idx 0). Severity must dominate idx.
test_pick_canonical_severity_fallback() {
  printf '# a\n\n' >reports/a.md
  write_finding reports/a.md "[DRY] low one" Medium "src/shared.rs:10"
  printf '# b\n\n' >reports/b.md
  write_finding reports/b.md "[DRY] high one" High "src/shared.rs:12"
  # No canonical_ref → forces _pick_canonical. Members listed low-then-high so a
  # naive "first member" pick would also be wrong.
  cat >verdict.json <<'JSON'
{ "units": [ { "type": "duplicate",
    "member_refs": ["a:dry-low-one", "b:dry-high-one"],
    "reason": "same underlying problem" } ] }
JSON
  local out; out="$(dry_run "$PWD/verdict.json" reports/a.md reports/b.md)"
  assert_eq 1 "$(count_units "$out")" "one duplicate unit" || { echo "$out" >&2; return 1; }
  # Severity beats idx: canonical is the High finding in b.md (idx 1), not a.md.
  grep -q 'canonical=b:dry-high-one' <<<"$out" \
    || { echo "  _pick_canonical did not select the higher-severity member" >&2; echo "$out" >&2; return 1; }
}

# Same file, judged independent (non-overlapping) → 2 independent units, full
# parallelism preserved.
test_same_file_independent() {
  printf '# a\n\n' >reports/a.md
  write_finding reports/a.md "[DRY] foo top" High "src/foo.rs:5"
  write_finding reports/a.md "[DRY] foo bottom" High "src/foo.rs:200"
  cat >verdict.json <<'JSON'
{ "units": [
  { "type": "independent", "canonical_ref": "a:dry-foo-top",
    "member_refs": ["a:dry-foo-top"], "reason": "x" },
  { "type": "independent", "canonical_ref": "a:dry-foo-bottom",
    "member_refs": ["a:dry-foo-bottom"], "reason": "y" } ] }
JSON
  local out; out="$(dry_run "$PWD/verdict.json" reports/a.md)"
  assert_eq 2 "$(count_units "$out")" "two independent units" || { echo "$out" >&2; return 1; }
}

# Same file, judged coupled → 1 coupled unit carrying both members.
test_same_file_coupled() {
  printf '# a\n\n' >reports/a.md
  write_finding reports/a.md "[DRY] foo a" High "src/foo.rs:10"
  write_finding reports/a.md "[DRY] foo b" High "src/foo.rs:14"
  cat >verdict.json <<'JSON'
{ "units": [ { "type": "coupled",
    "canonical_ref": "a:dry-foo-a",
    "member_refs": ["a:dry-foo-a", "a:dry-foo-b"],
    "reason": "overlap" } ] }
JSON
  local out; out="$(dry_run "$PWD/verdict.json" reports/a.md)"
  assert_eq 1 "$(count_units "$out")" "one coupled unit" || { echo "$out" >&2; return 1; }
  grep -q 'type=coupled .*members=\[a:dry-foo-a,a:dry-foo-b\]' <<<"$out" || { echo "$out" >&2; return 1; }
}

# run_worker builds one repeatable --finding <report>:<slug> arg PER member for a
# coupled 2-member unit (plan item 1c). Driven through the real dispatch path
# (non-DRY, real origin so pin_base succeeds) with a claude shim that records its
# argv; assert both members appear as separate --finding args.
test_coupled_unit_builds_two_finding_args() {
  printf '# a\n\n' >reports/a.md
  write_finding reports/a.md "[DRY] foo a" High "src/foo.rs:10"
  write_finding reports/a.md "[DRY] foo b" High "src/foo.rs:14"
  cat >verdict.json <<'JSON'
{ "units": [ { "type": "coupled",
    "canonical_ref": "a:dry-foo-a",
    "member_refs": ["a:dry-foo-a", "a:dry-foo-b"],
    "reason": "overlap" } ] }
JSON
  install_path_shims
  init_origin
  # Overwrite the claude stub with an argv recorder. run_worker invokes claude
  # twice (once for the worker dispatch, but only that call carries --finding);
  # record every invocation's argv, one line each.
  local argv="$TEST_TMPDIR/claude-argv.txt"
  cat >"$TEST_TMPDIR/shim/claude" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$argv"
exit 0
EOF
  chmod +x "$TEST_TMPDIR/shim/claude"
  local out
  set +e
  # MAX_PARALLEL=1 keeps dispatch serial/deterministic. The run "fails" (the stub
  # prints no PR URL) — irrelevant; we assert on the recorded argv only.
  out="$(NO_COLOR=1 DRY_RUN=0 MAX_PARALLEL=1 TRIAGE_VERDICT_FILE="$PWD/verdict.json" \
        bash "$SCRIPT" reports/a.md 2>&1)"
  set -e
  [[ -f "$argv" ]] || { echo "  claude was never invoked (run_worker not reached)" >&2; echo "$out" >&2; return 1; }
  local worker_line
  worker_line="$(grep -- '--finding' "$argv" | head -n1 || true)"
  [[ -n "$worker_line" ]] || { echo "  no claude invocation carried --finding args" >&2; cat "$argv" >&2; return 1; }
  # Both members present as distinct --finding <report>:<slug> args.
  grep -q -- '--finding [^ ]*reports/a.md:dry-foo-a' <<<"$worker_line" \
    || { echo "  missing --finding for dry-foo-a" >&2; echo "$worker_line" >&2; return 1; }
  grep -q -- '--finding [^ ]*reports/a.md:dry-foo-b' <<<"$worker_line" \
    || { echo "  missing --finding for dry-foo-b" >&2; echo "$worker_line" >&2; return 1; }
  # Exactly two --finding args (no spurious extras). grep -o emits one line per
  # match; count the lines.
  local n; n="$(grep -o -- '--finding' <<<"$worker_line" | wc -l | tr -d ' ')"
  assert_eq 2 "$n" "exactly two --finding args for a 2-member coupled unit"
}

# Singletons (no shared file) skip the judge entirely: a missing verdict file
# would make the judge die, so success here proves the judge was never called.
test_singletons_skip_judge() {
  printf '# a\n\n' >reports/a.md
  write_finding reports/a.md "[DRY] alpha" High "src/alpha.rs"
  write_finding reports/a.md "[DRY] beta" Low "src/beta.rs"
  # No TRIAGE_VERDICT_FILE → if the judge were invoked it would call claude;
  # in DRY mode claude is not required and no multi-cluster exists, so the run
  # must succeed with 2 independent units and never reference a verdict.
  local out; out="$(dry_run "" reports/a.md)"
  assert_eq 2 "$(count_units "$out")" "two independent singleton units" || { echo "$out" >&2; return 1; }
  grep -q 'type=independent' <<<"$out" || { echo "$out" >&2; return 1; }
}

# --limit 1 over {coupled bundle of 2, 1 singleton} → exactly 1 unit dispatched;
# the bundle is atomic (a unit is one row), never split.
test_limit_caps_units_atomically() {
  printf '# a\n\n' >reports/a.md
  write_finding reports/a.md "[DRY] pair one" High "src/pair.rs:10"
  write_finding reports/a.md "[DRY] pair two" High "src/pair.rs:12"
  write_finding reports/a.md "[DRY] lonely" Low "src/lonely.rs"
  cat >verdict.json <<'JSON'
{ "units": [ { "type": "coupled",
    "canonical_ref": "a:dry-pair-one",
    "member_refs": ["a:dry-pair-one", "a:dry-pair-two"],
    "reason": "overlap" } ] }
JSON
  local out; out="$(MAX_FINDINGS=1 dry_run "$PWD/verdict.json" reports/a.md)"
  assert_eq 1 "$(count_units "$out")" "limit caps to one unit" || { echo "$out" >&2; return 1; }
  # whichever unit survived, it is whole — no line shows a half-bundle (a coupled
  # unit always lists both pair members or none).
  if grep -q 'members=\[a:dry-pair-one\]' <<<"$out" || grep -q 'members=\[a:dry-pair-two\]' <<<"$out"; then
    echo "  bundle was split!" >&2; echo "$out" >&2; return 1
  fi
}

# Malformed verdict → fail-closed: non-zero exit, clear ABORT, no worktrees.
test_fail_closed_on_bad_verdict() {
  printf '# a\n\n' >reports/a.md
  write_finding reports/a.md "[DRY] foo a" High "src/foo.rs:10"
  write_finding reports/a.md "[DRY] foo b" High "src/foo.rs:14"
  printf 'this is not json' >verdict.json
  local out rc
  set +e
  out="$(dry_run "$PWD/verdict.json" reports/a.md)"
  rc=$?
  set -e
  [[ $rc -ne 0 ]] || { echo "  expected non-zero exit" >&2; echo "$out" >&2; return 1; }
  grep -q 'ABORT' <<<"$out" || { echo "$out" >&2; return 1; }
  # no worktrees created
  local wts; wts="$(find "$TEST_TMPDIR/.worktrees" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')"
  assert_eq 0 "$wts" "no worktrees on fail-closed"
}

# Verdict that fails to partition the findings (drops a member) → fail-closed.
test_fail_closed_on_partition_violation() {
  printf '# a\n\n' >reports/a.md
  write_finding reports/a.md "[DRY] foo a" High "src/foo.rs:10"
  write_finding reports/a.md "[DRY] foo b" High "src/foo.rs:14"
  cat >verdict.json <<'JSON'
{ "units": [ { "type": "independent",
    "canonical_ref": "a:dry-foo-a",
    "member_refs": ["a:dry-foo-a"],
    "reason": "dropped foo-b" } ] }
JSON
  local out rc
  set +e
  out="$(dry_run "$PWD/verdict.json" reports/a.md)"
  rc=$?
  set -e
  [[ $rc -ne 0 ]] || { echo "  expected non-zero exit" >&2; echo "$out" >&2; return 1; }
  grep -q 'partition' <<<"$out" || { echo "$out" >&2; return 1; }
}

# DRY run leaves no manifest behind: the write path is a real side effect, so
# DRY must skip it (preview only). This is the DRY-invariant half — the actual
# write_triage_manifest path is covered by test_fresh_run_writes_manifest below.
test_dry_run_skips_manifest() {
  printf '# a\n\n' >reports/a.md
  write_finding reports/a.md "[DRY] foo a" High "src/foo.rs:10"
  write_finding reports/a.md "[DRY] foo b" High "src/foo.rs:14"
  cat >verdict.json <<'JSON'
{ "units": [ { "type": "coupled",
    "canonical_ref": "a:dry-foo-a",
    "member_refs": ["a:dry-foo-a", "a:dry-foo-b"],
    "reason": "overlap" } ] }
JSON
  dry_run "$PWD/verdict.json" reports/a.md >/dev/null
  [[ ! -f reports/.triage.json ]] || { echo "  DRY must not write manifest" >&2; return 1; }
}

# Fresh NON-DRY run actually writes reports/.triage.json via write_triage_manifest,
# with the expected units/canonical/members shape. To stay offline we shim
# claude/gh and let the run stop right after the manifest write: the throwaway
# repo has no origin, so pin_base (which runs AFTER write_triage_manifest, BEFORE
# any worker spawn) fails — proving the manifest is committed pre-dispatch with no
# worktree side effects.
test_fresh_run_writes_manifest() {
  printf '# a\n\n' >reports/a.md
  write_finding reports/a.md "[DRY] foo a" High "src/foo.rs:10"
  write_finding reports/a.md "[DRY] foo b" High "src/foo.rs:14"
  cat >verdict.json <<'JSON'
{ "units": [ { "type": "coupled",
    "canonical_ref": "a:dry-foo-a",
    "member_refs": ["a:dry-foo-a", "a:dry-foo-b"],
    "reason": "overlap" } ] }
JSON
  install_path_shims
  # Non-DRY, no origin → manifest written, then pin_base aborts the run.
  local out rc
  set +e
  out="$(NO_COLOR=1 DRY_RUN=0 TRIAGE_VERDICT_FILE="$PWD/verdict.json" \
        bash "$SCRIPT" reports/a.md 2>&1)"
  rc=$?
  set -e
  [[ $rc -ne 0 ]] || { echo "  expected pin_base to abort (no origin)" >&2; echo "$out" >&2; return 1; }
  [[ -f reports/.triage.json ]] || { echo "  manifest NOT written on non-dry fresh run" >&2; echo "$out" >&2; return 1; }
  # Shape: one coupled unit, canonical = dry-foo-a, two members.
  jq -e '.units | length == 1' reports/.triage.json >/dev/null \
    || { echo "  expected exactly one unit" >&2; cat reports/.triage.json >&2; return 1; }
  jq -e '.units[0].type == "coupled"' reports/.triage.json >/dev/null \
    || { echo "  expected coupled unit" >&2; cat reports/.triage.json >&2; return 1; }
  jq -e '.units[0].canonical.slug == "dry-foo-a"' reports/.triage.json >/dev/null \
    || { echo "  expected canonical slug dry-foo-a" >&2; cat reports/.triage.json >&2; return 1; }
  jq -e '[.units[0].members[].slug] == ["dry-foo-a","dry-foo-b"]' reports/.triage.json >/dev/null \
    || { echo "  expected members [dry-foo-a, dry-foo-b]" >&2; cat reports/.triage.json >&2; return 1; }
  jq -e '.input_hash | type == "string" and (. | length) > 0' reports/.triage.json >/dev/null \
    || { echo "  expected non-empty input_hash" >&2; cat reports/.triage.json >&2; return 1; }
  # No worktrees created (manifest write precedes any dispatch).
  local wts; wts="$(find "$TEST_TMPDIR/.worktrees" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')"
  assert_eq 0 "$wts" "no worktrees on a pin_base-aborted fresh run"
}

# --resume loads reports/.triage.json and does NOT re-invoke the judge. Proven
# DIRECTLY: a claude recorder shim increments a counter on every invocation, and
# after --resume against a valid manifest the counter is 0 (judge never fired).
# The indirect check is kept too (cheap): a malformed verdict file is present, so
# if resume had re-judged it would die — it must not.
test_resume_loads_manifest_no_judge() {
  printf '# a\n\n' >reports/a.md
  write_finding reports/a.md "[DRY] foo a" High "src/foo.rs:10"
  write_finding reports/a.md "[DRY] foo b" High "src/foo.rs:14"
  # Hand-author a manifest with the correct hash so the staleness guard passes.
  local hash; hash="$(cat "$PWD/reports/a.md" | shasum -a 256 | awk '{print $1}')"
  cat >reports/.triage.json <<JSON
{ "base_shas": null,
  "input_hash": "$hash",
  "units": [ { "canonical": {"report_idx":0,"slug":"dry-foo-a","lineno":3},
               "type": "coupled",
               "members": [ {"report_idx":0,"slug":"dry-foo-a","lineno":3},
                            {"report_idx":0,"slug":"dry-foo-b","lineno":11} ] } ] }
JSON
  # claude recorder shim: counter file bumped on every invocation. (DRY mode does
  # not require claude, so any bump can only come from a judge call.)
  install_path_shims
  local counter="$TEST_TMPDIR/claude-calls.txt"; printf '0' >"$counter"
  cat >"$TEST_TMPDIR/shim/claude" <<EOF
#!/usr/bin/env bash
n="\$(cat "$counter")"; printf '%s' "\$((n+1))" >"$counter"
exit 0
EOF
  chmod +x "$TEST_TMPDIR/shim/claude"
  # Indirect guard retained: malformed verdict file → resume would die if it judged.
  printf 'not json' >verdict.json
  local out rc
  set +e
  out="$(NO_COLOR=1 DRY_RUN=1 RESUME=0 TRIAGE_VERDICT_FILE="$PWD/verdict.json" \
        bash "$SCRIPT" --resume reports/a.md 2>&1)"
  rc=$?
  set -e
  [[ $rc -eq 0 ]] || { echo "  resume should succeed without re-judging" >&2; echo "$out" >&2; return 1; }
  # Direct: the judge was never invoked.
  assert_eq 0 "$(cat "$counter")" "judge (claude) never invoked on --resume" || { echo "$out" >&2; return 1; }
  assert_eq 1 "$(count_units "$out")" "one coupled unit from manifest" || { echo "$out" >&2; return 1; }
  grep -q 'type=coupled .*members=\[a:dry-foo-a,a:dry-foo-b\]' <<<"$out" || { echo "$out" >&2; return 1; }
}

# --resume after a PARTIAL success must NOT report stale. The scheduler marks
# shipped findings "— RESOLVED (…)" in place as it goes, so by the next --resume
# the report content has changed — but only by the scheduler's own marker. The
# input_hash guard must ignore that marker (else --resume is unreachable after the
# first unit ships). Regression test for the staleness-guard blocker.
test_resume_after_partial_success_not_stale() {
  printf '# a\n\n' >reports/a.md
  write_finding reports/a.md "[DRY] foo a" High "src/foo.rs:10"
  write_finding reports/a.md "[DRY] foo b" High "src/foo.rs:14"
  # Manifest written at triage time, over the PRISTINE report (no markers yet).
  local hash; hash="$(cat "$PWD/reports/a.md" | shasum -a 256 | awk '{print $1}')"
  cat >reports/.triage.json <<JSON
{ "base_shas": null,
  "input_hash": "$hash",
  "units": [ { "canonical": {"report_idx":0,"slug":"dry-foo-a","lineno":3},
               "type": "independent",
               "members": [ {"report_idx":0,"slug":"dry-foo-a","lineno":3} ] },
             { "canonical": {"report_idx":0,"slug":"dry-foo-b","lineno":11},
               "type": "independent",
               "members": [ {"report_idx":0,"slug":"dry-foo-b","lineno":11} ] } ] }
JSON
  # Simulate the scheduler having shipped foo-a's unit: its H2 is now marked
  # RESOLVED in place (awk→tmp→mv, exactly mark_resolved's byte-preserving edit).
  awk 'NR==3 {print $0 " — RESOLVED (2026-06-09, #7)"; next} {print}' reports/a.md >reports/a.md.tmp
  mv reports/a.md.tmp reports/a.md
  local out rc
  set +e
  out="$(NO_COLOR=1 DRY_RUN=1 bash "$SCRIPT" --resume reports/a.md 2>&1)"
  rc=$?
  set -e
  [[ $rc -eq 0 ]] || { echo "  partial-success resume must not abort" >&2; echo "$out" >&2; return 1; }
  if grep -q 'stale' <<<"$out"; then
    echo "  scheduler's own RESOLVED marker wrongly tripped the staleness guard" >&2
    echo "$out" >&2; return 1
  fi
}

# --resume with a stale manifest (reports changed since triage) → fail-closed.
test_resume_stale_manifest_fails_closed() {
  printf '# a\n\n' >reports/a.md
  write_finding reports/a.md "[DRY] foo a" High "src/foo.rs:10"
  cat >reports/.triage.json <<'JSON'
{ "base_shas": null,
  "input_hash": "deadbeef-not-the-real-hash",
  "units": [ { "canonical": {"report_idx":0,"slug":"dry-foo-a","lineno":3},
               "type": "independent",
               "members": [ {"report_idx":0,"slug":"dry-foo-a","lineno":3} ] } ] }
JSON
  local out rc
  set +e
  out="$(NO_COLOR=1 DRY_RUN=1 bash "$SCRIPT" --resume reports/a.md 2>&1)"
  rc=$?
  set -e
  [[ $rc -ne 0 ]] || { echo "  expected non-zero exit on stale manifest" >&2; echo "$out" >&2; return 1; }
  grep -q 'stale' <<<"$out" || { echo "$out" >&2; return 1; }
}

# === Runner ===

run_test "cross-report duplicate → 1 unit, canonical = higher severity"   test_cross_report_duplicate
run_test "judge omits canonical_ref → _pick_canonical picks by severity"   test_pick_canonical_severity_fallback
run_test "same file, independent → 2 units (parallelism preserved)"        test_same_file_independent
run_test "same file, coupled → 1 unit with both members"                   test_same_file_coupled
run_test "coupled unit → run_worker builds 2 --finding args"               test_coupled_unit_builds_two_finding_args
run_test "singletons (no shared file) skip the judge"                      test_singletons_skip_judge
run_test "--limit caps work units atomically (bundle not split)"           test_limit_caps_units_atomically
run_test "malformed verdict → fail-closed, no worktrees"                   test_fail_closed_on_bad_verdict
run_test "verdict that drops a finding → fail-closed (partition)"          test_fail_closed_on_partition_violation
run_test "DRY run does not write the manifest"                             test_dry_run_skips_manifest
run_test "non-dry fresh run writes the manifest (shape asserted)"          test_fresh_run_writes_manifest
run_test "--resume loads manifest, never re-judges (call-count 0)"         test_resume_loads_manifest_no_judge
run_test "--resume after partial success → not stale (own marker ignored)" test_resume_after_partial_success_not_stale
run_test "--resume with stale manifest → fail-closed"                      test_resume_stale_manifest_fails_closed

echo ""
echo "Results: $PASS passed, $FAIL failed out of $((PASS + FAIL)) tests"
[[ "$FAIL" -gt 0 ]] && exit 1
exit 0
