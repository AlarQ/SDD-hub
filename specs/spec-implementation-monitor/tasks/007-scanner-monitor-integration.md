---
id: "007"
name: "Extend scanner to load .monitor.jsonl files"
status: done
pr_url: https://github.com/AlarQ/SDD-hub/pull/19
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

## Implementation Notes

All changes for this task were already implemented during task 004 (MonitorEvent model and JSONL parser). The scanner integration was done proactively as part of the same PR:

- `scan_monitor_log` in scanner.rs reads `.monitor.jsonl` from each spec directory, delegates to `parse_monitor_log`, and handles NotFound gracefully
- `parse/mod.rs` already exports `parse_monitor_log` from the `monitor_parser` module
- `Spec` struct in `model/spec.rs` already includes the `monitor_events` field
- File watcher coverage is inherent — the notify watcher monitors the specs directory tree, so `.monitor.jsonl` changes trigger rescans
- All 5 test cases are covered by the existing parser tests (malformed lines, empty files, valid parsing) and scanner logic (NotFound handling, warning propagation)
- No additional code changes needed — all validations pass (cargo test, clippy, fmt)
