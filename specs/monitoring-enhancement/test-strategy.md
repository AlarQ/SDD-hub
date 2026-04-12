---
feature: monitoring-enhancement
created: 2026-04-12
---

# Test Strategy: monitoring-enhancement

## Overview

This feature spans three tasks across two artifact types: a shell script (Task 001) and two markdown command files (Tasks 002, 003). Task 001 owns all runtime validation and security testing via executable bash tests. Tasks 002 and 003 own structural assertions about markdown content — they verify call site placement and step numbering, not runtime behavior.

## Task Test Responsibilities

### Task 001: add-feature-validation

- **Theme**: Prove that validate_id guards both choke points and all attack vectors are rejected at runtime
- **Owns**:
  - Runtime validation of feature names in set_context (valid, path traversal, spaces, empty)
  - Runtime validation of feature names in get_monitor_file (slashes)
  - Transitive protection: log_event with malicious feature is blocked by get_monitor_file
  - Task ID validation remains enforced in set_context
  - Second-order injection: poisoned context file values rejected by get_monitor_file
  - bash -n and shellcheck pass on monitor.sh
  - Context file content format: set_context writes only feature and task lines
  - Context overwrite: set_context with new values replaces previous context
  - Round-trip: set_context + read_context agree on format
  - Lifecycle: clear_context removes file created by set_context
  - .gitignore pre-condition check for .monitor-context
- **Must NOT test**: Markdown content or structure of implement.md or ship.md
- **Shared fixtures**: Temp directory with `specs/<feature>/` structure
- **Test invocation**: CLI mode (`./scripts/monitor.sh set_context ...`) to cover dispatch

### Task 002: wire-set-context-implement

- **Theme**: Prove implement.md contains the set_context call at the correct lifecycle position
- **Owns**:
  - implement.md contains a line calling monitor.sh set_context with feature and task_id
  - Uses full path ~/.claude/scripts/monitor.sh
  - Call appears after set-status in-progress and before branch creation
  - Step numbering is sequential with no gaps
- **Must NOT test**: Runtime behavior of set_context, validation logic, ship.md content

### Task 003: wire-clear-context-ship

- **Theme**: Prove ship.md contains the clear_context call at the correct lifecycle position
- **Owns**:
  - ship.md contains a line calling monitor.sh clear_context
  - Uses full path ~/.claude/scripts/monitor.sh
  - Call appears after PR creation and before metadata steps
  - Step numbering is sequential with no gaps
  - Structural proof that clear_context is unreachable if PR creation fails
- **Must NOT test**: Runtime behavior of clear_context, set_context placement, validation logic

## Spec Coverage Map

| # | Scenario | Owning Task | Type |
|---|----------|-------------|------|
| 1 | Monitor context is set when implementation starts | 002 | structural |
| 2 | Monitor context is cleared after PR creation | 003 | structural |
| 3 | Monitor context persists on /ship failure | 003 | structural |
| 4 | Monitor context is overwritten by next task | 001 | integration |
| 5 | Valid feature name is accepted | 001 | unit |
| 6 | Feature name with path traversal is rejected | 001 | unit |
| 7 | Feature name with slashes is rejected | 001 | unit |
| 8 | Empty feature name is rejected | 001 | unit |
| 9 | Feature name with spaces is rejected | 001 | unit |
| 10 | Path traversal via get_monitor_file is blocked | 001 | unit |
| 11 | Poisoned context file does not enable second-order injection | 001 | integration |
| 12 | Task ID validation remains enforced | 001 | unit |
| 13 | Monitor context contains no sensitive data | 001 | unit |
| 14 | Monitor context is excluded from version control | 001 | unit |

## Integration Test Plan

| Seam | Owning Task | Rationale |
|------|-------------|-----------|
| set_context + read_context round-trip | 001 | Proves write format and read parser agree |
| set_context overwrite semantics | 001 | Covers spec scenario 4 (stale context replaced) |
| clear_context removes file from set_context | 001 | Lifecycle bookend test |
| Poisoned context → read_context → log_event → rejected | 001 | Second-order injection path |
| Command files reference correct subcommand/arity | 002, 003 | Structural cross-module contract |

## Risk Flags

| Severity | Risk | Mitigation |
|----------|------|------------|
| High | Task 001 test_cases missing second-order injection, overwrite, and content-format scenarios | Added to task file per this strategy |
| Medium | .gitignore scenario has no natural task owner (no task modifies .gitignore) | Assigned to Task 001 as pre-condition check |
| Low | No e2e test orchestrating actual /implement → monitoring activation | Out of scope; structural + runtime tests at seam provide confidence |
| Low | Markdown structural tests could be brittle to step renumbering | Assert relative ordering, not absolute numbers |
| Low | CLI dispatch coverage for set_context/clear_context | Task 001 tests invoke via CLI mode, not sourcing |
