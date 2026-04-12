---
feature: monitoring-enhancement
status: draft
created: 2026-04-12
---

# Design: Wire Monitor Context into Workflow Commands

## Architecture Overview

This feature connects two existing layers — command markdown files and the monitoring shell script — with minimal new coupling. The commands gain two call sites to `monitor.sh` (CLI invocations), and `monitor.sh` gains validation at two choke points.

```
┌─────────────────┐     ┌─────────────────┐
│  /implement.md  │     │    /ship.md     │
│                 │     │                 │
│ Step 1.5:       │     │ Step 7.5:       │
│ set_context     │     │ clear_context   │
└────────┬────────┘     └────────┬────────┘
         │                       │
         ▼                       ▼
┌────────────────────────────────────────────┐
│            monitor.sh (CLI mode)           │
│                                            │
│  set_context ──► validate_id(feature)      │
│  get_monitor_file ──► validate_id(feature) │
│  clear_context ──► rm .monitor-context     │
└────────────────────────────────────────────┘
         │
         ▼
┌────────────────────────────────────────────┐
│  .monitor-context (project root)           │
│  feature=<name>                            │
│  task=<task_id>                            │
└────────────────────────────────────────────┘
         │
         ▼ (read by PostToolUse hook)
┌────────────────────────────────────────────┐
│  specs/<feature>/.monitor.jsonl            │
└────────────────────────────────────────────┘
```

## Architectural Decisions

### Placement of `set_context` in `/implement`

**Decision**: Place after Step 1 (task status set to `in-progress`), before branch creation.

**Why (against architecture rule 4 — clear interfaces)**: At Step 1, the task_id is known and the task is officially in-progress. This is the natural lifecycle boundary. Placing it later (after branch creation) would miss monitoring branch-setup commands and create an inconsistent boundary between "task is in progress" and "monitoring is active."

**Trade-off**: If `/implement` aborts between Step 1 and Step 5 (branch creation), a stale context file remains. Mitigated by serial execution — the next `/implement` overwrites it.

### Placement of `clear_context` in `/ship`

**Decision**: Place after Step 7 (PR creation), before metadata bookkeeping (steps 8-11).

**Why (against architecture rule 2 — single responsibility)**: PR creation is the last substantive action. Steps 8-11 (saving PR URL, final push) are bookkeeping that produces noise rather than monitoring signal. Clearing context here also means that if PR creation fails, context correctly persists (the task is still in-flight).

**Trade-off**: Steps 8-11 are not monitored. Acceptable — they are metadata, not implementation activity.

### Validation Strategy — Two Choke Points

**Decision**: Add `validate_id "$feature" "feature"` to `get_monitor_file` and `set_context` only.

**Why (against architecture rule 5 — validate at boundaries)**: There are exactly two distinct security surfaces: (1) path construction via `get_monitor_file` (used by `log_event`, `start_phase`, `end_phase`), and (2) context persistence via `set_context`. Validating at these choke points covers all attack vectors without redundant checks at every public function.

**Trade-off**: Understanding full coverage requires knowing the call graph. Acceptable for a 215-line script with a single maintainer.

### No Read-Side Validation in `read_context`

**Decision**: Do not add `validate_id` to values parsed from `.monitor-context`.

**Why (against architecture rule 5 — validate at boundaries)**: The file is written exclusively by `set_context` (which validates). The PostToolUse hook calls `log_event` with the read values, which flows through `get_monitor_file` (which validates). Double-checking here defends against a threat requiring local file access — at which point the attacker has far more powerful vectors. Pragmatic trade-off for a local CLI tool.

### Accept `monitor.sh` Size Overage

**Decision**: Keep `monitor.sh` as a single file (~225 lines after changes), exceeding the 150-line shell limit.

**Why (against general:languages/shell.md — 150-line limit)**: The script is cohesive with a single responsibility (monitoring event lifecycle). Splitting into `monitor-context.sh` + `monitor-events.sh` would create coupling through shared helpers (`find_project_root`, `validate_id`, `MONITOR_CONTEXT_FILE`) that violates architecture rule 7 (independent and composable). The overage is documented and justified. Hard ceiling: if it reaches 300 lines, split is warranted.

## Architecture Decision Records

### ADR-001: Monitor Context Lifecycle Boundaries

**Status:** Proposed  
**Context:** The monitoring infrastructure exists but never activates. We need to decide where in the `/implement` and `/ship` lifecycles to place context management. Commands are markdown instructions — no trap/finally mechanisms.  
**Decision:** `set_context` after Step 1 of `/implement`; `clear_context` after Step 7 of `/ship`. Monitored window: task-in-progress to PR-created.  
**Consequences:** Branch-setup activity is monitored. Stale context on early abort is mitigated by serial execution. Ship bookkeeping (steps 8-11) is not monitored.

### ADR-002: Feature Parameter Validation at Two Choke Points

**Status:** Proposed  
**Context:** `feature` parameter flows unsanitized into path construction (`specs/$feature/.monitor.jsonl`) and context file writing. Two distinct attack surfaces exist.  
**Decision:** Validate `feature` in `get_monitor_file` (path choke point) and `set_context` (persistence choke point). Do not add validation to every public function or to `read_context`.  
**Consequences:** Both surfaces covered with 2 lines of code. Coverage depends on understanding that `log_event`/`start_phase`/`end_phase` flow through `get_monitor_file`. Add a documentation comment noting the validation contract.

### ADR-003: Accept monitor.sh Size Overage (150 → ~225 lines)

**Status:** Proposed  
**Context:** Shell module limit is 150 lines. `monitor.sh` is 215 lines (225 after changes). Script is cohesive single-responsibility. Splitting creates coupling through shared helpers.  
**Decision:** Accept the overage. Do not split.  
**Consequences:** Single file remains easy to source and understand. Hard ceiling at 300 lines for future re-evaluation. Does not set a precedent — justification is specific to this script's high cohesion.

### ADR-004: Commands Couple to monitor.sh via CLI Invocation

**Status:** Proposed  
**Context:** Markdown commands need to call `monitor.sh`. Only mechanism available is CLI invocation (no sourcing from markdown).  
**Decision:** Commands invoke `~/.claude/scripts/monitor.sh <subcommand>` directly. No abstraction layer.  
**Consequences:** Explicit, visible coupling. If `monitor.sh` moves or API changes, two call sites need updating. Follows architecture rules 4 (clear interfaces) and 8 (explicit dependencies).

## Module Boundaries

| Module | Responsibility | Changes |
|--------|---------------|---------|
| `commands/implement.md` | Orchestrate task implementation | Add one `monitor.sh set_context` call |
| `commands/ship.md` | Orchestrate task shipping | Add one `monitor.sh clear_context` call |
| `scripts/monitor.sh` | Event lifecycle management | Add `validate_id` to 2 functions |

**Dependency direction**: Commands (high-level orchestration) → `monitor.sh` (low-level utility). Correct per architecture rule 6.

## Data Flow

1. User runs `/implement feature-name`
2. Command sets task status to `in-progress` via `task-manager.sh`
3. Command calls `monitor.sh set_context feature-name 001-task-name`
4. `set_context` validates both parameters, writes `.monitor-context`
5. During implementation, PostToolUse hook reads `.monitor-context` on each tool call
6. Hook calls `log_event` → appends to `specs/feature-name/.monitor.jsonl`
7. User runs `/ship feature-name`
8. Command creates PR
9. Command calls `monitor.sh clear_context`
10. `clear_context` removes `.monitor-context`
11. PostToolUse hook sees no context file → stops logging

## Risk Flags

| Severity | Risk | Mitigation |
|----------|------|------------|
| **Medium** | PostToolUse hook not wired in `templates/settings.json`. Even after this feature lands, zero mechanical events are captured because the hook never fires. | PRD Phase 2 identifies this as critical. Phase 1 delivers lifecycle management only (context set/clear). Event capture requires hook wiring in a subsequent change. |
| **Low** | Stale `.monitor-context` after interrupted `/implement` or failed `/ship`. | Serial execution model means next `/implement` overwrites. Manual cleanup: `monitor.sh clear_context`. |
| **Low** | Phase category mismatch between `monitor.sh` (emits `"category":"phase"`) and Rust TUI (`EventCategory` enum has no `Phase` variant). | Pre-existing issue. Phase events silently dropped by TUI. Not introduced by this change. |
| **Low** | No `/continue-task` integration — resumed tasks run unmonitored. | Deferred to Phase 2 per PRD scope. Infrequent recovery path. |
