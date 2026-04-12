---
id: "002"
name: wire-set-context-implement
title: Wire set_context into /implement command
status: todo
blocked_by: ["001"]
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
