---
id: "007"
name: "Leptos SSR shell + Splitter + spec list + task detail"
status: blocked
blocked_by: ["006"]
max_files: 20
estimated_files:
  - workflow-web/Cargo.toml
  - workflow-web/src/ui/mod.rs
  - workflow-web/src/ui/shell.rs
  - workflow-web/src/ui/top_bar.rs
  - workflow-web/src/ui/splitter.rs
  - workflow-web/src/ui/spec_list.rs
  - workflow-web/src/ui/task_detail.rs
  - workflow-web/src/ui/status_badge.rs
  - workflow-web/src/ui/routes.rs
  - workflow-web/style/tokens.css
  - workflow-web/style/main.css
  - workflow-web/style/splitter.css
  - workflow-web/style/dark.css
  - workflow-web/src/main.rs
  - workflow-web/tests/ssr_routes.rs
  - workflow-web/tests/ssr_frontmatter_escape.rs
  - workflow-web/tests/ssr_inner_html_grep.rs
  - workflow-web/tests/playwright/splitter.spec.ts
  - workflow-web/tests/playwright/spec_list.spec.ts
  - workflow-web/tests/playwright/task_detail.spec.ts
test_cases:
  - "GET / SSRs the project switcher and an empty pane state"
  - "GET /p/foo SSRs the spec list for project foo"
  - "GET /p/foo/bar SSRs the spec view + task list"
  - "GET /p/foo/bar/001 SSRs the task detail (frontmatter table + sanitized HTML body)"
  - "frontmatter scalar <img src=x onerror=alert(1)> renders as &lt;img not <img"
  - "task body renders from cached sanitized HTML (single inner_html sink)"
  - "grep gate: inner_html appears only in workflow-web/src/ui/task_detail.rs (or equivalent single sink)"
  - "status badge color/contrast meets WCAG AA on dark + light themes"
  - "Splitter drag updates pane fraction signal"
  - "Splitter ArrowLeft/Right keyboard resize updates fraction"
  - "Splitter persists fractions under localStorage[workflow-web.panes] with versioned schema"
  - "reload restores splitter fractions from localStorage"
  - "Splitter handle has role=separator, aria-valuemin/max/now attributes"
  - "Tailwind via cargo-leptos compiles tokens.css → final bundle"
  - "dark-mode default; [data-theme=light] override works"
ground_rules:
  - general:security/general.md
  - general:architecture/general.md
  - general:languages/rust/error-handling.md
  - general:testing/principles.md
  - project:languages/rust.md
---

## Description

Wire Leptos + leptos_axum SSR into workflow-web. Ship the smallest reviewable dashboard slice: shell, top bar with project switcher, custom CSS-grid Splitter (drag + keyboard a11y + `localStorage` persistence), spec list pane, task detail pane (frontmatter table + sanitized HTML body), status badges, dark-mode token system. Tailwind via `cargo-leptos`. No WASM islands yet. Implements FR-2..4, FR-8, FR-9, FR-18, SEC-FR-9, ADR-006, ADR-007 (SSR portion).

## Public API (UI)

- `<Shell>` — top-level route shell, owns active-project signal.
- `<Splitter direction=… persist_key=…>` — recursive layout primitive.
- `<SpecListPane>` — fetches `/api/specs?project=<p>` via SSR data.
- `<TaskDetail>` — frontmatter table (text-escaped) + body `inner_html` (only sink).

## Implementation Notes

- Splitter uses CSS Grid `grid-template-cols/rows: <frac>fr 4px <frac>fr`; pointer-down/move/up updates signal; 100ms debounced write to localStorage. Schema: `{ panes: {<key>: fraction}, version: 1 }`.
- Keyboard resize: divider focusable (`tabindex=0`); ArrowLeft/Right (or Up/Down for vertical) shift fraction by 0.05 step.
- `inner_html` appears in exactly one file (`task_detail.rs`). CI grep gate enforced in task 010, but this task structures code so the gate is passing by construction.
- Frontmatter values rendered via Leptos `view! { <td>{value}</td> }` (default text-escaping).
- Tokens in `style/tokens.css`: `--bg-base, --bg-elevated, --fg-default, --fg-muted, --accent, --warn, --error, --border, --code-bg`. Dark default; `[data-theme="light"]` overrides.
- Status aggregation: derive spec status from min/max task status (`blocked < todo < in-progress < implemented < review < done`).
