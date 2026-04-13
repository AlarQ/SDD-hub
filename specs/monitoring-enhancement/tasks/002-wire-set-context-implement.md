---
id: "002"
name: wire-set-context-implement
title: Wire set_context into /implement command
status: done
pr_url: https://github.com/AlarQ/SDD-hub/pull/23
blocked_by: ["001"]
max_files: 2
estimated_files:
  - "commands/implement.md"
  - "tests/test-implement-context.sh"
ground_rules:
  - "general:architecture/general.md"
  - "general:style/general.md"
test_cases:
  - "implement.md contains set_context call after task status change"
  - "set_context uses full path ~/.claude/scripts/monitor.sh"
  - "set_context is positioned before branch creation step"
  - "step numbering is consistent after insertion"
---

# Task: Wire set_context into /implement command

## Description

Add a `monitor.sh set_context` call to `commands/implement.md` after Step 1 (task status set to `in-progress`), before Step 2 (branch creation). Per ADR-001, this is the natural lifecycle boundary — monitoring starts when the task officially starts.

## Files

- `commands/implement.md`

## Acceptance Criteria

- New step inserted between current Step 1 and Step 2: "Set monitor context: `~/.claude/scripts/monitor.sh set_context $ARGUMENTS {task-id}`"
- Uses full path `~/.claude/scripts/monitor.sh` (per ADR-004)
- The `{task-id}` references the task ID determined in the prerequisite steps
- All subsequent step numbers are incremented
- No error handling added beyond what bash provides (visible error if monitor.sh not installed)
- Branch-setup activity occurs after context is set (monitored per ADR-001)

## Implementation Notes

### Decisions Made

- Inserted new Step 2 in `commands/implement.md`: `~/.claude/scripts/monitor.sh set_context $ARGUMENTS {task-id}` with a parenthetical clarifying `{task-id}` resolves to the numeric ID from prerequisite steps (e.g. `001`). Per ADR-001, placed immediately after `set-status in-progress` and before branch creation so all branch-setup activity is monitored.
- Old Steps 2–12 renumbered to 3–13. Step reference inside "Implement test bodies" updated from "step 9" to "step 10" to stay consistent.
- No error handling added — missing `monitor.sh` produces a visible bash error, correct failure mode signaling setup.sh was not run.
- Tests in `tests/test-implement-context.sh` assert relative ordering via line numbers, not absolute step numbers, per test-strategy.md guidance on brittleness risk.
- Task file was missing required `max_files` and `estimated_files` fields for task-manager.sh validation; both added before status change.
