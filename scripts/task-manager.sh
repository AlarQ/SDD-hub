#!/usr/bin/env bash
set -euo pipefail

# task-manager.sh — Validates and updates task files for the spec-driven workflow.
# Uses yq for YAML frontmatter parsing/updating.
# Usage: task-manager.sh <command> [args...]

# === CANONICAL STATE MACHINE ===
# Executable source of truth for task states and transitions.
# Human-readable docs: plan.md § "Task State Machine"
# If you change states/transitions here, update plan.md to match.
VALID_STATUSES=("blocked" "todo" "in-progress" "implemented" "review" "done")
REQUIRED_SCALAR_FIELDS=("id" "name" "status" "max_files")
REQUIRED_ARRAY_FIELDS=("ground_rules" "test_cases" "blocked_by" "estimated_files")

# Resolve general KB base path by detecting installation context
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$SCRIPT_DIR" == "$HOME/.claude/scripts" ]]; then
  GENERAL_KB_BASE="$HOME/.claude/knowledge-base"
else
  GENERAL_KB_BASE="knowledge-base/_general"
fi

# Source config-paths.sh if available (gives find_workflow_root, wf_resolve_root)
_WF_TM_PATHS_LOADED=0
if [[ -f "$SCRIPT_DIR/config-paths.sh" ]]; then
  # shellcheck source=scripts/config-paths.sh
  source "$SCRIPT_DIR/config-paths.sh"
  _WF_TM_PATHS_LOADED=1
fi

# Detect repo root for absolute path resolution when invoked from a subdir.
# Priority: WF_REPO_ROOT env → .workflow.yml walk-up → git root → CWD
_wf_tm_detect_repo_root() {
  [[ -n "${WF_REPO_ROOT:-}" ]] && { printf '%s' "$WF_REPO_ROOT"; return 0; }
  if [[ "$_WF_TM_PATHS_LOADED" == "1" ]]; then
    local root
    if root="$(wf_resolve_root "$PWD" 2>/dev/null)"; then printf '%s' "$root"; return 0; fi
  fi
  local git_root
  if git_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then printf '%s' "$git_root"; return 0; fi
  printf '%s' "$PWD"
}

# Lazy-evaluated — avoids source-time side effects (git rev-parse, dir walk)
: "${_WF_TM_REPO_ROOT:=$(_wf_tm_detect_repo_root)}"

# Source monitor.sh for event logging (guard: only if file exists)
MONITOR_AVAILABLE=false
if [[ -f "$SCRIPT_DIR/monitor.sh" ]]; then
  source "$SCRIPT_DIR/monitor.sh"
  MONITOR_AVAILABLE=true
fi

# Source submodules
# shellcheck source=scripts/task-status.sh
source "$SCRIPT_DIR/task-status.sh"
# shellcheck source=scripts/task-unblock.sh
source "$SCRIPT_DIR/task-unblock.sh"

# Emit a task_transition event if monitoring is active.
emit_transition_event() {
  local task_id="$1" from_status="$2" to_status="$3" task_file="$4"
  [[ "$MONITOR_AVAILABLE" = "true" ]] || return 0
  local ctx mon_feature
  if ctx="$(read_context 2>/dev/null)"; then
    mon_feature="$(echo "$ctx" | head -1)"
    [[ -n "$mon_feature" ]] || return 0
    log_event "$mon_feature" "task_transition" "$task_id" \
      "$(printf '{"from_status":"%s","to_status":"%s","task_file":"%s"}' \
        "$(escape_json_string "$from_status")" \
        "$(escape_json_string "$to_status")" \
        "$(escape_json_string "$task_file")")" || echo "WARN: monitor event emission failed" >&2
  fi
}

# Valid transitions: from -> to
get_allowed_transitions() {
  case "$1" in
    blocked)     echo "todo" ;;
    todo)        echo "in-progress" ;;
    in-progress) echo "implemented" ;;
    implemented) echo "review done" ;;
    review)      echo "implemented done" ;;
    done)        echo "" ;;
    *)           echo "" ;;
  esac
}

usage() {
  cat <<'EOF'
Usage: task-manager.sh <command> [args...]

Commands:
  validate <task-file>           Validate task file structure and fields
  set-status <task-file> <status> Update task status (validates transition)
  unblock <tasks-directory>      Check blocked tasks, unblock if dependencies are done
  next <tasks-directory>         Get next eligible task (status: todo)
  check-unvalidated <tasks-dir>  Check for tasks with status: implemented or review
  status <tasks-directory>       Show status dashboard with dependencies and health diagnostics
  help                           Show this help message
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

check_yq() {
  command -v yq >/dev/null 2>&1 || die "yq is not installed. Run: brew install yq"
}

# Extract YAML frontmatter from a markdown file and pass it to yq.
read_frontmatter() {
  local file="$1"
  local expression="${2:-.}"
  sed -n '/^---$/,/^---$/p' "$file" | sed '1d;$d' | yq eval "$expression" -
}

# Resolve a prefixed ground_rules path to a real file path (absolute).
resolve_ground_rule_path() {
  local prefixed_path="$1"
  local project_kb="${_WF_TM_REPO_ROOT}/knowledge-base"
  case "$prefixed_path" in
    general:*) echo "$GENERAL_KB_BASE/${prefixed_path#general:}" ;;
    project:*) echo "$project_kb/${prefixed_path#project:}" ;;
    *)         echo "$project_kb/$prefixed_path" ;;
  esac
}

# Update a field in the YAML frontmatter of a markdown file.
update_frontmatter() {
  local file="$1"
  local expression="$2"
  local second_delim
  second_delim=$(grep -n '^---$' "$file" | sed -n '2p' | cut -d: -f1)
  [ -z "$second_delim" ] && die "Cannot find frontmatter end delimiter in $file"
  local frontmatter
  frontmatter=$(sed -n "2,$((second_delim - 1))p" "$file")
  local body
  body=$(tail -n +"$((second_delim + 1))" "$file")
  local updated_frontmatter
  updated_frontmatter=$(echo "$frontmatter" | yq eval "$expression" -)
  {
    echo "---"
    echo "$updated_frontmatter"
    echo "---"
    [ -n "$body" ] && printf '%s\n' "$body"
  } > "$file"
}

# Validate required scalar and array fields, status, and max_files.
validate_required_fields() {
  local file="$1"
  for field in "${REQUIRED_SCALAR_FIELDS[@]}"; do
    local value
    value=$(read_frontmatter "$file" ".$field")
    if [ "$value" = "null" ] || [ -z "$value" ]; then
      die "Missing required field '$field' in $file"
    fi
  done
  for field in "${REQUIRED_ARRAY_FIELDS[@]}"; do
    local value
    value=$(read_frontmatter "$file" ".$field | type")
    if [ "$value" != "!!seq" ]; then
      die "Missing or non-array field '$field' in $file (must be a YAML array)"
    fi
  done
  local status
  status=$(read_frontmatter "$file" ".status")
  local valid=false
  for s in "${VALID_STATUSES[@]}"; do [ "$status" = "$s" ] && valid=true; done
  [ "$valid" = "true" ] || die "Invalid status '$status' in $file. Valid: ${VALID_STATUSES[*]}"
  local max_files
  max_files=$(read_frontmatter "$file" '.max_files')
  [[ "$max_files" =~ ^[0-9]+$ ]] || die "max_files must be a number in $file"
  [ "$max_files" -le 20 ] || die "max_files exceeds 20 in $file"
}

# Warn if ground_rules paths don't resolve to real files.
validate_ground_rules() {
  local file="$1"
  local rules_count
  rules_count=$(read_frontmatter "$file" '.ground_rules | length')
  for ((i = 0; i < rules_count; i++)); do
    local rule_path resolved_path
    rule_path=$(read_frontmatter "$file" ".ground_rules[$i]")
    resolved_path=$(resolve_ground_rule_path "$rule_path")
    [ -f "$resolved_path" ] || echo "WARNING: ground_rules path not found: $rule_path -> $resolved_path (in $file)"
  done
}

# Validate a task file has correct structure
cmd_validate() {
  local file="${1:-}"
  [ -z "$file" ] && die "Usage: task-manager.sh validate <task-file>"
  if [ ! -f "$file" ] && [[ "$file" != /* ]]; then
    local abs_candidate="$_WF_TM_REPO_ROOT/$file"
    [ -f "$abs_candidate" ] && file="$abs_candidate"
  fi
  [ -f "$file" ] || die "Task file not found: $file"
  local delim_count
  delim_count=$(grep -c '^---$' "$file" || true)
  [ "$delim_count" -lt 2 ] && die "Task file missing YAML frontmatter delimiters: $file"
  validate_required_fields "$file"
  validate_ground_rules "$file"
  local status
  status=$(read_frontmatter "$file" ".status")
  if [ "$status" = "blocked" ]; then
    local blocked_count
    blocked_count=$(read_frontmatter "$file" '.blocked_by | length')
    [ "$blocked_count" -gt 0 ] || die "Task has status 'blocked' but empty blocked_by: $file"
  fi
  echo "OK: $file"
}

# Update task status with transition validation
cmd_set_status() {
  local file="${1:-}"
  local new_status="${2:-}"
  [ -z "$file" ] || [ -z "$new_status" ] && die "Usage: task-manager.sh set-status <task-file> <new-status>"
  [ -f "$file" ] || die "Task file not found: $file"
  cmd_validate "$file" > /dev/null
  local valid=false
  for s in "${VALID_STATUSES[@]}"; do [ "$new_status" = "$s" ] && valid=true; done
  [ "$valid" = "true" ] || die "Invalid status '$new_status'. Valid: ${VALID_STATUSES[*]}"
  local current_status task_id
  current_status=$(read_frontmatter "$file" ".status")
  task_id=$(read_frontmatter "$file" ".id")
  local allowed
  allowed=$(get_allowed_transitions "$current_status")
  local transition_valid=false
  for target in $allowed; do [ "$target" = "$new_status" ] && transition_valid=true; done
  [ "$transition_valid" = "true" ] || die "Invalid transition: '$current_status' -> '$new_status' in $file. Allowed from '$current_status': $allowed"
  update_frontmatter "$file" ".status = \"$new_status\""
  echo "Status updated: $current_status -> $new_status ($file)"
  emit_transition_event "$task_id" "$current_status" "$new_status" "$file"
}

# Check for unvalidated work
cmd_check_unvalidated() {
  local dir="${1:-}"
  [ -z "$dir" ] && die "Usage: task-manager.sh check-unvalidated <tasks-directory>"
  [ -d "$dir" ] || die "Tasks directory not found: $dir"
  local found=false
  for task_file in "$dir"/*.md; do
    [ -f "$task_file" ] || continue
    local status id
    status=$(read_frontmatter "$task_file" ".status")
    id=$(read_frontmatter "$task_file" ".id")
    if [ "$status" = "implemented" ] || [ "$status" = "review" ]; then
      echo "Task $id ($task_file): status is '$status'"
      found=true
    fi
  done
  [ "$found" = "true" ] && return 1 || return 0
}

# Main dispatch
check_yq

case "${1:-help}" in
  validate)         shift; cmd_validate "$@" ;;
  set-status)       shift; cmd_set_status "$@" ;;
  unblock)          shift; cmd_unblock "$@" ;;
  next)             shift; cmd_next "$@" ;;
  check-unvalidated) shift; cmd_check_unvalidated "$@" ;;
  status)           shift; cmd_status "$@" ;;
  help|--help|-h)   usage ;;
  *)                die "Unknown command: $1. Run 'task-manager.sh help' for usage." ;;
esac
