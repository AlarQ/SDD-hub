---
id: "008"
name: "WASM islands: Mermaid + shiki + ActivityFeed"
status: blocked
blocked_by: ["007"]
max_files: 14
estimated_files:
  - workflow-web/Cargo.toml
  - workflow-web/src/islands/mod.rs
  - workflow-web/src/islands/mermaid.rs
  - workflow-web/src/islands/highlight.rs
  - workflow-web/src/islands/activity_feed.rs
  - workflow-web/src/islands/sse_client.rs
  - workflow-web/src/islands/hydration_check.rs
  - workflow-web/assets/mermaid-loader.js
  - workflow-web/assets/shiki-bundle.js
  - workflow-web/style/iframe.css
  - workflow-web/tests/playwright/mermaid_sandbox.spec.ts
  - workflow-web/tests/playwright/shiki_hydrate.spec.ts
  - workflow-web/tests/playwright/activity_feed_live.spec.ts
  - workflow-web/tests/playwright/bundle_network.spec.ts
test_cases:
  - "Mermaid block renders inside <iframe sandbox=\"allow-scripts\"> with no allow-same-origin"
  - "Mermaid iframe sets securityLevel: 'strict' via initialization payload"
  - "Mermaid iframe inherits theme via CSS-var query string"
  - "shiki applies token classes to fenced code blocks on hydrate"
  - "shiki grammars + themes are bundled — no network fetch after page load (Playwright network assert)"
  - "ActivityFeed connects to /events?project=<p> and renders incoming events live"
  - "ActivityFeed on receiving {type:lag} triggers full client refresh"
  - "ActivityFeed compares SSR-embedded seq vs hydrate seq; mismatch triggers refresh"
  - "mermaid and shiki bundles are lazy-loaded (dynamic import) — not in initial JS payload"
  - "client islands degrade gracefully without JS (SSR fallback content visible)"
  - "no console errors during hydration of any island"
ground_rules:
  - general:security/general.md
  - general:architecture/general.md
  - general:testing/principles.md
  - project:languages/rust.md
---

## Description

Add three WASM islands hydrated client-side: Mermaid (sandboxed iframe), shiki (bundled grammars/themes), ActivityFeed (SSE consumer with hydration-check + lag-refresh). Lazy-load mermaid + shiki bundles. Implements FR-7, FR-16, FR-17, SEC-FR-11, ADR-007 (island portion).

## Implementation Notes

- Mermaid: render via `<iframe srcdoc=... sandbox="allow-scripts">` (no `allow-same-origin`); pass source + theme CSS vars; mermaid.js loaded inside iframe with `securityLevel: 'strict'`, `maxTextSize`, `maxEdges` set.
- Shiki: build-time bundle of grammars (rust, typescript, bash, yaml, markdown) + 2 themes (light/dark) into a single chunk loaded on first highlight call.
- ActivityFeed: opens SSE at island mount; receives `{structural, monitor_append, lag, reset}`; renders rolling buffer of last 100 events. On `lag` or `reset` → `window.location.reload()`.
- Hydration check: SSR shell embeds `<meta name="cache-seq" content="N">`; islands read on mount; mismatch → refresh.
- `cargo-leptos` island config produces three separate WASM chunks.
