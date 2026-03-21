Ship a completed task: commit, push, and create a PR into the feature branch.

Feature name: $ARGUMENTS

## Prerequisites
1. Check that `knowledge-base/` directory exists — if not, refuse and instruct the user to run `/bootstrap` first
2. Read tasks from `specs/$ARGUMENTS/tasks/` — find all tasks with `status: done`
   - Filter to tasks that do NOT yet have a PR (no `pr_url` in frontmatter)
   - If no unshipped `done` tasks exist, report and stop
3. If multiple unshipped `done` tasks exist, ship the lowest-numbered one first

## Steps
1. Checkout the task branch: `feat/$ARGUMENTS/{task-id}-{task-name}`
2. Review `git status` — warn about any sensitive files (.env, credentials, secrets)
3. Stage and commit all changes with message: `{task-id}: {task-title}`
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
