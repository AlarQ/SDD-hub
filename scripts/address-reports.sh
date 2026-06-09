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
  # $LOG is unset until validate_env resolves it; early die() (git/jq/repo checks)
  # would otherwise trip set -u with "LOG: unbound variable". Skip the file append
  # until it exists — stdout line already carried the message.
  if [[ -n "${LOG:-}" ]]; then
    printf '%s | %s\n' "$ts" "$*" >>"$LOG"
  fi
}
die() { log "ERROR $*"; exit "$EXIT_FAILURE"; }

# Work-unit globals, populated by the triage phase (run_triage).
#   UNIT_MEMBERS["<canon_idx>:<canon_slug>"] = "idx:slug:lineno;idx:slug:lineno;..."
#                                              (canonical first; includes canonical)
#   UNIT_TYPE["<canon_idx>:<canon_slug>"]    = duplicate | coupled | independent
# Consumed by run_worker / finalize_success / reconcile_resume / the DRY print.
declare -A UNIT_MEMBERS=()
declare -A UNIT_TYPE=()

# LLM judge prompt. The scheduler pipes a {"clusters":[…]} payload on stdin and
# expects the {"units":[…]} contract back (and nothing else). See run_triage_judge.
TRIAGE_PROMPT="$(cat <<'EOF'
You are a triage judge for a parallel code-fix scheduler. You receive JSON on
stdin: { "clusters": [ { "cluster_id": N, "findings": [ ... ] } ] }. Every
cluster groups findings that touch at least one shared file. Classify the
findings in EACH cluster into work units.

Definitions:
- duplicate  = the findings describe the SAME underlying problem; one fix
               resolves all of them.
- coupled    = distinct fixes that edit overlapping code and would conflict if
               run on separate branches; they must share one branch/PR.
- independent= same file but non-overlapping regions, safe to fix in parallel;
               emit each as its own 1-member unit.

Use the "cited_lines" field as a hint, but widen: if either fix could
plausibly edit beyond its cited lines into the other region, treat the pair as
coupled rather than independent.

Rules you MUST satisfy:
- Every input finding appears in exactly ONE output unit.
- "canonical_ref" must be one of the "member_refs" in the same unit.
- Refer to findings only by their "ref" field.

Output ONLY this JSON (no prose, no code fences):
{ "units": [ { "type": "duplicate|coupled|independent",
               "canonical_ref": "<ref>",
               "member_refs": ["<ref>", "..."],
               "reason": "one line" } ] }
EOF
)"

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [-h] [--resume] [--limit N] [--cleanup] <report-path>...

Process all open H2 findings across one or more <report-path> files in
parallel via git worktrees. A triage phase first clusters findings that
share a file and asks an LLM judge to classify each cluster as duplicate /
coupled / independent, collapsing the flat list into work units — one unit =
one worktree = one branch = one PR, carrying 1+ findings. A single shared
worker pool is gated by MAX_PARALLEL across all reports. Scheduler owns
report writes (race-free).

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
    DRY_RUN=1     Print planned actions, do not spawn workers. Note: DRY_RUN
                  does NOT write reports/.triage.json — run once without DRY_RUN
                  before --resume can load the manifest.
    NO_COLOR=1    Disable ANSI (auto-off when not a TTY)

Output:
    reports/.scheduler.log                       High-level scheduler events
    reports/.triage.json                         Per-run work-unit manifest (--resume loads it)
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
  command -v jq  >/dev/null 2>&1 || die "jq not found in PATH (needed for triage JSON)"
  git rev-parse --show-toplevel >/dev/null 2>&1 || die "not inside a git repo"
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  REPORTS_DIR="$REPO_ROOT/reports"
  LOG="$REPORTS_DIR/.scheduler.log"
  SESSIONS_DIR="$REPORTS_DIR/.sessions"
  TRIAGE_MANIFEST="$REPORTS_DIR/.triage.json"
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

  # GNU `timeout` is absent on stock macOS (it lives in coreutils as `gtimeout`).
  # Resolve whichever exists into a prefix array; if neither is present, leave it
  # empty so the judge call still runs (no enforced ceiling) instead of dying
  # rc=127. The rc==124 timeout-abort path only triggers when a binary was found.
  TIMEOUT_PREFIX=()
  if command -v timeout >/dev/null 2>&1; then
    TIMEOUT_PREFIX=(timeout "${TRIAGE_TIMEOUT:-7200}")
  elif command -v gtimeout >/dev/null 2>&1; then
    TIMEOUT_PREFIX=(gtimeout "${TRIAGE_TIMEOUT:-7200}")
  else
    log "WARN no timeout/gtimeout in PATH — triage judge runs without a time ceiling (install coreutils for gtimeout)"
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

# ── Triage phase ─────────────────────────────────────────────────────────────
# Collapse the flat finding list into work units before dispatch. Findings that
# share a file form candidate clusters; an LLM judge classifies each colliding
# cluster as duplicate | coupled | independent. One unit = one worktree = one
# branch = one PR, carrying 1+ findings.
# See plan: ~/.claude/plans/currently-i-have-this-glowing-platypus.md

# Print the H2 body for the finding at $lineno: the heading line through the line
# before the next `## ` (or EOF).
extract_finding_block() {
  local report_abs="$1" lineno="$2"
  awk -v s="$lineno" 'NR==s {cap=1; print; next} cap && /^## / {exit} cap {print}' "$report_abs"
}

# From an H2 body on stdin, print the raw lines of the `**Files**:` section (the
# Files line itself plus following bullet lines, until the next bold field).
_files_section() {
  awk '
    /^\*\*Files\*\*/ { infiles=1; rest=$0; sub(/^\*\*Files\*\*:?[[:space:]]*/,"",rest); if (rest != "") print rest; next }
    infiles && /^[[:space:]]*-/   { print; next }
    infiles && /^\*\*/            { infiles=0; next }
    infiles && /^[[:space:]]*$/   { next }
    infiles                      { infiles=0 }
  '
}

# File paths cited by a finding (coarse: any path-like token, line suffix stripped).
# shellcheck disable=SC2016  # backticks/`$` are literal regex, not expansions
parse_finding_files() {
  _files_section \
    | grep -oE '`[^`]+`|[^[:space:],()]+' \
    | sed -E 's/^`//; s/`$//; s/:[0-9]+(-[0-9]+)?$//' \
    | grep -E '[/.]' \
    | grep -vE '^\*\*' \
    | sed -E 's#^\./##' \
    | sort -u || true
}

# `path:line` hints (the judge widens these; they do not gate clustering).
# shellcheck disable=SC2016  # backticks/`$` are literal regex, not expansions
parse_finding_cited() {
  _files_section \
    | grep -oE '`[^`]+`|[^[:space:],()]+' \
    | sed -E 's/^`//; s/`$//' \
    | grep -E '[/.].*:[0-9]+' \
    | sed -E 's/:([0-9]+)-[0-9]+$/:\1/' \
    | sort -u || true
}

# Severity word (lowercased) from a finding body on stdin; empty if absent.
parse_finding_severity() {
  { grep -iE '^\*\*Severity\*\*' \
    | head -n1 \
    | sed -E 's/^\*\*[Ss]everity\*\*:?[[:space:]]*//; s/[[:space:]]*$//' \
    | tr '[:upper:]' '[:lower:]' \
    | awk '{print $1}'; } || true
}

severity_rank() {
  case "$1" in
    critical)            printf '4' ;;
    high)                printf '3' ;;
    medium|moderate)     printf '2' ;;
    low)                 printf '1' ;;
    *)                   printf '0' ;;
  esac
}

# Build per-finding metadata indexed by flat position (0..P_COUNT-1) over the
# current $combined, plus a ref→position map. ref = "<base>:<slug>" (unique).
build_finding_metadata() {
  declare -gA REF_POS=()
  declare -gA F_HEADING=()
  declare -ga P_IDX=() P_SLUG=() P_LINENO=() P_HEADING=() P_SEV=() P_FILES=() P_CITED=()
  local pos=0 idx lineno slug heading report_abs block
  while IFS=: read -r idx lineno slug heading; do
    [[ -n "$slug" ]] || continue
    report_abs="${REPORT_ABS_BY_IDX[$idx]}"
    block="$(extract_finding_block "$report_abs" "$lineno")"
    P_IDX[pos]="$idx"
    P_SLUG[pos]="$slug"
    P_LINENO[pos]="$lineno"
    P_HEADING[pos]="$heading"
    P_SEV[pos]="$(printf '%s\n' "$block" | parse_finding_severity)"
    P_FILES[pos]="$(printf '%s\n' "$block" | parse_finding_files)"
    P_CITED[pos]="$(printf '%s\n' "$block" | parse_finding_cited)"
    REF_POS["${REPORT_BASE_BY_IDX[$idx]}:${slug}"]="$pos"
    F_HEADING["${idx}:${slug}"]="$heading"
    pos=$((pos + 1))
  done <<<"$combined"
  P_COUNT="$pos"
}

# Union-find clustering: two findings cluster iff they share ≥1 file path.
# Populates CLUSTERS — one entry per cluster, space-separated positions, both
# the positions within a cluster and the cluster list sorted ascending.
_uf_find() {
  local x="$1"
  while [[ "${_PARENT[$x]}" != "$x" ]]; do
    _PARENT[$x]="${_PARENT[${_PARENT[$x]}]}"
    x="${_PARENT[$x]}"
  done
  printf '%s' "$x"
}
_uf_union() {
  local ra rb
  ra="$(_uf_find "$1")"; rb="$(_uf_find "$2")"
  [[ "$ra" == "$rb" ]] && return 0
  _PARENT[$rb]="$ra"
}
build_clusters() {
  declare -gA _PARENT=()
  local p f
  for ((p = 0; p < P_COUNT; p++)); do _PARENT[$p]="$p"; done
  declare -A file_first=()
  for ((p = 0; p < P_COUNT; p++)); do
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      if [[ -n "${file_first[$f]:-}" ]]; then
        _uf_union "${file_first[$f]}" "$p"
      else
        file_first[$f]="$p"
      fi
    done <<<"${P_FILES[$p]}"
  done
  declare -A root_members=()
  local r
  for ((p = 0; p < P_COUNT; p++)); do
    r="$(_uf_find "$p")"
    root_members[$r]="${root_members[$r]:-} $p"
  done
  local -a tmp=()
  for r in "${!root_members[@]}"; do
    # shellcheck disable=SC2086
    tmp+=("$(printf '%s\n' ${root_members[$r]} | grep . | sort -n | tr '\n' ' ' | sed -E 's/ +$//' || true)")
  done
  CLUSTERS=()
  while IFS= read -r r; do
    [[ -n "$r" ]] && CLUSTERS+=("$r")
  done < <(printf '%s\n' "${tmp[@]}" | sort -n)
}

# One JSON finding object for the judge payload, by position.
_json_finding() {
  local pos="$1" ref body
  ref="${REPORT_BASE_BY_IDX[${P_IDX[$pos]}]}:${P_SLUG[$pos]}"
  body="$(extract_finding_block "${REPORT_ABS_BY_IDX[${P_IDX[$pos]}]}" "${P_LINENO[$pos]}")"
  jq -cn --arg ref "$ref" --argjson idx "${P_IDX[$pos]}" --argjson lineno "${P_LINENO[$pos]}" \
    --arg sev "${P_SEV[$pos]}" --arg heading "${P_HEADING[$pos]}" --arg body "$body" \
    --arg files "${P_FILES[$pos]}" --arg cited "${P_CITED[$pos]}" \
    '{ref:$ref, report_idx:$idx, lineno:$lineno, severity:$sev,
      files:($files|split("\n")|map(select(length>0))),
      cited_lines:($cited|split("\n")|map(select(length>0))),
      heading:$heading, body:$body}'
}

# {"clusters":[…]} payload for the given multi-finding cluster strings.
build_judge_payload() {
  local cid=0 clusters="[]" cl findings f pos
  local -a pp=()
  for cl in "$@"; do
    findings="[]"
    read -ra pp <<<"$cl"
    for pos in "${pp[@]}"; do
      f="$(_json_finding "$pos")"
      findings="$(jq -c --argjson f "$f" '. + [$f]' <<<"$findings")"
    done
    clusters="$(jq -c --argjson cid "$cid" --argjson fs "$findings" '. + [{cluster_id:$cid, findings:$fs}]' <<<"$clusters")"
    cid=$((cid + 1))
  done
  jq -cn --argjson cs "$clusters" '{clusters:$cs}'
}

# Invoke the judge. Returns the raw {"units":[…]} JSON on stdout. Fail-closed:
# any non-zero/timeout aborts the whole run before workers spawn (decision 6).
# Test hook: TRIAGE_VERDICT_FILE short-circuits the claude call with a canned file.
run_triage_judge() {
  local payload="$1" verdict inner rc
  if [[ -n "${TRIAGE_VERDICT_FILE:-}" ]]; then
    [[ -f "$TRIAGE_VERDICT_FILE" ]] || die "ABORT TRIAGE_VERDICT_FILE not found: $TRIAGE_VERDICT_FILE"
    cat "$TRIAGE_VERDICT_FILE"
    return 0
  fi
  set +e
  verdict="$(printf '%s' "$payload" | "${TIMEOUT_PREFIX[@]+"${TIMEOUT_PREFIX[@]}"}" claude -p "$TRIAGE_PROMPT" \
      --model "${CLAUDE_MODEL:-claude-sonnet-4-6}" \
      --permission-mode bypassPermissions --output-format json 2>>"$LOG")"
  rc=$?
  set -e
  (( rc == 124 )) && die "ABORT triage judge timed out (>${TRIAGE_TIMEOUT:-7200}s) — fail-closed, no workers spawned"
  (( rc == 0 )) || die "ABORT triage judge call failed (rc=$rc) — fail-closed, no workers spawned"
  # claude --output-format json wraps the answer in an envelope; the model's text
  # lives in .result. Strip any stray code fences before handing it to the parser.
  inner="$(jq -r '.result // empty' <<<"$verdict" 2>/dev/null || true)"
  [[ -n "$inner" ]] || inner="$verdict"
  printf '%s' "$inner" | sed -E '/^[[:space:]]*```/d'
}

_ref_in_list() {
  local needle="$1"; shift
  local x
  for x in "$@"; do [[ "$x" == "$needle" ]] && return 0; done
  return 1
}

# Deterministic canonical pick (judge fallback): highest severity, tie → lowest
# report_idx, tie → lowest lineno.
_pick_canonical() {
  local best="" best_rank=-1 best_idx=999999 best_line=999999 ref pos rank idx line
  for ref in "$@"; do
    pos="${REF_POS[$ref]}"
    rank="$(severity_rank "${P_SEV[$pos]}")"
    idx="${P_IDX[$pos]}"; line="${P_LINENO[$pos]}"
    if (( rank > best_rank )) \
       || { (( rank == best_rank )) && (( idx < best_idx )); } \
       || { (( rank == best_rank )) && (( idx == best_idx )) && (( line < best_line )); }; then
      best="$ref"; best_rank="$rank"; best_idx="$idx"; best_line="$line"
    fi
  done
  printf '%s' "$best"
}

# Append a serialized unit "type|canon_idx:canon_slug:canon_lineno|members" to
# UNITS_SER, given positions (used for singletons).
_append_unit_positions() {
  local type="$1" canon_pos="$2"; shift 2
  local canon="${P_IDX[$canon_pos]}:${P_SLUG[$canon_pos]}:${P_LINENO[$canon_pos]}"
  local members="" pos
  for pos in "$@"; do
    members+="${P_IDX[$pos]}:${P_SLUG[$pos]}:${P_LINENO[$pos]};"
  done
  UNITS_SER+=("${type}|${canon}|${members%;}")
}

# Same, given refs (canonical placed first). Used by the verdict parser.
_append_unit_refs() {
  local type="$1" canon="$2"; shift 2
  local cpos="${REF_POS[$canon]}"
  local canon_ser="${P_IDX[$cpos]}:${P_SLUG[$cpos]}:${P_LINENO[$cpos]}"
  local members="${canon_ser};" ref pos
  for ref in "$@"; do
    [[ "$ref" == "$canon" ]] && continue
    pos="${REF_POS[$ref]}"
    members+="${P_IDX[$pos]}:${P_SLUG[$pos]}:${P_LINENO[$pos]};"
  done
  UNITS_SER+=("${type}|${canon_ser}|${members%;}")
}

# Parse the judge verdict into UNITS_SER, enforcing the contract:
# valid type, canonical_ref ∈ member_refs, refs known, and the units partition
# the judged findings exactly once. Any violation → die (fail-closed).
parse_verdict_into_units() {
  local verdict="$1"; shift
  local -a multi=("$@")
  jq -e '.units | type == "array"' >/dev/null 2>&1 <<<"$verdict" \
    || die "ABORT triage judge returned malformed JSON (no .units array) — fail-closed"
  local input_refs cl pos
  local -a pp=()
  input_refs="$(for cl in "${multi[@]}"; do read -ra pp <<<"$cl"; for pos in "${pp[@]}"; do printf '%s\n' "${REPORT_BASE_BY_IDX[${P_IDX[$pos]}]}:${P_SLUG[$pos]}"; done; done | sort)"
  local n i type canon r seen=""
  n="$(jq '.units | length' <<<"$verdict")"
  for ((i = 0; i < n; i++)); do
    type="$(jq -r ".units[$i].type" <<<"$verdict")"
    case "$type" in duplicate|coupled|independent) ;; *) die "ABORT triage unit $i has bad type '$type' — fail-closed" ;; esac
    local -a mrefs=()
    while IFS= read -r r; do [[ -n "$r" ]] && mrefs+=("$r"); done < <(jq -r ".units[$i].member_refs[]?" <<<"$verdict")
    (( ${#mrefs[@]} > 0 )) || die "ABORT triage unit $i has empty member_refs — fail-closed"
    canon="$(jq -r ".units[$i].canonical_ref // empty" <<<"$verdict")"
    [[ -n "$canon" ]] || canon="$(_pick_canonical "${mrefs[@]}")"
    _ref_in_list "$canon" "${mrefs[@]}" || die "ABORT triage unit $i canonical_ref '$canon' not in member_refs — fail-closed"
    for r in "${mrefs[@]}"; do
      [[ -n "${REF_POS[$r]:-}" ]] || die "ABORT triage unit $i references unknown finding '$r' — fail-closed"
      seen+="${r}"$'\n'
    done
    _append_unit_refs "$type" "$canon" "${mrefs[@]}"
  done
  local seen_sorted
  seen_sorted="$(printf '%s' "$seen" | grep . | sort || true)"
  [[ "$seen_sorted" == "$input_refs" ]] \
    || die "ABORT triage units do not partition the judged findings exactly once — fail-closed"
}

# Fresh-run unit assembly: singletons become independent units directly (no
# judge); multi-finding clusters go to the judge in one batched call.
assemble_units() {
  UNITS_SER=()
  local cl pos cnt
  local -a pp=() multi=()
  for cl in "${CLUSTERS[@]}"; do
    read -ra pp <<<"$cl"
    cnt="${#pp[@]}"
    if (( cnt == 1 )); then
      pos="${pp[0]}"
      _append_unit_positions independent "$pos" "$pos"
    else
      multi+=("$cl")
    fi
  done
  if (( ${#multi[@]} > 0 )); then
    local payload verdict
    payload="$(build_judge_payload "${multi[@]}")"
    verdict="$(run_triage_judge "$payload")"
    parse_verdict_into_units "$verdict" "${multi[@]}"
  fi
}

# Staleness fingerprint of the input reports. The scheduler is itself the writer
# of the "— RESOLVED (date, #PR)" markers (mark_resolved appends them in place as
# units ship), so hashing raw file content would make every partial run
# invalidate its own manifest on --resume. Strip the scheduler's own marker
# suffix before hashing: a partial run no longer trips the guard, while a human
# editing finding text (or adding/removing a finding) still changes the hash and
# is correctly flagged stale. Both the written and the checked hash flow through
# this one function, so the strip is symmetric.
_reports_hash() {
  cat "${REPORT_ABS_BY_IDX[@]}" \
    | sed -E 's/ — RESOLVED \([^)]*\)//g' \
    | shasum -a 256 | awk '{print $1}'
}

# "idx:slug:lineno" → {report_idx,slug,lineno}
_ser_to_json() {
  local idx slug lineno
  IFS=: read -r idx slug lineno <<<"$1"
  jq -cn --argjson idx "$idx" --arg slug "$slug" --argjson lineno "$lineno" \
    '{report_idx:$idx, slug:$slug, lineno:$lineno}'
}
# "idx:slug:lineno;…" → [ {…}, … ]
_members_to_json() {
  local arr="[]" m
  local -a parts=()
  IFS=';' read -ra parts <<<"$1"
  for m in "${parts[@]}"; do
    [[ -n "$m" ]] || continue
    arr="$(jq -c --argjson o "$(_ser_to_json "$m")" '. + [$o]' <<<"$arr")"
  done
  printf '%s' "$arr"
}

# Persist UNITS_SER as reports/.triage.json (decision 8). Fresh runs overwrite;
# --resume loads instead of re-judging.
write_triage_manifest() {
  local hash units="[]" u type rest canon members
  hash="$(_reports_hash)"
  for u in "${UNITS_SER[@]}"; do
    type="${u%%|*}"; rest="${u#*|}"; canon="${rest%%|*}"; members="${rest#*|}"
    units="$(jq -c --arg type "$type" --argjson canon "$(_ser_to_json "$canon")" --argjson members "$(_members_to_json "$members")" \
      '. + [{canonical:$canon, type:$type, members:$members}]' <<<"$units")"
  done
  jq -n --arg hash "$hash" --argjson units "$units" \
    '{base_shas:null, input_hash:$hash, units:$units}' >"$TRIAGE_MANIFEST"
}

# --resume: load the manifest into UNITS_SER (no judge). Fail-closed if the
# manifest is missing/malformed or the reports changed since triage (stale hash).
load_triage_manifest() {
  [[ -f "$TRIAGE_MANIFEST" ]] || die "ABORT --resume requires $TRIAGE_MANIFEST (run without --resume first)"
  jq -e '.units | type == "array"' >/dev/null 2>&1 <"$TRIAGE_MANIFEST" \
    || die "ABORT malformed triage manifest: $TRIAGE_MANIFEST"
  local stored current
  stored="$(jq -r '.input_hash // empty' <"$TRIAGE_MANIFEST")"
  current="$(_reports_hash)"
  if [[ -n "$stored" && "$stored" != "$current" ]]; then
    die "ABORT triage manifest stale (report contents changed since triage) — re-run without --resume"
  fi
  UNITS_SER=()
  local n i type cidx cslug clineno members m
  n="$(jq '.units | length' <"$TRIAGE_MANIFEST")"
  for ((i = 0; i < n; i++)); do
    type="$(jq -r ".units[$i].type" <"$TRIAGE_MANIFEST")"
    cidx="$(jq -r ".units[$i].canonical.report_idx" <"$TRIAGE_MANIFEST")"
    cslug="$(jq -r ".units[$i].canonical.slug" <"$TRIAGE_MANIFEST")"
    clineno="$(jq -r ".units[$i].canonical.lineno" <"$TRIAGE_MANIFEST")"
    members=""
    while IFS= read -r m; do [[ -n "$m" ]] && members+="${m};"; done \
      < <(jq -r ".units[$i].members[] | \"\(.report_idx):\(.slug):\(.lineno)\"" <"$TRIAGE_MANIFEST")
    UNITS_SER+=("${type}|${cidx}:${cslug}:${clineno}|${members%;}")
  done
}

# Project UNITS_SER onto the scheduler's existing spine: populate UNIT_MEMBERS /
# UNIT_TYPE and rewrite $combined to canonical-only rows (idx:lineno:slug:heading).
# All downstream functions then iterate units, not raw findings.
materialize_units() {
  UNIT_MEMBERS=()
  UNIT_TYPE=()
  local u type rest canon members cidx cslug clineno heading new=""
  for u in "${UNITS_SER[@]}"; do
    type="${u%%|*}"; rest="${u#*|}"; canon="${rest%%|*}"; members="${rest#*|}"
    IFS=: read -r cidx cslug clineno <<<"$canon"
    UNIT_MEMBERS["${cidx}:${cslug}"]="$members"
    UNIT_TYPE["${cidx}:${cslug}"]="$type"
    heading="${F_HEADING["${cidx}:${cslug}"]:-$cslug}"
    new+="${cidx}:${clineno}:${cslug}:${heading}"$'\n'
  done
  combined="${new%$'\n'}"
}

# Orchestrate triage. Fresh: metadata → cluster → judge → manifest. Resume: load
# the manifest (no judge). Both end by materializing units onto $combined.
run_triage() {
  build_finding_metadata
  if [[ "$RESUME" == "1" ]]; then
    load_triage_manifest
  else
    build_clusters
    assemble_units
    [[ "$DRY_RUN" == "1" ]] || write_triage_manifest
  fi
  materialize_units
}

# Mark every member H2 of a unit RESOLVED with the same #PR (decisions 2, 3).
mark_unit_resolved() {
  local cidx="$1" cslug="$2" pr="$3"
  # Internal invariant: materialize_units always populates UNIT_MEMBERS for every
  # canonical key. A genuinely-missing entry would otherwise fall back to lineno 0,
  # whose mark_resolved awk (NR==0) silently never fires — the finding stays open
  # forever while the PR is counted a success and the worktree is removed. Fail
  # loud instead of swallowing it.
  [[ -n "${UNIT_MEMBERS["${cidx}:${cslug}"]:-}" ]] \
    || die "internal invariant violated: no UNIT_MEMBERS entry for canonical ${cidx}:${cslug} (materialize_units should have populated it)"
  local members="${UNIT_MEMBERS["${cidx}:${cslug}"]}"
  local m midx mslug mlineno
  local -a parts=()
  IFS=';' read -ra parts <<<"$members"
  for m in "${parts[@]}"; do
    [[ -n "$m" ]] || continue
    IFS=: read -r midx mslug mlineno <<<"$m"
    mark_resolved "${REPORT_ABS_BY_IDX[$midx]}" "$mlineno" "$pr"
  done
}

# Worktree dir name is "<base>-<slug>" with no delimiter marking the boundary, so
# the glob "<base>-*" over-matches when one report basename is a strict prefix of
# another (docs vs docs-budget): docs-* also matches docs-budget-<slug>. Attribute
# a dir to the LONGEST known basename that prefixes it — "docs" never claims a dir
# that "docs-budget" owns. Disambiguation is only possible (and only attempted)
# among the basenames passed to this invocation; print "" when none prefixes it.
_dir_owner_base() {
  local dirname="$1" b best=""
  for b in "${REPORT_BASE_BY_IDX[@]}"; do
    case "$dirname" in
      "$b"-*) (( ${#b} > ${#best} )) && best="$b" ;;
    esac
  done
  printf '%s' "$best"
}

check_stale_worktrees() {
  mkdir -p "$WORKTREES_DIR"
  local base p any_stale=0
  for base in "${REPORT_BASE_BY_IDX[@]}"; do
    while IFS= read -r p; do
      [[ -n "$p" ]] || continue
      [[ "$(_dir_owner_base "$(basename "$p")")" == "$base" ]] || continue
      if (( any_stale == 0 )); then
        any_stale=1
        log "ABORT stale worktrees found:"
      fi
      log "ABORT   $p (report=$base)"
    done < <(find "$WORKTREES_DIR" -maxdepth 1 -mindepth 1 -type d -name "${base}-*" 2>/dev/null || true)
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
  if awk -v ln="$lineno" -v sfx="$suffix" 'NR==ln {print $0 sfx; next} {print}' "$report_abs" >"$tmp" \
    && mv "$tmp" "$report_abs"; then
    return 0
  fi
  rm -f "$tmp"
  die "mark_resolved: failed to rewrite $report_abs (line $lineno)"
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

  # A unit carries 1+ findings (independent=1, duplicate/coupled=N). Build a
  # repeatable --finding <report>:<slug> arg per member; the skill fixes them all
  # in this one worktree → one PR. Branch/worktree/sentinel stay keyed on the
  # canonical (idx,slug) — the unit identity — so the spine below is unchanged.
  local members="${UNIT_MEMBERS["${idx}:${slug}"]:-${idx}:${slug}:${lineno}}"
  local -a fargs=() marr=()
  local m midx mslug mlineno
  IFS=';' read -ra marr <<<"$members"
  for m in "${marr[@]}"; do
    [[ -n "$m" ]] || continue
    IFS=: read -r midx mslug mlineno <<<"$m"
    fargs+=(--finding "${REPORT_ABS_BY_IDX[$midx]}:${mslug}")
  done

  rm -f "$SESSIONS_DIR/${idx}-${slug}.success"
  log "WORKER start $tag (type=${UNIT_TYPE["${idx}:${slug}"]:-independent} members=${#marr[@]})"

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
  ( cd "$wt" && ADDRESS_FINDINGS_AUTO=1 claude -p "/address-findings $report_abs ${fargs[*]} --auto" \
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
  local report_base="${REPORT_BASE_BY_IDX[$idx]}"
  local sentinel="$SESSIONS_DIR/${idx}-${slug}.success"
  local wt="$WORKTREES_DIR/${report_base}-${slug}"
  local tag="${report_base}:${slug}"
  local lineno pr
  if ! read -r lineno pr <"$sentinel"; then
    log "FAILED $tag (success sentinel unreadable: $sentinel)"
    return 1
  fi
  # One PR closes the whole unit: mark every member H2 (across reports) RESOLVED
  # with the same #PR (decisions 2, 3). One worktree removed.
  mark_unit_resolved "$idx" "$slug" "$pr"
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
      # Skip dirs a longer-prefix sibling basename owns (see _dir_owner_base).
      [[ "$(_dir_owner_base "$(basename "$p")")" == "$base" ]] || continue
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
      log "scheduler resume: $base:$slug already shipped #$pr — finalizing unit (mark all members + drop)"
      mark_unit_resolved "$idx" "$slug" "$pr"
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

# --limit N: keep the first N rows of $combined; defer the rest. After triage
# $combined is canonical-only (one row = one work unit), so the limit caps UNITS
# and a bundle is never split (a unit is one atomic row). Because resolved
# findings are filtered out by parse_open_findings, a later run continues with
# the next batch.
apply_limit() {
  (( LIMIT > 0 )) || return 0
  local total deferred
  total="$(printf '%s\n' "$combined" | grep -c . || true)"
  (( total > LIMIT )) || return 0
  combined="$(printf '%s\n' "$combined" | head -n "$LIMIT")"
  deferred=$((total - LIMIT))
  log "LIMIT applied $LIMIT of $total work units; $deferred deferred"
}

# Recursively TERM a process and all its descendants, children first. Portable
# (pgrep is on macOS + Linux; no setsid/process-group reliance). A worker pid is
# the `run_worker &` subshell, but the costly `claude` runs two levels down
# (subshell → `( … )` → claude), so a single-level kill would orphan it.
# shellcheck disable=SC2329  # invoked indirectly via on_interrupt (trap), not statically traceable
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
# shellcheck disable=SC2329  # invoked indirectly via `trap on_interrupt INT TERM`, not statically traceable
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

  # Triage: cluster findings by shared file, judge colliding clusters, and
  # collapse the flat list into work units. Fresh runs judge + write the manifest;
  # --resume loads it (no re-judge). After this, $combined is canonical-only.
  run_triage
  log "scheduler triage: findings=$total units=${#UNITS_SER[@]}"

  if [[ "$DRY_RUN" == "1" ]]; then
    apply_limit
    log "DRY worklist (work units):"
    local r_idx r_base r_lineno r_slug r_members m mb ms pretty
    while IFS=: read -r r_idx r_lineno r_slug _; do
      [[ -n "$r_slug" ]] || continue
      r_base="${REPORT_BASE_BY_IDX[$r_idx]}"
      r_members="${UNIT_MEMBERS["${r_idx}:${r_slug}"]:-${r_idx}:${r_slug}:${r_lineno}}"
      pretty=""
      local -a marr=()
      IFS=';' read -ra marr <<<"$r_members"
      for m in "${marr[@]}"; do
        [[ -n "$m" ]] || continue
        IFS=: read -r mb ms _ <<<"$m"
        pretty+="${REPORT_BASE_BY_IDX[$mb]}:${ms},"
      done
      log "DRY   unit type=${UNIT_TYPE["${r_idx}:${r_slug}"]:-independent} canonical=$r_base:$r_slug branch=address/${r_base}-${r_slug} wt=$WORKTREES_DIR/${r_base}-${r_slug} members=[${pretty%,}]"
    done <<<"$combined"
    log "DRY would: pin BASE_SHA, spawn up to $MAX_PARALLEL workers, mark all unit members RESOLVED per success"
    # FIX 4: DRY never writes the manifest (no side effects), so a non-DRY run is
    # the only thing that can produce reports/.triage.json that --resume loads.
    log "DRY NOTE manifest NOT written in DRY mode — run without DRY_RUN before --resume can load $TRIAGE_MANIFEST"
    # FIX 3: reconcile_resume mutates report files / worktrees / makes gh calls, so
    # it is intentionally skipped in DRY mode. The preview therefore reflects the
    # PRE-reconcile worklist — units already shipped (terminal PR) may still appear.
    if [[ "$RESUME" == "1" ]]; then
      log "DRY NOTE --resume preview is PRE-reconcile (reconcile is mutating, skipped in DRY) — already-shipped units may still appear above"
    fi
    exit "$EXIT_SUCCESS"
  fi

  # --resume: reconcile units against GitHub first (finalize already-shipped
  # units, clear dead worktrees), THEN apply the batch limit to whatever remains.
  if [[ "$RESUME" == "1" ]]; then
    reconcile_resume
    if [[ -z "$combined" ]]; then
      log "scheduler done (resume reconciled all work units; nothing left to dispatch)"
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
