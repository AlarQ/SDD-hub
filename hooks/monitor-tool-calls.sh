#!/usr/bin/env bash
# monitor-tool-calls.sh — PostToolUse hook that captures tool-level events
# during monitored spec implementation sessions.
#
# Receives JSON on stdin from Claude Code hook system.
# Reads .monitor-context for active feature/task.
# Exits silently (exit 0) when no active session or on any error.
#
# NOTE: No set -e or pipefail. This hook must never block the user's tool call,
# so all errors exit silently with exit 0. set -u is safe to keep — it catches
# unbound variable bugs without affecting the exit-0 contract.
set -u

# Read hook input from stdin early (stdin is consumed once).
INPUT="$(cat)" || exit 0
[[ -n "$INPUT" ]] || exit 0

# Source monitor.sh for shared functions (find_project_root, read_context, etc.).
MONITOR_SCRIPT="${HOME}/.claude/scripts/monitor.sh"
[[ -f "$MONITOR_SCRIPT" ]] || exit 0
source "$MONITOR_SCRIPT"
set +euo pipefail  # Restore non-strict mode — hook must never fail a tool call

# Read context (feature and task) via monitor.sh's read_context.
CONTEXT="$(read_context)" || exit 0
FEATURE="$(sed -n '1p' <<< "$CONTEXT")"
TASK="$(sed -n '2p' <<< "$CONTEXT")"
[[ -n "$FEATURE" ]] || exit 0

# Lightweight JSON string extraction (no jq dependency).
# Matches first occurrence of "key":"value" in the full JSON blob.
# NOTE: key must be a literal string — regex metacharacters are not escaped.
extract_json_string() {
  local json="$1" key="$2"
  local pattern="\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\""
  if [[ "$json" =~ $pattern ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

TOOL_NAME="$(extract_json_string "$INPUT" "tool_name")" || exit 0
[[ -n "$TOOL_NAME" ]] || exit 0

# Map tool to event category and build data payload.
case "$TOOL_NAME" in
  Read)
    FILE_PATH="$(extract_json_string "$INPUT" "file_path")" || FILE_PATH=""
    log_event "$FEATURE" "context_read" "$TASK" \
      "{\"file\":\"$(escape_json_string "$FILE_PATH")\",\"source\":\"hook\"}"
    ;;
  Agent)
    AGENT_NAME="$(extract_json_string "$INPUT" "description" || extract_json_string "$INPUT" "subagent_type" || printf '')"
    log_event "$FEATURE" "agent_invocation" "$TASK" \
      "{\"agent_name\":\"$(escape_json_string "$AGENT_NAME")\",\"source\":\"hook\"}"
    ;;
  Bash|Edit|Write|Glob|Grep)
    log_event "$FEATURE" "tool_call" "$TASK" \
      "{\"tool_name\":\"$(escape_json_string "$TOOL_NAME")\",\"source\":\"hook\"}"
    ;;
esac

exit 0
