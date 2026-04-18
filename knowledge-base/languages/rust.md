---
validation_tools:
  - cd workflow-tui && cargo clippy -- -D warnings
  - cd workflow-tui && cargo test
  - cd workflow-tui && cargo fmt -- --check
---

# Rust — Project-Specific Rules (workflow-tui)

General Rust rules live in `general:languages/rust.md`. These rules are specific to the workflow-tui TUI codebase.

## Architecture

- **Elm-like pattern** — `app.rs` owns all state and the `update()` function; UI widgets are pure render functions, no state mutations
- **Layer separation** — `ui/` renders only; `parse/` reads files only; `app.rs` owns transitions; `watcher.rs` owns fs events
- **No cross-layer calls** — `ui/` must not call `parse/`; `parse/` must not call `app.rs`

## Error Handling

- Propagate with `?`; surface errors to the event loop, not inline panics

## Dependencies (approved)

- `ratatui` — terminal UI rendering
- `crossterm` — terminal backend
- `notify` — file system watching
- `serde_yml` — YAML parsing for spec/task frontmatter
- `clap` — CLI argument parsing
- `anyhow` — error handling

Adding new dependencies requires explicit justification — keep the dep count minimal.

## File System Watching

- File change events come through `watcher.rs` → channel → event loop in `main.rs`
- Debounce file events before triggering re-parse — avoid redundant parses on rapid saves

## Validation Scope

All `cargo` commands must be run from `workflow-tui/` directory. The repo root has no Cargo workspace.
