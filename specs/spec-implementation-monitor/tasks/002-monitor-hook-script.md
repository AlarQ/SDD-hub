---
id: "002"
name: "Create PostToolUse hook for tool call monitoring"
status: todo
blocked_by:
  - "001"
max_files: 1
estimated_files:
  - hooks/monitor-tool-calls.sh
test_cases:
  - "hook exits silently when .monitor-context does not exist"
  - "hook logs context_read event for Read tool calls"
  - "hook logs agent_invocation event for Agent tool calls"
  - "hook logs tool_call event for Bash tool calls"
  - "hook logs tool_call event for Edit tool calls"
  - "hook logs tool_call event for Write tool calls"
  - "hook extracts file path from Read tool input"
  - "hook extracts agent name from Agent tool input"
  - "hook reads feature and task from .monitor-context"
ground_rules:
  - general:style/general.md
  - general:security/general.md
---

## Description

Create `hooks/monitor-tool-calls.sh` — a PostToolUse hook that automatically captures tool-level events during monitored sessions.

## Implementation Notes

- Receives JSON on stdin from Claude Code hook system
- First check: `.monitor-context` exists — if not, `exit 0` immediately (fast-exit optimization)
- Parse `tool_name` from hook input via lightweight JSON extraction
- Map tool to event category:
  - `Read` → `context_read` (extract `file_path` from tool input)
  - `Agent` → `agent_invocation` (extract agent name/type)
  - `Bash`, `Edit`, `Write`, `Glob`, `Grep` → `tool_call`
- Source `monitor.sh` and call `log_event`
- Must handle malformed hook input gracefully (exit 0, never fail the hook)
