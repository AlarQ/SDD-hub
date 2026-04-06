---
id: "002"
name: "Create PostToolUse hook for tool call monitoring"
status: done
blocked_by:
  - "001"
max_files: 2
estimated_files:
  - hooks/monitor-tool-calls.sh
  - tests/test-monitor-hook.sh
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

## Implementation Notes (AI)

- Uses `extract_json_value` with bash regex (`=~`) for lightweight JSON field extraction — no `jq` dependency, matching `monitor.sh` approach
- `find_project_root` duplicated from `monitor.sh` (cannot source monitor.sh before knowing project root for the fast-exit check)
- Agent name extraction prefers `description` field, falls back to `subagent_type` — matches how agents are typically invoked
- All exit paths use `exit 0` to never block the user's tool call on hook failure
- Tests use `HOME` override to point at a fake `~/.claude/scripts/monitor.sh` — isolates from user's actual installation
- Task branch named `feat/sim-002-monitor-hook-script` due to git ref conflict with `feat/spec-implementation-monitor` integration branch
