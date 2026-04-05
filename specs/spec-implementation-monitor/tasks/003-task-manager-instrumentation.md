---
id: "003"
name: "Add monitoring instrumentation to task-manager.sh"
status: todo
blocked_by:
  - "001"
max_files: 1
estimated_files:
  - scripts/task-manager.sh
test_cases:
  - "set-status logs task_transition event on successful transition"
  - "set-status does not log event when transition fails"
  - "unblock logs task_transition event for each unblocked task"
  - "no logging occurs when .monitor-context does not exist"
  - "logged event includes from_status and to_status"
  - "logged event includes task_file path"
ground_rules:
  - general:style/general.md
  - general:architecture/general.md
---

## Description

Instrument `scripts/task-manager.sh` to emit `task_transition` events via `monitor.sh` when task status changes occur.

## Changes

- In `cmd_set_status`: after successful `update_frontmatter`, check for `.monitor-context` and emit event
- In `cmd_unblock`: after each task is unblocked, emit event with `from: blocked, to: todo`
- Source `monitor.sh` at the top (with guard: only if the file exists)
