---
id: "015"
name: "Last-task-done trigger + /implement auto-chain"
status: blocked
blocked_by: ["014"]
max_files: 5
estimated_files:
  - scripts/task-manager.sh
  - scripts/monitor.sh
  - commands/implement.md
  - tests/test-task-manager.sh
  - tests/fixtures/last-task-done/
test_cases:
  - "task-manager.sh set-status <last-task> done emits spec_last_task_done on the feature's .monitor.jsonl"
  - "Detector scans the feature's tasks/ dir and confirms every task file has status: done before emitting"
  - "Detector does NOT emit spec_last_task_done when at least one task is still non-done"
  - "Detector does NOT emit when a prior spec_audit_done event already exists on the feature's .monitor.jsonl (idempotency)"
  - "/implement auto-chain observes spec_last_task_done and invokes /validate-impl <feature>"
  - "Standalone CLI task-manager.sh set-status done emits the event but does NOT auto-invoke /validate-impl (parity with existing monitoring pattern)"
  - "Concurrent set-status calls do not double-emit (file-lock or last-write-wins sentinel check)"
  - "spec_complete, spec_reopened, spec_last_task_done appear in monitor.sh closed allowlist"
ground_rules:
  - general:languages/shell.md
  - general:architecture/general.md
  - general:testing/principles.md
---

## Description

Wire the trigger that fires `/validate-impl` automatically when the final task in a spec transitions to `done`. Detection is shell-level (always-on); auto-invocation is `/implement`-level (interactive chain only), matching the existing event-emission pattern for `task_transition` events.

## Public API

- `scripts/task-manager.sh` — after successful `set-status done`, call a new private helper `maybe_emit_spec_last_task_done` that:
  1. Resolves the feature from the task file path (already used by monitor context).
  2. Counts tasks in the feature's tasks dir with `status != done`. If zero:
  3. Greps the feature's `.monitor.jsonl` for a prior `spec_audit_done` event. If absent:
  4. Emit `spec_last_task_done` via `log_event`.
- `commands/implement.md` — auto-chain step added: after its own `set-status done` invocation, check the feature's `.monitor.jsonl` tail for `spec_last_task_done` (emitted moments earlier); if present, invoke `/validate-impl "$feature"` as the final chain step before the chain exits.

## Implementation Notes

- Idempotency: the prior-`spec_audit_done` guard prevents re-triggering after a `reopen` verdict cycles new tasks to done. T017 is responsible for clearing the guard when spec truly restarts (deliberate re-audit requested).
- Serial execution rule (CLAUDE.md) already forbids concurrent task completion; a simple tail-grep check is sufficient. No file locks needed.
- Fixture under `tests/fixtures/last-task-done/` — 3 task files, feature dir, empty `.monitor.jsonl`. Tests walk all tasks through the state machine and assert event emission on the final transition only.
- Do not modify the task state machine. `done` remains terminal. Reopen flow (T017) inserts new `todo` tasks; it does not revert existing `done` tasks.
