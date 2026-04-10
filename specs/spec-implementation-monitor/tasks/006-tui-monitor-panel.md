---
id: "006"
name: "Implement Monitor panel rendering in TUI"
status: done
blocked_by:
  - "004"
  - "005"
max_files: 3
estimated_files:
  - workflow-tui/src/ui/monitor.rs
  - workflow-tui/src/ui/mod.rs
  - workflow-tui/src/model/spec.rs
test_cases:
  - "empty event list shows 'No monitoring data' message"
  - "events render in chronological order"
  - "each event shows timestamp, category badge, task ID, and summary"
  - "category badges use distinct colors"
  - "context_read events show file path"
  - "agent_invocation events show agent name and reason"
  - "task_transition events show from and to status"
  - "validation_result events show gate name, status, and findings count"
  - "scroll offset controls which events are visible"
ground_rules:
  - project:languages/rust.md
  - general:style/general.md
  - general:architecture/general.md
---

## Description

Implement the Monitor panel widget that renders the event feed.

## New File: `ui/monitor.rs`

- `render(frame, events, area, is_active)` — renders scrollable event feed
- Each event line: `HH:MM:SS  CATEGORY  TASK  summary`
- Category badge colored by type (Cyan, Blue, Yellow, Magenta, Green/Red, Gray)
- Scrollable via existing scroll_offset mechanism
- "No monitoring data" placeholder when event list is empty

## Modifications

### `model/spec.rs`
- Add `monitor_events: Vec<MonitorEvent>` field to `Spec`

### `ui/mod.rs`
- Replace Monitor placeholder with actual `monitor::render()` call
- Pass `spec.monitor_events` to Monitor panel

## Implementation Notes

- `render()` signature includes `scroll_offset` parameter (passed from `app.scroll_offset`) for scroll support
- `category_badge()` delegates color to `styles::event_category_color()` to avoid duplicating the category-to-color mapping
- `format_summary()` handles both `from_status`/`to_status` and shorthand `from`/`to` keys for task transitions (defensive against both emission formats)
- Similarly, `agent_name`/`agent` and `tool_name`/`tool` alternates are handled for agent invocations and tool calls
- `validation_result` color uses the base category color (Green) from styles; per-status coloring (Red for findings) deferred to future enhancement
- `feature` and `correlation_id` fields on `MonitorEvent` are deserialized but not yet read by rendering — marked with `#[allow(dead_code)]` since they're structurally required for the JSONL schema
- Scanner extended with `scan_monitor_log()` that reads `.monitor.jsonl` from each spec directory; missing file returns empty vec (no warning)
- Removed all `#[allow(dead_code)]` and `#[allow(unused_imports)]` annotations from tasks 004/005 that were waiting for this task
- Also modified: `parse/scanner.rs` (new `scan_monitor_log` fn), `parse/mod.rs` (removed unused import allow), `model/monitor_event.rs` (removed dead_code allows), `app.rs` (updated test Spec constructors)
