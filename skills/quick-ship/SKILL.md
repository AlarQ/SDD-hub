---
name: quick-ship
description: Ship current changes: commit, push, and create a PR. Works in any git repo without the spec-driven workflow.
disable-model-invocation: false
args:
  - name: branch-or-title
    description: Optional branch name or PR title (used as $ARGUMENTS in body)
    required: false
---

Optional: branch name or PR title via $ARGUMENTS

## Prerequisites
1. Verify we're in a git repository — if not, refuse and stop.

### Vault-mode preflight

Source the loader first:

```bash
source ~/.claude/scripts/config-loader.sh 2>/dev/null && wf_load_config 2>/dev/null || true
```

If `WF_SPEC_STORAGE_MODE=vault`:
1. Parse `$ARGUMENTS` for `--repo <name>` (any position). Strip the flag and value before treating the remainder as branch name / PR title. Refuse if `--repo` appears without a value.
2. Without `--repo <name>`, refuse: "Vault config detected — pass `--repo <name>` to pick a bound repo (one of: $WF_REPO_NAMES)."
3. Resolve `target_path="$(wf_repo_path "$name")"` — must succeed (loader exit 7 / function rc 1 on unknown).
4. Vault `repos[]` lives in per-spec `config.yml`, not `.workflow.yml`. For `/quick-ship` (which is spec-less), resolve `<name>` against `default_repos[]` from `.workflow.yml`. Validate the name shape *before* feeding it into yq (no interpolation; use `strenv()`):
   ```bash
   [[ "$name" =~ ^[a-z0-9][a-z0-9_-]{0,31}$ ]] || { echo "ERROR: --repo name invalid" >&2; exit 1; }
   target_path="$(name="$name" yq -r '.default_repos[] | select(.name == strenv(name)) | .path' "$WF_CONFIG_FILE" | head -1)"
   [[ -z "$target_path" || "$target_path" == "null" ]] && { echo "ERROR: --repo '$name' not in .workflow.yml default_repos[]" >&2; exit 1; }
   target_path="${target_path/#\~/$HOME}"
   toplevel="$(git -C "$target_path" rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: $target_path not a git work tree" >&2; exit 1; }
   [[ "$(cd "$target_path" && pwd -P)" == "$(cd "$toplevel" && pwd -P)" ]] || { echo "ERROR: $target_path is inside repo $toplevel, not the toplevel" >&2; exit 1; }
   ```
5. All subsequent `git` / `gh` ops in this command run as `git -C "$target_path"` and `(cd "$target_path" && gh ...)`.
2. Check for shippable work (at least one must be true):
   - Staged changes exist
   - Unstaged changes exist
   - Unpushed commits on current branch
   - If none of the above, report "Nothing to ship" and stop
3. Scan `git status` and `git diff --cached --name-only` for sensitive files (.env, .env.*, credentials*, secrets*, *-key.pem, *.key, *.p12). If any match, present them to the user via the `AskUserQuestion` tool with options "Abort" (default — recommended) and "Proceed anyway". Stop on Abort.

## Steps

### 1. Assess current state
- Run `git status`, `git diff --stat`, and `git log @{upstream}..HEAD --oneline 2>/dev/null` to understand what will be shipped
- Determine the default branch: `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'` — fall back to `main`, then `master`

### 2. Handle branching
- **If on the default branch (main/master):**
  - Create a new branch before committing
  - Use `$ARGUMENTS` as branch name if provided; otherwise generate a short descriptive name from the changes (e.g., `fix/null-check-in-parser`, `feat/add-user-export`)
  - `git checkout -b <branch-name>`
- **If already on a feature branch:**
  - Stay on it
  - Check if a PR already exists for this branch: `gh pr view --json url 2>/dev/null`

### 3. Stage and commit
- If there are unstaged changes, stage them: `git add -A`
- If there are staged changes (either pre-staged or just staged), commit:
  - Analyze the diff to write a concise, descriptive commit message
  - Use conventional commit format: `type: description` (feat, fix, refactor, docs, chore, test, style)
  - Do NOT add any "Co-Authored-By" line
- If working tree is clean but unpushed commits exist, skip to push

### 4. Push
- `git push -u origin <current-branch>`

### 5. Create or update PR
- **If no PR exists for this branch:**
  ```
  gh pr create --base <default-branch> \
    --title "<conventional commit format title matching the commit>" \
    --body "<body per ~/.claude/scripts/pr-body-convention.md — ## Why + ## What changed + optional mermaid; no footer (no gates in quick-ship)>"
  ```
  - Use `$ARGUMENTS` as PR title if provided and a branch was not created from it
- **If a PR already exists:**
  - Report that new commits were pushed to the existing PR
  - Show the existing PR URL

### 6. Report
- Output the PR URL
- Show a one-line summary of what was shipped (files changed, insertions, deletions)

## Important
- Do NOT add any "Co-Authored-By" line to the commit message
- Do NOT merge the PR — human reviews and merges
- Do NOT require knowledge-base/, specs/, or any workflow artifacts
- This command works in any git repo
