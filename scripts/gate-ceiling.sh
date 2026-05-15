#!/usr/bin/env bash
# gate-ceiling.sh — canonical helpers for ceiling/effective-set/union computation.
# One source of truth for gate selection used by /validate (per-task) and
# /validate-impl (spec-wide). Inputs come from env vars exported by config-loader.sh.
#
# Required env (caller must source config-loader.sh + wf_load_config first):
#   WF_GATE_POOL       absolute path to gates.yml (repo mode)
#   WF_TASK_GATE_POOL  per-task bound-repo gates.yml (vault mode; overrides
#                      WF_GATE_POOL). Resolve via scripts/multi-repo-resolution.md.
#   WF_SPEC_GATES      newline-separated ceiling gate IDs (spec eligible set)
#
# Public helpers:
#   wf_gc_task_languages <task_md>            -> language tags from one task
#   wf_gc_union_languages <tasks_dir>         -> union of tags across all tasks
#   wf_gc_gate_field <pool> <id> <field>      -> field value from gates.yml
#   wf_compute_effective_set <task_file>      -> per-task intersection (one id per line)
#   wf_compute_union_set <spec_dir>           -> spec-wide union (one id per line)
#
# Exit codes (effective_set / union_set):
#   0  ok, set printed (may be empty if task allows)
#   3  empty result on code-bearing input AND not allowed (fail-closed, ADR-003)
#   90 yq missing
#
# shellcheck disable=SC1090,SC1091

if [[ "${WF_GATE_CEILING_LOADED:-0}" == "1" ]]; then
  return 0 2>/dev/null || exit 0
fi
WF_GATE_CEILING_LOADED=1

wf_gc__err() { echo "ERROR: $*" >&2; }

wf_gc_task_languages() {
  local task_md="$1"
  [[ -f "$task_md" ]] || return 0
  awk '
    /^ground_rules:/ { in_gr=1; next }
    in_gr && /^[a-zA-Z_]+:/ { in_gr=0 }
    in_gr && /languages\// {
      sub(/.*languages\//, ""); sub(/\/.*/, ""); sub(/\.md.*/, "");
      print
    }
  ' "$task_md" | sort -u
}

wf_gc_union_languages() {
  local tasks_dir="$1"
  [[ -d "$tasks_dir" ]] || return 0
  local f
  while IFS= read -r f; do
    wf_gc_task_languages "$f"
  done < <(find "$tasks_dir" -maxdepth 1 -name '*.md' -print 2>/dev/null | sort) | sort -u
}

wf_gc_gate_field() {
  local pool="$1" id="$2" field="$3"
  command -v yq >/dev/null 2>&1 || return 90
  yq e -r ".gates[] | select(.id == \"$id\") | .$field" "$pool" 2>/dev/null
}

# Internal: ceiling ∩ {g | g.applies_to ∩ langs ≠ ∅ ∨ "any" ∈ g.applies_to}
wf_gc__intersect() {
  local pool="$1" ceiling="$2" langs="$3"
  command -v yq >/dev/null 2>&1 || { wf_gc__err "yq required"; return 90; }
  local lang_set=" any "
  while IFS= read -r l; do [[ -n "$l" ]] && lang_set="$lang_set$l "; done <<< "$langs"
  local id applies_json tag
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    applies_json="$(yq e -r ".gates[] | select(.id == \"$id\") | .applies_to[]" "$pool" 2>/dev/null)" || continue
    [[ -z "$applies_json" ]] && continue
    while IFS= read -r tag; do
      [[ -z "$tag" ]] && continue
      if [[ "$lang_set" == *" $tag "* ]]; then
        printf '%s\n' "$id"; break
      fi
    done <<< "$applies_json"
  done <<< "$ceiling" | sort -u
}

# wf_compute_effective_set <task_file>
# Per-task intersection. rc 3 if empty AND task frontmatter does not set
# `empty_intersection_ok: true` AND the task is code-bearing (has language tags).
wf_compute_effective_set() {
  local task_file="$1"
  # Vault mode: caller resolves the bound repo's gates.yml into
  # WF_TASK_GATE_POOL (see scripts/multi-repo-resolution.md). Repo mode:
  # WF_GATE_POOL from the single pool. One must be set.
  local pool="${WF_TASK_GATE_POOL:-${WF_GATE_POOL:?WF_TASK_GATE_POOL or WF_GATE_POOL must be set}}"
  local ceiling="${WF_SPEC_GATES:-}"
  [[ -f "$task_file" ]] || { wf_gc__err "task file missing: $task_file"; return 1; }
  local langs eff allow code_bearing
  langs="$(wf_gc_task_languages "$task_file")"
  code_bearing=0; [[ -n "$langs" ]] && code_bearing=1
  eff="$(wf_gc__intersect "$pool" "$ceiling" "$langs")" || return $?
  if [[ -z "$eff" && "$code_bearing" == "1" ]]; then
    allow="$(awk '/^empty_intersection_ok:/ {print $2; exit}' "$task_file" | tr -d '"')"
    [[ "$allow" == "true" ]] || return 3
  fi
  printf '%s' "$eff"
}

# wf_compute_union_set <spec_dir>
# Spec-wide union over all tasks under <spec_dir>/tasks/.
# rc 3 on empty union AND code-bearing spec.
wf_compute_union_set() {
  local spec_dir="$1"
  local pool="${WF_TASK_GATE_POOL:-${WF_GATE_POOL:?WF_TASK_GATE_POOL or WF_GATE_POOL must be set}}"
  local ceiling="${WF_SPEC_GATES:-}"
  local tasks_dir="$spec_dir/tasks"
  local langs union code_bearing
  langs="$(wf_gc_union_languages "$tasks_dir")"
  code_bearing=0; [[ -n "$langs" ]] && code_bearing=1
  union="$(wf_gc__intersect "$pool" "$ceiling" "$langs")" || return $?
  if [[ -z "$union" && "$code_bearing" == "1" ]]; then
    return 3
  fi
  printf '%s' "$union"
}
