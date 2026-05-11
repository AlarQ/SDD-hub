---
id: "002"
name: "workflow-web crate scaffold + clap CLI + startup validation"
status: blocked
blocked_by: ["001"]
max_files: 14
estimated_files:
  - workflow-web/Cargo.toml
  - workflow-web/src/main.rs
  - workflow-web/src/config.rs
  - workflow-web/src/app_state.rs
  - workflow-web/src/error.rs
  - workflow-web/src/tracing_setup.rs
  - workflow-web/src/tracing_redact.rs
  - workflow-web/tests/cli.rs
  - workflow-web/tests/startup_invariants.rs
  - workflow-web/tests/fixtures/empty/.gitkeep
  - workflow-web/tests/fixtures/with_projects/projects/foo/specs/bar/spec.md
  - Cargo.toml
test_cases:
  - "workflow-web --help shows root, --bind, --port, --allowed-host (repeatable), --log"
  - "non-existent root path exits with code 7"
  - "root missing projects/ subdir exits with code 4"
  - "non-loopback --bind 0.0.0.0 exits with code 4"
  - "empty --allowed-host list exits with code 4"
  - "malformed CLI args exit with code 2"
  - "symlinked root directory exits with code 2"
  - "valid invocation binds 127.0.0.1:8787 and returns 404 on /"
  - "SIGINT triggers clean shutdown"
  - "tracing redaction layer scrubs sk-…, ghp_…, JWT, AWS keys in test log records"
  - "no env var matching *_TOKEN|*_KEY|*_SECRET|*_PASSWORD is read at startup (grep gate)"
  - "AppState struct exposes Arc<Cache>, Arc<BroadcastHub>, Arc<Config> with stub cache/hub"
ground_rules:
  - general:security/general.md
  - general:architecture/general.md
  - general:architecture/api-design.md
  - general:languages/rust/api-layer.md
  - general:languages/rust/error-handling.md
  - general:languages/rust/_index.md
  - general:testing/principles.md
  - project:languages/rust.md
---

## Description

Add `workflow-web` crate. Implement clap-derive CLI + `Config::validate_invariants()` + `AppState` skeleton + tracing-subscriber with redaction layer + `main.rs` that validates, binds, serves an empty router, and shuts down cleanly. Exit codes per ADR-010.

## Acceptance Criteria

- Pinned `=x.y.z` versions for `ammonia`, `pulldown-cmark`, `axum`, `tower-http`, `notify`, `serde_yml` (SEC-FR-25). Rest from workspace.
- CLI surface per FR-22.
- Startup invariants per FR-23 + SEC-FR-1, SEC-FR-22.
- AppState defined with stub cache + hub (filled in tasks 3 + 5).
- Redaction layer scrubs canonical secret patterns (SEC-FR-19).
- Integration test asserts each exit code on a tmpdir fixture.

## Implementation Notes

- Use `tracing-subscriber::fmt` with custom `Layer` for redaction (regex pre-format).
- Exit-code helper centralizes 0/2/4/7 mapping; no `unwrap()` in startup path — use `expect` with descriptive message before bind, `?` thereafter (`general:languages/rust/error-handling.md`).
- No HTTP routes yet — empty `axum::Router` returning 404. Tower middleware deferred to task 4.
- `Config` is `Arc`-shared and immutable post-validation.
