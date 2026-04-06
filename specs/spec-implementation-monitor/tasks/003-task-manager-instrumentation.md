---
id: "003"
name: "Add monitoring instrumentation to task-manager.sh"
status: done
blocked_by:
  - "001"
max_files: 2
estimated_files:
  - scripts/task-manager.sh
  - tests/test-task-manager-monitor.sh
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

## Implementation Notes

- `monitor.sh` is sourced from `$SCRIPT_DIR` (same directory as `task-manager.sh`), using a `MONITOR_AVAILABLE` flag to guard event emission calls
- `read_context` from `monitor.sh` is used to get the active feature/task from `.monitor-context`, avoiding direct file parsing duplication
- Event emission uses `|| true` to prevent monitoring failures from breaking task management operations
- `cmd_set_status` uses the context's task ID for the event (matches the active task being transitioned)
- `cmd_unblock` uses the unblocked task's own ID from frontmatter for the event (since the unblocked task differs from the context's active task)
- Tests use copied scripts in a temp directory to isolate from the installed environment
