# Design: Spec Implementation Monitor

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│  Emission Layer                                             │
│                                                             │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │ PostToolUse  │    │ Slash cmds   │    │ task-manager  │  │
│  │ Hook         │    │ /implement   │    │ .sh           │  │
│  │              │    │ /validate    │    │               │  │
│  │ tool_call    │    │ kb_rule      │    │ task_         │  │
│  │ context_read │    │ validation_  │    │ transition    │  │
│  │ agent_       │    │ result       │    │               │  │
│  │ invocation   │    │              │    │               │  │
│  └──────┬───────┘    └──────┬───────┘    └──────┬───────┘  │
│         │                   │                   │           │
│         └─────────┬─────────┴─────────┬─────────┘           │
│                   ▼                   ▼                     │
│         ┌─────────────────┐  ┌────────────────┐            │
│         │ .monitor-context│  │  monitor.sh    │            │
│         │ (active session)│  │  (log_event)   │            │
│         └─────────────────┘  └───────┬────────┘            │
│                                      │                     │
│                                      ▼                     │
│                          specs/<feature>/                   │
│                          .monitor.jsonl                     │
└──────────────────────────┬──────────────────────────────────┘
                           │
                    ┌──────┴──────┐
                    │ notify      │
                    │ file watcher│
                    └──────┬──────┘
                           │
┌──────────────────────────┴──────────────────────────────────┐
│  TUI Layer                                                  │
│                                                             │
│  ┌──────────────┐  ┌──────────────────────────────────────┐│
│  │ Sidebar      │  │  2x2 Detail Grid                     ││
│  │              │  │                                       ││
│  │ SpecList     │  │  ┌─────────────┐ ┌─────────────┐    ││
│  │ (always      │  │  │  DepGraph   │ │  Reports    │    ││
│  │  visible)    │  │  └─────────────┘ └─────────────┘    ││
│  │              │  │  ┌─────────────┐ ┌─────────────┐    ││
│  │              │  │  │  Progress   │ │  Monitor    │    ││
│  │              │  │  └─────────────┘ └─────────────┘    ││
│  └──────────────┘  └──────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

## Module Boundaries

### Shell Layer (emission)

| Module | Responsibility | Inputs | Outputs |
|--------|---------------|--------|---------|
| `monitor.sh` | Event construction and file append | category, task, data args | JSONL line appended to `.monitor.jsonl` |
| `monitor-tool-calls.sh` | Hook: capture tool-level events | PostToolUse hook JSON | Calls `monitor.sh log_event` |
| `.monitor-context` | Cross-process state bridge | Written by commands | Read by hooks |

### Rust Layer (display)

| Module | Responsibility | Inputs | Outputs |
|--------|---------------|--------|---------|
| `model/monitor_event.rs` | Domain types for events | — | `MonitorEvent`, `EventCategory` |
| `parse/monitor_parser.rs` | JSONL line parsing | File content | `Vec<MonitorEvent>` |
| `ui/monitor.rs` | Render Monitor panel | `&[MonitorEvent]`, `Rect` | Frame draw calls |
| `ui/layout.rs` (modified) | Sidebar + 2x2 grid | Terminal `Rect` | Layout regions |
| `app.rs` (modified) | Panel navigation with sidebar | Key events | State updates |

### Event Ownership Contract

Clear boundary to prevent duplicate events:

| Category | Owner | Emitter |
|----------|-------|---------|
| `context_read` | Hook | `monitor-tool-calls.sh` |
| `tool_call` | Hook | `monitor-tool-calls.sh` |
| `agent_invocation` | Hook (lifecycle) + Command (reason) | Hook logs start/complete; command enriches via correlation_id |
| `kb_rule` | Command | `/implement` via `monitor.sh` |
| `task_transition` | Command | `task-manager.sh` via `monitor.sh` |
| `validation_result` | Command | `/validate` via `monitor.sh` |

## Detailed Design

### `monitor.sh` — Event Logger

```bash
# Public API:
#   log_event <feature> <category> <task_id> <json_data>
#   start_phase <feature> <task_id> <phase_name>  -> prints correlation_id
#   end_phase <feature> <correlation_id>
#   set_context <feature> <task_id>
#   clear_context
```

- Uses `printf` for JSON construction (no `jq` dependency — see ADR risk flag)
- Timestamps via `date -u +"%Y-%m-%dT%H:%M:%S.000Z"` (second precision; millisecond not reliably available in POSIX shell)
- Correlation IDs: `<phase>-<task>-<epoch>` (e.g., `impl-003-1712345678`)
- Append via `>>` — atomic for lines under PIPE_BUF (4096 bytes), which all events will be

### `monitor-tool-calls.sh` — PostToolUse Hook

```bash
# Receives: JSON on stdin from Claude Code hook system
# Reads: .monitor-context for active feature/task
# Behavior:
#   1. Check .monitor-context exists — if not, exit 0 (no active session)
#   2. Parse tool_name from hook input
#   3. Map to event category:
#      - Read -> context_read (extract file path)
#      - Agent -> agent_invocation (extract agent name)
#      - Bash, Edit, Write -> tool_call (extract tool name)
#   4. Call monitor.sh log_event
```

Fast-exit optimization: the `.monitor-context` existence check is the first operation — hooks that fire outside of monitored sessions add near-zero overhead.

### `task-manager.sh` — Instrumentation

Add `monitor.sh` calls to `cmd_set_status` and `cmd_unblock`:

```bash
# In cmd_set_status, after successful update:
if [ -f ".monitor-context" ]; then
  source .monitor-context
  monitor.sh log_event "$feature" "task_transition" "$task_id" \
    "{\"from_status\":\"$current_status\",\"to_status\":\"$new_status\",\"task_file\":\"$file\"}"
fi
```

### Rust: `MonitorEvent` Model

```rust
// model/monitor_event.rs

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EventCategory {
    ContextRead,
    KbRule,
    TaskTransition,
    AgentInvocation,
    ValidationResult,
    ToolCall,
}

#[derive(Debug, Clone, Deserialize)]
pub struct MonitorEvent {
    pub ts: String,
    pub category: EventCategory,
    #[serde(default)]
    pub task: Option<String>,
    pub feature: String,
    #[serde(default)]
    pub correlation_id: Option<String>,
    pub data: serde_json::Value,
}
```

### Rust: JSONL Parser

```rust
// parse/monitor_parser.rs

pub fn parse_monitor_log(content: &str, source: &str) -> (Vec<MonitorEvent>, Vec<String>) {
    let mut events = Vec::new();
    let mut warnings = Vec::new();

    for (i, line) in content.lines().enumerate() {
        let line = line.trim();
        if line.is_empty() { continue; }
        match serde_json::from_str::<MonitorEvent>(line) {
            Ok(event) => events.push(event),
            Err(e) => warnings.push(format!("{source}:{}: {e}", i + 1)),
        }
    }

    (events, warnings)
}
```

### Rust: Layout — Sidebar + 2x2 Grid

```rust
// ui/layout.rs

pub struct DashboardLayout {
    pub sidebar: Rect,
    pub grid: [Rect; 4],  // DepGraph, Reports, Progress, Monitor
}

pub fn build_layout(area: Rect) -> DashboardLayout {
    let columns = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(25), Constraint::Percentage(75)])
        .split(area);

    let rows = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Percentage(50), Constraint::Percentage(50)])
        .split(columns[1]);

    let top = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(50), Constraint::Percentage(50)])
        .split(rows[0]);

    let bottom = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(50), Constraint::Percentage(50)])
        .split(rows[1]);

    DashboardLayout {
        sidebar: columns[0],
        grid: [top[0], top[1], bottom[0], bottom[1]],
    }
}
```

### Rust: Panel Navigation Update

```rust
// app.rs — Panel enum changes

pub enum Panel {
    SpecList,    // Sidebar — always rendered, but can be "active" for selection
    DepGraph,    // Grid [0]
    Reports,     // Grid [1]
    Progress,    // Grid [2]
    Monitor,     // Grid [3]
}
```

Tab cycles through all 5 panels. When SpecList is active, j/k selects specs. When a grid panel is active, j/k scrolls that panel's content.

### Rust: Monitor Panel Rendering

Each event line rendered as:

```
14:32:01  AGENT    003  Code Quality Pragmatist — post-implementation check
14:32:05  READ     003  src/app.rs
14:32:10  TOOL     003  Edit (src/model/event.rs)
14:33:00  TRANSIT  003  in-progress → implemented
14:33:15  VALID    003  security: pass (0 findings)
```

Color coding by category:
- `context_read` → Cyan
- `kb_rule` → Blue
- `task_transition` → Yellow
- `agent_invocation` → Magenta
- `validation_result` → Green (pass) / Red (findings/error)
- `tool_call` → Gray

### Scanner Extension

`scan_specs` in `scanner.rs` extended to look for `.monitor.jsonl` in each spec directory:

```rust
// In scan_specs, after scanning tasks and reports:
let (monitor_events, monitor_warns) = scan_monitor_log(&path);
warnings.extend(monitor_warns);

specs.push(Spec {
    name,
    tasks,
    reports,
    monitor_events,  // new field
});
```

### `setup.sh` Changes

Add installation of:
- `scripts/monitor.sh` → `~/.claude/scripts/monitor.sh` (executable)
- `hooks/monitor-tool-calls.sh` → `~/.claude/hooks/monitor-tool-calls.sh` (executable)

Add verification checks for both files.

## Architecture Decision Records

### ADR-001: JSONL File as Event Store

**Status**: Proposed

**Context**: The monitoring system needs persistent, auditable event storage. The existing workflow is entirely file-based (markdown specs, YAML frontmatter, YAML reports). The TUI already watches the filesystem for changes via the `notify` crate.

**Decision**: Use a single `.monitor.jsonl` file per feature at `specs/<feature>/.monitor.jsonl`. Events are appended as single JSON lines. Tracked in git for audit purposes. No concurrent writer support.

**Consequences**:
- (+) Zero infrastructure — emission is `echo >>`, TUI reuses file watcher
- (+) Git-trackable audit trail, inspectable with `cat`, `grep`, `jq`
- (-) Linear scan on every TUI refresh (bounded by feature lifetime)
- (-) Single-writer assumption — one Claude session per feature

### ADR-002: Hybrid Event Emission

**Status**: Proposed

**Context**: Events split naturally into mechanical (tool calls, file reads) and semantic (task transitions, validation results). Hooks can intercept tool calls but lack workflow context. Commands have workflow context but cannot intercept tool calls.

**Decision**: PostToolUse hooks capture `tool_call`, `context_read`, and `agent_invocation` lifecycle events. Slash commands emit `task_transition`, `kb_rule`, and `validation_result` via `monitor.sh`. Bridge via `.monitor-context` file.

**Consequences**:
- (+) Automatic coverage for high-volume events, precise semantics for domain events
- (-) Two emission paths; event ownership contract must be documented and enforced
- (-) Hook reads `.monitor-context` on every tool call (mitigated by fast-exit check)

### ADR-003: `.monitor-context` for Cross-Process State

**Status**: Proposed

**Context**: Claude Code hooks run as separate shell processes with no shared memory or inherited environment. Hooks need to know the active feature/task.

**Decision**: Commands write `feature=<name>` and `task=<id>` to `.monitor-context` in the project root. Hooks read it. File is `.gitignore`d. Commands overwrite at every task start.

**Consequences**:
- (+) Simple shell read/write, works across all process boundaries
- (-) Stale after crashes — mitigated by timestamp check (2-hour expiry)
- (-) Single-feature per project — acceptable given serial execution constraint

### ADR-004: serde_json for Event Parsing

**Status**: Proposed

**Context**: TUI needs to parse JSONL. serde_yml (already in deps) can technically parse JSON but introduces edge cases and semantic confusion.

**Decision**: Add `serde_json` as an explicit dependency. Use `serde_json::Value` for the flexible `data` field.

**Consequences**:
- (+) Correct, fast, idiomatic JSON parsing
- (-) One more dependency (minimal cost — widely used, often already transitive)

### ADR-005: Left Sidebar Layout

**Status**: Proposed

**Context**: Current 2x2 grid has 4 panels. Adding Monitor makes 5. SpecList functions as navigation (selecting a spec to view details), making it a natural sidebar.

**Decision**: Restructure to left sidebar (SpecList, ~25% width) + right 2x2 grid (DepGraph, Reports, Progress, Monitor).

**Consequences**:
- (+) SpecList always visible, improving navigation UX
- (+) Right grid remains clean 2x2; Monitor gets full quadrant
- (-) Layout rewrite touches all UI modules — implement as isolated task, verify existing panels first
- (-) Sidebar must degrade gracefully on narrow terminals

## Data Flow

```
1. /implement starts task 003 on feature "auth-system"
   → monitor.sh set_context auth-system 003
   → writes .monitor-context: feature=auth-system\ntask=003
   → monitor.sh log_event auth-system task_transition 003 {"from":"todo","to":"in-progress"}

2. Claude reads src/auth.rs via Read tool
   → PostToolUse hook fires
   → monitor-tool-calls.sh reads .monitor-context → feature=auth-system, task=003
   → monitor.sh log_event auth-system context_read 003 {"file":"src/auth.rs"}

3. Claude spawns Code Quality Pragmatist agent
   → PostToolUse hook fires
   → monitor-tool-calls.sh detects Agent tool
   → monitor.sh log_event auth-system agent_invocation 003 {"agent":"Code Quality Pragmatist","phase":"start"}

4. /validate runs security gate → pass with 0 findings
   → monitor.sh log_event auth-system validation_result 003 {"gate":"security","status":"pass","findings_count":0}

5. TUI file watcher detects .monitor.jsonl change
   → rescan → parse new events → render in Monitor panel
```

## Dependencies

### New Rust crate
- `serde_json = "1.0"` — JSONL parsing

### New shell scripts
- `scripts/monitor.sh` — event logger (no new system dependencies — uses `printf`, `date`)
- `hooks/monitor-tool-calls.sh` — PostToolUse hook

### Modified files
- `scripts/task-manager.sh` — add monitor calls to `cmd_set_status`, `cmd_unblock`
- `setup.sh` — add installation of `monitor.sh` and `monitor-tool-calls.sh`
- `workflow-tui/Cargo.toml` — add `serde_json`
- `workflow-tui/src/app.rs` — Panel::Monitor, navigation changes
- `workflow-tui/src/model/` — add `monitor_event.rs`, update `mod.rs`, extend `Spec`
- `workflow-tui/src/parse/` — add `monitor_parser.rs`, update `mod.rs`, extend `scanner.rs`
- `workflow-tui/src/ui/` — add `monitor.rs`, update `layout.rs`, `mod.rs`
