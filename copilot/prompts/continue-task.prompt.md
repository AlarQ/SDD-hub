---
name: continue-task
description: Resume work on an in-progress task for a feature
agent: 'agent'
argument-hint: "feature name"
---

Resume work on the current in-progress task for a feature.

The user should provide the feature name in their message.

## Prerequisites
1. Check that `knowledge-base/` directory exists — if not, refuse and instruct the user to run `/bootstrap` first
2. Read tasks from `specs/<feature>/tasks/` — find tasks in an active state, checking in this priority order:
   - `status: in-progress`
   - `status: implemented`
   - `status: review`
   - `status: done` without a `pr_url` in frontmatter
   - If no tasks in any active state: report "No active tasks found. Run `/implement <feature>` to start the next task."

## Phase Detection

Examine the active task's status and existing artifacts to determine where work left off:

| Condition | Detected Phase | Action |
|-----------|---------------|--------|
| `in-progress`, task branch has no commits ahead of `feat/<feature>` | Implementation (start) | Checkout task branch, continue implementing |
| `in-progress`, code changes exist on task branch | Implementation (mid) | Checkout task branch, continue coding/testing |
| `implemented`, no reports in `specs/<feature>/reports/` for this task | Validation needed | Remind: "Run `/validate <feature>`" |
| `implemented` or `review`, reports exist with `review_status: pending` findings | Review findings | Remind: "Run `/review-findings <feature>`" |
| `done`, no `pr_url` in task frontmatter | Ship needed | Remind: "Run `/ship <feature>`" |
| `done`, `pr_url` exists, PR state is `OPEN` | Merge needed | Remind: "Merge the PR, then run `/implement <feature>` for the next task" |

## Steps
1. Identify the active task using the priority order above
2. Check git status for uncommitted changes from a previous session — if present, mention them
3. Check if the task branch exists: `feat/<feature>/{task-id}-{task-name}`
4. Determine the current phase using the detection table
5. Announce what you're resuming:
   ```
   Resuming: {task-id}: {task-title}
   Feature: <feature>
   Phase: {detected phase}
   Status: {current task status}
   ```
6. If phase is Implementation (start or mid): checkout the task branch and continue implementing following the `/implement` workflow
7. For all other phases: remind the user which command to run next

## If No Active Task
Report the feature status summary — how many tasks in each state (blocked, todo, in-progress, implemented, review, done) — and suggest the next action based on the current state.
