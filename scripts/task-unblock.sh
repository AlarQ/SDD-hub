#!/usr/bin/env bash
# task-unblock.sh — cmd_unblock, cmd_next: dependency resolution and next-task selection.
# Sourced by task-manager.sh. Requires: read_frontmatter, update_frontmatter, die, emit_transition_event.

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
      emit_transition_event "$task_id" "blocked" "todo" "$task_file"
    fi
  done

  echo "Unblocked $unblocked task(s)"
}

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
