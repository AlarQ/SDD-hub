# Rust — Project-Specific Rules (workflow-core + workflow-web)

General Rust rules live in `general:languages/rust.md`. These rules are specific to the Rust workspace in this repo (root Cargo workspace; `workflow-core` shared lib + `workflow-web` Leptos SSR + Axum dashboard). The prior `workflow-tui` crate was retired in workflow-web-ui task 001 — its `model/`+`parse/` were harvested into `workflow-core`.

## Architecture

- **Workspace layout** — root `Cargo.toml` declares `[workspace] members = ["workflow-core", "workflow-web"]`. `workflow-core` is the shared library (`model/`, `parse/`, `WatchSource`/`WatchEvent`); `workflow-web` is the binary (handlers, SSE, watchers, cache, sanitizer, broadcast hub, Leptos SSR + WASM islands).
- **Layer separation** — `parse/` reads files only; `workflow-core` holds no web- or UI-specific code; web handlers read the cache, watchers invalidate it
- **Dependency direction** — consumers (`workflow-web`) depend on `workflow-core`; never the reverse
- **No cross-layer calls** — `api/` handlers must not call `parse/` directly; they go through the cache

## Error Handling

- Propagate with `?`; surface errors to the event loop, not inline panics

## Dependencies (approved)

Canonical dep list + per-crate justification lives in `specs/workflow-web-ui/design.md` (Cargo dependencies table). Core idiom crates: `serde`/`serde_yml`/`serde_json` (frontmatter + JSONL), `clap` (CLI), `anyhow`/`thiserror` (errors), `notify`/`notify-debouncer-mini` (fs watching). Adding new dependencies requires explicit justification — keep the dep count minimal.

## File System Watching

- File change events come through the `WatchSource` impls in `workflow-web` (structural debounced watcher + `.monitor.jsonl` tail watcher) → per-project broadcast hub → SSE
- Debounce structural events before invalidating the cache — avoid redundant re-parses on rapid saves (per ADR-004)

## Validation Scope

The repo root **is** a Cargo workspace (`members = ["workflow-core", "workflow-web"]`). All `cargo` commands run from the repo root with `--workspace` (`cargo check --workspace`, `cargo test --workspace`). `workflow-core` must also build standalone via `cargo check -p workflow-core`. (Supersedes the prior per-crate `workflow-tui/` scope — see ADR-002 / spec-review-4.)
