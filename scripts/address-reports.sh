#!/usr/bin/env bash
# Parallel scheduler: process all open H2 findings across one or more report
# files concurrently via git worktrees, with a single shared MAX_PARALLEL
# worker pool. One PR per finding.
# See plan: ~/.claude/plans/address-reports-parallel.md
set -euo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME
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

_colorize_tag() {
  local msg="$1" head rest color
  head="${msg%%[[:space:]]*}"
  rest="${msg#"$head"}"
  case "$head" in
    REPORT)      color="$C_BOLD$C_CYAN" ;;
    LIMIT)       color="$C_BOLD$C_YELLOW" ;;
    WORKER)      color="$C_BOLD$C_BLUE" ;;
    SESSION)     color="$C_BOLD$C_MAGENTA" ;;
    DRY)         color="$C_BOLD$C_YELLOW" ;;
    SKIP)        color="$C_YELLOW" ;;
    FAILED)      color="$C_BOLD$C_RED" ;;
    DONE)        color="$C_BOLD$C_GREEN" ;;
    ABORT|ERROR) color="$C_BOLD$C_RED" ;;
    scheduler)   color="$C_BOLD$C_GREEN" ;;
    *)           color="" ;;
  esac
  if [[ -n "$color" ]]; then
    printf '%s%s%s%s' "$color" "$head" "$C_RESET" "$rest"
  else
    printf '%s' "$msg"
  fi
}

# Highlight structured fields inside a log line:
#   key=value         → cyan key, green value
#   slug names        → magenta (after "slug ")
#   #1234 PR refs     → bold yellow
#   /paths/...        → dim
#   sha1 hex (>=7)    → yellow
_highlight_fields() {
  local s="$1"
  # PR refs (#1234)
  s="$(printf '%s' "$s" | LC_ALL=C sed -E "s/(#[0-9]+)/${C_BOLD}${C_YELLOW}\1${C_RESET}/g")"
  # key=value  (alnum/underscore key, non-space value up to next space)
  s="$(printf '%s' "$s" | LC_ALL=C sed -E "s/([A-Za-z_][A-Za-z0-9_]*)=([^ ]+)/${C_CYAN}\1${C_RESET}=${C_GREEN}\2${C_RESET}/g")"
  # absolute paths
  s="$(printf '%s' "$s" | LC_ALL=C sed -E "s|(/[A-Za-z0-9_./-]+)|${C_DIM}\1${C_RESET}|g")"
  # bare SHA1 hex of length >=7 (avoid mangling already-colored text by anchoring on space boundaries)
  s="$(printf '%s' "$s" | LC_ALL=C sed -E "s/( )([0-9a-f]{7,40})( |$)/\1${C_YELLOW}\2${C_RESET}\3/g")"
  printf '%s' "$s"
}

log() {
  local ts colored
  ts="$(date -Iseconds 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [[ -n "$C_RESET" ]]; then
    colored="$(_colorize_tag "$*")"
    colored="$(_highlight_fields "$colored")"
  else
    colored="$*"
  fi
  printf '%s%s%s %s|%s %s\n' "$C_DIM" "$ts" "$C_RESET" "$C_DIM" "$C_RESET" "$colored"
  printf '%s | %s\n' "$ts" "$*" >>"$LOG"
}
die() { log "ERROR $*"; exit "$EXIT_FAILURE"; }

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [-h] [--resume] [--limit N] [--cleanup] <report-path>...

Process all open H2 findings across one or more <report-path> files in
parallel via git worktrees. One PR per finding. A single shared worker
pool is gated by MAX_PARALLEL across all reports. Scheduler owns report
writes (race-free).

Options:
    -h, --help    Show this help
    --resume      Self-heal a prior interrupted run: for each open finding,
                  reconcile against GitHub. If its PR already exists, mark it
                  RESOLVED and drop it (no duplicate PR); if a worktree was
                  left but no PR, remove it and re-dispatch fresh. Without
                  --resume the run fails closed on any stale worktree.
    --limit N     Address at most N open findings this run (the rest are
                  deferred to a later run). Findings are taken in worklist
                  order. Env: MAX_FINDINGS. 0 = no limit (default).
    --cleanup     Sweep stale worktrees (.worktrees/<base>-* siblings) for the
                  given report basenames, then exit. Does not dispatch workers.

Environment:
    MAX_PARALLEL  Worker pool size, shared across all reports (default: 2)
    MAX_FINDINGS  Default for --limit (default: 0 = no limit)
    CLAUDE_MODEL  Model id passed to claude --model (default: claude-sonnet-4-6)
    DRY_RUN=1     Print planned actions, do not spawn workers
    NO_COLOR=1    Disable ANSI (auto-off when not a TTY)

Output:
    reports/.scheduler.log                       High-level scheduler events
    reports/.sessions/<base>-<slug>-<stamp>.log  Per-worker claude session log

Examples:
    $SCRIPT_NAME reports/dry-violations-user.md
    $SCRIPT_NAME reports/dry-violations-user.md reports/docs-budget.md
    DRY_RUN=1 $SCRIPT_NAME reports/foo.md reports/bar.md
    MAX_PARALLEL=4 $SCRIPT_NAME reports/foo.md reports/bar.md
    $SCRIPT_NAME --limit 2 reports/arch-user.md
    $SCRIPT_NAME --resume reports/arch-user.md
    $SCRIPT_NAME --cleanup reports/arch-user.md
EOF
}

parse_args() {
  REPORTS=()
  CLEANUP=0
  RESUME=0
  LIMIT="${MAX_FINDINGS:-0}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)  usage; exit "$EXIT_SUCCESS" ;;
      --cleanup)  CLEANUP=1; shift ;;
      --resume)   RESUME=1; shift ;;
      --limit)    shift; [[ $# -gt 0 ]] || { echo "$SCRIPT_NAME: --limit requires an argument" >&2; exit "$EXIT_INVALID_ARGS"; }; LIMIT="$1"; shift ;;
      --limit=*)  LIMIT="${1#*=}"; shift ;;
      --)         shift; while [[ $# -gt 0 ]]; do REPORTS+=("$1"); shift; done ;;
      -*)         usage >&2; exit "$EXIT_INVALID_ARGS" ;;
      *)          REPORTS+=("$1"); shift ;;
    esac
  done
  [[ "$LIMIT" =~ ^[0-9]+$ ]] || { echo "$SCRIPT_NAME: --limit must be a non-negative integer: $LIMIT" >&2; exit "$EXIT_INVALID_ARGS"; }
  [[ ${#REPORTS[@]} -gt 0 ]] || { usage >&2; exit "$EXIT_INVALID_ARGS"; }
}

validate_env() {
  command -v git >/dev/null 2>&1 || die "git not found in PATH"
  git rev-parse --show-toplevel >/dev/null 2>&1 || die "not inside a git repo"
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  REPORTS_DIR="$REPO_ROOT/reports"
  LOG="$REPORTS_DIR/.scheduler.log"
  SESSIONS_DIR="$REPORTS_DIR/.sessions"
  WORKTREES_DIR="$REPO_ROOT/../.worktrees"
  # Worktrees live in a per-repo sibling dir ($REPO_ROOT/../.worktrees). The
  # parent must be writable or every `git worktree add` fails mid-run. Fail
  # fast with a clear message instead.
  local wt_parent
  wt_parent="$(cd "$REPO_ROOT/.." 2>/dev/null && pwd || true)"
  [[ -n "$wt_parent" ]] || die "cannot resolve worktree parent dir for $REPO_ROOT"
  [[ -w "$wt_parent" ]] || die "worktree parent not writable: $wt_parent (needed to create $WORKTREES_DIR)"
  [[ -d "$REPORTS_DIR" ]] || die "reports directory missing: $REPORTS_DIR"
  mkdir -p "$SESSIONS_DIR"

  REPORT_ABS_BY_IDX=()
  REPORT_BASE_BY_IDX=()
  local r abs base existing
  for r in "${REPORTS[@]}"; do
    [[ -f "$r" ]] || die "report not found: $r"
    abs="$(cd "$(dirname "$r")" && pwd)/$(basename "$r")"
    base="$(basename "$r" .md)"
    for existing in "${REPORT_BASE_BY_IDX[@]+"${REPORT_BASE_BY_IDX[@]}"}"; do
      [[ "$existing" != "$base" ]] || die "duplicate report basename '$base' (paths must have distinct filenames)"
    done
    REPORT_ABS_BY_IDX+=("$abs")
    REPORT_BASE_BY_IDX+=("$base")
  done

  MAX_PARALLEL="${MAX_PARALLEL:-2}"
  [[ "$MAX_PARALLEL" =~ ^[1-9][0-9]*$ ]] || die "MAX_PARALLEL must be a positive integer: $MAX_PARALLEL"
  DRY_RUN="${DRY_RUN:-0}"

  if [[ "$DRY_RUN" != "1" ]]; then
    command -v claude >/dev/null 2>&1 || die "claude CLI not found (needed unless DRY_RUN=1)"
    command -v gh     >/dev/null 2>&1 || die "gh CLI not found (needed unless DRY_RUN=1)"
  fi

  : >>"$LOG"
}

# kebab-case slug from heading text. Strip leading '## ', lowercase,
# non-alnum → '-', squeeze and trim '-'.
slugify() {
  local s="$1"
  s="${s#\#\# }"
  s="$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]')"
  s="$(printf '%s' "$s" | LC_ALL=C sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
  printf '%s' "$s"
}

# Emit "<line>:<slug>:<heading>" per open finding. Heading text retained verbatim.
parse_open_findings() {
  local report="$1" line heading slug
  while IFS=: read -r line heading; do
    # Skip closed / structural sections.
    if [[ "$heading" =~ RESOLVED ]] \
      || [[ "$heading" =~ \ -\ DONE$ ]] \
      || [[ "$heading" =~ ^##\ Summary ]] \
      || [[ "$heading" =~ ^##\ Already\ Resolved ]]; then
      continue
    fi
    slug="$(slugify "$heading")"
    [[ -n "$slug" ]] || continue
    printf '%s:%s:%s\n' "$line" "$slug" "$heading"
  done < <(grep -nE '^## ' "$report" || true)
}

# Detect duplicate slugs. Abort with line numbers if any.
check_duplicate_slugs() {
  local findings="$1" dup
  dup="$(printf '%s\n' "$findings" | awk -F: '{print $2}' | sort | uniq -d)"
  if [[ -n "$dup" ]]; then
    local s lines
    while IFS= read -r s; do
      lines="$(printf '%s\n' "$findings" | awk -F: -v s="$s" '$2==s {printf "%s%s", sep, $1; sep=","}')"
      die "duplicate slug '$s' at lines $lines"
    done <<<"$dup"
  fi
}

check_stale_worktrees() {
  mkdir -p "$WORKTREES_DIR"
  local base stale any_stale=0
  for base in "${REPORT_BASE_BY_IDX[@]}"; do
    stale="$(find "$WORKTREES_DIR" -maxdepth 1 -mindepth 1 -type d -name "${base}-*" 2>/dev/null || true)"
    if [[ -n "$stale" ]]; then
      any_stale=1
      log "ABORT stale worktrees found for report=$base:"
      while IFS= read -r p; do log "ABORT   $p"; done <<<"$stale"
    fi
  done
  (( any_stale == 0 )) || die "remove or inspect stale worktrees before re-running"
}

pin_base() {
  log "scheduler fetch origin main"
  git -C "$REPO_ROOT" fetch origin main >/dev/null 2>&1 || die "git fetch origin main failed"
  BASE_SHA="$(git -C "$REPO_ROOT" rev-parse origin/main)"
  log "scheduler base sha=$BASE_SHA"
}

# Append " — RESOLVED (YYYY-MM-DD, #PR)" to the H2 at given line in the report.
# Scheduler-only writer → no concurrency.
mark_resolved() {
  local report_abs="$1" lineno="$2" pr="$3" today suffix tmp
  today="$(date -u +%Y-%m-%d)"
  suffix=" — RESOLVED (${today}, #${pr})"
  tmp="$(mktemp)"
  awk -v ln="$lineno" -v sfx="$suffix" 'NR==ln {print $0 sfx; next} {print}' "$report_abs" >"$tmp"
  mv "$tmp" "$report_abs"
}

# Extract first PR number from a claude session log. /quick-ship prints
# a github.com/.../pull/<N> URL on success.
extract_pr_num() {
  local logf="$1"
  grep -oE 'github\.com/[^ )"]+/pull/[0-9]+' "$logf" 2>/dev/null \
    | head -n1 | grep -oE '[0-9]+$' || true
}

# Fallback: query GitHub for a PR opened from this worker's branch. Used when
# the worker shipped but the session log was truncated before /quick-ship
# printed the PR URL (e.g. long pre-push test hook).
extract_pr_num_from_gh() {
  local branch="$1"
  command -v gh >/dev/null 2>&1 || { printf ''; return; }
  gh pr list --head "$branch" --state all --json number \
    --jq '.[0].number' 2>/dev/null || true
}

# Worker runs in a backgrounded subshell. MUST NOT edit the report file
# (would race with sibling workers). Writes a status sentinel for the
# scheduler to consume post-wait.
#   success → $SESSIONS_DIR/<slug>.success containing "<lineno> <pr>"
#   failure → no .success file; worktree kept with FAILED marker
run_worker() {
  local idx="$1" slug="$2" heading="$3" lineno="$4"
  local report_abs="${REPORT_ABS_BY_IDX[$idx]}"
  local report_base="${REPORT_BASE_BY_IDX[$idx]}"
  local wt branch session_log stamp rc pr tag
  tag="${report_base}:${slug}"
  wt="$WORKTREES_DIR/${report_base}-${slug}"
  branch="address/${report_base}-${slug}"
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  session_log="$SESSIONS_DIR/${report_base}-${slug}-${stamp}.log"

  rm -f "$SESSIONS_DIR/${idx}-${slug}.success"
  log "WORKER start $tag"

  # Collision-safe dispatch: the branch name is deterministic, so a prior aborted
  # run can leave it orphaned (worktree swept, `branch -D` never ran) and the
  # `-b` below would fail with "a branch named ... already exists". This is the
  # same hazard reconcile_resume() handles on --resume, hoisted here so every
  # dispatch is safe. Only drop a stale branch with NO terminal (OPEN/MERGED) PR —
  # a branch backing a live PR is a real conflict that must surface, not be nuked.
  if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$branch"; then
    if [[ -n "$(resume_terminal_pr "$branch")" ]]; then
      log "FAILED $tag (stale branch $branch has a terminal PR; reconcile manually or run --resume)"
      return 1
    fi
    git -C "$REPO_ROOT" worktree prune >/dev/null 2>&1 || true
    git -C "$REPO_ROOT" branch -D "$branch" >/dev/null 2>&1 \
      && log "WORKER $tag deleted stale local branch $branch for clean re-dispatch"
    if git -C "$REPO_ROOT" ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
      git -C "$REPO_ROOT" push origin --delete "$branch" >/dev/null 2>&1 \
        && log "WORKER $tag deleted stale remote branch origin/$branch (no terminal PR)"
    fi
  fi

  if ! git -C "$REPO_ROOT" worktree add "$wt" -b "$branch" "$BASE_SHA" >>"$session_log" 2>&1; then
    log "FAILED $tag (worktree add failed; see $session_log)"
    return 1
  fi

  set +e
  ( cd "$wt" && ADDRESS_FINDINGS_AUTO=1 claude -p "/address-findings $report_abs --finding $slug --auto" \
      --model "${CLAUDE_MODEL:-claude-sonnet-4-6}" \
      --permission-mode bypassPermissions \
      --output-format stream-json --verbose ) >>"$session_log" 2>&1
  rc=$?
  set -e

  if [[ $rc -ne 0 ]]; then
    log "FAILED $tag (claude rc=$rc; worktree kept at $wt; log $session_log)"
    touch "$wt/FAILED"
    return 1
  fi

  pr="$(extract_pr_num "$session_log")"
  if [[ -z "$pr" ]]; then
    pr="$(extract_pr_num_from_gh "$branch")"
    if [[ -n "$pr" ]]; then
      log "WORKER $tag PR# from gh fallback (#$pr; session log lacked URL)"
    fi
  fi
  if [[ -z "$pr" ]]; then
    log "FAILED $tag (no PR# in session log or gh; worktree kept at $wt; log $session_log)"
    touch "$wt/FAILED"
    return 1
  fi

  printf '%s %s\n' "$lineno" "$pr" >"$SESSIONS_DIR/${idx}-${slug}.success"
  log "WORKER done $tag #$pr (pending scheduler mark + worktree cleanup)"
  return 0
}

# Scheduler-side: consume a worker's success sentinel. Single process,
# race-free. Edits report and removes worktree.
finalize_success() {
  local idx="$1" slug="$2"
  local report_abs="${REPORT_ABS_BY_IDX[$idx]}"
  local report_base="${REPORT_BASE_BY_IDX[$idx]}"
  local sentinel="$SESSIONS_DIR/${idx}-${slug}.success"
  local wt="$WORKTREES_DIR/${report_base}-${slug}"
  local tag="${report_base}:${slug}"
  local lineno pr
  if ! read -r lineno pr <"$sentinel"; then
    log "FAILED $tag (success sentinel unreadable: $sentinel)"
    return 1
  fi
  mark_resolved "$report_abs" "$lineno" "$pr"
  rm -f "$sentinel"
  git -C "$REPO_ROOT" worktree remove "$wt" >/dev/null 2>&1 \
    || log "scheduler warn: could not remove worktree $wt"
  return 0
}

# Reap any finished pids in the pool. Mutates pids/slugs/succeeded/failed/failed_slugs
# in the caller's scope (function is invoked, not subshell'd).
# Uses kill -0 polling instead of `wait -n` so we never lose the pid→exit-code
# mapping needed to attribute success/failure to a slug.
_reap_finished() {
  local -a kept_pids=() kept_slugs=() kept_idxs=()
  local i pid s idx
  for i in "${!pids[@]}"; do
    pid="${pids[$i]}"; s="${slugs[$i]}"; idx="${idxs[$i]}"
    if kill -0 "$pid" 2>/dev/null; then
      kept_pids+=("$pid"); kept_slugs+=("$s"); kept_idxs+=("$idx")
    else
      if wait "$pid"; then
        if finalize_success "$idx" "$s"; then
          succeeded=$((succeeded + 1))
        else
          failed=$((failed + 1)); failed_tags+=("${REPORT_BASE_BY_IDX[$idx]}:${s}")
        fi
      else
        failed=$((failed + 1)); failed_tags+=("${REPORT_BASE_BY_IDX[$idx]}:${s}")
      fi
    fi
  done
  pids=("${kept_pids[@]+"${kept_pids[@]}"}")
  slugs=("${kept_slugs[@]+"${kept_slugs[@]}"}")
  idxs=("${kept_idxs[@]+"${kept_idxs[@]}"}")
}

dispatch_pool() {
  local findings="$1"
  # pids/slugs/idxs are GLOBAL (no `local`) so the SIGINT/SIGTERM trap can see
  # and signal in-flight workers. failed_tags stays local to this call.
  pids=(); slugs=(); idxs=()
  local -a failed_tags=()
  local succeeded=0 failed=0
  local idx lineno slug heading

  while IFS=: read -r idx lineno slug heading; do
    [[ -n "$slug" ]] || continue
    while (( ${#pids[@]} >= MAX_PARALLEL )); do
      sleep 1
      _reap_finished
    done
    run_worker "$idx" "$slug" "$heading" "$lineno" &
    pids+=("$!"); slugs+=("$slug"); idxs+=("$idx")
  done <<<"$findings"

  while (( ${#pids[@]} > 0 )); do
    sleep 1
    _reap_finished
  done

  log "scheduler summary: succeeded=$succeeded failed=$failed"
  if (( failed > 0 )); then
    log "FAILED kept worktrees:"
    local t base slug
    for t in "${failed_tags[@]}"; do
      base="${t%%:*}"; slug="${t#*:}"
      log "FAILED   $WORKTREES_DIR/${base}-${slug}"
    done
    return 1
  fi
  return 0
}

# --cleanup: sweep stale worktrees for the given report basenames, then exit.
# Removes tracked worktrees via git; falls back to rm -rf for untracked dirs.
do_cleanup() {
  mkdir -p "$WORKTREES_DIR"
  local base p removed=0
  for base in "${REPORT_BASE_BY_IDX[@]}"; do
    while IFS= read -r p; do
      [[ -n "$p" ]] || continue
      if git -C "$REPO_ROOT" worktree remove --force "$p" >/dev/null 2>&1; then
        log "scheduler cleanup removed worktree $p"
      else
        rm -rf "$p" && log "scheduler cleanup rm -rf $p (untracked)"
      fi
      removed=$((removed + 1))
    done < <(find "$WORKTREES_DIR" -maxdepth 1 -mindepth 1 -type d -name "${base}-*" 2>/dev/null || true)
  done
  git -C "$REPO_ROOT" worktree prune >/dev/null 2>&1 || true
  log "scheduler cleanup done removed=$removed"
}

# Reconcile-only PR check: a finding counts as TERMINAL (shipped, don't re-run)
# only if an OPEN or MERGED PR exists on its branch. A PR a human CLOSED without
# merging means the fix was rejected — that finding must re-dispatch, not be
# silently marked RESOLVED. (extract_pr_num_from_gh uses --state all and would
# wrongly match the closed PR — never use it for the resume terminal check.)
resume_terminal_pr() {
  local branch="$1"
  command -v gh >/dev/null 2>&1 || { printf ''; return; }
  gh pr list --head "$branch" --state all --json number,state \
    --jq '[.[] | select(.state=="OPEN" or .state=="MERGED")][0].number // empty' \
    2>/dev/null || true
}

# --resume reconcile: for every row in $combined, check GitHub for a terminal
# (OPEN/MERGED) PR on its deterministic branch (address/<base>-<slug>).
#   terminal PR → interrupted finalize: mark RESOLVED, drop worktree, drop row
#                (prevents the key hazard: a duplicate PR).
#   no terminal PR → worker died mid-fix (or its PR was rejected): remove the
#                leftover worktree + the stale local AND remote branch, keep the
#                row so it re-dispatches fresh from the pinned BASE_SHA.
# Mutates the global $combined in place.
reconcile_resume() {
  local new_combined="" idx lineno slug heading base branch wt pr
  while IFS=: read -r idx lineno slug heading; do
    [[ -n "$slug" ]] || continue
    base="${REPORT_BASE_BY_IDX[$idx]}"
    branch="address/${base}-${slug}"
    wt="$WORKTREES_DIR/${base}-${slug}"
    pr="$(resume_terminal_pr "$branch")"
    if [[ -n "$pr" ]]; then
      log "scheduler resume: $base:$slug already shipped #$pr — finalizing (mark + drop)"
      mark_resolved "${REPORT_ABS_BY_IDX[$idx]}" "$lineno" "$pr"
      if [[ -d "$wt" ]]; then
        git -C "$REPO_ROOT" worktree remove --force "$wt" >/dev/null 2>&1 || rm -rf "$wt"
      fi
      git -C "$REPO_ROOT" worktree prune >/dev/null 2>&1 || true
      continue
    fi
    if [[ -d "$wt" ]]; then
      log "scheduler resume: $base:$slug no terminal PR but leftover worktree — removing for re-dispatch"
      git -C "$REPO_ROOT" worktree remove --force "$wt" >/dev/null 2>&1 || rm -rf "$wt"
    fi
    # A dead worker leaves the branch behind (worktree add -b created it; it may
    # also have been pushed before dying). No OPEN/MERGED PR references it, so
    # both the local and any pushed remote copy are safe to drop — re-dispatch
    # needs a fresh -b branch from BASE_SHA, and a surviving remote branch would
    # otherwise cause a non-fast-forward push collision on the next ship.
    git -C "$REPO_ROOT" worktree prune >/dev/null 2>&1 || true
    if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$branch"; then
      git -C "$REPO_ROOT" branch -D "$branch" >/dev/null 2>&1 \
        && log "scheduler resume: deleted stale local branch $branch for clean re-dispatch"
    fi
    if git -C "$REPO_ROOT" ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
      git -C "$REPO_ROOT" push origin --delete "$branch" >/dev/null 2>&1 \
        && log "scheduler resume: deleted stale remote branch origin/$branch (no terminal PR)"
    fi
    new_combined+="${idx}:${lineno}:${slug}:${heading}"$'\n'
  done <<<"$combined"
  combined="${new_combined%$'\n'}"
}

# --limit N: keep the first N rows of $combined; defer the rest. Because
# resolved findings are filtered out by parse_open_findings, a later run with
# the same --limit automatically continues with the next batch.
apply_limit() {
  (( LIMIT > 0 )) || return 0
  local total deferred
  total="$(printf '%s\n' "$combined" | grep -c . || true)"
  (( total > LIMIT )) || return 0
  combined="$(printf '%s\n' "$combined" | head -n "$LIMIT")"
  deferred=$((total - LIMIT))
  log "LIMIT applied $LIMIT of $total open findings; $deferred deferred"
}

# Recursively TERM a process and all its descendants, children first. Portable
# (pgrep is on macOS + Linux; no setsid/process-group reliance). A worker pid is
# the `run_worker &` subshell, but the costly `claude` runs two levels down
# (subshell → `( … )` → claude), so a single-level kill would orphan it.
_kill_tree() {
  local pid="$1" child
  for child in $(pgrep -P "$pid" 2>/dev/null); do
    _kill_tree "$child"
  done
  kill -TERM "$pid" 2>/dev/null || true
}

# SIGINT/SIGTERM: stop in-flight workers (and their claude grandchildren), then
# leave worktrees + reports intact (resumable state) and print the exact resume
# command before exiting. Without killing the workers, a `kill -TERM` of the
# scheduler orphans them — they could open a PR after we announced the run
# frozen, racing a later --resume.
on_interrupt() {
  trap '' INT TERM   # ignore re-entry while we tear down
  local p killed=0
  for p in ${pids[@]+"${pids[@]}"}; do
    _kill_tree "$p"
    killed=$((killed + 1))
  done
  (( killed > 0 )) && log "INTERRUPTED signalled $killed in-flight worker(s)"
  wait 2>/dev/null || true
  log "INTERRUPTED worktrees + reports left intact (resumable)"
  log "INTERRUPTED resume with: $SCRIPT_NAME --resume ${REPORTS[*]:-<report-path>...}"
  exit "$EXIT_FAILURE"
}

main() {
  parse_args "$@"
  validate_env
  trap on_interrupt INT TERM

  if [[ "$CLEANUP" == "1" ]]; then
    do_cleanup
    exit "$EXIT_SUCCESS"
  fi

  local combined="" per_report count total=0 idx report_abs report_base
  for idx in "${!REPORT_ABS_BY_IDX[@]}"; do
    report_abs="${REPORT_ABS_BY_IDX[$idx]}"
    report_base="${REPORT_BASE_BY_IDX[$idx]}"
    per_report="$(parse_open_findings "$report_abs")"
    if [[ -z "$per_report" ]]; then
      log "REPORT skip $report_base (no open findings)"
      continue
    fi
    check_duplicate_slugs "$per_report"
    count="$(printf '%s\n' "$per_report" | wc -l | tr -d ' ')"
    log "REPORT enqueue $report_base findings=$count"
    total=$((total + count))
    # Prefix each row with idx → "idx:lineno:slug:heading"
    while IFS= read -r row; do
      [[ -n "$row" ]] || continue
      combined+="${idx}:${row}"$'\n'
    done <<<"$per_report"
  done

  if (( total == 0 )); then
    log "scheduler done (no open findings across ${#REPORTS[@]} reports)"
    exit "$EXIT_SUCCESS"
  fi

  # Strip trailing newline for clean here-string consumption.
  combined="${combined%$'\n'}"

  log "scheduler start: reports=${#REPORTS[@]} findings=$total MAX_PARALLEL=$MAX_PARALLEL LIMIT=$LIMIT RESUME=$RESUME DRY_RUN=$DRY_RUN"

  if [[ "$DRY_RUN" == "1" ]]; then
    apply_limit
    log "DRY worklist:"
    local r_idx r_base
    while IFS=: read -r r_idx lineno slug heading; do
      [[ -n "$slug" ]] || continue
      r_base="${REPORT_BASE_BY_IDX[$r_idx]}"
      log "DRY   report=$r_base line=$lineno slug=$slug wt=$WORKTREES_DIR/${r_base}-${slug} branch=address/${r_base}-${slug}"
    done <<<"$combined"
    log "DRY would: pin BASE_SHA, spawn up to $MAX_PARALLEL workers, mark RESOLVED per success"
    exit "$EXIT_SUCCESS"
  fi

  # --resume: reconcile against GitHub first (finalize already-shipped findings,
  # clear dead worktrees), THEN apply the batch limit to whatever remains.
  if [[ "$RESUME" == "1" ]]; then
    reconcile_resume
    if [[ -z "$combined" ]]; then
      log "scheduler done (resume reconciled all open findings; nothing left to dispatch)"
      exit "$EXIT_SUCCESS"
    fi
  fi

  apply_limit

  # check_stale_worktrees stays fail-closed by default — it forces inspection
  # of leftover worktrees. --resume opted into self-healing above, so skip it.
  if [[ "$RESUME" != "1" ]]; then
    check_stale_worktrees
  fi
  pin_base

  if dispatch_pool "$combined"; then
    log "scheduler done"
    exit "$EXIT_SUCCESS"
  else
    log "scheduler done with failures"
    exit "$EXIT_FAILURE"
  fi
}

main "$@"
