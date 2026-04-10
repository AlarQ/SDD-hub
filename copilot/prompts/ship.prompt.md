---
name: ship
description: Ship a completed task - commit, push, and create a PR
agent: 'agent'
argument-hint: "feature name"
---

Ship a completed task: commit, push, and create a PR into the feature branch.

The user should provide the feature name in their message.

## Prerequisites
1. Check that `knowledge-base/_general/` (general) exists — if not, refuse and say: "General knowledge base not found. Run `setup-copilot.sh` from the dev-workflow repo first."
2. Check that `knowledge-base/` (project) exists with project-specific files — if not, refuse and instruct the user to run `/bootstrap` first
3. Read tasks from `specs/<feature>/tasks/` — find all tasks with `status: done`
   - Filter to tasks that do NOT yet have a PR (no `pr_url` in frontmatter)
   - If no unshipped `done` tasks exist, report and stop
4. Verify all validation gates passed for this task: check `specs/<feature>/reports/` for report files matching this task's ID
   - If any report has `status: findings` or `status: error`, refuse and say: "Validation gate(s) have unresolved findings or errors. Run `/review-findings <feature>` first."
   - If no reports directory exists or all reports show `status: pass` (or reports were already cleaned up by `/validate`), proceed
5. If multiple unshipped `done` tasks exist, ship the lowest-numbered one first

## Steps
1. Verify the task branch exists: `git rev-parse --verify feat/<feature>/{task-id}-{task-name}` — if it doesn't exist, refuse and say: "Task branch `feat/<feature>/{task-id}-{task-name}` not found. Was `/implement` completed for this task?"
2. Checkout the task branch: `feat/<feature>/{task-id}-{task-name}`
3. Verify the branch has commits ahead of the integration branch: `git log feat/<feature>..HEAD --oneline`
   - If no commits and no uncommitted changes exist, refuse and say: "Task branch has no changes to ship. Was `/implement` completed for this task?"
4. Review `git status` — warn about any sensitive files (.env, credentials, secrets)
5. Stage and commit all changes using conventional commit format: `type(task-id): {task-title}` where type is determined from the task context (feat, fix, refactor, docs, chore, test, style) — skip if working tree is clean and commits already exist
6. Push the task branch: `git push -u origin feat/<feature>/{task-id}-{task-name}`
7. Create PR targeting the feature branch:
   ```
   gh pr create --base feat/<feature> \
     --title "type(task-id): {task-title}" \
     --body "<summary of changes based on the diff>"
   ```
8. Save the PR URL to the task file frontmatter as `pr_url`
9. Report the PR URL as final output

IMPORTANT:
- Do NOT add any "Co-Authored-By" line to the commit message
- Do NOT merge the PR — human reviews and merges
- Remind the user: "Merge the PR, then run `/implement <feature>` for the next task"
