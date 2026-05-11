---
id: "004"
name: "Path guard + read-only API routes + security middleware"
status: blocked
blocked_by: ["003"]
max_files: 20
estimated_files:
  - workflow-web/src/api/mod.rs
  - workflow-web/src/api/error.rs
  - workflow-web/src/api/envelope.rs
  - workflow-web/src/api/path_guard.rs
  - workflow-web/src/api/projects.rs
  - workflow-web/src/api/specs.rs
  - workflow-web/src/api/tasks.rs
  - workflow-web/src/api/reports.rs
  - workflow-web/src/api/monitor.rs
  - workflow-web/src/api/editor.rs
  - workflow-web/src/middleware/host_guard.rs
  - workflow-web/src/middleware/security_headers.rs
  - workflow-web/src/middleware/rate_limit.rs
  - workflow-web/src/middleware/decision_log.rs
  - workflow-web/src/main.rs
  - workflow-web/tests/api_path_traversal.rs
  - workflow-web/tests/api_host_header.rs
  - workflow-web/tests/api_csp_headers.rs
  - workflow-web/tests/api_envelope.rs
  - workflow-web/tests/api_editor_uri.rs
test_cases:
  - "GET /api/spec/foo/bar/../../etc/passwd returns 400 invalid_path; decision=blocked_traversal logged"
  - "URL-encoded traversal %2e%2e%2f returns 400; decision=blocked_traversal"
  - "NUL byte injection in segment returns 400"
  - "symlinked file inside root with target outside root returns 400; decision=blocked_symlink"
  - "extension outside {.md,.yml,.yaml,.jsonl} returns 404 not_found"
  - "Host: attacker.example returns 400; decision=blocked_host"
  - "Host: localhost:<port> returns 200"
  - "CSP header matches SEC-FR-12 exactly on every response"
  - "X-Content-Type-Options, X-Frame-Options, Referrer-Policy, Permissions-Policy headers present"
  - "ApiErrorResponse envelope {error:{code,message}} for every 4xx/5xx"
  - "internal Debug/Display never appears in response body (only in server log)"
  - "oversized file returns 413 too_large with limit:2097152"
  - "GET /api/open-in-editor returns href matching ^vscode://file/[^?#]+:\\d+$"
  - "open-in-editor href rejects query string or fragment in input"
  - "POST/PUT/PATCH/DELETE not registered: rg -n '\\.route\\(.*(post|put|patch|delete)' workflow-web/src/ returns no matches"
  - "rate limit 100/s burst 200 triggers 429 on overrun"
  - "header read timeout 5s; total non-SSE timeout 30s"
  - "body limit 16 KiB enforced"
  - "decision_log uses paths relative to root; no absolute paths in log records"
  - "every API response carries the {data, meta:{seq, boot_id}} envelope"
ground_rules:
  - general:security/general.md
  - general:architecture/general.md
  - general:architecture/api-design.md
  - general:languages/rust/api-layer.md
  - general:languages/rust/error-handling.md
  - general:testing/principles.md
  - project:languages/rust.md
---

## Description

Build the read-only JSON API surface. Path guard runs before any handler; segment allowlist + canonicalize + ancestor check + symlink reject + extension allowlist. Host-header guard, security headers (CSP), rate limit, timeouts, body limit, decision logging applied as tower-http middleware. Error envelope strictly enforced. Implements SEC-FR-2..7, 10, 12, 13, 17, 18, 20, 21, 24, plus FR-1..5, FR-19.

## Public API

Routes per design.md §Backend Design. All return `{data, meta}` or `{error}` envelope. Path params extracted with axum `Path`; first action of every handler is `path_guard::resolve(...)`.

## Implementation Notes

- Path guard: segment regex `^[A-Za-z0-9._-]{1,128}$`, reject `.`/`..`/NUL; `tokio::fs::canonicalize` + `starts_with(canonical_root)`; `symlink_metadata` on every ancestor — any symlink → reject.
- Editor URI: server constructs `vscode://file/<canonical_abs_path>[:line[:col]]`. Strip any query/fragment from inputs before processing. Validate shape with regex before returning.
- `ApiErrorResponse` impls `IntoResponse`; maps `CoreError` via `From` (`general:languages/rust/api-layer.md`).
- Decision logging via dedicated tower layer that emits structured `tracing` events with `decision`, `path_rel`, `host`. Never log full `Debug`/`Display` of the request body.
- Rate limit via `tower-governor` keyed on connection peer; loopback-only so blast radius limited.
- CI grep gate added in task 010 enforces SEC-FR-24; this task already passes the gate by construction.
