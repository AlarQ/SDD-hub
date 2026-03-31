Ship a completed task: commit, push, and create a PR into the feature branch.

Feature name: $ARGUMENTS

## Prerequisites
1. Check that `knowledge-base/` directory exists — if not, refuse and instruct the user to run `/bootstrap` first
2. Read tasks from `specs/$ARGUMENTS/tasks/` — find all tasks with `status: done`
   - Filter to tasks that do NOT yet have a PR (no `pr_url` in frontmatter)
   - If no unshipped `done` tasks exist, report and stop
3. Verify all validation gates passed for this task: check `specs/$ARGUMENTS/reports/` for report files matching this task's ID
   - If any report has `status: findings` or `status: error`, refuse and say: "Validation gate(s) have unresolved findings or errors. Run `/review-findings $ARGUMENTS` first."
   - If no reports directory exists or all reports show `status: pass` (or reports were already cleaned up by `/validate`), proceed
4. If multiple unshipped `done` tasks exist, ship the lowest-numbered one first

## Steps
1. Verify the task branch exists: `git rev-parse --verify feat/$ARGUMENTS/{task-id}-{task-name}` — if it doesn't exist, refuse and say: "Task branch `feat/$ARGUMENTS/{task-id}-{task-name}` not found. Was `/implement` completed for this task?"
2. Checkout the task branch: `feat/$ARGUMENTS/{task-id}-{task-name}`
3. Verify the branch has commits ahead of the integration branch: `git log feat/$ARGUMENTS..HEAD --oneline`
   - If no commits and no uncommitted changes exist, refuse and say: "Task branch has no changes to ship. Was `/implement` completed for this task?"
4. Review `git status` — warn about any sensitive files (.env, credentials, secrets)
5. Stage and commit all changes with message: `{task-id}: {task-title}` (skip if working tree is clean and commits already exist)
4. Push the task branch: `git push -u origin feat/$ARGUMENTS/{task-id}-{task-name}`
5. Create PR targeting the feature branch:
   ```
   gh pr create --base feat/$ARGUMENTS \
     --title "{task-id}: {task-title}" \
     --body "<summary of changes based on the diff>"
   ```
6. Save the PR URL to the task file frontmatter as `pr_url`
7. Report the PR URL as final output

IMPORTANT:
- Do NOT add any "Co-Authored-By" line to the commit message
- Do NOT merge the PR — human reviews and merges
- Remind the user: "Merge the PR, then run `/implement $ARGUMENTS` for the next task"
