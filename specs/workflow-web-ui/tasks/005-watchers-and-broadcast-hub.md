---
id: "005"
name: "Structural + tail watchers + BroadcastHub with replay buffer"
status: blocked
blocked_by: ["004"]
max_files: 12
estimated_files:
  - workflow-web/src/watcher/mod.rs
  - workflow-web/src/watcher/structural.rs
  - workflow-web/src/watcher/tail.rs
  - workflow-web/src/broadcast/mod.rs
  - workflow-web/src/broadcast/event.rs
  - workflow-web/src/broadcast/replay.rs
  - workflow-web/src/app_state.rs
  - workflow-web/src/main.rs
  - workflow-web/tests/watcher_structural.rs
  - workflow-web/tests/watcher_tail.rs
  - workflow-web/tests/broadcast_hub.rs
  - workflow-web/tests/watcher_vim_save.rs
test_cases:
  - "structural watcher emits WatchEvent::Structural with debounce in 100–250ms window"
  - "structural watcher excludes .monitor.jsonl from its subscription"
  - "structural event triggers cache.invalidate for affected path"
  - "structural watcher enforces per-path rate cap of 20 events/s"
  - "tail watcher emits MonitorAppend with parsed JSONL events, not raw bytes"
  - "tail watcher handles vim atomic-rename save (inode change) by re-opening from offset 0"
  - "tail watcher resets offset to 0 when file size decreases"
  - "JSONL line > 64 KiB is skipped; counter increments; synthetic {type:parse_skip} emitted"
  - "BroadcastHub assigns monotonic per-project seq via AtomicU64"
  - "replay buffer holds at least 256 most recent events per project"
  - "replay_since(project, last_seq) returns events with seq > last_seq when within window"
  - "replay_since returns Reset{boot_id} when last_seq is outside ring window"
  - "1000 events on a paused receiver: first event after resume is Lag{dropped:n}, subsequent in seq order"
  - "broadcast channel capacity 256; Lagged(n) from receiver maps to Event::Lag"
  - "boot_id is a fresh Uuid per process start"
ground_rules:
  - general:security/general.md
  - general:architecture/general.md
  - general:languages/rust/concurrency.md
  - general:languages/rust/ownership.md
  - general:languages/rust/error-handling.md
  - general:testing/principles.md
  - project:languages/rust.md
---

## Description

Two-watcher event production pipeline + per-project broadcast hub with monotonic seq, ring buffer, and `boot_id`. No SSE endpoint yet (deferred to 006). Implements ADR-004 + ADR-005 + SEC-FR-14, 15 (queue cap), 16.

## Public API

- `Watcher::spawn(root, cache, hub) -> JoinHandle` — owns its notify subscription.
- `BroadcastHub::publish(project, event)` — assigns seq, pushes to ring, fans out on broadcast.
- `BroadcastHub::subscribe(project) -> (broadcast::Receiver, Vec<Event>)` — attach + return replay window (if any).
- `BroadcastHub::replay_since(project, last_seq) -> ReplayResult { Replay(Vec<Event>) | Reset{boot_id} }`.

## Implementation Notes

- `notify-debouncer-mini` for structural; raw `notify` poll for tail (lower latency).
- Tail watcher uses `tokio::fs::File::seek` from stored byte offset; reads delta; parses line-by-line through `workflow_core::parse::monitor_parser` (line cap 64 KiB enforced before parse).
- Inode tracked via `std::os::unix::fs::MetadataExt` (Linux/macOS); fallback to `(dev, ino, len)` triple.
- BroadcastHub: `DashMap<ProjectId, Topic>` where `Topic { sender, seq: AtomicU64, ring: Mutex<VecDeque<Event>> }`. Ring under tokio `Mutex` because push happens off the publish path.
- `boot_id: Uuid::new_v4()` stored in `Arc<BroadcastHub>` at construction.
- Watchers run as `tokio::spawn`ed long-lived tasks; shutdown via cancellation token on SIGINT.
