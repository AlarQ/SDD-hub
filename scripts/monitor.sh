#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2088
set -euo pipefail

# monitor.sh — Event logger for the spec implementation monitoring system.
# Appends JSONL events to $WF_SPEC_STORAGE/<feature>/.monitor.jsonl.
# Source-able by other scripts: source ~/.claude/scripts/monitor.sh
# Public sourcing API: log_event, start_phase, end_phase, set_context,
#   read_context, clear_context, escape_json_string.
# No external dependencies (uses printf for JSON, date for timestamps).

MONITOR_CONTEXT_FILE=".monitor-context"

# === Bootstrap: source config-paths.sh and monitor-validators.sh if available ===
_wf_mon_self_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
_WF_MON_PATHS_LOADED=0
if [[ -f "$_wf_mon_self_dir/config-paths.sh" ]]; then
  # shellcheck source=scripts/config-paths.sh
  source "$_wf_mon_self_dir/config-paths.sh"
  _WF_MON_PATHS_LOADED=1
fi
# shellcheck source=scripts/monitor-validators.sh
[[ -f "$_wf_mon_self_dir/monitor-validators.sh" ]] && source "$_wf_mon_self_dir/monitor-validators.sh"
unset _wf_mon_self_dir

# Private: validate_id with label arg for readable error messages.
# Keeps config-paths.sh's canonical one-argument validate_id untouched.
_wf_mon_validate_labeled_id() {
  local value="${1:-}" label="${2:-id}"
  if [[ "$value" =~ ^[a-zA-Z0-9_-]{1,64}$ ]]; then return 0; fi
  echo "ERROR: Invalid $label: must be non-empty alphanumeric, hyphens, or underscores" >&2; return 1
}

# === Helpers (public when sourced) ===

get_timestamp() { date -u +"%Y-%m-%dT%H:%M:%S.000Z"; }
get_epoch()     { date +%s; }

escape_json_string() {
  local val="$1"
  val="${val//\\/\\\\}"; val="${val//\"/\\\"}"; val="${val//$'\n'/\\n}"; val="${val//$'\t'/\\t}"
  printf '%s' "$val"
}

# _find_workflow_root — delegates to wf_resolve_root (config-paths.sh) when loaded
_find_workflow_root() {
  if [[ "$_WF_MON_PATHS_LOADED" == "1" ]]; then
    wf_resolve_root "$PWD" 2>/dev/null || return 1
    return 0
  fi
  [[ -n "${WF_REPO_ROOT:-}" ]] && { printf '%s' "$WF_REPO_ROOT"; return 0; }
  return 1
}

get_spec_storage() {
  if [[ -n "${WF_SPEC_STORAGE:-}" ]]; then
    [[ "$WF_SPEC_STORAGE" == *".."* ]] && { echo "ERROR: WF_SPEC_STORAGE must not contain .." >&2; return 1; }
    printf '%s' "$WF_SPEC_STORAGE"; return 0
  fi
  local root
  root="$(_find_workflow_root)" || return 1
  if command -v yq >/dev/null 2>&1 && [[ -f "$root/.workflow.yml" ]]; then
    local raw
    raw="$(yq e '.spec_storage // "specs/"' "$root/.workflow.yml" 2>/dev/null)" || { echo "ERROR: Failed to read .workflow.yml" >&2; return 2; }
    case "$raw" in
      /*) printf '%s' "$raw" ;;
      "~"|"~/"*) printf '%s' "${HOME}${raw:1}" ;;
      *) printf '%s' "$root/$raw" ;;
    esac
    return 0
  fi
  echo "ERROR: No .workflow.yml found. Run /bootstrap to initialise workflow config." >&2
  return 2
}

get_monitor_file() {
  local feature="$1"
  _wf_mon_validate_labeled_id "$feature" "feature" || return 1
  local storage
  storage="$(get_spec_storage)" || return 1
  printf '%s' "$storage/$feature/.monitor.jsonl"
}

require_project_root() {
  _find_workflow_root || {
    echo "ERROR: Cannot find project root" >&2; return 1
  }
}

# === Internal ===

write_event() {
  local monitor_file="$1" json_line="$2"
  printf '%s\n' "$(redact_home "$json_line")" >> "$monitor_file"
}

# === Public API ===

log_event() {
  local feature="${1:?Usage: log_event <feature> <category> <task_id> <json_data>}"
  local category="${2:?Usage: log_event <feature> <category> <task_id> <json_data>}"
  local task_id="${3:-}"
  local json_data="${4:?Usage: log_event <feature> <category> <task_id> <json_data>}"
  validate_category "$category" || return 1
  check_yaml_body "$json_data" || return 1
  if [[ -z "$json_data" || ( "$json_data" != "null" && "$json_data" != "true" && "$json_data" != "false" && ! "$json_data" =~ ^[0-9] && ! "$json_data" =~ ^\{ && ! "$json_data" =~ ^\[ && ! "$json_data" =~ ^\" ) ]]; then
    echo "ERROR: json_data must be a valid JSON fragment" >&2; return 1
  fi
  local ts monitor_file
  ts="$(get_timestamp)"
  monitor_file="$(get_monitor_file "$feature")" || return 1
  local task_field=""
  if [[ -n "$task_id" ]]; then
    _wf_mon_validate_labeled_id "$task_id" "task_id" || return 1
    task_field="$(printf '"task":"%s",' "$(escape_json_string "$task_id")")"
  fi
  local line
  line="$(printf '{"ts":"%s","category":"%s",%s"feature":"%s","data":%s}' \
    "$ts" "$(escape_json_string "$category")" "$task_field" \
    "$(escape_json_string "$feature")" "$json_data")"
  write_event "$monitor_file" "$line"
}

start_phase() {
  local feature="${1:?Usage: start_phase <feature> <task_id> <phase_name>}"
  local task_id="${2:?Usage: start_phase <feature> <task_id> <phase_name>}"
  local phase_name="${3:?Usage: start_phase <feature> <task_id> <phase_name>}"
  _wf_mon_validate_labeled_id "$task_id" "task_id" || return 1
  _wf_mon_validate_labeled_id "$phase_name" "phase_name" || return 1
  local epoch ts monitor_file correlation_id
  epoch="$(get_epoch)"; ts="$(get_timestamp)"
  correlation_id="${phase_name}-${task_id}-${epoch}"
  monitor_file="$(get_monitor_file "$feature")" || return 1
  local line
  line="$(printf '{"ts":"%s","category":"phase","task":"%s","feature":"%s","correlation_id":"%s","data":{"phase":"%s","action":"start"}}' \
    "$ts" "$(escape_json_string "$task_id")" "$(escape_json_string "$feature")" \
    "$(escape_json_string "$correlation_id")" "$(escape_json_string "$phase_name")")"
  write_event "$monitor_file" "$line"
  printf '%s' "$correlation_id"
}

end_phase() {
  local feature="${1:?Usage: end_phase <feature> <correlation_id> <phase_name>}"
  local correlation_id="${2:?Usage: end_phase <feature> <correlation_id> <phase_name>}"
  local phase_name="${3:?Usage: end_phase <feature> <correlation_id> <phase_name>}"
  _wf_mon_validate_labeled_id "$correlation_id" "correlation_id" || return 1
  local ts monitor_file
  ts="$(get_timestamp)"
  monitor_file="$(get_monitor_file "$feature")" || return 1
  local line
  line="$(printf '{"ts":"%s","category":"phase","feature":"%s","correlation_id":"%s","data":{"phase":"%s","action":"end"}}' \
    "$ts" "$(escape_json_string "$feature")" "$(escape_json_string "$correlation_id")" \
    "$(escape_json_string "$phase_name")")"
  write_event "$monitor_file" "$line"
}

set_context() {
  local feature="${1:?Usage: set_context <feature> <task_id>}"
  local task_id="${2:?Usage: set_context <feature> <task_id>}"
  _wf_mon_validate_labeled_id "$feature" "feature" || return 1
  _wf_mon_validate_labeled_id "$task_id" "task_id" || return 1
  local root
  root="$(require_project_root)" || return 1
  local tmp_file
  tmp_file="$(mktemp "$root/.monitor-context.XXXXXX")"
  printf 'feature=%s\ntask=%s\n' "$feature" "$task_id" > "$tmp_file"
  mv "$tmp_file" "$root/$MONITOR_CONTEXT_FILE"
}

read_context() {
  local root
  root="$(_find_workflow_root 2>/dev/null)" || return 1
  local context_file="$root/$MONITOR_CONTEXT_FILE"
  [[ -f "$context_file" ]] || return 1
  local feature="" task=""
  while IFS='=' read -r key value; do
    case "$key" in feature) feature="$value" ;; task) task="$value" ;; esac
  done < "$context_file"
  [[ -n "$feature" ]] || return 1
  _wf_mon_validate_labeled_id "$feature" "feature" || return 1
  if [[ -n "$task" ]]; then _wf_mon_validate_labeled_id "$task" "task_id" || return 1; fi
  printf '%s\n%s\n' "$feature" "$task"
}

clear_context() {
  local root
  root="$(_find_workflow_root 2>/dev/null)" || return 0
  rm -f "$root/$MONITOR_CONTEXT_FILE"
}

# === CLI mode (when run directly, not sourced) ===

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  subcmd="${1:?Usage: monitor.sh <command> [args...]}"
  shift
  case "$subcmd" in
    log_event)    log_event "$@" ;;
    start_phase)  start_phase "$@" ;;
    end_phase)    end_phase "$@" ;;
    set_context)  set_context "$@" ;;
    read_context) read_context "$@" ;;
    clear_context) clear_context "$@" ;;
    *)
      echo "Unknown command: $subcmd" >&2
      echo "Commands: log_event, start_phase, end_phase, set_context, read_context, clear_context" >&2
      exit 1
      ;;
  esac
fi
