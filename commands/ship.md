Ship a completed task: commit, push, and create a PR into the feature branch.

Feature name: $ARGUMENTS

## Prerequisites
1. Read and follow `~/.claude/knowledge-base-rules.md` for knowledge base prerequisites and resolution rules
2. Read tasks from `specs/$ARGUMENTS/tasks/` — find all tasks with `status: done`
   - Filter to tasks that do NOT yet have a PR (no `pr_url` in frontmatter)
   - If no unshipped `done` tasks exist, report and stop
3. Verify all validation gates passed for this task: check `specs/$ARGUMENTS/reports/` for report files matching this task's ID
   - If any report has `status: findings` or `status: error`, refuse and say: "Validation gate(s) have unresolved findings or errors. Run `/review-findings $ARGUMENTS` first."
   - If no reports directory exists or all reports show `status: pass` (or reports were already cleaned up by `/validate`), proceed
4. If multiple unshipped `done` tasks exist, ship the lowest-numbered one first

## Step 0 — Load Spec Config

Before running any step, load the spec config (substituting the actual feature name for `$ARGUMENTS`):

```bash
bash -c 'source ~/.claude/scripts/config-loader.sh && wf_load_config --spec $ARGUMENTS && printf "WF_SPEC_CONFIG_FILE=%s\nWF_SPEC_GATES=%s\n" "${WF_SPEC_CONFIG_FILE:-}" "$WF_SPEC_GATES"'
```

On non-zero exit:
- Exit code 4: stop — "Missing spec config for '$ARGUMENTS'. Expected: `specs/$ARGUMENTS/config.yml` — create it via `/explore $ARGUMENTS`."
- Any other non-zero: stop — print the loader error and halt.

**Snapshot drift check** — if `.monitor-context-snapshot` exists in the repo root, compare the current config state against the snapshot written by `/implement`:

```bash
bash -c 'source ~/.claude/scripts/config-loader.sh && wf_load_config --spec $ARGUMENTS && wf_check_snapshot_drift .monitor-context-snapshot'
```

If output is `SNAPSHOT_DRIFT`: stop — "Config drift detected: `specs/$ARGUMENTS/config.yml` changed since `/implement` started. Re-approve the config via `/config $ARGUMENTS` or restore the original, then re-run `/ship`."
If `SNAPSHOT_OK` or snapshot file absent: proceed.

## Steps
1. Verify the task branch exists: `git rev-parse --verify feat/$ARGUMENTS/{task-id}-{task-name}` — if it doesn't exist, refuse and say: "Task branch `feat/$ARGUMENTS/{task-id}-{task-name}` not found. Was `/implement` completed for this task?"
2. Checkout the task branch: `feat/$ARGUMENTS/{task-id}-{task-name}`
3. Verify the branch has commits ahead of the integration branch: `git log feat/$ARGUMENTS..HEAD --oneline`
   - If no commits and no uncommitted changes exist, refuse and say: "Task branch has no changes to ship. Was `/implement` completed for this task?"
4. Review `git status` — warn about any sensitive files (.env, credentials, secrets)
5. Stage and commit all changes using conventional commit format: `type(task-id): {task-title}` where type is determined from the task context (feat, fix, refactor, docs, chore, test, style) — skip if working tree is clean and commits already exist
6. Push the task branch: `git push -u origin feat/$ARGUMENTS/{task-id}-{task-name}`
7. Create PR targeting the feature branch:
   ```
   gh pr create --base feat/$ARGUMENTS \
     --title "type(task-id): {task-title}" \
     --body "<summary of changes based on the diff>"
   ```
8. Clear monitor context: `$HOME/.claude/scripts/monitor.sh clear_context` (non-fatal — proceed even if this fails; stale context is overwritten by the next `/implement`)
9. Save the PR URL to the task file frontmatter as `pr_url`
10. Commit the updated task file with the PR URL: `git add <task-file> && git commit -m "chore(task-id): add PR URL"`
11. Push the commit: `git push`
12. Report the PR URL as final output

IMPORTANT:
- Do NOT add any "Co-Authored-By" line to the commit message
- Do NOT merge the PR — human reviews and merges
- Remind the user: "Merge the PR, then run `/implement $ARGUMENTS` for the next task"
