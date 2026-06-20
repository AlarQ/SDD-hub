# Ship Procedure

Canonical, deterministic ship procedure: commit + push + mark/open the task PR.
Run **inline** by its two callers — never as a slash command:

- `/validate` zero-findings PASS path.
- `/review-and-ship` finding-addressing tail (only when the current task is at
  status `review`).

Same shared-doc pattern as `scripts/pr-body-convention.md` /
`scripts/multi-repo-resolution.md`: the caller inlines this prose; no command
auto-invokes another.

## Precondition contract (caller provides; this procedure does NOT re-do)

The caller has already:

- Loaded the spec config — `WF_SPEC_CONFIG_FILE`, `WF_SPEC_GATES`,
  `WF_BRANCH_STRATEGY` (`per-task` default | `single-branch`), storage mode
  (`WF_SPEC_STORAGE_MODE`).
- Resolved multi-repo to `WF_TASK_REPO_PATH` per
  `~/.claude/scripts/multi-repo-resolution.md`. All `git`/`gh` operations below
  run against `WF_TASK_REPO_PATH` (`git -C "$WF_TASK_REPO_PATH" …`,
  `gh` from inside that directory). The PR opens against that repo's remote
  only — never the vault.
- Resolved the exact task to ship: `<task-file>`, `<task-id>`, `<task-title>`,
  and `$ARGUMENTS` (feature name). This procedure ships **that** task — it does
  NOT scan `tasks/` for unshipped done tasks.

This procedure does **not** re-validate findings — both callers structurally
guarantee findings are handled (zero-findings pass, or all findings addressed),
so there is **no** report-status refusal guard here.

## Snapshot drift check

If `.monitor-context-snapshot` exists in the repo root, compare the current
config state against the snapshot written by `/implement`:

```bash
bash -c 'source ~/.claude/scripts/config-loader.sh && wf_load_config --spec $ARGUMENTS && wf_check_snapshot_drift .monitor-context-snapshot'
```

- `SNAPSHOT_DRIFT`: stop — "Config drift detected: `specs/$ARGUMENTS/config.yml`
  changed since `/implement` started. Re-approve the config via `/config
  $ARGUMENTS` or restore the original, then re-run `/validate $ARGUMENTS`."
- `SNAPSHOT_OK` or snapshot absent: proceed.

## Branch resolution

Steps 1–3 resolve and validate the branch to ship. The branch differs by
`WF_BRANCH_STRATEGY`:

**`per-task`** (default):
1. Verify the task branch exists: `git -C "$WF_TASK_REPO_PATH" rev-parse --verify feat/$ARGUMENTS/{task-id}-{task-name}` — if it doesn't exist, refuse and say: "Task branch `feat/$ARGUMENTS/{task-id}-{task-name}` not found in $WF_TASK_REPO_PATH. Was `/implement` completed for this task?"
2. Checkout the task branch: `git -C "$WF_TASK_REPO_PATH" checkout feat/$ARGUMENTS/{task-id}-{task-name}`
3. Verify the branch has commits ahead of the integration branch: `git -C "$WF_TASK_REPO_PATH" log feat/$ARGUMENTS..HEAD --oneline`
   - If no commits and no uncommitted changes exist, refuse and say: "Task branch has no changes to ship. Was `/implement` completed for this task?"

**`single-branch`**:
1. There is no task sub-branch. Checkout the integration branch: `git -C "$WF_TASK_REPO_PATH" checkout feat/$ARGUMENTS`
2. Read the task's `task_base_sha` from frontmatter (recorded by `/implement`). If absent, refuse: "task_base_sha missing — was `/implement` completed for this task under single-branch strategy?"
3. Verify the task produced commits: `git -C "$WF_TASK_REPO_PATH" log ${task_base_sha}..HEAD --oneline`
   - If empty and no uncommitted changes exist, refuse and say: "No changes for this task to ship."

## Commit + push

4. Review `git status` — warn about any sensitive files (.env, credentials, secrets).
5. Stage and commit all changes using conventional commit format: `type(task-id): {task-title}` (`git -C "$WF_TASK_REPO_PATH" add -A && git -C "$WF_TASK_REPO_PATH" commit -m "…"`) — skip if working tree is clean and commits already exist. One commit covers everything staged at this point (e.g. fixes applied by `/review-and-ship`).
6. Push:
   - **`per-task`**: `git -C "$WF_TASK_REPO_PATH" push -u origin feat/$ARGUMENTS/{task-id}-{task-name}`
   - **`single-branch`**: `git -C "$WF_TASK_REPO_PATH" push -u origin feat/$ARGUMENTS`

## `single-branch` PR handling (Step 7 replacement)

Under `single-branch`, **PR creation is deferred to the final task only**. Determine if this is the last task: check the feature `.monitor.jsonl` tail for a `spec_last_task_done` event (same signal `/implement` uses for spec-done detection):

```bash
tail -50 specs/$ARGUMENTS/.monitor.jsonl 2>/dev/null | grep -q '"category":"spec_last_task_done"'
```

- **Not the last task** → push only (done in Step 6). No PR, no `pr_url`. Print: "Pushed to `feat/$ARGUMENTS` (review deferred). Run `/implement $ARGUMENTS` for the next task." Skip Steps 7–10.
- **Last task** → open **one spec-level PR** ready-for-review with **base `main`** (PR base asymmetry: `per-task` base = `feat/$ARGUMENTS`; `single-branch` base = `main`):
  ```
  (cd "$WF_TASK_REPO_PATH" && gh pr create --base main \
    --title "feat($ARGUMENTS): <spec title>" \
    --body "<body per ~/.claude/scripts/pr-body-convention.md at spec scope — ## Why + ## What changed across all tasks + mermaid (single-branch spec PRs are prime diagram candidates)>

  validation: pass")
  ```
  Emit `~/.claude/scripts/monitor.sh log_event $ARGUMENTS pr_ready <task-id> '{"pr_url":"<url>"}'`. Then persist `pr_url` to **this final task only** via Steps 9–10. Earlier tasks intentionally keep no `pr_url`.

**Multi-repo (`single-branch`)**: the spec PR fans out per bound repo — mirror the `/validate-impl` per-repo fan-out. Last-task detection is spec-global; create one `--base main` PR per bound repo that has tasks (skip repos with no tasks). Persist each repo's `pr_url`.

## `per-task` PR handling (Step 7)

7. PR handling — `/implement` already opened a draft PR. Read the task's `pr_url` from frontmatter:
   - **If `pr_url` exists and PR state is `OPEN` and `isDraft: true`**: mark it ready-for-review instead of creating a new one:
     ```
     (cd "$WF_TASK_REPO_PATH" && gh pr ready <pr_url>)
     ```
     Then refresh the PR body to include the final post-validation diff summary + `validation: pass`:
     ```
     (cd "$WF_TASK_REPO_PATH" && gh pr edit <pr_url> --body "<body per ~/.claude/scripts/pr-body-convention.md — ## Why + ## What changed + optional mermaid>

     validation: pass")
     ```
     Emit `~/.claude/scripts/monitor.sh log_event $ARGUMENTS pr_ready <task-id> '{"pr_url":"<url>"}'`.
   - **If no `pr_url` in frontmatter** (e.g. `/implement` PR step failed, or legacy flow): create the PR ready-for-review:
     ```
     (cd "$WF_TASK_REPO_PATH" && gh pr create --base feat/$ARGUMENTS \
       --title "type(task-id): {task-title}" \
       --body "<body per ~/.claude/scripts/pr-body-convention.md — ## Why + ## What changed + optional mermaid>

     validation: pass")
     ```
   - **If `pr_url` exists but state is `MERGED` or `CLOSED`**: refuse and say: "PR <url> is already <state>. Nothing to ship."
8. Clear monitor context: `$HOME/.claude/scripts/monitor.sh clear_context` (non-fatal — proceed even if this fails; stale context is overwritten by the next `/implement`).
9. Save the PR URL to the task file frontmatter via `~/.claude/scripts/task-manager.sh set-pr-url <task-file> <url>` (under `single-branch`, only the final task reaches this step) (idempotent — overwrites existing value if the draft PR path above already wrote one). The task file lives in the vault/spec dir, **not** the bound repo.
10. Persist the task-file change:
    - **Single-repo mode** (`WF_SPEC_STORAGE_MODE=repo`): `git add <task-file> && git commit -m "chore(task-id): add PR URL" && git push`
    - **Vault mode**: detect whether the vault dir is itself a git repo — `vault_repo="$(git -C "$WF_REPO_ROOT" rev-parse --show-toplevel 2>/dev/null)"`. If non-empty, commit there: `git -C "$vault_repo" add "<task-file>" && git -C "$vault_repo" commit -m "chore(task-id): add PR URL" && git -C "$vault_repo" push`. If empty, print warning: "pr_url written to <task-file> but vault is not a git repo — persist manually." Do not silently skip.
11. Report the PR URL as final output.

IMPORTANT:
- Do NOT add any "Co-Authored-By" line to the commit message.
- Do NOT merge the PR — human reviews and merges.
- Remind the user: "Merge the PR, then run `/implement $ARGUMENTS` for the next task."
