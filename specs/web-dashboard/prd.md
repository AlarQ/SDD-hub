# PRD — web-dashboard (Phase 1)

## Summary

A local, read-only web dashboard that mirrors the existing `workflow-tui` (Rust ratatui) views in a browser. Built as an all-Rust WASM SPA using **Dioxus fullstack**. Solves the TUI's scalability pain (no text wrapping, growing data density causes visual fatigue) by giving a richer, properly laid-out browser UI for a single solo user on localhost.

Phase 1 is strictly read-only parity + live reload. Phase 2 (separate spec, later) will add interactive `/review-findings` with file-drop decision handoff and status feedback from Claude Code.

## User Perspective

- **User**: Ernest, sole operator. No multi-user, no remote, no shared access.
- **Problem**: TUI text non-wrapping + growing data density = fatigue. Terminal doesn't scale as workflow artifacts grow.
- **Shortest path**: read-only parity with TUI in the browser, shipped alongside the existing TUI (TUI remains untouched). Defer all interactivity to Phase 2.

## Scope

### In
- New Cargo workspace with three crates:
  - `workflow-core/` — shared headless domain (models, parsers, watcher), extracted from existing `workflow-tui/src/{model,parse,watcher.rs}`
  - `workflow-tui/` — existing TUI, refactored to depend on `workflow-core`
  - `workflow-web/` — new Dioxus fullstack binary
- Web dashboard provides parity with all five TUI views:
  1. Spec list with status
  2. Task list per spec with state badges (`blocked`/`todo`/`in-progress`/`implemented`/`review`/`done`)
  3. Validation reports viewer (markdown)
  4. Dependency graph
  5. Live reload on filesystem changes
- All-Rust stack end-to-end. Dioxus web target now; desktop target reachable in the future without rewrite.

### Out (Phase 1)
- Any mutations / interactivity (approve, reject, comment, form submit)
- File-drop decision handoff to Claude Code
- Status feedback loop (pending/picked-up/applied/errored)
- Auth, multi-user, remote access
- TUI replacement — TUI stays, both tools coexist
- Serving paths outside `specs/`
- `/learn-from-reports` rule-candidate review UI
- `/pr-review` UI

## Framework & Tooling

- **Framework**: Dioxus fullstack (SSR + hydration, server functions, WASM client). Axum under the hood.
- **Build tool**: `dx` CLI.
- **Router**: `dioxus-router` with URL-per-spec routing (`/spec/:name`, `/spec/:name/task/:id`, `/spec/:name/graph`).
- **Styling**: Tailwind v4 (CSS-first config, no PostCSS pipeline) + thin `design-tokens.css` defining CSS custom properties for colors/spacing/radius. No component library.
- **Dep graph**: Mermaid.js, loaded via Dioxus `eval` / `use_eval` JS interop. Server emits Mermaid text; client renders to SVG.

## Security

All items below are mandatory for Phase 1 middleware wiring and path handling.

1. **Path traversal / info disclosure** — All file reads go through a canonicalize + allowlist gate:
   - Single allowlisted root: `<project>/specs/` (no `knowledge-base/` or other paths)
   - Canonicalize requested path (resolve `..`, resolve symlinks), reject if resolved path does not start with allowlist root
   - Reject `..` segments, absolute paths, and URL-encoded equivalents at input validation layer before open
   - Extension whitelist: `.md`, `.yaml`, `.yml`, `.jsonl`
2. **Loopback bind** — Hardcoded `127.0.0.1`. No `--bind` flag (no way to override).
3. **Port** — Fixed default `8787`, `--port N` CLI override.
4. **No static serving from repo root** — Dioxus asset serving is for in-binary embedded WASM/CSS bundle only, not disk. All spec content flows through typed server functions.
5. **Host header allowlist + strict same-origin CORS** — Middleware from Phase 1 onward:
   - Accept only `Host: 127.0.0.1:8787` or `Host: localhost:8787`
   - CORS responds only to same-origin; no wildcard
   - Blocks DNS rebinding and cross-site POSTs ahead of Phase 2 mutations
   - CSRF tokens deferred to Phase 2 (no mutations in Phase 1)
6. **DoS guards on watcher / parser**:
   - Do not follow symlinks during `specs/` scan
   - File size caps: 1 MB for markdown / YAML; 10 MB for `.monitor.jsonl`; reject oversize with a `ParseDiagnostic`
   - Debounced watcher (`notify-debouncer-full`, 150 ms window)
   - Parser tolerates transient parse failures on half-written files (retry once after ~50 ms before surfacing diagnostic)

## Data Flow & Architecture

- **Push channel**: Server-Sent Events (SSE) — unidirectional, auto-reconnect, no WebSocket frame protocol. Phase 2 mutations will POST separately.
- **Initial hydration**: SSR embeds full spec snapshot into the page (no loading flash). Same serde types server and client via `workflow-core::dto`.
- **Incremental updates**: events are path-keyed deltas, not full snapshots:
  ```
  { kind: SpecChanged | TaskChanged | ReportAdded | MonitorAppended, spec_id, task_id?, path }
  ```
  Client re-reads affected entity via server fn. Keeps payloads small and avoids half-written file races.
- **Monotonic `revision: u64` per spec** — bumped on any change. Client detects missed events after SSE reconnect and triggers full resync.
- **`.monitor.jsonl` streaming** — snapshot holds only `{size, mtime}` metadata, never full contents. Tail-offset fetch via dedicated Axum range endpoint (server fns can't stream easily).
- **Snapshot cache** — `Arc<RwLock<Snapshot>>` populated by watcher, not rebuilt per request. Watcher event → re-parse affected file → swap in under write lock → broadcast delta.
- **Multi-tab awareness** — SSE subscriptions share one `tokio::sync::broadcast`; policy = drop-oldest with forced full resync on lag (never silently skip events).

## Type & API Boundaries

- **Split `workflow-core` into two layers**:
  - `domain` — internal, parser-facing types (free to refactor)
  - `dto` — serde-stable wire types, explicit `From<Domain>` conversions
- **`ParseDiagnostic` DTO** — bad specs surface as "spec X failed to parse at line N" instead of silently vanishing from the UI.
- **Enum tag strategy** frozen up front (`#[serde(tag = "kind")]`) — changing later breaks hydration.
- **RPC**: Dioxus server functions for all typed calls (`list_specs`, `get_spec`, `get_task`, `get_report`). Raw Axum routes only for SSE stream and monitor tail range fetch.

## UI / UX Requirements

### Layout
- **Three-pane desktop** layout: left rail (spec list, narrow) | center (task list for selected spec) | right (contextual detail — report, task body, metadata). Collapsible panes.
- **Dep graph** gets a full-width route (`/spec/:name/graph`), not the right pane — it needs space.
- **URL-per-spec routing** — browser back/forward, bookmarkable, reload-stable.

### State
- Two-level granular store:
  - `specs_index` — lightweight list (name + status only), always loaded
  - `spec_detail` — tasks, reports, body — loaded only when a spec is selected
- Per-spec and per-task signals keyed by stable ID; keyed iteration on lists so only changed rows re-render.

### Typography & density
- System UI sans-serif for chrome; monospace **only** for task IDs, file paths, code blocks in reports.
- Line-height ≥ 1.5 on prose, 1.3 on dense lists.
- Max 72ch on markdown/report views.
- Status badges: pill shape + color + icon + text (colorblind-safe, scannable).
- **Light / dark / system** toggle from day 1; default follows OS preference, manual override persisted in `localStorage`.

### Dep graph
- Mermaid.js via Dioxus `eval` / `use_eval` interop.
- Server generates Mermaid text (`graph TD\n  001[...] --> 002[...]`); client hands to Mermaid, which renders SVG.
- Accept full re-render on status change (graphs are small; acceptable trade for simplicity).

## Testing

- **Unit tests** (`workflow-core`):
  - Parsers (frontmatter, task, report, monitor)
  - Path-safety gate (canonicalize + allowlist, `..` rejection, symlink-escape rejection, extension whitelist)
  - File-size caps and parse-depth bounds
- **Integration tests** (`workflow-web`):
  - Server function round-trip (DTO stability)
  - SSE event shape and ordering
  - Host-header allowlist behavior
  - Same-origin CORS behavior
- **E2E**: out of scope for Phase 1 (solo user, manual browser smoke).

## Performance

- Debounced watcher (150 ms, `notify-debouncer-full`).
- Snapshot cached in `Arc<RwLock<_>>`, not rebuilt per request.
- `spec_detail` loaded lazily on selection.
- `.monitor.jsonl` served via tail-offset range fetch, never full re-read.
- Target: ≤ 200 ms initial hydration at 100 specs.

## Affected Modules

- New: `workflow-core/` crate (extracted domain + DTO + parse + watcher)
- New: `workflow-web/` crate (Dioxus fullstack app, Axum server, SSE broadcaster, Mermaid text generator)
- Modified: `workflow-tui/` — depends on `workflow-core` instead of inline modules
- Modified: `Cargo.toml` at repo root — becomes a workspace
- Modified: `CLAUDE.md` — document new binary and workspace layout
- Modified: `docs/workflow-diagram.md` — only if the web dashboard changes any flow (Phase 1 is read-only observation, likely no diagram change; audit during `/propose`)
- Not modified: `setup.sh` (web binary is per-project, run via `dx serve` or compiled binary; not installed globally like commands)

## Applicable Ground Rules

- `general:security/general.md` — input validation, path traversal, secrets, least privilege
- `general:architecture/general.md` — composition, modularity, single responsibility, separation of concerns
- `general:testing/principles.md` — testability, pure functions, test isolation
- `general:style/general.md` — function/module size limits, naming conventions
- `project:languages/rust.md` — Elm-like architecture reference (TUI), anyhow error handling, approved deps

**New dependencies to vet during `/propose`**: `dioxus`, `dioxus-fullstack`, `dioxus-router`, `axum`, `tokio`, `tower`, `notify-debouncer-full`, `tailwindcss` (v4 via `dx` pipeline), plus whatever Mermaid loading strategy chooses (CDN vs bundled).

## Agent Insights (Explore Phase)

Advisory input captured during exploration. Decisions above supersede where they conflict.

### UX Researcher
- Validate that density / wrapping is the actual pain, not the interaction model. If the real need is "click a finding → see diff inline," read-only parity will not fix it.
- File-drop handoff in Phase 2 has latency risk — no visible feedback ("did Claude pick it up?") quietly erodes trust; plan pending / picked-up / applied / errored status surfacing.
- Concurrent TUI + web on the same spec both watch FS — need explicit lock or documented last-write-wins rule to avoid silent divergence.
- Shortest-path risk flagged: `/review-findings` is the hardest interactive flow to ship first; read-only parity first (this spec) separates "is the web shell useful?" from "is file-drop viable?". Addressed by splitting into Phase 1 (this spec) and Phase 2 (later).
- Missing-need flag: `/learn-from-reports` rule-candidate review and rejected-finding → rule promotion share ~80% UI with `/review-findings`. Worth revisiting during Phase 2 scoping.

### Security Engineer
- Tampering / path traversal — canonicalize, reject `..`, symlink escape, absolute paths; allowlist `specs/**` and known extensions. HTTP surface is broader than a local TTY.
- Spoofing via bind — bind explicitly to `127.0.0.1`; document that any local process on a shared machine can reach the port.
- Info disclosure via file serving — never serve `.git/`, `.env`, `node_modules/`, or arbitrary repo files.
- CSRF / DNS rebinding — Host-header allowlist + strict same-origin CORS baked in Phase 1 because Phase 2 adds mutations.
- DoS via watcher / parser — cap file size, debounce events, bound parser; symlink loops and huge frontmatter are real risks even without an attacker.

### Backend Architect
- SSE (not WebSocket) for the push channel; `notify-debouncer-full` 150–300 ms server-side debounce; broadcast channel policy = drop-oldest with forced full resync on lag (never silent skip).
- Hydrate with full snapshot via SSR; incremental updates are path-keyed deltas `{kind, spec_id, task_id?, path}`; monotonic `revision: u64` per spec detects missed events on SSE reconnect; `.monitor.jsonl` streams via tail offsets, not full re-send.
- Server functions for typed RPC; raw Axum only for SSE stream and monitor tail range fetch. Snapshot cached in `Arc<RwLock<_>>` populated by watcher, not per-request.
- Split `workflow-core` into `domain` and `dto`; add `ParseDiagnostic` DTO so bad specs render errors instead of vanishing; freeze enum tag strategy up front.
- Parser must tolerate transient parse failures on half-written files (retry once after ~50 ms); Phase 2 writes use tmpfile + rename.

### UX Architect
- Signal granularity — per-spec and per-task signals keyed by stable ID; `specs_index` vs `spec_detail` store split; keyed iteration so only changed rows re-render.
- Layout — three-pane desktop (spec rail | task list | contextual detail), collapsible; dep graph as a full-width route; URL-per-spec routing is the biggest UX win over TUI.
- Dep graph — prototype early (highest-risk view); decision taken: Mermaid.js via Dioxus JS interop (trade-off accepted: coarser re-renders, no new DSL since Mermaid already used in repo docs).
- Typography — system UI for chrome, monospace only for IDs / paths / code; line-height ≥ 1.5 prose, 1.3 lists; 72ch max on markdown; pill badges with color + icon + text; light / dark / system toggle day 1.
- Design system — Tailwind v4 + thin `design-tokens.css`; no component library for 5 views; Phase 2 form primitives via headless-only crate (`dioxus-primitives` or hand-rolled on Tailwind).
