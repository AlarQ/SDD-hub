#!/usr/bin/env bash
# validate-impl.sh — sourced helpers for the /validate-impl command (FR-15, ADR-008).
# Builds the Karen wrapper prompt, persists the audit report, and emits monitor events.
# Depends on: config-loader.sh (caller sources it first), monitor.sh (sourced by helpers).
# shellcheck disable=SC1090,SC1091

if [[ "${WF_VALIDATE_IMPL_LOADED:-0}" == "1" ]]; then
  return 0 2>/dev/null || exit 0
fi
WF_VALIDATE_IMPL_LOADED=1

_wf_vi_dir() { cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd; }
# shellcheck source=scripts/monitor.sh
source "$(_wf_vi_dir)/monitor.sh"

wf_vi__err() { echo "ERROR: $*" >&2; }

# wf_vi_parse_frs <spec.md> -> stdout: FR ids, one per line (FR-1, FR-2, ...)
wf_vi_parse_frs() {
  local spec_md="$1"
  [[ -f "$spec_md" ]] || { wf_vi__err "spec.md missing: $spec_md"; return 1; }
  grep -E '^### FR-[0-9]+:' "$spec_md" | sed -E 's/^### (FR-[0-9]+):.*/\1/'
}

# wf_vi_diff_range <feature> -> stdout: <merge-base>..HEAD
wf_vi_diff_range() {
  local feature="$1"
  local base="feat/$feature"
  local mb
  mb="$(git merge-base main "$base" 2>/dev/null || git rev-parse "${base}^" 2>/dev/null || echo HEAD~1)"
  printf '%s..HEAD' "$mb"
}

# wf_vi_build_prompt <feature> <spec_dir> [extra_evidence_file]
# -> stdout: full Karen wrapper prompt
wf_vi_build_prompt() {
  local feature="$1" spec_dir="$2" extra="${3:-}"
  local spec_md="$spec_dir/spec.md" prd_md="$spec_dir/prd.md"
  local tasks_dir="$spec_dir/tasks" reports_dir="$spec_dir/reports"
  local fr_list task_list report_paths diff_range
  fr_list="$(wf_vi_parse_frs "$spec_md")" || return 1
  task_list="$(find "$tasks_dir" -maxdepth 1 -name '*.md' -print 2>/dev/null | sort)"
  report_paths="$(find "$reports_dir" -maxdepth 2 -name '*.md' -o -name '*.yaml' 2>/dev/null | sort || true)"
  diff_range="$(wf_vi_diff_range "$feature")"

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
