---
feature: monitoring-enhancement
status: draft
created: 2026-04-12
---

# PRD: Wire Monitor Context into Workflow Commands

## Problem

The monitoring infrastructure (monitor.sh, PostToolUse hook, TUI monitor panel) is fully built but never activates during real workflow usage. No slash command creates `.monitor-context`, so the hook never logs events and the TUI monitor panel is always empty.

## Solution

- `/implement` calls `monitor.sh set_context <feature> <task_id>` when starting a task
- `/ship` calls `monitor.sh clear_context` after PR creation
- Add `validate_id` for the `feature` parameter in `monitor.sh` (security fix — feature name currently flows unsanitized into file path construction)

## Scope

### In

- `commands/implement.md` — add `set_context` call at task start
- `commands/ship.md` — add `clear_context` call after PR creation
- `scripts/monitor.sh` — add feature name validation via existing `validate_id`

### Out

- `/validate`, `/continue-task`, `/pr-review` standalone monitoring (future work)
- JSONL rotation or size caps (pre-existing concern, not introduced here)
- Stale context recovery on interruption (accepted risk for now)

## User Perspective

- **Who benefits:** Developers using the spec-driven workflow
- **Problem solved:** Monitoring data flows automatically — the TUI dashboard shows real-time tool calls, task transitions, and validation results without manual setup
- **Shortest path:** Two `monitor.sh` calls wired into existing commands, plus one validation fix

## Security

- `.monitor-context` contains only feature name and task ID — no secrets or sensitive data
- File is `.gitignore`d
- **Fix required:** `feature` parameter lacks `validate_id` — values like `../../etc` could resolve outside the specs tree. Apply existing `validate_id` guard to `feature` in `set_context`, `log_event`, `start_phase`, and `get_monitor_file`

## Testing

- Manual verification: run `/implement`, confirm `.monitor-context` created and events flow; run `/ship`, confirm `.monitor-context` removed
- Unit test for feature name validation in existing monitor test suite

## Known Risks (Accepted)

- **Stale context on interruption:** If `/ship` fails or is interrupted before `clear_context`, events may log against the wrong task. Acceptable for a local CLI tool
- **JSONL unbounded growth:** No size cap or rotation — pre-existing, not introduced by this feature
- **Context origin:** No way to distinguish legitimate vs manual `set_context` calls — acceptable for local tooling

## Applicable Ground Rules

- `general:style/general.md`
- `general:architecture/general.md`
- `general:security/general.md`
- `general:languages/shell.md`

## Phase 2: Full Monitoring Pipeline

Gaps identified by implementation audit of `spec-implementation-monitor`. Current PRD (Phase 1) wires `set_context` and `clear_context` into two commands. Phase 2 closes the remaining gaps to make monitoring functional end-to-end.

### Critical — monitoring non-functional without these

- **Wire `PostToolUse` hook in `templates/settings.json`** — `monitor-tool-calls.sh` is installed but never fires because `settings.json` only has `PreToolUse` and `Stop` entries. Without this, zero mechanical events (tool_call, context_read) are captured.
- **Add `.monitor-context` to `.gitignore`** — Security section states it should be ignored; no implementation task covers it. Risk: stale context files get committed.

### Spec compliance — data contract fixes

- **Fix `phase` category mismatch** — `start_phase`/`end_phase` in `monitor.sh` emit `"category":"phase"` but the Rust `EventCategory` enum has no `Phase` variant (`monitor_event.rs`). All phase timing events silently fail to deserialize and are dropped. Fix: add `Phase` variant to Rust enum, or change shell to emit an existing category.
- **Add `phase` field to agent invocation events** — spec defines `{agent_name, reason, phase: "start"|"complete"|"error"}` but hook emits only `{agent_name, source: "hook"}`. `PostToolUse` can only observe completion, not start — lifecycle tracking design needs revisiting.

### Command instrumentation — expand coverage

- **`/validate` — log `validation_result` events** per gate after report is written
- **`/review-findings` — log finding review decisions** (accept/reject per group)
- **`/continue-task` — re-establish `set_context`** when resuming a task mid-flight

### TUI polish

- **Per-status coloring for `validation_result`** — currently always Green via `event_category_color()`. Spec requires Red for findings/error status. Deferred as known deviation in task 006.

### Resilience

- **`.monitor-context` stale expiry (2-hour TTL)** — ADR-003 specifies timestamp-based expiry to handle crashes/interruptions. Neither `monitor.sh` nor the hook implements any age check; context file is read unconditionally.

## Agent Insights (Explore Phase)

### UX Researcher

- `/validate` and `/ship` used independently (outside `/implement`'s auto-chain) would get no monitoring if context is only set in `/implement` — deferred to future work per scope decision
- Stale context risk if developer abandons task mid-flight — accepted risk
- `/continue-task` is an under-examined flow that would need `set_context` re-established — deferred
- Value depends on TUI presenting useful signal, not just raw events
- `clear_context` timing after `/ship` may miss `/pr-review` activity — accepted trade-off

### Security Engineer

- **Tampering (path injection):** `feature` name flows unsanitized into path construction — fix by applying `validate_id` to feature parameter
- **Stale context leakage:** Interrupted `/ship` could cause events to log to wrong spec — accepted risk
- **JSONL unbounded growth:** No size cap — low severity for local tooling
- **Context origin:** Cannot distinguish legitimate vs manual calls — acceptable
- **Priority:** Only feature-name validation warrants a code fix
