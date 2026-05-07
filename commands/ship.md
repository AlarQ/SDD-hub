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

> See `~/.claude/scripts/step0-load-config.md` for canonical invocation and remediation. This step uses: `WF_SPEC_CONFIG_FILE`, `WF_SPEC_GATES`.

**Snapshot drift check** — if `.monitor-context-snapshot` exists in the repo root, compare the current config state against the snapshot written by `/implement`:

```bash
bash -c 'source ~/.claude/scripts/config-loader.sh && wf_load_config --spec $ARGUMENTS && wf_check_snapshot_drift .monitor-context-snapshot'
```

If output is `SNAPSHOT_DRIFT`: stop — "Config drift detected: `specs/$ARGUMENTS/config.yml` changed since `/implement` started. Re-approve the config via `/config $ARGUMENTS` or restore the original, then re-run `/ship`."
If `SNAPSHOT_OK` or snapshot file absent: proceed.

### Multi-repo resolution

Resolve the task's bound repo per `~/.claude/scripts/multi-repo-resolution.md` → sets `WF_TASK_REPO_PATH`. All `git` and `gh` operations below run against `WF_TASK_REPO_PATH` via `git -C "$WF_TASK_REPO_PATH" …` and `gh -R "$(git -C "$WF_TASK_REPO_PATH" config --get remote.origin.url)" …` (or by using `gh` from inside the repo directory). The PR opens against that repo's remote only — never the vault.


## Steps
1. Verify the task branch exists: `git -C "$WF_TASK_REPO_PATH" rev-parse --verify feat/$ARGUMENTS/{task-id}-{task-name}` — if it doesn't exist, refuse and say: "Task branch `feat/$ARGUMENTS/{task-id}-{task-name}` not found in $WF_TASK_REPO_PATH. Was `/implement` completed for this task?"
2. Checkout the task branch: `git -C "$WF_TASK_REPO_PATH" checkout feat/$ARGUMENTS/{task-id}-{task-name}`
3. Verify the branch has commits ahead of the integration branch: `git -C "$WF_TASK_REPO_PATH" log feat/$ARGUMENTS..HEAD --oneline`
   - If no commits and no uncommitted changes exist, refuse and say: "Task branch has no changes to ship. Was `/implement` completed for this task?"
4. Review `git status` — warn about any sensitive files (.env, credentials, secrets)
5. Stage and commit all changes using conventional commit format: `type(task-id): {task-title}` (`git -C "$WF_TASK_REPO_PATH" add -A && git -C "$WF_TASK_REPO_PATH" commit -m "…"`) — skip if working tree is clean and commits already exist
6. Push the task branch: `git -C "$WF_TASK_REPO_PATH" push -u origin feat/$ARGUMENTS/{task-id}-{task-name}`
7. Create PR targeting the feature branch (run from `$WF_TASK_REPO_PATH` so `gh` picks up the right remote):
   ```
   (cd "$WF_TASK_REPO_PATH" && gh pr create --base feat/$ARGUMENTS \
     --title "type(task-id): {task-title}" \
     --body "<summary of changes based on the diff>")
   ```
8. Clear monitor context: `$HOME/.claude/scripts/monitor.sh clear_context` (non-fatal — proceed even if this fails; stale context is overwritten by the next `/implement`)
9. Save the PR URL to the task file frontmatter as `pr_url`. The task file lives in the vault/spec dir, **not** the bound repo.
10. Persist the task-file change:
    - **Single-repo mode** (`WF_SPEC_STORAGE_MODE=repo`): `git add <task-file> && git commit -m "chore(task-id): add PR URL" && git push`
    - **Vault mode**: detect whether the vault dir is itself a git repo — `vault_repo="$(git -C "$WF_REPO_ROOT" rev-parse --show-toplevel 2>/dev/null)"`. If non-empty, commit there: `git -C "$vault_repo" add "<task-file>" && git -C "$vault_repo" commit -m "chore(task-id): add PR URL" && git -C "$vault_repo" push`. If empty, print warning: "pr_url written to <task-file> but vault is not a git repo — persist manually." Do not silently skip.
12. Report the PR URL as final output

IMPORTANT:
- Do NOT add any "Co-Authored-By" line to the commit message
- Do NOT merge the PR — human reviews and merges
- Remind the user: "Merge the PR, then run `/implement $ARGUMENTS` for the next task"
