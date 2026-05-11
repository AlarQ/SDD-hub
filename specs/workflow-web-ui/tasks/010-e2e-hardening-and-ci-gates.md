---
id: "010"
name: "E2E hardening: Playwright smoke + CI security gates"
status: blocked
blocked_by: ["009"]
max_files: 14
estimated_files:
  - workflow-web/tests/playwright/smoke.spec.ts
  - workflow-web/tests/playwright/security_csp.spec.ts
  - workflow-web/tests/playwright/security_traversal.spec.ts
  - workflow-web/tests/playwright/security_host_header.spec.ts
  - workflow-web/tests/playwright/security_size_caps.spec.ts
  - workflow-web/tests/playwright/fixture-tree/projects/foo/specs/bar/spec.md
  - workflow-web/tests/playwright/playwright.config.ts
  - .github/workflows/workflow-web-ci.yml
  - deny.toml
  - scripts/gates/grep-inner-html.sh
  - scripts/gates/grep-write-methods.sh
  - scripts/gates/grep-secret-env.sh
  - workflow-web/Cargo.toml
  - Cargo.toml
test_cases:
  - "Playwright smoke: boot binary → open / → switch project → open task → drag splitter → resize via keyboard"
  - "Playwright Mermaid sandbox assertion: iframe sandbox attr present, no allow-same-origin"
  - "Playwright bundle assertion: no fetch after initial hydration for mermaid/shiki grammars"
  - "Playwright SSE live: touch spec.md, assert task pane updates within 1s"
  - "CI runs cargo audit → green"
  - "CI runs cargo deny check → green; deny.toml denies advisories + duplicates"
  - "CI grep gate scripts/gates/grep-inner-html.sh exits non-zero on inner_html outside the single sink"
  - "CI grep gate scripts/gates/grep-write-methods.sh exits non-zero on any POST/PUT/PATCH/DELETE route in workflow-web/src/"
  - "CI grep gate scripts/gates/grep-secret-env.sh exits non-zero on any std::env::var matching *_TOKEN|*_KEY|*_SECRET|*_PASSWORD"
  - "CI runs cargo fmt --check, cargo clippy -- -D warnings, cargo test --workspace"
  - "all SEC-FR-25 pinned crates (ammonia, pulldown-cmark, axum, tower-http, notify, serde_yml) have =x.y.z versions"
  - "CSP header verified by Playwright on every Leptos route"
  - "path traversal returns 400 in real-browser flow (Playwright)"
  - "Host header attack flow blocked end-to-end (Playwright)"
ground_rules:
  - general:security/general.md
  - general:architecture/general.md
  - general:testing/principles.md
  - project:languages/rust.md
---

## Description

Final hardening pass. Playwright e2e covers happy path + key security invariants in a real browser. CI workflow runs cargo audit, cargo deny, three grep gates (inner_html / write methods / secret env vars), fmt/clippy/test on every push. Verifies pinned versions. Implements SEC-FR-9, SEC-FR-23, SEC-FR-24, SEC-FR-25, FR-21 (target).

## Implementation Notes

- Playwright fixture tree pre-built under `tests/playwright/fixture-tree/` with one project + one spec + tasks + a malicious sample (`<script>` in markdown) to assert sanitization end-to-end.
- `playwright.config.ts` boots `workflow-web` against the fixture tree via `webServer:` config.
- Grep gate scripts are small POSIX shell with `set -euo pipefail`; ride existing `scripts/` conventions.
- `deny.toml` denies CVE advisories, unmaintained crates, and duplicate semver-major versions.
- CI runs in parallel where possible (rust gates vs playwright).
