---
name: pr-review
description: Read the current PR's review comments and address them.
disable-model-invocation: false
args:
  - name: pr-number
    description: PR number, optional — resolved from current git branch if omitted (used as $ARGUMENTS in body)
    required: false
---

Optional argument: a PR number to target. If omitted, the PR is resolved from the current git branch.

PR number (optional): $ARGUMENTS

This command reads a PR's comments, sorts each into **informational** (asking for an explanation/answer) or **change** (requesting a code change), and addresses each accordingly — posting a `[claude]` reply on every comment it handles. Task status is unchanged; everything happens on the PR.

## 1. Resolve the PR

- First, fail-fast on auth: run `gh auth status`; if not authenticated, exit with "Run `gh auth login` first."
- If `$ARGUMENTS` is a PR number, use it. Otherwise resolve from the current branch:
  ```bash
  gh pr view --json number,state,isDraft,headRepository
  ```
- `OWNER_REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)`
- `ME=$(gh api user --jq .login)`
- Remaining fail-fast checks (each fatal, with explicit message):
  - No PR for the current branch → exit with "No PR found for this branch. Pass a PR number or open a PR first."
  - PR state not `OPEN` → exit with "PR is <state>. Nothing to address."

## 2. Fetch comments (review + issue)

```bash
PR=<number>
gh api "repos/$OWNER_REPO/pulls/$PR/comments" > /tmp/pr-review-comments.json
gh api "repos/$OWNER_REPO/issues/$PR/comments" > /tmp/pr-issue-comments.json
```

- Review comments (`pulls/.../comments`) have `path`, `line`, `in_reply_to_id` — anchored to a file/line.
- Issue comments (`issues/.../comments`) are PR-wide, no file/line.

## 3. Filter out bot/self input

Skip any comment where:
- `user.login == $ME` (don't reply to your own threads), or
- the body starts with `[claude]` (a previous reply from this command).

There is no reaction-based dedup — re-running the command re-processes any human comment that is still open; use `Skip` in the loop below for ones you've already handled.

## 4. Classify each remaining comment (inline)

For each comment, label it using the comment body plus the PR diff (`git diff <base>...HEAD`, base = the PR's base branch):

- **`informational`** — asks a question or requests an explanation; no code change needed.
- **`change`** — requests a code modification.

(Old `nit` comments are just small `change`s.)

Print a one-line-per-comment classification table (id, kind `review|issue`, type, one-line summary) before the loop.

## 5. Per-comment loop

For each classified comment, invoke `AskUserQuestion` (per `~/.claude/scripts/ask-user-protocol.md`) — one tool call per comment with options `Apply`, `Re-classify`, `Skip`. On `Re-classify`, follow up with options `informational`, `change`, `skip`.

Reply and (for changes) commit per the comment's `kind`:

- **`review`** comment → threaded reply:
  ```bash
  gh api "repos/$OWNER_REPO/pulls/$PR/comments" -f body="[claude] …" -F in_reply_to=<id>
  ```
- **`issue`** comment → top-level reply quoting the original:
  ```bash
  gh pr comment $PR --body "[claude] re: <short-quote>

  <reply body>"
  ```

### Actions

- **`informational`**: compose a direct answer (grounded in the code), post the reply:
  ```
  [claude] <direct answer in 1-3 sentences>.
  Source: <file:line> | (none — design choice)
  ```

- **`change`**: apply the code change (Edit/Write), then stage **only the files you just edited** for this comment (not `git add -A` — avoid sweeping in unrelated dirty files), commit, and push:
  ```bash
  git add <files edited for this comment> && git commit -m "pr-review: address comment <id>"
  git push   # upstream already exists — the command required an OPEN PR for this branch
  ```
  Reply citing the resulting short-sha:
  ```
  [claude] addressed in <short-sha>.
  What: <bullet list of changes>
  How: <one-line technique / approach>
  ```

## 6. Tail

After the loop:
- If any comments were `Skip`ped → print: "Some comments deferred. Re-run `/pr-review` after addressing, or run `/validate` to proceed regardless."
- Else → print: "All comments addressed. Run `/validate` next."

Never auto-invoke the next command.
