#!/usr/bin/env bash
set -euo pipefail

# task-manager.sh — Validates and updates task files for the spec-driven workflow.
# Uses yq for YAML frontmatter parsing/updating.
# Usage: task-manager.sh <command> [args...]

VALID_STATUSES=("blocked" "todo" "in-progress" "implemented" "review" "done")
REQUIRED_FIELDS=("id" "name" "status" "ground_rules" "test_cases" "blocked_by" "max_files" "estimated_files")

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
# Task files use --- delimited frontmatter at the top.
read_frontmatter() {
  local file="$1"
  local expression="${2:-.}"
  # Extract content between first --- and second ---
  sed -n '/^---$/,/^---$/p' "$file" | sed '1d;$d' | yq eval "$expression" -
}

# Update a field in the YAML frontmatter of a markdown file.
update_frontmatter() {
  local file="$1"
  local expression="$2"

  # Get line number of the second --- delimiter
  local second_delim
  second_delim=$(grep -n '^---$' "$file" | sed -n '2p' | cut -d: -f1)
  [ -z "$second_delim" ] && die "Cannot find frontmatter end delimiter in $file"

  # Extract frontmatter (between line 2 and second_delim - 1)
  local frontmatter
  frontmatter=$(sed -n "2,$((second_delim - 1))p" "$file")

  # Extract body (everything after second ---)
  local body
  body=$(tail -n +"$((second_delim + 1))" "$file")

  # Update frontmatter via yq
  local updated_frontmatter
  updated_frontmatter=$(echo "$frontmatter" | yq eval "$expression" -)

  # Write back
  {
    echo "---"
    echo "$updated_frontmatter"
    echo "---"
    [ -n "$body" ] && printf '%s\n' "$body"
  } > "$file"
}

# Validate a task file has correct structure
cmd_validate() {
  local file="${1:-}"
  [ -z "$file" ] && die "Usage: task-manager.sh validate <task-file>"
  [ -f "$file" ] || die "Task file not found: $file"

  # Check frontmatter delimiters exist
  local delim_count
  delim_count=$(grep -c '^---$' "$file" || true)
  [ "$delim_count" -lt 2 ] && die "Task file missing YAML frontmatter delimiters: $file"

  # Check required fields
  for field in "${REQUIRED_FIELDS[@]}"; do
    local value
    value=$(read_frontmatter "$file" ".$field")
    if [ "$value" = "null" ] || [ -z "$value" ]; then
      die "Missing required field '$field' in $file"
    fi
  done

  # Validate status value
  local status
  status=$(read_frontmatter "$file" ".status")
  local valid=false
  for s in "${VALID_STATUSES[@]}"; do
    [ "$status" = "$s" ] && valid=true
  done
  [ "$valid" = "true" ] || die "Invalid status '$status' in $file. Valid: ${VALID_STATUSES[*]}"

  # Validate ground_rules paths point to real files
  local rules_count
  rules_count=$(read_frontmatter "$file" '.ground_rules | length')
  for ((i = 0; i < rules_count; i++)); do
    local rule_path
    rule_path=$(read_frontmatter "$file" ".ground_rules[$i]")
    [ -f "$rule_path" ] || echo "WARNING: ground_rules path not found: $rule_path (in $file)"
  done

  # Validate blocked_by references if status is blocked
  if [ "$status" = "blocked" ]; then
    local blocked_count
    blocked_count=$(read_frontmatter "$file" '.blocked_by | length')
    [ "$blocked_count" -gt 0 ] || die "Task has status 'blocked' but empty blocked_by: $file"
  fi

  # Validate max_files is a number
  local max_files
  max_files=$(read_frontmatter "$file" '.max_files')
  [[ "$max_files" =~ ^[0-9]+$ ]] || die "max_files must be a number in $file"
  [ "$max_files" -le 20 ] || die "max_files exceeds 20 in $file"

  echo "OK: $file"
}

# Update task status with transition validation
cmd_set_status() {
  local file="${1:-}"
  local new_status="${2:-}"
  [ -z "$file" ] || [ -z "$new_status" ] && die "Usage: task-manager.sh set-status <task-file> <new-status>"
  [ -f "$file" ] || die "Task file not found: $file"

  # Validate new status is valid
  local valid=false
  for s in "${VALID_STATUSES[@]}"; do
    [ "$new_status" = "$s" ] && valid=true
  done
  [ "$valid" = "true" ] || die "Invalid status '$new_status'. Valid: ${VALID_STATUSES[*]}"

  # Get current status
  local current_status
  current_status=$(read_frontmatter "$file" ".status")

  # Check transition is allowed
  local allowed
  allowed=$(get_allowed_transitions "$current_status")
  local transition_valid=false
  for target in $allowed; do
    [ "$target" = "$new_status" ] && transition_valid=true
  done

  [ "$transition_valid" = "true" ] || die "Invalid transition: '$current_status' -> '$new_status' in $file. Allowed from '$current_status': $allowed"

  # Update the status
  update_frontmatter "$file" ".status = \"$new_status\""
  echo "Status updated: $current_status -> $new_status ($file)"
}

# Check blocked tasks and unblock if all dependencies are done
cmd_unblock() {
  local dir="${1:-}"
  [ -z "$dir" ] && die "Usage: task-manager.sh unblock <tasks-directory>"
  [ -d "$dir" ] || die "Tasks directory not found: $dir"

  local unblocked=0

  for task_file in "$dir"/*.md; do
    [ -f "$task_file" ] || continue

    local status
    status=$(read_frontmatter "$task_file" ".status")
    [ "$status" = "blocked" ] || continue

    local blocked_count
    blocked_count=$(read_frontmatter "$task_file" '.blocked_by | length')
    local all_done=true

    for ((i = 0; i < blocked_count; i++)); do
      local dep_id
      dep_id=$(read_frontmatter "$task_file" ".blocked_by[$i]")

      # Find the task file with this ID
      local dep_done=false
      for other_file in "$dir"/*.md; do
        [ -f "$other_file" ] || continue
        local other_id
        other_id=$(read_frontmatter "$other_file" ".id")
        if [ "$other_id" = "$dep_id" ]; then
          local other_status
          other_status=$(read_frontmatter "$other_file" ".status")
          [ "$other_status" = "done" ] && dep_done=true
          break
        fi
      done

      [ "$dep_done" = "true" ] || { all_done=false; break; }
    done

    if [ "$all_done" = "true" ]; then
      update_frontmatter "$task_file" '.status = "todo"'
      local task_id
      task_id=$(read_frontmatter "$task_file" ".id")
      echo "Unblocked: task $task_id ($task_file)"
      unblocked=$((unblocked + 1))
    fi
  done

  echo "Unblocked $unblocked task(s)"
}

# Get next eligible task (status: todo, ordered by filename)
cmd_next() {
  local dir="${1:-}"
  [ -z "$dir" ] && die "Usage: task-manager.sh next <tasks-directory>"
  [ -d "$dir" ] || die "Tasks directory not found: $dir"

  for task_file in "$dir"/*.md; do
    [ -f "$task_file" ] || continue

    local status
    status=$(read_frontmatter "$task_file" ".status")
    if [ "$status" = "todo" ]; then
      echo "$task_file"
      return 0
    fi
  done

  # No eligible task — report blocked tasks
  echo "No eligible tasks (status: todo) found."
  echo ""
  echo "Current task statuses:"
  for task_file in "$dir"/*.md; do
    [ -f "$task_file" ] || continue
    local id status blocked_by
    id=$(read_frontmatter "$task_file" ".id")
    status=$(read_frontmatter "$task_file" ".status")
    echo "  Task $id: $status"
    if [ "$status" = "blocked" ]; then
      blocked_by=$(read_frontmatter "$task_file" '.blocked_by | join(", ")')
      echo "    blocked by: $blocked_by"
    fi
  done
  return 1
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

  if [ "$found" = "true" ]; then
    return 1
  fi
  return 0
}

# Main dispatch
check_yq

case "${1:-help}" in
  validate)         shift; cmd_validate "$@" ;;
  set-status)       shift; cmd_set_status "$@" ;;
  unblock)          shift; cmd_unblock "$@" ;;
  next)             shift; cmd_next "$@" ;;
  check-unvalidated) shift; cmd_check_unvalidated "$@" ;;
  help|--help|-h)   usage ;;
  *)                die "Unknown command: $1. Run 'task-manager.sh help' for usage." ;;
esac
