#!/usr/bin/env bash
# task-status.sh — cmd_status: comprehensive task status dashboard.
# Sourced by task-manager.sh. Requires: read_frontmatter, die.

cmd_status() {
  local dir="${1:-}"
  [ -z "$dir" ] && die "Usage: task-manager.sh status <tasks-directory>"
  [ -d "$dir" ] || die "Tasks directory not found: $dir"

  local task_ids=()
  local task_names=()
  local task_statuses=()
  local task_blocked_bys=()

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
  done

  local total=${#task_ids[@]}
  [ "$total" -eq 0 ] && die "No task files found in $dir"

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

  declare -A unblocks_map
  for ((i = 0; i < total; i++)); do
    local deps="${task_blocked_bys[$i]}"
    [ -z "$deps" ] && continue
    IFS=',' read -ra dep_arr <<< "$deps"
    for dep_id in "${dep_arr[@]}"; do
      dep_id=$(echo "$dep_id" | xargs)
      if [ -n "${unblocks_map[$dep_id]+x}" ]; then
        unblocks_map[$dep_id]="${unblocks_map[$dep_id]},${task_ids[$i]}"
      else
        unblocks_map[$dep_id]="${task_ids[$i]}"
      fi
    done
  done

  local diagnostics=()

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

  for ((i = 0; i < total; i++)); do
    if [ "${task_statuses[$i]}" = "in-progress" ]; then
      diagnostics+=("stuck_in_progress: Task ${task_ids[$i]} (${task_names[$i]}) is in-progress. If abandoned, reset status to 'todo' in YAML frontmatter and clean up the branch.")
    fi
    if [ "${task_statuses[$i]}" = "implemented" ]; then
      diagnostics+=("unvalidated: Task ${task_ids[$i]} (${task_names[$i]}) is implemented but not validated. Run /validate.")
    fi
    if [ "${task_statuses[$i]}" = "review" ]; then
      diagnostics+=("pending_review: Task ${task_ids[$i]} (${task_names[$i]}) has findings awaiting review. Run /review-findings.")
    fi
  done

  local non_done=$((total - count_done))
  if [ "$non_done" -gt 0 ] && [ "$count_todo" -eq 0 ] && [ "$count_in_progress" -eq 0 ] && [ "$count_implemented" -eq 0 ] && [ "$count_review" -eq 0 ]; then
    diagnostics+=("deadlock: All $count_blocked remaining tasks are blocked with nothing in progress. Check dependency IDs for errors.")
  fi

  for ((i = 0; i < total; i++)); do
    [ "${task_statuses[$i]}" = "done" ] && continue
    local deps="${task_blocked_bys[$i]}"
    [ -z "$deps" ] && continue
    local visited="${task_ids[$i]}"
    local queue="$deps"
    while [ -n "$queue" ]; do
      local next_queue=""
      IFS=',' read -ra q_arr <<< "$queue"
      for q_id in "${q_arr[@]}"; do
        q_id=$(echo "$q_id" | xargs)
        if echo ",$visited," | grep -q ",$q_id,"; then
          if [ "$q_id" = "${task_ids[$i]}" ]; then
            diagnostics+=("circular_dependency: Task ${task_ids[$i]} is part of a dependency cycle. Break the cycle by removing one dependency.")
          fi
          continue
        fi
        visited="$visited,$q_id"
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
