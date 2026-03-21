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

# Show comprehensive status dashboard as YAML
cmd_status() {
  local dir="${1:-}"
  [ -z "$dir" ] && die "Usage: task-manager.sh status <tasks-directory>"
  [ -d "$dir" ] || die "Tasks directory not found: $dir"

  # Collect all task data
  local task_ids=()
  local task_names=()
  local task_statuses=()
  local task_blocked_bys=()
  local task_files_list=()

  for task_file in "$dir"/*.md; do
    [ -f "$task_file" ] || continue
    local id name status blocked_by
    id=$(read_frontmatter "$task_file" ".id")
    name=$(read_frontmatter "$task_file" ".name")
    status=$(read_frontmatter "$task_file" ".status")
    blocked_by=$(read_frontmatter "$task_file" '.blocked_by | join(",")')
    [ "$blocked_by" = "null" ] && blocked_by=""

    task_ids+=("$id")
    task_names+=("$name")
    task_statuses+=("$status")
    task_blocked_bys+=("$blocked_by")
    task_files_list+=("$task_file")
  done

  local total=${#task_ids[@]}
  [ "$total" -eq 0 ] && die "No task files found in $dir"

  # Count statuses
  local count_done=0 count_todo=0 count_blocked=0 count_in_progress=0 count_implemented=0 count_review=0
  for status in "${task_statuses[@]}"; do
    case "$status" in
      done)         count_done=$((count_done + 1)) ;;
      todo)         count_todo=$((count_todo + 1)) ;;
      blocked)      count_blocked=$((count_blocked + 1)) ;;
      in-progress)  count_in_progress=$((count_in_progress + 1)) ;;
      implemented)  count_implemented=$((count_implemented + 1)) ;;
      review)       count_review=$((count_review + 1)) ;;
    esac
  done

  # Build reverse dependency map: which tasks does each task unblock
  # For each task, look at its blocked_by and record the reverse
  declare -A unblocks_map
  for ((i = 0; i < total; i++)); do
    local deps="${task_blocked_bys[$i]}"
    [ -z "$deps" ] && continue
    IFS=',' read -ra dep_arr <<< "$deps"
    for dep_id in "${dep_arr[@]}"; do
      dep_id=$(echo "$dep_id" | xargs) # trim
      if [ -n "${unblocks_map[$dep_id]+x}" ]; then
        unblocks_map[$dep_id]="${unblocks_map[$dep_id]},${task_ids[$i]}"
      else
        unblocks_map[$dep_id]="${task_ids[$i]}"
      fi
    done
  done

  # Health diagnostics
  local diagnostics=()

  # Check: orphan dependencies (blocked_by references non-existent IDs)
  for ((i = 0; i < total; i++)); do
    local deps="${task_blocked_bys[$i]}"
    [ -z "$deps" ] && continue
    IFS=',' read -ra dep_arr <<< "$deps"
    for dep_id in "${dep_arr[@]}"; do
      dep_id=$(echo "$dep_id" | xargs)
      local found=false
      for existing_id in "${task_ids[@]}"; do
        [ "$existing_id" = "$dep_id" ] && { found=true; break; }
      done
      if [ "$found" = "false" ]; then
        diagnostics+=("orphan_dependency: Task ${task_ids[$i]} references non-existent dependency ID '$dep_id'. Fix the blocked_by field.")
      fi
    done
  done

  # Check: stuck in-progress
  for ((i = 0; i < total; i++)); do
    if [ "${task_statuses[$i]}" = "in-progress" ]; then
      diagnostics+=("stuck_in_progress: Task ${task_ids[$i]} (${task_names[$i]}) is in-progress. If abandoned, reset status to 'todo' in YAML frontmatter and clean up the branch.")
    fi
  done

  # Check: unvalidated work
  for ((i = 0; i < total; i++)); do
    if [ "${task_statuses[$i]}" = "implemented" ]; then
      diagnostics+=("unvalidated: Task ${task_ids[$i]} (${task_names[$i]}) is implemented but not validated. Run /validate.")
    fi
    if [ "${task_statuses[$i]}" = "review" ]; then
      diagnostics+=("pending_review: Task ${task_ids[$i]} (${task_names[$i]}) has findings awaiting review. Run /review-findings.")
    fi
  done

  # Check: deadlock (all remaining non-done tasks are blocked, none todo/in-progress)
  local non_done=$((total - count_done))
  if [ "$non_done" -gt 0 ] && [ "$count_todo" -eq 0 ] && [ "$count_in_progress" -eq 0 ] && [ "$count_implemented" -eq 0 ] && [ "$count_review" -eq 0 ]; then
    diagnostics+=("deadlock: All $count_blocked remaining tasks are blocked with nothing in progress. Check dependency IDs for errors.")
  fi

  # Check: circular dependencies (simple detection via DFS)
  # Build adjacency: task -> tasks it depends on
  local has_cycle=false
  for ((i = 0; i < total; i++)); do
    [ "${task_statuses[$i]}" = "done" ] && continue
    local deps="${task_blocked_bys[$i]}"
    [ -z "$deps" ] && continue

    # Walk the chain from this task to see if it loops back
    local visited="${task_ids[$i]}"
    local queue="$deps"

    while [ -n "$queue" ]; do
      local next_queue=""
      IFS=',' read -ra q_arr <<< "$queue"
      for q_id in "${q_arr[@]}"; do
        q_id=$(echo "$q_id" | xargs)
        # Check if we've visited this
        if echo ",$visited," | grep -q ",$q_id,"; then
          if [ "$q_id" = "${task_ids[$i]}" ]; then
            diagnostics+=("circular_dependency: Task ${task_ids[$i]} is part of a dependency cycle. Break the cycle by removing one dependency.")
            has_cycle=true
          fi
          continue
        fi
        visited="$visited,$q_id"
        # Find this task's deps
        for ((j = 0; j < total; j++)); do
          if [ "${task_ids[$j]}" = "$q_id" ]; then
            local j_deps="${task_blocked_bys[$j]}"
            [ -n "$j_deps" ] && next_queue="$next_queue,$j_deps"
            break
          fi
        done
      done
      queue="${next_queue#,}"
    done
  done

  # Output as YAML
  echo "---"
  echo "summary:"
  echo "  total: $total"
  echo "  done: $count_done"
  echo "  todo: $count_todo"
  echo "  in_progress: $count_in_progress"
  echo "  implemented: $count_implemented"
  echo "  review: $count_review"
  echo "  blocked: $count_blocked"
  echo "  percent_complete: $((count_done * 100 / total))"
  echo ""
  echo "tasks:"
  for ((i = 0; i < total; i++)); do
    echo "  - id: \"${task_ids[$i]}\""
    echo "    name: \"${task_names[$i]}\""
    echo "    status: \"${task_statuses[$i]}\""
    local deps="${task_blocked_bys[$i]}"
    if [ -n "$deps" ]; then
      echo "    blocked_by: [$(echo "$deps" | sed 's/,/, /g')]"
    else
      echo "    blocked_by: []"
    fi
    local ub="${unblocks_map[${task_ids[$i]}]:-}"
    if [ -n "$ub" ]; then
      echo "    unblocks: [$(echo "$ub" | sed 's/,/, /g')]"
    else
      echo "    unblocks: []"
    fi
  done
  echo ""
  echo "diagnostics:"
  if [ ${#diagnostics[@]} -eq 0 ]; then
    echo "  - none"
  else
    for diag in "${diagnostics[@]}"; do
      echo "  - \"$diag\""
    done
  fi
  echo "---"
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
