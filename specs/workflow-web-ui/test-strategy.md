---
feature: workflow-web-ui
tier: large
---

# Test Strategy — workflow-web-ui

## Overview

Large-tier feature with a clear data-flow spine: filesystem → workflow-core parse → cache+sanitizer → watchers → broadcast hub → SSE → SSR/islands. Test responsibilities allocated along that spine: each backend task owns unit + Rust integration tests for its module(s); each cross-module seam is owned by the **later** task on the spine (it has both sides in hand); Playwright e2e is concentrated in 008–010 with **010 owning real-browser security regression**. Aggressive de-duplication: host-header, path-traversal, CSP, and stored-XSS scenarios get exactly **one** Rust integration test (004 / 003 / 005) **plus** exactly one Playwright e2e test (010) — no third copy.

## Task Test Responsibilities

### 001 — workspace-and-core-extraction
- **Theme:** Move-only refactor preserves parser semantics and TUI behavior; workflow-core compiles standalone.
- **Owns:** workflow-core parser unit tests (moved from TUI); WatchSource/WatchEvent shape; TUI smoke run on existing fixture; `cargo check/test --workspace`; cargo aliases resolve.
- **Must not test:** sanitizer (003); notify-backed watcher behavior (005); web HTTP (002+).
- **Seam:** TUI ↔ workflow-core import boundary.
- **Produces:** `workflow-core/tests/fixtures/parsers/` (reused by 003, 005, 006).

### 002 — web-crate-scaffold-cli-startup
- **Theme:** CLI surface + startup invariants fail closed with correct exit codes before any socket binds.
- **Owns:** CLI parse; exit codes 0/2/4/7 on tmpdir fixtures; symlinked root → exit 2; tracing redaction (sk-…, ghp-…, JWT, AWS); SEC-FR-23 secret-env grep; AppState skeleton; clean SIGINT.
- **Must not test:** HTTP handler logic (004); host-header at request time (004); cache fill (003).
- **Seam:** CLI ↔ AppState.
- **Produces:** `tests/fixtures/empty/`; `tests/fixtures/with_projects/projects/foo/specs/bar/spec.md`; symlinked-root helper.

### 003 — cache-sanitizer-scanner
- **Theme:** Sanitizer is the single XSS trust boundary; cache keying tolerates mtime granularity; cold scan populates without HTTP.
- **Owns:** **canonical XSS Rust unit suite** (`<script>`, `on*`, `javascript:`, `data:`, `vscode:`, SEC-FR-8 allowlist); cache hit/miss/invalidate/sweep on `(mtime, len)`; len-tiebreak under mtime collision; scanner cold-scan; cold-scan perf advisory <500ms; >2 MiB → `CoreError::TooLarge { limit:2097152 }`; mermaid block >16 KiB rejected.
- **Must not test:** HTTP envelope around TooLarge (004); frontmatter HTML escaping (007); Mermaid iframe (008/010); re-testing sanitizer through HTTP.
- **Seams:** Sanitizer ↔ Cache (stores sanitized HTML); Scanner ↔ Cache.
- **Produces:** `tests/fixtures/xss/{script,onerror,data_uri,vscode_link,javascript_url}.md`; `tests/fixtures/large/huge.md`; `tests/fixtures/large/oversized_mermaid.md`; 100-spec generated tree.

### 004 — path-guard-and-readonly-api
- **Theme:** Every API handler is gated by path-guard + host-guard + envelope + CSP; no write methods exist; error opacity preserved.
- **Owns:** path-guard Rust integration (../, %2e%2e%2f, NUL, segment regex, ext allowlist); **canonical symlink-escape Rust test**; **canonical Rust host-header test**; CSP + nosniff/XFO/Referrer/Permissions on every response; envelope shape; internal Debug/Display never leaks; 413 too_large body; editor URI shape `^vscode://file/[^?#]+(:\d+){0,2}$`; rate-limit 100/s burst 200 → 429; timeouts; body 16 KiB; decision log uses relative paths; IO error masked as 404 with full errno in log only.
- **Must not test:** SSE-specific behavior (006) beyond inheriting middleware; Mermaid iframe (008/010); stored-XSS through SSR (010 Playwright); sanitizer allowlist details (003).
- **Seams:** path-guard ↔ every handler; cache ↔ handlers; CoreError ↔ ApiErrorResponse.
- **Produces:** `tests/fixtures/symlinks/escape_root/` helper (reused by 010).

### 005 — watchers-and-broadcast-hub
- **Theme:** Watchers debounce + handle editor atomic-rename; hub assigns monotonic seq; replay buffer and lag semantics correct.
- **Owns:** structural watcher 100–250ms debounce; excludes `.monitor.jsonl`; per-path rate cap 20/s; structural event triggers cache.invalidate; tail watcher emits parsed `MonitorAppend`; **canonical vim atomic-rename inode-swap test**; size-decrease → offset 0; JSONL line >64 KiB skipped with `parse_skip`; hub monotonic per-project seq; ring buffer ≥256; replay_since within/outside window → Replay/Reset; channel cap 256 → Lagged → `Event::Lag`; boot_id fresh per process.
- **Must not test:** SSE handler (006); ActivityFeed lag-refresh UX (008); end-to-end 500ms SLA (006/010).
- **Seams:** structural watcher ↔ cache; watcher ↔ hub publish path.
- **Produces:** `tests/fixtures/watcher/vim_atomic/` + `simulate_vim_save(path)` helper; `tests/fixtures/watcher/jsonl_oversized_line.jsonl`; deterministic notify driver harness.

### 006 — sse-endpoint-with-resume
- **Theme:** SSE endpoint translates BroadcastHub to wire correctly: id, event, resume, reset, lag, client cap.
- **Owns:** wire format `id:<seq> event:<type>`; **canonical end-to-end watcher→SSE 500ms timing**; Last-Event-ID replay; outside-window → reset; boot_id mismatch → reset; 1000-events-paused → Lag first; monitor.jsonl → MonitorAppend within 200ms; 33rd client → 503 + `Retry-After: 1`.
- **Must not test:** host/CSP middleware logic (004) — only a single smoke that the route is wrapped; ActivityFeed UX (008); watcher internals (005).
- **Seam owner:** watcher → hub → SSE end-to-end (has both sides).
- **Consumes:** 002 with_projects/, 005 watcher harness, 003 cache.

### 007 — leptos-ssr-shell-spec-and-task-views
- **Theme:** SSR produces correct HTML for shell, splitter, spec list, task detail; frontmatter is text-escaped; `inner_html` appears exactly once.
- **Owns:** SSR route tests for `/`, `/p/foo`, `/p/foo/bar`, `/p/foo/bar/001`; **canonical frontmatter scalar escape test** (`<img onerror>` → `&lt;img`); task body checksum-equality with cache.html; test-time grep `inner_html` only in `task_detail.rs`; status badge WCAG-AA; **Playwright splitter drag + ArrowLeft/Right keyboard + localStorage persistence + reload restore**; splitter aria attrs; Tailwind/cargo-leptos build; dark-mode default + `[data-theme=light]` override.
- **Must not test:** Mermaid/shiki/SSE islands (008); dep-graph/report cards/editor button (009); markdown-body stored XSS (003 unit + 010 e2e); CSP headers (004/010).
- **Seams:** cache.html ↔ TaskDetail.inner_html single sink; `/api/task` ↔ SSR rendering.
- **Produces:** Playwright bootstrap (config + webServer helper) — reused by 008/009/010; `tests/fixtures/frontmatter_xss/spec.md`.

### 008 — wasm-islands-mermaid-shiki-activity-feed
- **Theme:** Islands hydrate, lazy-load, and consume SSE; Mermaid sandbox iframe correct; ActivityFeed handles lag/reset.
- **Owns (Playwright):** **canonical Mermaid sandbox attribute test** (`<iframe sandbox="allow-scripts">` no `allow-same-origin`); `securityLevel:'strict'` init payload; iframe theme inheritance via CSS-var query string; shiki token classes on hydrate; **bundle-network assertion** (no fetch after hydration for mermaid/shiki); ActivityFeed live; on `lag` → full refresh; SSR-seq mismatch → refresh; no console errors; SSR fallback content visible without JS.
- **Must not test:** server-side mermaid source generation (009); sanitizer (003); SSE wire format (006); CSP/host-header (010 e2e CSP).
- **Seams:** SSE → ActivityFeed island; cache-seq ↔ island hydration check.
- **Produces:** `assets/mermaid-loader.js` + `assets/shiki-bundle.js` (referenced by 009).

### 009 — dep-graph-report-cards-editor-button
- **Theme:** Dep-graph mermaid source well-formed; finding cards render every card-model field; editor button uses server-constructed URI.
- **Owns:** Rust snapshot of dep_graph `graph TD` source from `blocked_by`; finding card field surface; confidence shown only when `source=llm`; Playwright dep-graph rendered in Mermaid island (light smoke, no duplicate sandbox audit); snippet collapse/expand >20 lines; severity ribbon contrast; editor button → `/api/open-in-editor` → `vscode://file/<abs>:<line>`; href shape; rejects non-positive-integer line.
- **Must not test:** Mermaid sandbox attrs (008); `/api/open-in-editor` server response shape (004); sanitizer stripping author `vscode:` links (003).
- **Seam:** task list → mermaid source generation → island rendering.
- **Produces:** `tests/fixtures/reports/{finding_full,finding_llm,finding_oversize_snippet}.yml`; `tests/fixtures/tasks_with_blocked_by/`.

### 010 — e2e-hardening-and-ci-gates
- **Theme:** Real-browser end-to-end proves security invariants hold in production wire conditions; CI gates make regressions impossible.
- **Owns:** Playwright smoke happy-path; **e2e CSP regression** (the e2e half of SEC-FR-12; Rust half in 004); **e2e path-traversal regression**; **e2e host-header regression**; **e2e size-caps** (5 MiB → 413; JSONL truncation); **e2e stored-XSS regression** (`<script>` renders as text in real browser); **e2e SSE live SLA <1s**; CI: cargo audit + deny + fmt + clippy `-D warnings` + test --workspace; CI grep gates `grep-inner-html.sh`, `grep-write-methods.sh`, `grep-secret-env.sh`; SEC-FR-25 pinned-version assertion.
- **Must not test:** anything already owned at the Rust level — only one real-browser regression per invariant.
- **Seam owner:** binary boot ↔ Playwright webServer ↔ real-browser HTTP.
- **Produces:** `tests/playwright/fixture-tree/projects/foo/specs/bar/` (canonical e2e tree with malicious `<script>` sample).

### 011 — retire-workflow-tui
- **Theme:** Deletion is clean: workspace builds, workflow-core remains UI-agnostic, docs updated.
- **Owns:** `cargo check/test --workspace` post-removal; workflow-core builds standalone; no references to workflow-tui in CLAUDE.md/README; git history preserved.
- **Seam:** workflow-core ↔ workflow-web after TUI removal.

## Spec Coverage Map (BDD scenario → owning task)

| Scenario | Owner | Type |
|---|---|---|
| Boot scans master-brain root | 007 | integration |
| Project switcher routes | 007 | integration |
| Task detail shows frontmatter + body | 007 | integration |
| Pane sizes persist across reload | 007 | e2e |
| Keyboard resize of pane | 007 | e2e |
| Spec file save triggers SSE event | 006 | integration |
| Last-Event-ID resume within ring window | 006 | integration |
| Last-Event-ID resume outside ring window | 006 | integration |
| Slow client receives lag notice | 006 | integration |
| monitor.jsonl append streams parsed events | 006 | integration |
| Markdown renders sanitized HTML | 003 | unit |
| Mermaid block renders in sandboxed island | 008 | e2e |
| Code highlighting hydrates on island | 008 | e2e |
| Open-in-editor URI is server-constructed | 004 | integration |
| Reject parent-directory traversal | 004 | integration |
| Reject URL-encoded traversal | 004 | integration |
| Reject NUL byte injection | 004 | integration |
| Reject symlink escaping root | 004 | integration |
| Reject foreign Host header | 004 | integration |
| Accept localhost host | 004 | integration |
| Script tags in markdown are stripped | 003 | unit |
| Author-supplied vscode: links are stripped | 003 | unit |
| Frontmatter scalar is HTML-escaped | 007 | integration |
| Oversized markdown returns 413 | 004 | integration |
| JSONL tail capped at 1 MiB | 004 | integration |
| Oversized JSONL line is skipped | 005 | integration |
| SSE client cap enforced | 006 | integration |
| Reject non-loopback bind | 002 | integration |
| No write methods registered | 010 | integration |
| Internal IO error is masked | 004 | integration |

## Integration Seams

| Seam | Owner | Rationale |
|---|---|---|
| TUI ↔ workflow-core import boundary | 001 | Only task in which TUI consumes the extracted core. |
| CLI ↔ AppState | 002 | Both built here. |
| Sanitizer ↔ Cache | 003 | Single task implements both. |
| Scanner ↔ Cache | 003 | Same task. |
| Path-guard ↔ every API handler | 004 | Both built here; parameterized test. |
| Cache ↔ API handlers | 004 | First task that wires handlers. |
| CoreError ↔ ApiErrorResponse | 004 | From impl lives here. |
| Structural watcher ↔ Cache | 005 | Both sides. |
| Watcher ↔ Hub publish | 005 | Both sides. |
| Watcher → Hub → SSE end-to-end | 006 | Latest task on spine — full chain exercisable. |
| Cache.html ↔ TaskDetail.inner_html (single sink) | 007 | Sink introduced here; checksum + grep. |
| `/api/task` ↔ SSR rendering | 007 | First consumer. |
| SSE → ActivityFeed island | 008 | Island lives here; 006 proves server. |
| Cache-seq ↔ island hydration check | 008 | Behavioral contract is client-side. |
| Task list → dep-graph source → Mermaid island | 009 | Generator built here, island reused. |
| Binary boot ↔ Playwright webServer | 010 | Only real-browser surface. |
| workflow-core ↔ workflow-web post-TUI-removal | 011 | Only task that touches removal. |

## Risk Flags

| Risk | Severity | Mitigation |
|---|---|---|
| Duplication: host-header + path-traversal + CSP could be triple-tested (Rust unit + integration + Playwright). | medium | Two-layer cap: 004 Rust integration + 010 Playwright. No third layer. Reviewer rejects duplicates. |
| Duplication: stored-XSS at sanitizer + SSR + Playwright. | medium | 003 owns sanitizer unit. 007 owns ONLY frontmatter-scalar escape (distinct code path). 010 owns ONE real-browser regression. 007 must NOT add markdown-body XSS tests. |
| Tail-watcher inode-swap fragile on CI (macOS vs Linux, tmpfs in containers). | high | 005 uses deterministic helper (write temp + rename), not real editors. Linux + macOS CI matrix. `#[cfg(unix)]`. |
| SSE timing assertions (500ms/200ms) flaky on loaded CI. | high | Generous ceilings (2s hard; 500ms soft-logged). `tokio::time::pause` where feasible. Playwright 010 SLA uses 1s ceiling. |
| Mermaid sandbox attributes only verifiable in real browser. | medium | Exclusive Playwright ownership in 008 + 010. No Rust-side iframe markup check. |
| Cache mtime granularity 1s on tmpfs. | medium | 003 len-tiebreak test fixes mtime explicitly + changes len. Don't rely on natural mtime changes within same second. |
| 100-spec cold-scan perf target hard to maintain on shared CI. | low | 003 marks perf assertion non-blocking (warn-only). Bench only, nightly. |
| Playwright + cargo-leptos boot brittle; risk of multiple boot scripts across 008/009/010. | medium | 007 produces canonical bootstrap. 008/009/010 reuse helper. Reviewer rejects duplicate webServer config. |
| Frontmatter-XSS fixture in 007 vs body-XSS fixture in 003 — drift risk. | low | Cross-reference in fixture README; keep both distinct on purpose. |
| Post-TUI-removal, no regression coverage on the TUI surface beyond `cargo check`. | low | 011 explicit: workflow-core builds standalone + tests pass. TUI retired — accepted. |
| Read-only contract (SEC-FR-24) only at CI time — local dev could regress. | low | 010 wires grep gate into `scripts/pre-commit-hook.sh`. |

## Shared Fixtures

| Fixture | Producer | Consumers |
|---|---|---|
| `workflow-core/tests/fixtures/parsers/` | 001 | 003, 005, 006 |
| `tests/fixtures/empty/` | 002 | 002 |
| `tests/fixtures/with_projects/projects/foo/specs/bar/spec.md` | 002 | 003, 004, 005, 006, 007, 008, 009 |
| Symlinked-root tmpdir helper | 002 | 004 |
| `tests/fixtures/xss/{script,onerror,data_uri,vscode_link,javascript_url}.md` | 003 | 007 (sibling frontmatter_xss/), 010 |
| `tests/fixtures/large/huge.md` (5 MiB) | 003 | 004, 010 |
| `tests/fixtures/large/oversized_mermaid.md` | 003 | 010 |
| 100-spec generated tree | 003 | 005 (storm test if used) |
| Watcher harness + deterministic notify driver | 005 | 006 |
| `simulate_vim_save(path)` helper + vim_atomic fixture | 005 | 010 (if e2e watcher flake) |
| `tests/fixtures/watcher/jsonl_oversized_line.jsonl` | 005 | 010 |
| Symlink-escape helper | 004 | 010 |
| Playwright bootstrap (config + webServer helper) | 007 | 008, 009, 010 |
| `tests/fixtures/frontmatter_xss/spec.md` | 007 | 007 |
| `assets/mermaid-loader.js` + `shiki-bundle.js` | 008 | 009 |
| `tests/fixtures/reports/{finding_full,finding_llm,finding_oversize_snippet}.yml` | 009 | 009 |
| `tests/fixtures/tasks_with_blocked_by/` | 009 | 009 |
| `tests/playwright/fixture-tree/projects/foo/specs/bar/` | 010 | 010 |

**Allocation principle:** every fixture produced by the earliest task that needs it; downstream tasks add files under the same root. Two intentional exceptions: 002's `with_projects/` (minimal — for fast tmpdir cloning) vs 010's Playwright `fixture-tree/` (rich — needs reports, monitor events, XSS sample).
