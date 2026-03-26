---
name: ship
description: Ship a completed task - commit, push, and create a PR
agent: 'agent'
argument-hint: "feature name"
---

Ship a completed task: commit, push, and create a PR into the feature branch.

The user should provide the feature name in their message.

## Prerequisites
1. Check that `knowledge-base/` directory exists — if not, refuse and instruct the user to run `/bootstrap` first
2. Read tasks from `specs/<feature>/tasks/` — find all tasks with `status: done`
   - Filter to tasks that do NOT yet have a PR (no `pr_url` in frontmatter)
   - If no unshipped `done` tasks exist, report and stop
3. If multiple unshipped `done` tasks exist, ship the lowest-numbered one first

## Steps
1. Verify the task branch exists: `git rev-parse --verify feat/<feature>/{task-id}-{task-name}` — if it doesn't exist, refuse and say: "Task branch `feat/<feature>/{task-id}-{task-name}` not found. Was `/implement` completed for this task?"
2. Checkout the task branch: `feat/<feature>/{task-id}-{task-name}`
3. Verify the branch has commits ahead of the integration branch: `git log feat/<feature>..HEAD --oneline`
   - If no commits and no uncommitted changes exist, refuse and say: "Task branch has no changes to ship. Was `/implement` completed for this task?"
4. Review `git status` — warn about any sensitive files (.env, credentials, secrets)
5. Stage and commit all changes with message: `{task-id}: {task-title}` (skip if working tree is clean and commits already exist)
6. Push the task branch: `git push -u origin feat/<feature>/{task-id}-{task-name}`
7. Create PR targeting the feature branch:
   ```
   gh pr create --base feat/<feature> \
     --title "{task-id}: {task-title}" \
     --body "<summary of changes based on the diff>"
   ```
8. Save the PR URL to the task file frontmatter as `pr_url`
9. Report the PR URL as final output

IMPORTANT:
- Do NOT add any "Co-Authored-By" line to the commit message
- Do NOT merge the PR — human reviews and merges
- Remind the user: "Merge the PR, then run `/implement <feature>` for the next task"
