---
id: "007"
name: "Extend scanner to load .monitor.jsonl files"
status: blocked
blocked_by:
  - "004"
max_files: 2
estimated_files:
  - workflow-tui/src/parse/scanner.rs
  - workflow-tui/src/parse/mod.rs
test_cases:
  - "scanner finds .monitor.jsonl in spec directory"
  - "scanner returns empty events when .monitor.jsonl does not exist"
  - "scanner returns parsed events when .monitor.jsonl has valid content"
  - "scanner includes warnings for malformed JSONL lines"
  - "file watcher triggers rescan when .monitor.jsonl is modified"
ground_rules:
  - project:languages/rust.md
  - general:testing/principles.md
---

## Description

Extend `parse/scanner.rs` to scan for `.monitor.jsonl` alongside tasks and reports.

## Changes

### `parse/scanner.rs`
- Add `scan_monitor_log(spec_dir: &Path) -> (Vec<MonitorEvent>, Vec<String>)`
- Reads `<spec_dir>/.monitor.jsonl` if it exists
- Called from `scan_specs` for each spec directory
- Attach results to `Spec` struct

### `parse/mod.rs`
- Export `parse_monitor_log` from `monitor_parser`
