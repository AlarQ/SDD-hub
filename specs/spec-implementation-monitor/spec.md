# Spec: Spec Implementation Monitor

## Overview

A real-time monitoring system that captures and displays all actions during spec-driven implementation. Events are logged to a JSONL file per feature, and the workflow TUI renders them in a dedicated Monitor panel with live updates.

## Motivation

Understanding what happens during spec implementation — which files were read, which KB rules applied, which agents were invoked, how long phases took — enables tuning commands, agents, and ground rules. The full audit trail (tracked in git, never deleted) supports post-hoc analysis and conclusions.

## Event Categories

### 1. Context Reads
- **What**: Files read during implementation (source code, config, specs)
- **Source**: Hooks intercepting `Read` tool calls and `Bash` cat/head/tail
- **Data**: `{file, source: "hook"}`

### 2. KB Rule Usage
- **What**: Knowledge base items loaded/applied during task execution
- **Source**: Command instrumentation when ground_rules are resolved
- **Data**: `{rule_path, prefix: "general"|"project", resolved_path}`

### 3. Task State Transitions
- **What**: Status changes (e.g., `todo -> in-progress -> implemented`)
- **Source**: `task-manager.sh` instrumentation on `set-status` and `unblock`
- **Data**: `{task_id, from_status, to_status, task_file}`

### 4. Agent Invocations
- **What**: Specialized agents spawned and their lifecycle
- **Source**: Hooks intercepting `Agent` tool calls + command-level annotation
- **Data**: `{agent_name, reason, phase: "start"|"complete"|"error"}`

### 5. Validation Gate Results
- **What**: Pass/fail per validation gate, findings count
- **Source**: Command instrumentation in `/validate`
- **Data**: `{gate, task_id, status: "pass"|"findings"|"error", findings_count}`

### 6. Time Tracking
- **What**: Duration of phases, agent runs, and overall task execution
- **Source**: Computed from paired start/end events with matching correlation IDs
- **Data**: `{phase, duration_ms}` (derived, not directly emitted — computed by TUI from event pairs)

### 7. Tool Call Volume
- **What**: Count of bash/edit/read/write calls per task
- **Source**: Hooks intercepting tool calls, aggregated by tool name
- **Data**: `{tool_name, source: "hook"}`

## Event Schema

Each event is a single JSON line in `.monitor.jsonl`:

```json
{
  "ts": "2026-04-05T14:32:01.123Z",
  "category": "context_read|kb_rule|task_transition|agent_invocation|validation_result|tool_call",
  "task": "003",
  "feature": "spec-implementation-monitor",
  "correlation_id": "impl-003-1712345678",
  "data": { ... }
}
```

Fields:
- `ts` — ISO 8601 timestamp with milliseconds
- `category` — one of the 6 emittable categories (time tracking is derived)
- `task` — task ID (may be empty for feature-level events)
- `feature` — feature/spec name
- `correlation_id` — groups related events (e.g., agent start + complete)
- `data` — category-specific payload

## File Location

`specs/<feature>/.monitor.jsonl` — one file per feature, hidden (dotfile), tracked in git, never deleted.

## Emission Architecture

### Shell Script: `monitor.sh`

New global script installed via `setup.sh` to `~/.claude/scripts/monitor.sh`.

Functions:
- `log_event <feature> <category> <task_id> <json_data>` — appends a JSONL line to `specs/<feature>/.monitor.jsonl`
- `start_phase <feature> <task_id> <phase_name>` — logs a start event with a correlation ID, prints the ID
- `end_phase <feature> <correlation_id>` — logs an end event matching the correlation ID

Design: Pure append-only. No reads, no locks (single-writer assumption — one Claude session per feature). Uses `date` for timestamps, `jq` for JSON construction.

### Hook Scripts

New hook scripts installed via `setup.sh`:

- `monitor-tool-calls.sh` — `PostToolUse` hook that captures:
  - `Read` tool calls → `context_read` events
  - `Agent` tool calls → `agent_invocation` events
  - `Bash`/`Edit`/`Write` tool calls → `tool_call` events

The hook must detect the active feature/task context. Strategy: read a `.monitor-context` file in the project root that commands set when starting work on a task. Format: `feature=<name>\ntask=<id>`.

### Command Instrumentation

Slash commands add explicit `monitor.sh` calls for semantic events:
- `/implement` — sets `.monitor-context`, logs KB rule usage, task transitions
- `/validate` — logs validation gate results
- `/review-findings` — logs finding review decisions
- `/ship` — logs task completion

## TUI Integration

### New Panel: Monitor

5th panel in the Tab cycle: SpecList → DepGraph → Reports → Progress → **Monitor**.

Displays:
- Scrollable event feed for the selected spec
- Each event rendered as a colored, formatted line:
  - Timestamp (dimmed)
  - Category badge (colored by category)
  - Task ID (if present)
  - Summary (from data payload)
- Scroll with j/k or arrow keys (existing scroll behavior)

### New Model: `MonitorEvent`

```rust
struct MonitorEvent {
    ts: String,
    category: EventCategory,
    task: Option<String>,
    feature: String,
    correlation_id: Option<String>,
    data: serde_json::Value,
}

enum EventCategory {
    ContextRead,
    KbRule,
    TaskTransition,
    AgentInvocation,
    ValidationResult,
    ToolCall,
}
```

### New Parser: `monitor_parser.rs`

Reads `specs/<feature>/.monitor.jsonl`, parses each line into `MonitorEvent`. Tolerant of malformed lines (skip with warning).

### Scanner Extension

`scanner.rs` extended to also scan for `.monitor.jsonl` in each spec directory and attach parsed events to the `Spec` model.

### Layout Change

Grid changes from 2x2 to accommodate 5 panels. Options evaluated in design.

## Scenarios (BDD)

### Event Logging

```
Given a project with specs/my-feature/tasks/001-setup.md
When /implement starts work on task 001
Then a .monitor-context file is created with feature=my-feature, task=001
And monitor.sh logs a task_transition event {from: "todo", to: "in-progress"}
```

```
Given an active .monitor-context with feature=my-feature, task=001
When Claude reads src/app.rs via the Read tool
Then the PostToolUse hook logs a context_read event with file=src/app.rs
```

```
Given an active .monitor-context
When Claude spawns the "Code Quality Pragmatist" agent
Then the hook logs an agent_invocation event with phase=start
And when the agent completes, logs phase=complete with matching correlation_id
```

```
Given /validate runs the security gate on task 001
When the gate returns status: findings with 3 findings
Then monitor.sh logs a validation_result event {gate: "security", status: "findings", findings_count: 3}
```

### TUI Display

```
Given specs/my-feature/.monitor.jsonl contains 50 events
When the user selects my-feature in the SpecList panel
And navigates to the Monitor panel
Then all 50 events are displayed in chronological order
And the user can scroll through the full list
```

```
Given the TUI is showing the Monitor panel for my-feature
When a new event is appended to .monitor.jsonl
Then the file watcher triggers a rescan
And the new event appears at the bottom of the feed
```

```
Given the Monitor panel is showing events
When an event has category=agent_invocation
Then it is rendered with a distinct color (e.g., Magenta)
And shows the agent name and reason
```

### Edge Cases

```
Given specs/my-feature/.monitor.jsonl contains a malformed line
When the TUI parses the file
Then the malformed line is skipped with a warning
And all valid events are displayed
```

```
Given no .monitor.jsonl exists for the selected spec
When the user navigates to the Monitor panel
Then a "No monitoring data" message is displayed
```

```
Given .monitor-context does not exist
When a PostToolUse hook fires
Then the hook exits silently without logging (no active monitoring session)
```

## Out of Scope

- Filtering/search within the Monitor panel (future enhancement)
- Aggregated statistics/dashboards (future enhancement)
- Multi-session support (concurrent Claude sessions on same feature)
- Export to external systems (Grafana, etc.)
- Copilot integration for monitoring (Claude Code only for now)
