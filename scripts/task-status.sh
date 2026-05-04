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

  # Cycle detection via Kahn's topological sort (awk).
  # Build edge list `dep -> task` (since `blocked_by` lists predecessors).
  # Any node not removable in topological order is part of a cycle (or
  # downstream of one). Diagnostic format preserved for back-compat.
  local _edges=""
  for ((i = 0; i < total; i++)); do
    local deps="${task_blocked_bys[$i]}"
    [ -z "$deps" ] && continue
    IFS=',' read -ra dep_arr <<< "$deps"
    for dep_id in "${dep_arr[@]}"; do
      dep_id=$(echo "$dep_id" | xargs)
      [ -z "$dep_id" ] && continue
      _edges+="$dep_id $(echo "${task_ids[$i]}" | xargs)"$'\n'
    done
  done
  local _nodes=""
  for ((i = 0; i < total; i++)); do
    _nodes+="${task_ids[$i]}"$'\n'
  done
  local cycle_nodes
  cycle_nodes="$(awk -v nodes="$_nodes" -v edges="$_edges" '
    BEGIN {
      n = split(nodes, narr, "\n")
      for (i = 1; i <= n; i++) if (narr[i] != "") { node[narr[i]] = 1; indeg[narr[i]] = 0 }
      m = split(edges, earr, "\n")
      for (i = 1; i <= m; i++) {
        if (earr[i] == "") continue
        split(earr[i], pair, " ")
        from = pair[1]; to = pair[2]
        # Only count edges between known nodes (orphan deps handled separately).
        if (!(from in node) || !(to in node)) continue
        succ[from] = (from in succ ? succ[from] " " to : to)
        indeg[to]++
      }
      # Kahn: queue nodes with indeg 0; peel them, decrementing successors.
      q = ""
      for (k in node) if (indeg[k] == 0) q = q " " k
      while (q != "") {
        sub(/^ /, "", q)
        cur = q; sub(/ .*/, "", cur)
        if (q ~ / /) sub(/^[^ ]+ /, "", q); else q = ""
        removed[cur] = 1
        if (cur in succ) {
          c = split(succ[cur], cs, " ")
          for (i = 1; i <= c; i++) {
            indeg[cs[i]]--
            if (indeg[cs[i]] == 0) q = q " " cs[i]
          }
        }
      }
      # Anything not removed is in or downstream of a cycle.
      for (k in node) if (!(k in removed)) print k
    }
  ' | sort -u)"
  if [ -n "$cycle_nodes" ]; then
    while IFS= read -r cn; do
      [ -z "$cn" ] && continue
      diagnostics+=("circular_dependency: Task $cn is part of a dependency cycle. Break the cycle by removing one dependency.")
    done <<< "$cycle_nodes"
  fi

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
