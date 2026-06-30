#!/usr/bin/env bash
# Architecture-improvement pipeline: find architectural deepening opportunities
# in a target repo, write them as reports/*.md, gate for review, then open one
# PR per finding via the parallel worktree scheduler (address-reports.sh).
#
# Two stages, gated by default:
#   Stage 1 (find)    — one deep arch analysis (Opus), writes reports/*.md.
#   Gate              — list reports + open-finding count; stop unless --yes.
#   Stage 2 (address) — hand the reports to address-reports.sh (Sonnet workers).
#
# See plan: ~/.claude/plans/starry-crafting-hennessy.md
set -euo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly EXIT_SUCCESS=0
readonly EXIT_FAILURE=1
readonly EXIT_INVALID_ARGS=2

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'; C_MAGENTA=$'\033[35m'; C_CYAN=$'\033[36m'
else
  C_RESET=''; C_DIM=''; C_BOLD=''; C_RED=''; C_GREEN=''
  C_YELLOW=''; C_BLUE=''; C_MAGENTA=''; C_CYAN=''
fi

# Tag coloring mirrors address-reports.sh so stage-1 + stage-2 logs read alike.
_colorize_tag() {
  local msg="$1" head rest color
  head="${msg%%[[:space:]]*}"
  rest="${msg#"$head"}"
  case "$head" in
    SCAN)        color="$C_BOLD$C_CYAN" ;;
    REPORT)      color="$C_BOLD$C_CYAN" ;;
    GATE)        color="$C_BOLD$C_YELLOW" ;;
    STAGE2)      color="$C_BOLD$C_BLUE" ;;
    MANIFEST)    color="$C_BOLD$C_MAGENTA" ;;
    ARCHIVE)     color="$C_BOLD$C_GREEN" ;;
    USAGE)       color="$C_BOLD$C_CYAN" ;;
    SKIP)        color="$C_YELLOW" ;;
    INTERRUPTED) color="$C_BOLD$C_RED" ;;
    FAILED|ERROR|ABORT) color="$C_BOLD$C_RED" ;;
    DONE)        color="$C_BOLD$C_GREEN" ;;
    pipeline)    color="$C_BOLD$C_GREEN" ;;
    *)           color="" ;;
  esac
  if [[ -n "$color" ]]; then
    printf '%s%s%s%s' "$color" "$head" "$C_RESET" "$rest"
  else
    printf '%s' "$msg"
  fi
}

log() {
  local ts colored
  ts="$(date -Iseconds 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [[ -n "$C_RESET" ]]; then
    colored="$(_colorize_tag "$*")"
  else
    colored="$*"
  fi
  printf '%s%s%s %s|%s %s\n' "$C_DIM" "$ts" "$C_RESET" "$C_DIM" "$C_RESET" "$colored"
  # $LOG may be unset during very early failures; guard.
  [[ -n "${LOG:-}" ]] && printf '%s | %s\n' "$ts" "$*" >>"$LOG" || true
}
die() { log "ERROR $*"; exit "$EXIT_FAILURE"; }

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [options] [<repo-path>]

Find architectural deepening opportunities in <repo-path> (default: .), write
them as reports/*.md, gate for review, then open one PR per finding via
isolated git worktrees.

Arguments:
    <repo-path>   Target git repository (default: current directory).

Options:
    --yes         Chain past the review gate straight into stage 2 (address).
                  Without it, the pipeline stops after writing reports.
    --limit N     Address at most N findings this run (passed to the scheduler;
                  the PR unit is the finding). Env: MAX_FINDINGS.
    --resume      Self-healing re-run: skip a fresh scan if reports exist and
                  pass --resume to the scheduler (reconcile shipped findings,
                  re-dispatch dead workers — no duplicate PRs).
    --rescan      Force a fresh stage 1 (clears prior reports/*.md first).
    --cleanup     Delegate to the scheduler's --cleanup (sweep stale worktrees
                  for the existing reports), then exit.
    -h, --help    Show this help.

Environment:
    ARCH_FIND_MODEL  Model for stage 1 analysis (default: claude-opus-4-8).
    CLAUDE_MODEL     Model for stage 2 workers (default: claude-sonnet-4-6).
    MAX_PARALLEL     Stage 2 worker pool size (default: 2).
    MAX_FINDINGS     Default for --limit (default: 0 = no limit).
    NO_COLOR=1       Disable ANSI.

Output:
    <repo>/reports/*.md            One report per finding (gitignored scratch).
    <repo>/reports/.pipeline.log   Stage 1 + orchestrator events.
    <repo>/reports/.scheduler.log  Stage 2 scheduler events.

Examples:
    $SCRIPT_NAME ~/code/myrepo
    $SCRIPT_NAME --yes --limit 2 ~/code/myrepo
    $SCRIPT_NAME --resume ~/code/myrepo
    $SCRIPT_NAME --rescan ~/code/myrepo
    $SCRIPT_NAME --cleanup ~/code/myrepo
EOF
}

parse_args() {
  TARGET_ARG="."
  YES=0
  RESUME=0
  RESCAN=0
  CLEANUP=0
  LIMIT="${MAX_FINDINGS:-0}"
  local got_target=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)  usage; exit "$EXIT_SUCCESS" ;;
      --yes)      YES=1; shift ;;
      --resume)   RESUME=1; shift ;;
      --rescan)   RESCAN=1; shift ;;
      --cleanup)  CLEANUP=1; shift ;;
      --limit)    shift; [[ $# -gt 0 ]] || { echo "$SCRIPT_NAME: --limit requires an argument" >&2; exit "$EXIT_INVALID_ARGS"; }; LIMIT="$1"; shift ;;
      --limit=*)  LIMIT="${1#*=}"; shift ;;
      --)         shift; [[ $# -gt 0 ]] && { TARGET_ARG="$1"; got_target=1; shift; } ;;
      -*)         usage >&2; exit "$EXIT_INVALID_ARGS" ;;
      *)          if [[ $got_target -eq 1 ]]; then echo "$SCRIPT_NAME: only one <repo-path> allowed" >&2; exit "$EXIT_INVALID_ARGS"; fi; TARGET_ARG="$1"; got_target=1; shift ;;
    esac
  done
  [[ "$LIMIT" =~ ^[0-9]+$ ]] || { echo "$SCRIPT_NAME: --limit must be a non-negative integer: $LIMIT" >&2; exit "$EXIT_INVALID_ARGS"; }
  if [[ "$RESCAN" == "1" && "$RESUME" == "1" ]]; then
    echo "$SCRIPT_NAME: --rescan and --resume are mutually exclusive" >&2
    exit "$EXIT_INVALID_ARGS"
  fi
}

validate_env() {
  command -v git >/dev/null 2>&1 || die "git not found in PATH"
  [[ -d "$TARGET_ARG" ]] || die "repo path not a directory: $TARGET_ARG"
  REPO_ROOT="$(git -C "$TARGET_ARG" rev-parse --show-toplevel 2>/dev/null)" \
    || die "not a git repository: $TARGET_ARG"
  REPORTS_DIR="$REPO_ROOT/reports"
  mkdir -p "$REPORTS_DIR"
  LOG="$REPORTS_DIR/.pipeline.log"
  : >>"$LOG"

  git -C "$REPO_ROOT" remote get-url origin >/dev/null 2>&1 \
    || die "target repo has no 'origin' remote (needed to open PRs)"

  command -v claude >/dev/null 2>&1 || die "claude CLI not found in PATH"
  command -v gh     >/dev/null 2>&1 || die "gh CLI not found in PATH"

  SCHEDULER="$SCRIPT_DIR/address-reports.sh"
  if [[ ! -x "$SCHEDULER" ]]; then
    SCHEDULER="$(command -v address-reports.sh 2>/dev/null || true)"
  fi
  [[ -n "$SCHEDULER" && -x "$SCHEDULER" ]] \
    || die "address-reports.sh scheduler not found next to $SCRIPT_NAME or on PATH"

  ARCH_FIND_MODEL="${ARCH_FIND_MODEL:-claude-opus-4-8}"
}

# Append reports/ to the target repo's .gitignore if not already ignored.
# Reports are ephemeral scratch in the main checkout; never committed.
ensure_reports_gitignored() {
  if git -C "$REPO_ROOT" check-ignore -q reports 2>/dev/null; then
    return 0
  fi
  local gi="$REPO_ROOT/.gitignore"
  printf '\n# Architecture-pipeline scratch (uncommitted findings)\n/reports/\n' >>"$gi"
  log "pipeline added /reports/ to $gi"
}

# Count open H2 findings in a report (mirrors scheduler parse_open_findings).
count_open() {
  local report="$1"
  grep -nE '^## ' "$report" 2>/dev/null | awk -F: '
    { h = substr($0, index($0,":")+1) }
    h ~ /RESOLVED/         { next }
    h ~ / - DONE$/         { next }
    h ~ /^## Summary/      { next }
    h ~ /^## Already Resolved/ { next }
    { c++ }
    END { print c+0 }
  '
}

# Glob of real report files (exclude dotfiles like .scheduler.log/.pipeline.log
# and the authoring template _TEMPLATE.md, whose placeholder H2s are not findings).
report_files() {
  find "$REPORTS_DIR" -maxdepth 1 -type f -name '*.md' ! -name '.*' ! -name '_TEMPLATE.md' 2>/dev/null | sort
}

reports_exist_nonempty() {
  local f
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    [[ -s "$f" ]] && return 0
  done < <(report_files)
  return 1
}

# Archive fully-resolved reports (count_open == 0) out of the live reports/ dir
# into reports/done/. Preserves the audit trail while scans stop re-reading spent
# files — report_files() is find -maxdepth 1, so reports/done/ is invisible to
# every scan/tally. Plain mv: reports/ is gitignored scratch (see
# ensure_reports_gitignored), so the archive is gitignored too, no commit. On a
# basename collision in done/ (same code unit resurfaced a later cycle) splice a
# UTC stamp before .md rather than clobber the earlier archive. Idempotent.
# Sets ARCHIVED_COUNT to the number moved this call.
ARCHIVED_COUNT=0
archive_resolved_reports() {
  ARCHIVED_COUNT=0
  local done_dir="$REPORTS_DIR/done"
  local f base target stamp
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    [[ "$(count_open "$f")" == "0" ]] || continue
    mkdir -p "$done_dir"
    base="$(basename "$f")"
    target="$done_dir/$base"
    if [[ -e "$target" ]]; then
      stamp="$(date -u +%Y%m%dT%H%M%SZ)"
      target="$done_dir/${base%.md}.$stamp.md"
    fi
    if mv "$f" "$target"; then
      log "ARCHIVE moved $base -> done/$(basename "$target")"
      ARCHIVED_COUNT=$((ARCHIVED_COUNT + 1))
    fi
  done < <(report_files)
}

# Pull the last stream-json result line from a claude session log and emit
# "in out cache_read cache_creation cost". Always rc 0 with 5 numeric fields,
# even when jq is missing, the log is absent, or no result line was written — so
# callers' read/arithmetic never trip set -e.
extract_usage() {
  local log="$1" line out='0 0 0 0 0'
  if [[ -s "$log" ]] && command -v jq >/dev/null 2>&1; then
    line="$(grep -E '"type":"result"' "$log" 2>/dev/null | tail -1 || true)"
    if [[ -n "$line" ]]; then
      out="$(printf '%s\n' "$line" | jq -r '
        [ (.usage.input_tokens // 0), (.usage.output_tokens // 0),
          (.usage.cache_read_input_tokens // 0),
          (.usage.cache_creation_input_tokens // 0),
          (.total_cost_usd // 0) ] | join(" ")' 2>/dev/null || true)"
      [[ -n "$out" ]] || out='0 0 0 0 0'
    fi
  fi
  printf '%s\n' "$out"
}

# shellcheck disable=SC2016  # intentional literal prompt — $-tokens must not expand
STAGE1_PROMPT='Run the /improve-codebase-architecture analysis on THIS repository in SCAN-ONLY, headless mode.

CRITICAL behavior overrides (this is an automated batch run, no human present):
- Do steps 1-2 of the skill (Explore + identify deepening opportunities) ONLY.
- SKIP step 2 candidate-presentation-to-user and SKIP step 3 grilling loop entirely. Do NOT ask the user anything. Do NOT call AskUserQuestion or ExitPlanMode. Never wait for input.
- For EACH deepening opportunity you would have presented, instead WRITE it to disk as a finding report in the audit-finding format.

Output contract — write findings as report files:
- One H2 finding per opportunity. Group findings by their owning code unit (crate/package/module): all findings whose primary file lives in unit <U> go into reports/architecture-<U>.md (kebab-case unit slug).
- Create reports/ if missing. Create each report file with this header if it does not exist:

  # Findings: `<unit>`

  **Date**: <today YYYY-MM-DD>
  **Scope**: `<unit>`

  ---

- Then append each finding as exactly one H2 block:

  ## [architecture] <short specific title>

  **Severity**: <High|Medium|Low>

  **Files**:
  - `<path>:<line>` (concrete file:line, not vague)
  - `<additional file>`

  **Problem**:
  <Why the current architecture causes friction — shallow module, leaky seam, missing locality, etc. Use the deletion test.>

  **Fix**:
  <Concrete deepening: what interface/seam changes, what moves where. Point at files.>

  ---

Hard rules:
- Every finding MUST cite at least one concrete file:line. No vague "consider restructuring X" findings.
- Heading text must be unique after slugify within a file. If a finding with the same slug already exists, skip it.
- No YAML frontmatter in report files. Only reserved meta-H2s allowed: ## Summary, ## Already Resolved.
- Do NOT fix anything. Do NOT edit source code. Your only writes are the report files under reports/.
- When done, print a one-line summary: how many findings written across how many report files.'

# Stage 1: run the arch scan headless. Skips by default if reports already
# exist (avoids a duplicate expensive Opus pass on an accidental re-run).
run_scan() {
  ensure_reports_gitignored
  if [[ "$RESCAN" == "1" ]]; then
    log "SCAN --rescan: clearing prior reports/*.md"
    local f
    while IFS= read -r f; do [[ -n "$f" ]] && rm -f "$f"; done < <(report_files)
  elif reports_exist_nonempty; then
    log "SKIP stage 1 — reports already exist (use --rescan to force a fresh scan)"
    return 0
  fi

  log "SCAN start model=$ARCH_FIND_MODEL repo=$REPO_ROOT"
  local rc=0
  ( cd "$REPO_ROOT" && claude -p "$STAGE1_PROMPT" \
      --model "$ARCH_FIND_MODEL" \
      --permission-mode bypassPermissions \
      --output-format stream-json --verbose ) >>"$LOG" 2>&1 || rc=$?
  if [[ $rc -ne 0 ]]; then
    die "stage 1 scan failed (claude rc=$rc; see $LOG)"
  fi

  local f n
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    n="$(count_open "$f")"
    log "REPORT created $f findings=$n"
  done < <(report_files)
  reports_exist_nonempty || log "SCAN produced no report files (no findings)"

  # Stage-1 scan usage: the last result line in the append-only $LOG is this run's.
  local su_in su_out su_cr su_cc su_cost
  read -r su_in su_out su_cr su_cc su_cost < <(extract_usage "$LOG") || true
  log "USAGE scan in=$su_in out=$su_out cache_read=$su_cr cache_creation=$su_cc cost=\$$su_cost"
}

# Gate: tally open findings; stop unless --yes. Sweeps any already-fully-resolved
# reports into reports/done/ first (e.g. all findings shipped on a prior run), so
# they neither pad the tally nor linger as scratch.
gate() {
  archive_resolved_reports

  local total=0 f n
  GATE_REPORTS=()
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    n="$(count_open "$f")"
    (( n > 0 )) || continue
    GATE_REPORTS+=("$f")
    total=$((total + n))
  done < <(report_files)

  log "GATE ${total} open findings across ${#GATE_REPORTS[@]} report(s)"

  if (( total == 0 )); then
    if (( ARCHIVED_COUNT > 0 )); then
      log "DONE no open findings — archived $ARCHIVED_COUNT resolved report(s) -> reports/done/"
    else
      log "DONE no open findings — nothing to address."
    fi
    exit "$EXIT_SUCCESS"
  fi

  if [[ "$YES" != "1" ]]; then
    log "GATE stopped (review reports, then re-run with --yes to address)"
    local limflag=""
    (( LIMIT > 0 )) && limflag=" --limit $LIMIT"
    echo ""
    echo "  Reports written:"
    local r
    for r in "${GATE_REPORTS[@]}"; do echo "    - $r"; done
    echo ""
    echo "  Next: $SCRIPT_NAME --yes${limflag} $REPO_ROOT"
    exit "$EXIT_SUCCESS"
  fi
}

# Stage 2: hand reports to the scheduler. Inherits CLAUDE_MODEL + MAX_PARALLEL
# from the environment; passes --limit / --resume through.
run_address() {
  local -a sched_flags=()
  [[ "$RESUME" == "1" ]] && sched_flags+=("--resume")
  (( LIMIT > 0 )) && sched_flags+=("--limit" "$LIMIT")

  log "STAGE2 handoff scheduler=$SCHEDULER reports=${#GATE_REPORTS[@]} flags=[${sched_flags[*]:-}]"

  # Lower-bound stamp (UTC, same format as the scheduler's session-log stamps) so
  # report_usage counts only THIS run's worker logs, not leftovers from --resume.
  RUN_START_STAMP="$(date -u +%Y%m%dT%H%M%SZ)"

  # Snapshot pre-run open counts for the manifest. Indexed array aligned to
  # GATE_REPORTS by position (bash 3.2 — macOS default — has no associative
  # arrays or namerefs). Global so `manifest` can read it without a nameref.
  PRE_OPEN_BY_IDX=()
  local i
  for i in "${!GATE_REPORTS[@]}"; do
    PRE_OPEN_BY_IDX[i]="$(count_open "${GATE_REPORTS[$i]}")"
  done

  local rc=0
  ( cd "$REPO_ROOT" && "$SCHEDULER" "${sched_flags[@]+"${sched_flags[@]}"}" "${GATE_REPORTS[@]}" ) || rc=$?

  manifest "$rc"
  archive_resolved_reports
  (( ARCHIVED_COUNT > 0 )) && log "ARCHIVE swept $ARCHIVED_COUNT resolved report(s) -> reports/done/"
  report_usage
  return "$rc"
}

# Final manifest block: per report → addressed/remaining count, then per finding
# → its PR# (scraped from the scheduler's "WORKER done <base>:<slug> #<pr>"
# lines), then kept-worktree count. The per-finding PR attribution is the useful
# audit unit — a flat PR list loses which finding shipped where.
manifest() {
  local rc="$1"
  local sched_log="$REPORTS_DIR/.scheduler.log"
  log "MANIFEST stage 2 finished (scheduler rc=$rc)"
  local i f base post pre addressed line
  for i in "${!GATE_REPORTS[@]}"; do
    f="${GATE_REPORTS[$i]}"
    base="$(basename "$f" .md)"
    post="$(count_open "$f" 2>/dev/null || echo 0)"
    pre="${PRE_OPEN_BY_IDX[$i]:-0}"
    addressed=$(( pre - post ))
    (( addressed < 0 )) && addressed=0
    log "MANIFEST $(basename "$f") addressed=$addressed remaining=$post"
    # Per-finding PR lines for this report's basename, e.g.
    #   "WORKER done architecture-foo:leaky-seam #123 (pending ...)"
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      log "MANIFEST   $line"
    done < <(grep -oE "WORKER done ${base}:[^ ]+ #[0-9]+" "$sched_log" 2>/dev/null \
               | sed -E 's/^WORKER done //' | sort -u || true)
  done
  local kept
  kept="$(find "$REPO_ROOT/../.worktrees" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ' || echo 0)"
  log "MANIFEST kept worktrees: $kept (run --cleanup to sweep)"
  if (( rc == 0 )); then
    log "DONE pipeline complete."
  else
    log "FAILED stage 2 reported failures — inspect $sched_log + kept worktrees."
  fi
}

# Per-session + grand-total token usage for the cloud runs in THIS pipeline
# invocation: the stage-1 scan (from $LOG) + each stage-2 worker (from the
# scheduler's reports/.sessions/*.log — read-only; the scheduler is never
# edited). The scheduler's triage-judge session captures its usage into a shell
# variable, never to a log file, so it cannot be reported here.
report_usage() {
  local sessions_dir="$REPORTS_DIR/.sessions"
  local f namep stamp label u
  local -a rows=()

  # Stage-1 scan row (already logged in run_scan; re-read here for the total).
  rows+=("scan $(extract_usage "$LOG")")

  # Stage-2 worker rows for this run. The stamp filter drops leftover .sessions
  # logs from earlier --resume runs (stamp < this run's start).
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    namep="$(basename "$f" .log)"
    stamp="${namep##*-}"
    [[ -n "${RUN_START_STAMP:-}" && "$stamp" < "$RUN_START_STAMP" ]] && continue
    label="$(printf '%s' "$namep" | sed -E 's/-[0-9]{8}T[0-9]{6}Z$//')"
    u="$(extract_usage "$f")"
    local w_in w_out w_cr w_cc w_cost
    read -r w_in w_out w_cr w_cc w_cost <<<"$u" || true
    log "USAGE worker $label in=$w_in out=$w_out cache_read=$w_cr cache_creation=$w_cc cost=\$$w_cost"
    rows+=("$label $u")
  done < <(find "$sessions_dir" -maxdepth 1 -type f -name '*.log' 2>/dev/null | sort)

  # One awk pass sums integer tokens + the float cost (bash 3.2 can't do floats).
  # Row layout: "<label> <in> <out> <cache_read> <cache_creation> <cost>".
  local total
  total="$(printf '%s\n' "${rows[@]}" | awk '
    { n++; i+=$2; o+=$3; cr+=$4; cc+=$5; cost+=$6 }
    END { printf "%d %d %d %d %d %.4f", n, i, o, cr, cc, cost }')"
  local t_n t_in t_out t_cr t_cc t_cost
  read -r t_n t_in t_out t_cr t_cc t_cost <<<"$total" || true
  log "USAGE TOTAL sessions=$t_n in=$t_in out=$t_out cache_read=$t_cr cache_creation=$t_cc cost=\$$t_cost"
}

on_interrupt() {
  local yesflag=""
  [[ "$YES" == "1" ]] && yesflag=" --yes"
  log "INTERRUPTED signal received — reports + worktrees left intact (resumable)"
  log "INTERRUPTED resume with: $SCRIPT_NAME --resume${yesflag} ${REPO_ROOT:-$TARGET_ARG}"
  exit "$EXIT_FAILURE"
}

main() {
  RUN_START_STAMP=''   # set in run_address; safe default for stage-2-skipping paths
  parse_args "$@"
  validate_env
  trap on_interrupt INT TERM

  if [[ "$CLEANUP" == "1" ]]; then
    local -a rs=()
    local f
    while IFS= read -r f; do [[ -n "$f" ]] && rs+=("$f"); done < <(report_files)
    if [[ ${#rs[@]} -eq 0 ]]; then
      log "DONE cleanup: no report files to key worktrees off — nothing to sweep."
      exit "$EXIT_SUCCESS"
    fi
    log "pipeline delegating --cleanup to scheduler for ${#rs[@]} report(s)"
    ( cd "$REPO_ROOT" && "$SCHEDULER" --cleanup "${rs[@]}" )
    exit "$EXIT_SUCCESS"
  fi

  run_scan
  gate          # exits here unless --yes and there are open findings
  run_address
}

main "$@"
