---
id: "004"
name: "Add MonitorEvent model and JSONL parser to TUI"
status: done
blocked_by: []
max_files: 4
estimated_files:
  - workflow-tui/Cargo.toml
  - workflow-tui/src/model/monitor_event.rs
  - workflow-tui/src/model/mod.rs
  - workflow-tui/src/parse/monitor_parser.rs
test_cases:
  - "parse valid JSONL line into MonitorEvent"
  - "parse all six event categories correctly"
  - "skip empty lines without warning"
  - "skip malformed lines with warning including line number"
  - "parse event with missing optional fields (task, correlation_id)"
  - "parse event with arbitrary JSON in data field"
  - "EventCategory deserializes from snake_case strings"
  - "multiple valid lines parsed into Vec<MonitorEvent>"
ground_rules:
  - project:languages/rust.md
  - general:testing/principles.md
  - general:architecture/general.md
---

## Description

Add the Rust domain types and JSONL parser for monitoring events.

## New Files

### `model/monitor_event.rs`
- `EventCategory` enum: `ContextRead`, `KbRule`, `TaskTransition`, `AgentInvocation`, `ValidationResult`, `ToolCall`
- `MonitorEvent` struct with serde deserialization
- Color method on `EventCategory` for TUI rendering

### `parse/monitor_parser.rs`
- `parse_monitor_log(content: &str, source: &str) -> (Vec<MonitorEvent>, Vec<String>)`
- Line-by-line JSONL parsing, tolerant of malformed lines

## Dependency
- Add `serde_json = "1.0"` to `Cargo.toml`

## Implementation Notes
- Types and parser are `#[allow(dead_code)]` / `#[allow(unused_imports)]` since they're consumed by later tasks (scanner integration in task 005+, TUI rendering)
- Also fixed pre-existing `collapsible_if` clippy warnings in `scanner.rs` and `main.rs` (Rust 1.93 made these errors under `-D warnings`)
- Also applied `cargo fmt` formatting fixes across the existing codebase
- `parse/mod.rs` re-exports `parse_monitor_log` for public use by scanner
- `model/mod.rs` re-exports `EventCategory` and `MonitorEvent` for public use
