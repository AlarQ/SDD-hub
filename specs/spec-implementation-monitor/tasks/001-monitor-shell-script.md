---
id: "001"
name: "Create monitor.sh event logger script"
status: done
pr_url: https://github.com/AlarQ/SDD-hub/pull/8
blocked_by: []
max_files: 1
estimated_files:
  - scripts/monitor.sh
test_cases:
  - "log_event appends valid JSONL line to .monitor.jsonl"
  - "log_event creates .monitor.jsonl if it does not exist"
  - "start_phase prints correlation_id to stdout"
  - "end_phase logs event with matching correlation_id"
  - "set_context writes feature and task to .monitor-context"
  - "clear_context removes .monitor-context file"
  - "log_event with empty task_id omits task field"
  - "JSON output is valid single-line JSON per event"
  - "timestamps are ISO 8601 UTC format"
ground_rules:
  - general:style/general.md
  - general:architecture/general.md
---

## Description

Create `scripts/monitor.sh` — the core event logging script for the monitoring system.

## Public API

- `log_event <feature> <category> <task_id> <json_data>` — append JSONL line
- `start_phase <feature> <task_id> <phase_name>` — log start event, print correlation_id
- `end_phase <feature> <correlation_id>` — log end event with matching ID
- `set_context <feature> <task_id>` — write `.monitor-context` file
- `clear_context` — remove `.monitor-context` file

## Implementation Notes

- Use `printf` for JSON construction (no `jq` dependency)
- Timestamps: `date -u +"%Y-%m-%dT%H:%M:%S.000Z"`
- Correlation IDs: `<phase>-<task>-<epoch>`
- Append via `>>` to `specs/<feature>/.monitor.jsonl`
- Source-able by other scripts: `source ~/.claude/scripts/monitor.sh`
- `escape_json_string` handles backslash, double-quote, newline, and tab escaping for safe JSON embedding
- `find_project_root` walks up from `$PWD` looking for `specs/` directory — enables both sourced and direct invocation
- CLI mode uses `BASH_SOURCE[0] == $0` guard so the script works both when sourced and when invoked directly
- When `task_id` is empty, the `"task"` key is omitted entirely from the JSON (not set to null or empty string)
- `end_phase` extracts phase name from correlation_id prefix for the `data.phase` field
- Tests in `tests/test-monitor.sh` use temp directories with synthetic `specs/<feature>/` structures
