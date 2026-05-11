# PRD — workflow-web-ui

## Problem

Current Rust TUI (`workflow-tui/`) does not scale visually with many specs/tasks/reports. Cramped, hard to discover, weak rich-content rendering (Mermaid, code, finding cards).

## User & Value

- **Primary user:** solo dev (Ernest), local machine.
- **Pains:** scale, visual quality, discoverability, rich content.
- **Value:** fast multi-pane web dashboard mirroring current TUI data, rendering rich content properly, scaling to ~100 specs / 1k tasks / project.

## Scope (v1)

### In
- New `workflow-web/` Leptos crate (SSR + Axum fullstack, single binary).
- Shared lib crate extracted from `workflow-tui/` (`model/`, `parse/`) — used by both TUI (until retired) and web.
- Multi-project discovery: server takes a master-brain root path, scans `projects/*/specs/`.
- Project switcher (one project at a time in UI).
- Web-native IA from day one: multi-pane resizable layout, persisted pane sizes.
- Read-only views: spec list, task detail (frontmatter + body + status), report finding cards (with code snippets), Mermaid dep graphs, live activity feed from `.monitor.jsonl`.
- Live updates via file-watcher (`notify`) → SSE push, with debouncing + Last-Event-ID resume.
- "Open in editor" links via local URI scheme (e.g. `vscode://`).
- Tailwind via `cargo-leptos`. Dark-mode-default, CSS-variable theme tokens.
- Client-side rendering for Mermaid (`mermaid.js`) and code highlighting (`shiki`) in WASM islands.
- Bind `127.0.0.1` only. No auth. `Host` header allowlist middleware. Path-traversal guard against configured root.
- Tests: unit on shared parser lib, integration on Axum handlers + SSE, Playwright e2e smoke flow.
- Retire `workflow-tui/` in final task once web UI reaches parity.

### Out
- Search (global or per-spec) — deferred to v2.
- Workflow command triggering from UI (read-only only).
- Multi-user / auth / LAN access.
- Write paths of any kind.
- Stakeholder/PM views, sharing, export.

## Non-Functional

- **Security:** localhost-only bind hard-coded, path canonicalization vs root, sanitized markdown render (`pulldown-cmark` + `ammonia`), Host-header allowlist, capped per-file read size, paginated JSONL tail.
- **Scale guards:** debounced/coalesced watcher events, capped SSE per-client queue depth (drop-oldest with `lag` notice).

## Integration Points

- Filesystem: `<root>/projects/*/specs/<feature>/{prd,spec,design,tasks/,reports/,.monitor.jsonl,config.yml}`.
- `notify` crate (already used in TUI) for file watching.
- `pulldown-cmark` + `ammonia` for markdown sanitization.
- `mermaid.js` + `shiki` (client) for diagrams + syntax.
- Editor URI scheme for click-out.

## Architecture Direction

- Single Cargo workspace: `workflow-tui/` (existing, eventual retirement), `workflow-web/` (new), `workflow-core/` or similar shared lib (extracted parsers/models).
- Leptos SSR + Axum, single binary `workflow-web <root>`.
- Parser cache keyed by `(path, mtime, len)` or content hash.
- SSE event schema `{type, project, feature, path, seq}` with monotonic `seq`.
- Dedicated tail watcher for `.monitor.jsonl` with byte-offset cursor; structural watcher for everything else.

## Applicable Ground Rules

- `general:security/security-patterns.md` (path traversal, input validation, no log secrets)
- `general:code-quality.md` (modular, functional, small modules)
- `project:languages/rust.md` (Rust style, error handling)

## Open Design Questions (for /propose)

- Shared lib crate name + boundary (which modules move from `workflow-tui/`).
- Parser cache implementation (in-memory `DashMap` vs LRU).
- Pane layout primitive — build from scratch vs lift an existing Leptos splitter component.
- Concrete event types and SSE topic filtering granularity.

## Agent Insights (Explore Phase)

### UX Researcher
- "TUI parity" assumption may inherit terminal constraints — validated by choosing **web-native IA from day one**.
- Edge case: live reload during `/implement` — solo dev keeps UI open while files mutate; needs file-watcher + handles partial writes / stale Mermaid renders.
- Edge case: `.monitor.jsonl` + reports grow during validation — read-only still needs tailing, not snapshot reads.
- Risk: shipping without global search leaves discoverability pain unsolved (user accepted; deferred to v2).
- Risk: "rich content" hides distinct rendering needs — Mermaid, code, finding cards each have own perf/render concerns.

### Security Engineer
- **Path traversal (HIGH):** canonicalize resolved paths, assert under configured root.
- **Localhost bind scope (MED):** hard-code `127.0.0.1`, reject overrides broadening to `0.0.0.0`.
- **Markdown/YAML stored XSS (MED):** sanitize via `pulldown-cmark` + `ammonia`; treat frontmatter values as untrusted.
- **DoS via unbounded reads + watcher fanout (MED):** cap file read size, paginate JSONL tail, debounce notify events.
- **DNS rebinding / CSRF on localhost (LOW-MED):** `Host` header allowlist middleware.

### Backend Architect
- Watcher fanout: 100-250ms debounce; spec watched globs vs polled; dedicated `.monitor.jsonl` tail watcher (byte-offset cursor) vs structural watcher.
- Parser cache keyed `(path, mtime, len)` or content hash. Cold-scan budget <500ms for 100 specs. Lazy-per-route vs eager-on-boot to be decided.
- SSE: one connection per client with topic filtering; event schema `{type, project, feature, path, seq}`; monotonic seq + Last-Event-ID resume; capped queue depth.
- JSONL tailing: per-file inode tracking; emit parsed events not raw lines; skip malformed lines, never crash stream.
- Read-only contract explicit; path traversal validation; bind 127.0.0.1.

### UX Architect
- Lock signal/resource boundary for SSE updates (`Suspense` + `Resource` vs CSR island) before panes proliferate.
- CSS lock-in (Tailwind via cargo-leptos chosen); design tokens day one.
- Multi-pane resizable layout primitive: persisted sizes, min/max, collapse — spec shell first.
- Dark-mode-default; CSS-variable theme tokens; dense table rules (monospace lanes for IDs/paths).
- Mermaid + syntax highlighting boundary: client-side chosen (mermaid.js + shiki in WASM islands).
