#!/usr/bin/env bash
set -euo pipefail

# monitor.sh — Event logger for the spec implementation monitoring system.
# Appends JSONL events to specs/<feature>/.monitor.jsonl.
# Source-able by other scripts: source ~/.claude/scripts/monitor.sh
# Public sourcing API: log_event, start_phase, end_phase, set_context,
#   read_context, clear_context, escape_json_string.
# No external dependencies (uses printf for JSON, date for timestamps).

MONITOR_CONTEXT_FILE=".monitor-context"

# === Helpers (public when sourced) ===

get_timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%S.000Z"
}

get_epoch() {
  date +%s
}

escape_json_string() {
  local val="$1"
  val="${val//\\/\\\\}"
  val="${val//\"/\\\"}"
  val="${val//$'\n'/\\n}"
  val="${val//$'\t'/\\t}"
  printf '%s' "$val"
}

find_project_root() {
  local dir="${PWD}"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/specs" ]]; then
      printf '%s' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

get_monitor_file() {
  local feature="$1"
  local root
  root="$(find_project_root)" || return 1
  printf '%s' "$root/specs/$feature/.monitor.jsonl"
}

require_monitor_file() {
  local feature="$1"
  get_monitor_file "$feature" || {
    echo "ERROR: Cannot find project root with specs/ directory" >&2
    return 1
  }
}

require_project_root() {
  find_project_root || {
    echo "ERROR: Cannot find project root with specs/ directory" >&2
    return 1
  }
}

validate_id() {
  local value="$1" label="$2"
  if [[ ! "$value" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "ERROR: Invalid $label: must be alphanumeric, hyphens, or underscores" >&2
    return 1
  fi
}

# === Internal ===

write_event() {
  local monitor_file="$1" json_line="$2"
  printf '%s\n' "$json_line" >> "$monitor_file"
}

# === Public API ===

log_event() {
  local feature="${1:?Usage: log_event <feature> <category> <task_id> <json_data>}"
  local category="${2:?Usage: log_event <feature> <category> <task_id> <json_data>}"
  local task_id="${3:-}"
  local json_data="${4:?Usage: log_event <feature> <category> <task_id> <json_data>}"

  local ts
  ts="$(get_timestamp)"

  local monitor_file
  monitor_file="$(require_monitor_file "$feature")" || return 1

  local task_field=""
  if [[ -n "$task_id" ]]; then
    validate_id "$task_id" "task_id" || return 1
    task_field="$(printf '"task":"%s",' "$(escape_json_string "$task_id")")"
  fi

  local line
  line="$(printf '{"ts":"%s","category":"%s",%s"feature":"%s","data":%s}' \
    "$ts" \
    "$(escape_json_string "$category")" \
    "$task_field" \
    "$(escape_json_string "$feature")" \
    "$json_data")"

  write_event "$monitor_file" "$line"
}

start_phase() {
  local feature="${1:?Usage: start_phase <feature> <task_id> <phase_name>}"
  local task_id="${2:?Usage: start_phase <feature> <task_id> <phase_name>}"
  local phase_name="${3:?Usage: start_phase <feature> <task_id> <phase_name>}"
  validate_id "$task_id" "task_id" || return 1

  local epoch
  epoch="$(get_epoch)"
  local correlation_id="${phase_name}-${task_id}-${epoch}"

  local ts
  ts="$(get_timestamp)"

  local monitor_file
  monitor_file="$(require_monitor_file "$feature")" || return 1

  local line
  line="$(printf '{"ts":"%s","category":"phase","task":"%s","feature":"%s","correlation_id":"%s","data":{"phase":"%s","action":"start"}}' \
    "$ts" \
    "$(escape_json_string "$task_id")" \
    "$(escape_json_string "$feature")" \
    "$(escape_json_string "$correlation_id")" \
    "$(escape_json_string "$phase_name")")"

  write_event "$monitor_file" "$line"
  printf '%s' "$correlation_id"
}

end_phase() {
  local feature="${1:?Usage: end_phase <feature> <correlation_id> <phase_name>}"
  local correlation_id="${2:?Usage: end_phase <feature> <correlation_id> <phase_name>}"
  local phase_name="${3:?Usage: end_phase <feature> <correlation_id> <phase_name>}"

  local ts
  ts="$(get_timestamp)"

  local monitor_file
  monitor_file="$(require_monitor_file "$feature")" || return 1

  local line
  line="$(printf '{"ts":"%s","category":"phase","feature":"%s","correlation_id":"%s","data":{"phase":"%s","action":"end"}}' \
    "$ts" \
    "$(escape_json_string "$feature")" \
    "$(escape_json_string "$correlation_id")" \
    "$(escape_json_string "$phase_name")")"

  write_event "$monitor_file" "$line"
}

set_context() {
  local feature="${1:?Usage: set_context <feature> <task_id>}"
  local task_id="${2:?Usage: set_context <feature> <task_id>}"
  validate_id "$task_id" "task_id" || return 1

  local root
  root="$(require_project_root)" || return 1

  printf 'feature=%s\ntask=%s\n' "$feature" "$task_id" > "$root/$MONITOR_CONTEXT_FILE"
}

read_context() {
  local root
  root="$(find_project_root)" || return 1
  local context_file="$root/$MONITOR_CONTEXT_FILE"
  [[ -f "$context_file" ]] || return 1

  local feature="" task=""
  while IFS='=' read -r key value; do
    case "$key" in
      feature) feature="$value" ;;
      task)    task="$value" ;;
    esac
  done < "$context_file"
  [[ -n "$feature" ]] || return 1

  printf '%s\n%s\n' "$feature" "$task"
}

clear_context() {
  local root
  root="$(find_project_root)" || return 0
  rm -f "$root/$MONITOR_CONTEXT_FILE"
}

# === CLI mode (when run directly, not sourced) ===

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  subcmd="${1:?Usage: monitor.sh <command> [args...]}"
  shift
  case "$subcmd" in
    log_event)   log_event "$@" ;;
    start_phase) start_phase "$@" ;;
    end_phase)   end_phase "$@" ;;
    set_context) set_context "$@" ;;
    read_context)  read_context "$@" ;;
    clear_context) clear_context "$@" ;;
    *)
      echo "Unknown command: $subcmd" >&2
      echo "Commands: log_event, start_phase, end_phase, set_context, read_context, clear_context" >&2
      exit 1
      ;;
  esac
fi
