#!/usr/bin/env bash
# validate-impl.sh — sourced helpers for the /validate-impl command (FR-15, ADR-008).
# Builds the Odium wrapper prompt, persists the audit report, and emits monitor events.
# Depends on: config-loader.sh (caller sources it first), monitor.sh (sourced by helpers).
# shellcheck disable=SC1090,SC1091

if [[ "${WF_VALIDATE_IMPL_LOADED:-0}" == "1" ]]; then
  return 0 2>/dev/null || exit 0
fi
WF_VALIDATE_IMPL_LOADED=1

_wf_vi_dir() { cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd; }
# shellcheck source=scripts/monitor.sh
source "$(_wf_vi_dir)/monitor.sh"
# shellcheck source=scripts/gate-ceiling.sh
source "$(_wf_vi_dir)/gate-ceiling.sh"

wf_vi__err() { echo "ERROR: $*" >&2; }

# wf_vi_parse_frs <spec.md> -> stdout: FR ids, one per line (FR-1, FR-2, ...)
wf_vi_parse_frs() {
  local spec_md="$1"
  [[ -f "$spec_md" ]] || { wf_vi__err "spec.md missing: $spec_md"; return 1; }
  grep -E '^### FR-[0-9]+:' "$spec_md" | sed -E 's/^### (FR-[0-9]+):.*/\1/'
}

# wf_vi_diff_range <feature> -> stdout: <merge-base>..HEAD
# Fails loudly (rc 5) when neither `merge-base main feat/<feature>` nor
# `feat/<feature>^` can be resolved. No silent HEAD~1 fallback — auditing the
# wrong diff range would silently corrupt the spec-completion report.
wf_vi_diff_range() {
  local feature="$1"
  local base="feat/$feature"
  local mb
  if mb="$(git merge-base main "$base" 2>/dev/null)" && [[ -n "$mb" ]]; then
    printf '%s..HEAD' "$mb"
    return 0
  fi
  if mb="$(git rev-parse "${base}^" 2>/dev/null)" && [[ -n "$mb" ]]; then
    printf '%s..HEAD' "$mb"
    return 0
  fi
  echo "ERROR: Cannot determine diff range for $feature; refusing to audit" >&2
  return 5
}

# wf_vi_build_prompt <feature> <spec_dir> [extra_evidence_file]
# -> stdout: full Odium wrapper prompt
wf_vi_build_prompt() {
  local feature="$1" spec_dir="$2" extra="${3:-}"
  local spec_md="$spec_dir/spec.md" prd_md="$spec_dir/prd.md"
  local tasks_dir="$spec_dir/tasks" reports_dir="$spec_dir/reports"
  local fr_list task_list report_paths diff_range
  fr_list="$(wf_vi_parse_frs "$spec_md")" || return 1
  task_list="$(find "$tasks_dir" -maxdepth 1 -name '*.md' -print 2>/dev/null | sort)"
  report_paths="$(find "$reports_dir" -maxdepth 2 \( -name '*.md' -o -name '*.yaml' \) 2>/dev/null | sort || true)"
  diff_range="$(wf_vi_diff_range "$feature")" || return $?

  printf '# Spec Completion Audit — %s\n\n' "$feature"
  printf 'You are auditing spec `%s` for claimed-vs-actual completion. Output Markdown.\n\n' "$feature"
  printf '## FR Allowlist\n\nReject any FR id not in this list:\n\n'
  printf '%s\n' "$fr_list" | sed 's/^/- /'
  printf '\n## PRD Scope\n\n'
  if [[ -f "$prd_md" ]]; then
    awk '/^## (IN|OUT) (of )?[Ss]cope/,/^## /' "$prd_md" | sed '$d'
  else
    printf '_(prd.md missing)_\n'
  fi
  printf '\n## Tasks\n\n'
  printf '%s\n' "$task_list" | sed 's|^|- |'
  printf '\n## Existing Reports\n\n'
  if [[ -n "$report_paths" ]]; then printf '%s\n' "$report_paths" | sed 's|^|- |'; else printf '_(none)_\n'; fi
  printf '\n## Git Diff Range\n\n`%s`\n\n' "$diff_range"
  if [[ -n "$extra" && -f "$extra" ]]; then
    printf '## Additional Evidence — Failing Gate Output\n\n```\n'
    cat "$extra"
    printf '\n```\n\n'
  fi
  printf '## Required Output\n\n'
  printf 'Produce a single Markdown document with:\n\n'
  printf '1. YAML frontmatter `feature`, `timestamp`, `scope`, `verdict ∈ {complete, reopen}`.\n'
  printf '2. **FR × Status Matrix** — table with one row per FR id above. Status ∈ `{implemented, partial, missing}`.\n'
  printf '3. **Orphan Code** — code paths in the diff not traceable to any FR.\n'
  printf '4. **Over-Engineering Flags** — anything outside PRD scope.\n\n'
  printf 'Verdict `complete` only if every FR is `implemented` and no blocking gate failed.\n'
}

# wf_vi_write_report <feature> <spec_dir> <verdict> <body_file> -> stdout: report path
wf_vi_write_report() {
  local feature="$1" spec_dir="$2" verdict="$3" body_file="$4"
  case "$verdict" in complete|reopen) ;; *) wf_vi__err "invalid verdict: $verdict"; return 1 ;; esac
  local ts reports_dir out
  ts="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
  reports_dir="$spec_dir/reports"
  mkdir -p "$reports_dir"
  out="$reports_dir/spec-audit-$ts.md"
  {
    printf -- '---\n'
    printf 'feature: %s\n' "$feature"
    printf 'timestamp: %s\n' "$ts"
    printf 'scope: %s\n' "${WF_VALIDATE_SCOPE:-per-task}"
    printf 'verdict: %s\n' "$verdict"
    printf -- '---\n\n'
    [[ -f "$body_file" ]] && cat "$body_file"
  } > "$out"
  printf '%s' "$out"
}

# wf_vi_set_spec_shipped <spec_dir> — flips spec.md frontmatter status to shipped.
wf_vi_set_spec_shipped() {
  local spec_md="$1/spec.md"
  [[ -f "$spec_md" ]] || { wf_vi__err "spec.md missing: $spec_md"; return 1; }
  command -v yq >/dev/null 2>&1 || { wf_vi__err "yq required"; return 1; }
  yq --front-matter=process e -i '.status = "shipped"' "$spec_md"
}

# Canonical impls live in gate-ceiling.sh (wf_gc_*).

# wf_vi_run_union_gates <feature> <spec_dir> <log_file>
# Computes the union of spec-eligible gates ∩ language-applicable gates across
# all tasks in the spec, then executes each gate's `command` once.
# Stdout: a single JSON line `{"verdict":"reopen|"","gate_failures":[...],"log_path":"…"}`.
#   verdict        — "reopen" if any blocking gate failed, "" otherwise.
#   gate_failures  — array of {id,blocking,exit_code} for every non-zero gate exit.
#   log_path       — same value passed in as <log_file>.
# Side effects: appends each gate's stdout/stderr to <log_file>.
# Returns: 0 on normal completion (even if gates failed), 3 on empty-union
# fail-closed (ADR-003), 90 on missing yq.
wf_vi_run_union_gates() {
  local feature="$1" spec_dir="$2" log_file="$3"
  : > "$log_file"
  # Vault mode: caller (per scripts/multi-repo-resolution.md) sets
  # WF_TASK_GATE_POOL to the bound repo's .workflow.yml before invoking; repo
  # mode uses the single WF_GATE_POOL.
  local pool="${WF_TASK_GATE_POOL:-${WF_GATE_POOL:?WF_TASK_GATE_POOL or WF_GATE_POOL must be set}}"
  local ceiling="${WF_SPEC_GATES:-}"
  local tasks_dir="$spec_dir/tasks"
  local langs union code_bearing
  langs="$(wf_gc_union_languages "$tasks_dir")"
  union="$(wf_gc__intersect "$pool" "$ceiling" "$langs")"
  code_bearing=0
  [[ -n "$langs" ]] && code_bearing=1

  if [[ -z "$union" ]]; then
    if [[ "$code_bearing" == "1" ]]; then
      wf_vi__err "Empty union on code-bearing spec — fail-closed (ADR-003)."
      printf 'EMPTY_UNION_FAIL_CLOSED: spec=%s langs=[%s] ceiling=[%s]\n' \
        "$feature" "$(echo "$langs" | tr '\n' ' ')" "$(echo "$ceiling" | tr '\n' ' ')" >> "$log_file"
      return 3
    fi
    printf '{"verdict":"","gate_failures":[],"log_path":"%s"}' \
      "$(escape_json_string "$log_file")"
    return 0
  fi

  local forced="" id cmd blocking rc failures=""
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    cmd="$(wf_gc_gate_field "$pool" "$id" command)"
    blocking="$(wf_gc_gate_field "$pool" "$id" blocking)"
    # Fail closed: `blocking` must be exactly the JSON boolean true/false.
    # null/empty OR any non-bool literal (typo, "yes", "True", …) → "true",
    # so a typo can never silently disable the hard-block and the value is
    # always a valid JSON boolean when interpolated into the verdict below.
    [[ "$blocking" == "false" ]] || blocking="true"
    {
      printf -- '----- gate: %s (blocking=%s) -----\n' "$id" "$blocking"
      printf 'CMD: %s\n' "$cmd"
    } >> "$log_file"
    if [[ -z "$cmd" || "$cmd" == "null" ]]; then
      printf 'ERROR: gate %s has no command in pool\n' "$id" >> "$log_file"
      failures+="${failures:+,}$(printf '{"id":"%s","blocking":%s,"exit_code":-1}' \
        "$(escape_json_string "$id")" "$blocking")"
      [[ "$blocking" == "true" ]] && forced="reopen"
      continue
    fi
    bash -c "$cmd" >> "$log_file" 2>&1; rc=$?
    printf 'EXIT: %d\n' "$rc" >> "$log_file"
    if [[ "$rc" -ne 0 ]]; then
      failures+="${failures:+,}$(printf '{"id":"%s","blocking":%s,"exit_code":%d}' \
        "$(escape_json_string "$id")" "$blocking" "$rc")"
      [[ "$blocking" == "true" ]] && forced="reopen"
    fi
  done <<< "$union"

  printf '{"verdict":"%s","gate_failures":[%s],"log_path":"%s"}' \
    "$forced" "$failures" "$(escape_json_string "$log_file")"
}

# wf_vi_emit_start <feature>
wf_vi_emit_start() {
  log_event "$1" spec_audit_start "" '{}'
}
# wf_vi_emit_done <feature> <verdict> <report_path>
wf_vi_emit_done() {
  local feature="$1" verdict="$2" path="$3"
  log_event "$feature" spec_audit_done "" \
    "$(printf '{"verdict":"%s","report":"%s"}' "$verdict" "$(escape_json_string "$path")")"
}
# wf_vi_emit_complete <feature>
wf_vi_emit_complete() { log_event "$1" spec_complete "" '{}'; }
# wf_vi_emit_reopen <feature>
wf_vi_emit_reopen()   { log_event "$1" spec_reopened "" '{}'; }

# ===========================================================================
# Per-task coverage audit (Phase 3 of /validate). Task-scoped siblings of the
# spec-scoped helpers above. Reuse the same Odium agent (agents/odium.md
# untouched); only the wrapper prompt and report writer differ. The report is
# the YAML findings form (NOT wf_vi_write_report's markdown FR-matrix form) so
# /review-findings consumes it unchanged.
# ===========================================================================

# wf_vi_task_diff_range <feature> <task_file> -> stdout: <base>..HEAD
# All git runs in WF_TASK_REPO_PATH (vault/multi-repo safe; default cwd).
# Resolution order:
#   1. single-branch + resolvable task_base_sha → <sha>..HEAD
#   2. merge-base feat/<feature> HEAD            → <mb>..HEAD   (same range
#      Phase 2 hands advisory agents)
#   3. wf_vi_diff_range fallback (merge-base main feat/<feature>)
# Nothing resolves → rc 5 (loud fail; never a silent HEAD~1).
wf_vi_task_diff_range() {
  local feature="$1" task_file="$2"
  local gitdir="${WF_TASK_REPO_PATH:-.}"
  local sha mb
  sha="$(bash -c 'source ~/.claude/scripts/task-manager.sh && read_frontmatter "$1" .task_base_sha' _ "$task_file" 2>/dev/null)"
  sha="${sha//\"/}"
  [[ "$sha" == "null" ]] && sha=""
  if [[ "${WF_BRANCH_STRATEGY:-per-task}" == "single-branch" && -n "$sha" ]] \
     && git -C "$gitdir" rev-parse --verify --quiet "$sha" >/dev/null 2>&1; then
    printf '%s..HEAD' "$sha"
    return 0
  fi
  if mb="$(git -C "$gitdir" merge-base "feat/$feature" HEAD 2>/dev/null)" && [[ -n "$mb" ]]; then
    printf '%s..HEAD' "$mb"
    return 0
  fi
  local fb
  if fb="$(cd "$gitdir" 2>/dev/null && wf_vi_diff_range "$feature" 2>/dev/null)" && [[ -n "$fb" ]]; then
    printf '%s' "$fb"
    return 0
  fi
  echo "ERROR: wf_vi_task_diff_range: cannot resolve diff range for $feature (task $task_file); refusing to audit" >&2
  return 5
}

# wf_vi__task_acceptance_rows <task_file> (private) -> Given/When/Then body rows,
# skipping the header (`| # | Given …`) and separator (`|---|…`) rows.
wf_vi__task_acceptance_rows() {
  awk '/^## Acceptance/{f=1;next} /^## /{f=0}
       f && /^\|/ && $0 !~ /^\| *# *\| *Given/ && $0 !~ /^\|[-: |]+\|$/ {print}' "$1"
}

# wf_vi__task_fr_refs <task_file> (private) -> sorted-unique FR ids from the
# `## Implements` table's `| FR | … |` row.
wf_vi__task_fr_refs() {
  awk '/^## Implements/{f=1;next} /^## /{f=0} f && /^\| *FR *\|/ {print}' "$1" \
    | grep -oE 'FR-[0-9]+' | sort -u
}

# _wf_vi_yaml_dq <text> -> double-quoted, escaped YAML scalar.
_wf_vi_yaml_dq() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '"%s"' "$s"
}

# wf_vi_build_task_prompt <feature> <task_file> <spec_dir> <diff_range> -> prompt
# Per-task framing: audits the diff against the task's OWN acceptance only.
wf_vi_build_task_prompt() {
  local feature="$1" task_file="$2" spec_dir="$3" diff_range="$4"
  local task_id
  task_id="$(bash -c 'source ~/.claude/scripts/task-manager.sh && read_frontmatter "$1" .id' _ "$task_file" 2>/dev/null)"
  task_id="${task_id//\"/}"
  [[ -z "$task_id" || "$task_id" == "null" ]] && task_id="$(basename "$task_file" .md)"

  printf '# Per-Task Coverage Audit — %s / task %s\n\n' "$feature" "$task_id"
  printf 'Audit whether the implemented diff for **this single task** covers the task'\''s OWN acceptance criteria. Scope is the task, NOT the whole spec. Do not re-derive spec.md FRs. Output Markdown.\n\n'

  printf '## Acceptance Basis\n\n'
  if [[ "${WF_SPEC_TRACK:-feature}" == "technical" ]]; then
    printf 'Technical-track task. Acceptance points (from `technical_acceptance:` frontmatter):\n\n'
    local ta n=0
    while IFS= read -r ta; do
      [[ -z "$ta" ]] && continue
      n=$((n + 1))
      printf '%d. %s\n' "$n" "$ta"
    done < <(bash -c 'source ~/.claude/scripts/task-manager.sh && read_frontmatter "$1" ".technical_acceptance[]"' _ "$task_file" 2>/dev/null)
    [[ "$n" -eq 0 ]] && printf '_(none declared)_\n'
  else
    printf 'Feature-track task. Acceptance points (from `## Acceptance` Given/When/Then rows):\n\n'
    local rows; rows="$(wf_vi__task_acceptance_rows "$task_file")"
    if [[ -n "$rows" ]]; then printf '%s\n' "$rows"; else printf '_(no acceptance rows found)_\n'; fi
    printf '\n### FR Reference Allowlist\n\nReject any FR id not in this list:\n\n'
    local frs; frs="$(wf_vi__task_fr_refs "$task_file")"
    if [[ -n "$frs" ]]; then printf '%s\n' "$frs" | sed 's/^/- /'; else printf '_(none)_\n'; fi
  fi

  printf '\n## Git Diff Range\n\n`%s`\n\nRun `git diff %s` yourself to inspect the implemented change.\n\n' "$diff_range" "$diff_range"

  printf '## Required Output\n\n'
  printf 'Produce a single Markdown document with:\n\n'
  printf '1. YAML frontmatter: `feature`, `task_id`, `timestamp`, `verdict ∈ {complete, reopen}`.\n'
  printf '2. **Acceptance × Coverage Matrix** — a table with one row per acceptance point above. Columns: `point`, `status ∈ {covered, partial, missing}`, `evidence`.\n'
  printf '3. **Orphan Code** — code paths in the diff not traceable to any acceptance point.\n\n'
  printf 'Verdict `complete` only if EVERY acceptance point is `covered`. Any `partial` or `missing` point → `reopen`.\n'
}

# wf_vi_write_task_coverage_report <feature> <spec_dir> <task_id> <verdict> <matrix_file>
# -> stdout: report path (reports/<task-id>-coverage.yaml, gate id `coverage`).
# complete → status: pass, findings: []. reopen → one finding per missing/partial
# matrix row (severity high/medium, source: llm). Lenient parse: a table row is a
# finding only if a cell holds exactly `missing`/`partial`; everything else
# (covered rows, header, separator, unknown tokens) is skipped — never crashes.
wf_vi_write_task_coverage_report() {
  local feature="$1" spec_dir="$2" task_id="$3" verdict="$4" matrix_file="$5"
  case "$verdict" in complete|reopen) ;; *) wf_vi__err "invalid verdict: $verdict"; return 1 ;; esac
  local reports_dir="$spec_dir/reports" out
  mkdir -p "$reports_dir"
  out="$reports_dir/${task_id}-coverage.yaml"

  if [[ "$verdict" == "complete" ]]; then
    { printf 'gate: coverage\n'; printf 'task_id: %s\n' "$task_id"; printf 'status: pass\n'; printf 'findings: []\n'; } > "$out"
    printf '%s' "$out"; return 0
  fi

  local tmp_f; tmp_f="$(mktemp)"
  local n=0 row point status sev
  while IFS= read -r row; do
    [[ "$row" == \|* ]] || continue
    status="$(printf '%s' "$row" | tr '|' '\n' | sed 's/^ *//;s/ *$//' \
      | tr '[:upper:]' '[:lower:]' | grep -Ex 'missing|partial' | head -1)"
    case "$status" in
      missing) sev=high ;;
      partial) sev=medium ;;
      *) continue ;;
    esac
    point="$(printf '%s' "$row" | awk -F'|' '{print $2}' | sed 's/^ *//;s/ *$//')"
    [[ -z "$point" ]] && point="(unnamed acceptance point)"
    n=$((n + 1))
    {
      printf -- '  - id: coverage-%d\n' "$n"
      printf '    severity: %s\n' "$sev"
      printf '    category: coverage\n'
      printf '    title: %s\n' "$(_wf_vi_yaml_dq "$point")"
      printf '    description: %s\n' "$(_wf_vi_yaml_dq "Acceptance point not fully covered by the task diff (status: $status).")"
      printf '    review_status: pending\n'
      printf '    source: llm\n'
    } >> "$tmp_f"
  done < "$matrix_file"

  {
    printf 'gate: coverage\n'
    printf 'task_id: %s\n' "$task_id"
    if [[ "$n" -gt 0 ]]; then
      printf 'status: findings\n'
      printf 'findings:\n'
      cat "$tmp_f"
    else
      printf 'status: pass\n'
      printf 'findings: []\n'
    fi
  } > "$out"
  rm -f "$tmp_f"
  printf '%s' "$out"
}

# wf_vi_emit_coverage_start <feature> <task_id>
wf_vi_emit_coverage_start() { log_event "$1" coverage_audit_start "${2:-}" '{}'; }
# wf_vi_emit_coverage_done <feature> <task_id> <verdict> <report_path>
wf_vi_emit_coverage_done() {
  local feature="$1" task_id="$2" verdict="$3" path="$4"
  log_event "$feature" coverage_audit_done "$task_id" \
    "$(printf '{"verdict":"%s","report":"%s"}' "$verdict" "$(escape_json_string "$path")")"
}
