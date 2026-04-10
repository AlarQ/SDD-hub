Ship current changes: commit, push, and create a PR. Works in any git repo without the spec-driven workflow.

Optional: branch name or PR title via $ARGUMENTS

## Prerequisites
1. Verify we're in a git repository — if not, refuse and stop
2. Check for shippable work (at least one must be true):
   - Staged changes exist
   - Unstaged changes exist
   - Unpushed commits on current branch
   - If none of the above, report "Nothing to ship" and stop
3. Scan `git status` and `git diff --cached --name-only` for sensitive files (.env, .env.*, credentials*, secrets*, *-key.pem, *.key, *.p12) — if found, warn the user and ask whether to proceed

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
    --body "<summary of all changes in the branch>"
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
