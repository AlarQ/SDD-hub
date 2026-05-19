Resume work on the current in-progress task for a feature.

Feature name: $ARGUMENTS

## Prerequisites
1. Read and follow `$WF_GENERAL_KB/_rules.md` for knowledge base prerequisites and resolution rules
2. Read tasks from `specs/$ARGUMENTS/tasks/` — find tasks in an active state, checking in this priority order:
   - `status: in-progress`
   - `status: implemented`
   - `status: review`
   - `status: done` without a `pr_url` in frontmatter
   - If no tasks in any active state: report "No active tasks found. Run `/implement $ARGUMENTS` to start the next task."

## Step 0 — Load Spec Config

```bash
bash -c 'source ~/.claude/scripts/config-loader.sh && wf_load_config --spec $ARGUMENTS && printf "WF_BRANCH_STRATEGY=%s\n" "${WF_BRANCH_STRATEGY:-per-task}"'
```

> See `~/.claude/scripts/step0-load-config.md` for canonical invocation and remediation. This step uses: `WF_BRANCH_STRATEGY` (`per-task` default | `single-branch`; absent → `per-task`).

## Phase Detection

Examine the active task's status and existing artifacts to determine where work left off.

**`per-task`** (default):

| Condition | Detected Phase | Action |
|-----------|---------------|--------|
| `in-progress`, task branch has no commits ahead of `feat/$ARGUMENTS` | Implementation (start) | Checkout task branch, continue implementing. When implementation completes, stop and instruct: "Run `/validate $ARGUMENTS` next." |
| `in-progress`, code changes exist on task branch | Implementation (mid) | Checkout task branch, continue coding/testing. When implementation completes, stop and instruct: "Run `/validate $ARGUMENTS` next." |
| `implemented`, no reports in `specs/$ARGUMENTS/reports/` for this task | Validation needed | Stop and instruct: "Run `/validate $ARGUMENTS` next." |
| `implemented` or `review`, reports exist with actionable (non-info severity) `review_status: pending` findings | Review findings | Stop and instruct: "Run `/review-findings $ARGUMENTS` next." |
| `done`, reports still exist in `specs/$ARGUMENTS/reports/` (mining did not run) | Mining needed | Stop and instruct: "Run `/learn-from-reports $ARGUMENTS` next." |
| `done`, no `pr_url` in task frontmatter | Ship needed | Stop and instruct: "Run `/ship $ARGUMENTS` next." |
| `done`, `pr_url` exists, PR state is `OPEN` | Merge needed | Remind: "Merge the PR, then run `/implement $ARGUMENTS` for the next task" |

**`single-branch`** — there is no task sub-branch and no per-task PR; use `task_base_sha` (frontmatter) for start/mid detection:

| Condition | Detected Phase | Action |
|-----------|---------------|--------|
| `in-progress`, `${task_base_sha}..HEAD` on `feat/$ARGUMENTS` is empty | Implementation (start) | Stay on `feat/$ARGUMENTS`, continue implementing. When done, stop: "Run `/validate $ARGUMENTS` next." |
| `in-progress`, `${task_base_sha}..HEAD` has commits | Implementation (mid) | Stay on `feat/$ARGUMENTS`, continue coding/testing. When done, stop: "Run `/validate $ARGUMENTS` next." |
| `implemented`, no reports for this task | Validation needed | Stop: "Run `/validate $ARGUMENTS` next." |
| `implemented` or `review`, reports with actionable pending findings | Review findings | Stop: "Run `/review-findings $ARGUMENTS` next." |
| `done`, reports still exist (mining did not run) | Mining needed | Stop: "Run `/learn-from-reports $ARGUMENTS` next." |
| `done`, no `pr_url` (non-final task — normal under single-branch) | Ship needed | Stop: "Run `/ship $ARGUMENTS` next." (`/ship` handles last-vs-non-last: non-last pushes only, last opens the spec PR) |
| `done`, final task, `pr_url` exists, spec PR `OPEN` | Merge spec PR | Remind: "Merge the spec PR into `main`, then the spec is shipped." |

## Steps
1. Identify the active task using the priority order above
2. Check git status for uncommitted changes from a previous session — if present, mention them
3. (`per-task` only) Check if the task branch exists: `feat/$ARGUMENTS/{task-id}-{task-name}`. Under `single-branch` there is no task sub-branch — skip this check; the working branch is `feat/$ARGUMENTS` and a missing sub-branch is **not** an error.
4. Determine the current phase using the detection table
5. Announce what you're resuming:
   ```
   Resuming: {task-id}: {task-title}
   Feature: $ARGUMENTS
   Phase: {detected phase}
   Status: {current task status}
   ```
6. If phase is Implementation (start or mid): checkout the task branch (`per-task`) or stay on `feat/$ARGUMENTS` (`single-branch`) and continue implementing following the `/implement` workflow
7. For all other phases: read and follow the appropriate command file to continue the workflow automatically

## If No Active Task
Report the feature status summary — how many tasks in each state (blocked, todo, in-progress, implemented, review, done) — and suggest the next action based on the current state.
