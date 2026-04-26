#!/usr/bin/env bash
# monitor-validators.sh — Category allowlist and payload validation helpers for monitor.sh.
# Sourced by monitor.sh. No external dependencies.

# Closed category allowlist (T003). Unknown category → log_event exits non-zero.
_WF_VALID_CATEGORIES=(
  task_transition phase tool_call context_read agent_invocation
  validation_result finding_found finding_accepted finding_rejected task_update
  config_inferred config_approved agent_spawn gate_skip
)

redact_home() {
  local s="$1"
  if [[ -n "${HOME:-}" ]]; then
    s="${s//"${HOME}"/~}"
    s="${s//"${HOME}/"/~/}"
  fi
  printf '%s' "$s"
}

validate_category() {
  local category="$1"
  validate_id "$category" "category" || return 1
  local cat
  for cat in "${_WF_VALID_CATEGORIES[@]}"; do
    [[ "$cat" == "$category" ]] && return 0
  done
  echo "ERROR: Unknown category: '$category'. Valid: ${_WF_VALID_CATEGORIES[*]}" >&2
  return 1
}

check_yaml_body() {
  local data="$1"
  if [[ "$data" == *'---'* || "$data" == *'"gates":'* || "$data" == *'"tasks":'* || "$data" == *'"status":'* || "$data" == *'"blocked_by":'* ]]; then
    echo "ERROR: log_event: payload must not contain YAML structural content" >&2
    return 1
  fi
}
