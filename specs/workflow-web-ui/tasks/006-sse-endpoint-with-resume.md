---
id: "006"
name: "SSE endpoint with Last-Event-ID resume + concurrent-client cap"
status: blocked
blocked_by: ["005"]
max_files: 8
estimated_files:
  - workflow-web/src/api/events.rs
  - workflow-web/src/api/sse_limit.rs
  - workflow-web/src/api/mod.rs
  - workflow-web/src/main.rs
  - workflow-web/tests/sse_live_update.rs
  - workflow-web/tests/sse_resume.rs
  - workflow-web/tests/sse_lag.rs
  - workflow-web/tests/sse_client_cap.rs
test_cases:
  - "GET /events?project=foo emits SSE stream with id:<seq> and event:<type>"
  - "spec.md save delivers SSE event with type=structural within 500ms"
  - "Last-Event-ID within ring window replays events seq>N before live stream"
  - "Last-Event-ID outside ring window emits {type:reset, boot_id} then live"
  - "boot_id mismatch on resume emits reset"
  - "1000 events while client paused: on resume first event is {type:lag, dropped:N}"
  - ".monitor.jsonl append delivers MonitorAppend event with parsed payload within 200ms"
  - "33rd concurrent SSE client receives 503 with Retry-After: 1"
  - "SSE route enforces host-header + CSP middleware from task 004"
  - "raw JSONL bytes never appear in MonitorAppend payload"
ground_rules:
  - general:security/general.md
  - general:architecture/general.md
  - general:architecture/api-design.md
  - general:languages/rust/api-layer.md
  - general:languages/rust/concurrency.md
  - general:languages/rust/error-handling.md
  - general:testing/principles.md
  - project:languages/rust.md
---

## Description

Wire `GET /events?project=<p>` SSE endpoint to BroadcastHub. Handle `Last-Event-ID` (replay vs reset). Enforce concurrent-client cap 32 → 503 + `Retry-After: 1`. Implements FR-10..12, FR-14, SEC-FR-15.

## Implementation Notes

- Use `axum::response::sse::Sse` + `tokio_stream::wrappers::BroadcastStream`.
- `Last-Event-ID` parsed from request header; non-numeric → start fresh.
- Concurrent-client cap via shared `AtomicUsize` counter; RAII guard decrements on drop.
- Each event serialized as `Sse::Event::default().id(seq).event(type).data(json)`.
- Host-guard + CSP middleware from task 004 already cover this route by router-level layering.
