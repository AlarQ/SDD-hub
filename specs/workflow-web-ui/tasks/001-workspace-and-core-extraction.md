---
id: "001"
name: "Cargo workspace + workflow-core extraction"
status: todo
blocked_by: []
max_files: 20
estimated_files:
  - Cargo.toml
  - Cargo.lock
  - .cargo/config.toml
  - workflow-core/Cargo.toml
  - workflow-core/src/lib.rs
  - workflow-core/src/model/mod.rs
  - workflow-core/src/model/spec.rs
  - workflow-core/src/model/task.rs
  - workflow-core/src/model/report.rs
  - workflow-core/src/model/monitor_event.rs
  - workflow-core/src/parse/mod.rs
  - workflow-core/src/parse/scanner.rs
  - workflow-core/src/parse/task_parser.rs
  - workflow-core/src/parse/report_parser.rs
  - workflow-core/src/parse/monitor_parser.rs
  - workflow-core/src/parse/frontmatter.rs
  - workflow-core/src/watch.rs
  - workflow-tui/Cargo.toml
  - workflow-tui/src/main.rs
  - CLAUDE.md
test_cases:
  - "workflow-core compiles standalone with cargo check -p workflow-core"
  - "workflow-core unit tests pass for spec/task/report parsers (moved from TUI)"
  - "workflow-tui imports workflow_core::{model, parse} and builds clean"
  - "workflow-tui runtime behavior unchanged: cargo run -p workflow-tui -- <fixture> displays same spec list"
  - "WatchSource trait defines Structural and MonitorAppend variants on WatchEvent"
  - "cargo check --workspace succeeds from repo root"
  - "cargo test --workspace passes"
  - ".cargo/config.toml aliases tui and web resolve"
  - "CLAUDE.md Build & Run section updated to reflect workspace layout"
ground_rules:
  - general:architecture/general.md
  - general:languages/rust/ownership.md
  - general:languages/rust/concurrency.md
  - general:languages/rust/_index.md
  - general:testing/principles.md
  - project:languages/rust.md
---

## Description

Convert repo to Cargo workspace. Extract `model/` and `parse/` from `workflow-tui/src/` into a new `workflow-core` crate. Add `WatchSource` trait + `WatchEvent` enum stub. TUI consumes core and continues to work unchanged. Implements ADR-001 + ADR-002.

## Acceptance Criteria

- Root `Cargo.toml` declares `[workspace] members = ["workflow-core","workflow-tui"]` with shared `[workspace.dependencies]` (serde, anyhow, tokio, tracing, serde_yml, serde_json).
- `workflow-core/src/{model,parse}` mirror the TUI's prior modules, file-for-file. `workflow-tui/src/{model,parse}` deleted.
- `WatchSource` trait + `WatchEvent { Structural{path}, MonitorAppend{project, feature, events} }` live in `workflow-core/src/watch.rs`. Notify impls deferred to consumers.
- `cargo check --workspace`, `cargo test --workspace`, `cargo run -p workflow-tui -- <fixture>` all green.
- `.cargo/config.toml` adds `[alias]` `tui = "run -p workflow-tui --"` and `web = "run -p workflow-web --"`.
- CLAUDE.md Build & Run + Project Structure sections updated.

## Implementation Notes

- Edition 2024 across all crates.
- TUI's `watcher.rs` keeps its notify impl; uses the trait surface from core but the concrete type stays in TUI for now (web crate will provide its own impl).
- Move-only refactor — no semantic changes to parsers. Verify by running TUI against existing fixture.
- Keep module size < 100 LOC where feasible (`general:architecture/general.md`).
