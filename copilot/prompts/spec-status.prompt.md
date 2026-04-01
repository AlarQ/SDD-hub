---
name: spec-status
description: Show a comprehensive status dashboard for a feature's tasks
agent: 'agent'
argument-hint: "feature name"
---

Show a comprehensive status dashboard for a feature's tasks.

The user should provide the feature name in their message.

## Prerequisites
1. Check that `knowledge-base/_general/` (general) exists — if not, refuse and say: "General knowledge base not found. Run `setup-copilot.sh` from the dev-workflow repo first."
2. Check that `knowledge-base/` (project) exists with project-specific files — if not, refuse and instruct the user to run `/bootstrap` first
3. Check that `specs/<feature>/tasks/` directory exists and contains task files — if not, refuse and say: "No tasks found for feature '<feature>'. Run `/propose <feature>` first."

## Steps

### 1. Gather task data
Run `./scripts/task-manager.sh status specs/<feature>/tasks/` to get a machine-readable YAML summary of all tasks, their statuses, dependencies, and health diagnostics.

### 2. Display task summary table
Present all tasks in a table sorted by task ID:

```
| ID  | Task Name              | Status       |
|-----|------------------------|--------------|
| 001 | setup-database         | done         |
| 002 | implement-user-repo    | in-progress  |
| 003 | add-auth-middleware    | blocked      |
```

### 3. Display progress overview
Show aggregate counts and a progress bar:
- Total tasks, completed (done), in-flight (in-progress/implemented/review), blocked, todo
- Percentage complete: `done / total * 100`

### 4. Display dependency graph
Show which tasks block which, as a readable tree or list:
```
001 (done) -> unblocks 002, 003
002 (in-progress) -> unblocks 004
003 (blocked by 001, 002)
```
Only show tasks that participate in dependencies (have `blocked_by` or are referenced as blockers).

### 5. Display health diagnostics
Flag any unhealthy states that need human attention:

- **Stuck in-progress**: Task is `in-progress` but may need manual intervention (stale branch, abandoned work). Suggest: "Reset status to `todo` in the task file YAML frontmatter and clean up the branch."
- **Deadlocked**: All remaining tasks are `blocked` with none `todo` or `in-progress` — nothing can progress. Suggest: "Check dependency IDs for errors. A task may reference a non-existent dependency."
- **Orphan dependency**: A task's `blocked_by` references an ID that doesn't exist in any task file. Suggest: "Fix the `blocked_by` field — ID not found."
- **Circular dependency**: Tasks that form a cycle where A blocks B blocks A (directly or transitively). Suggest: "Break the cycle by removing one dependency."
- **Unvalidated work**: Tasks stuck at `implemented` or `review` — blocking further implementation. Suggest: "Run `/validate <feature>`" or "Run `/review-findings <feature>`."
- **Blocked by non-done**: A `blocked` task whose dependencies are all present but some are stuck at unhealthy statuses themselves (not progressing toward `done`).

If no health issues are found, say: "No health issues detected."

### 6. Suggest next action
Based on the current state, suggest what the user should do next:
- If a task is `implemented` or `review`: "Run `/validate <feature>`" or "Run `/review-findings <feature>`"
- If a task is `todo` and none is `in-progress`: "Run `/implement <feature>`"
- If all tasks are `done`: "All tasks complete! Create the final PR: `gh pr create --base main`"
- If deadlocked or stuck: Explain what manual fix is needed

## Output format
Use markdown formatting with headers, tables, and code blocks for readability. Keep it concise — this is a dashboard, not a report.
