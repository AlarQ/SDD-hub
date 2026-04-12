---
id: "003"
name: wire-clear-context-ship
title: Wire clear_context into /ship command
status: todo
blocked_by: ["001"]
ground_rules:
  - "general:architecture/general.md"
  - "general:style/general.md"
test_cases:
  - "ship.md contains clear_context call after PR creation"
  - "clear_context uses full path ~/.claude/scripts/monitor.sh"
  - "clear_context is positioned after PR creation and before metadata steps"
  - "step numbering is consistent after insertion"
---

# Task: Wire clear_context into /ship command

## Description

Add a `monitor.sh clear_context` call to `commands/ship.md` after Step 7 (PR creation), before Step 8 (save PR URL). Per ADR-001, PR creation is the last substantive action — metadata bookkeeping after this point is intentionally unmonitored.

## Files

- `commands/ship.md`

## Acceptance Criteria

- New step inserted between current Step 7 and Step 8: "Clear monitor context: `~/.claude/scripts/monitor.sh clear_context`"
- Uses full path `~/.claude/scripts/monitor.sh` (per ADR-004)
- All subsequent step numbers are incremented (Steps 8-11 become 9-12)
- If PR creation fails (Step 7), `clear_context` is NOT reached — context correctly persists
- No error handling or conditional logic added
