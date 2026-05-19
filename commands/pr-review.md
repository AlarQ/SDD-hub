Fetch and respond to PR review comments, with agent-powered code review analysis.

Feature name: $ARGUMENTS

**Note:** `/pr-review` runs against the **draft PR** opened by `/implement` (pre-validation human review loop) or against a ready PR opened by `/ship`. In both cases, task status is unchanged — comment resolution happens entirely on the PR. The loop is idempotent: comments already addressed (marked with a Claude-authored `eyes` reaction on the original comment) are skipped on re-runs.

## Prerequisites
1. Read and follow `$WF_GENERAL_KB/_rules.md` for knowledge base prerequisites and resolution rules
2. Identify the task: extract task ID from the current branch name (`feat/$ARGUMENTS/{task-id}-{task-name}`) and read the matching task file from `specs/$ARGUMENTS/tasks/`
   - If not on a task branch, check if `$ARGUMENTS` was provided and look for `done` tasks with a `pr_url` — use the most recently shipped one
   - If no task can be identified, refuse and say: "Cannot determine which task this PR belongs to. Run from a task branch or provide the feature name."
3. Read the task's `ground_rules`, resolving prefixes per `$WF_GENERAL_KB/_rules.md`

## Step 0 — Load Spec Config

Load the spec config before spawning any agent (substitute actual feature name for `$ARGUMENTS`):

```bash
bash -c 'source ~/.claude/scripts/config-loader.sh && wf_load_config --spec $ARGUMENTS && printf "WF_SPEC_AGENTS_PR_REVIEW=%s\n" "${WF_SPEC_AGENTS_PR_REVIEW:-}"'
```

> See `~/.claude/scripts/step0-load-config.md` for canonical invocation and remediation. This step uses: `WF_SPEC_AGENTS_PR_REVIEW`.

If `WF_SPEC_AGENTS_PR_REVIEW` is non-empty, spawn those agent IDs instead of the default `engineering-code-reviewer`. Resolve each ID per the Agent ID grammar in `design.md §Backend Design §Agent ID grammar`. Unknown ID → stop with error.

### Multi-repo resolution

After Step 0, resolve the task's bound repo per `~/.claude/scripts/multi-repo-resolution.md` → sets `WF_TASK_REPO_PATH`. Code Reviewer (and any agent in `WF_SPEC_AGENTS_PR_REVIEW`) receives `WF_TASK_REPO_PATH` plus the diff scoped to that repo (`git -C "$WF_TASK_REPO_PATH" diff <base>...HEAD`). All `gh pr` calls run from inside `WF_TASK_REPO_PATH` so they target the right remote.

If the task identification step fell back to "most recent shipped task", read its `repo:` field from the task file before proceeding.

## Phase 1: Agent-Powered Code Review

Spawn the agent(s) from `WF_SPEC_AGENTS_PR_REVIEW` (if non-empty) or fall back to the default `Code Reviewer` agent (`engineering-code-reviewer`) when the list is empty. The agent(s) receive:
- The full PR diff (`git diff <base-branch>...HEAD`)
- The task file (scope, acceptance criteria, ground rules)
- All `ground_rules` files referenced in the task (per `knowledge-base-rules.md`)
- The project's `CLAUDE.md`

### Agent Output Contract
The agent must return findings using the structured output schema defined in the `Code Reviewer` agent definition (`📤 PR Review Output` section). All findings use `source: llm`.

If the agent errors or times out, report the failure to the user and proceed directly to Phase 2 (human PR comments).

### Presenting Agent Findings
1. Group findings by priority: blockers first, then suggestions, then nits
2. For each finding: print the finding details as plain output, then invoke `AskUserQuestion` (per `~/.claude/scripts/ask-user-protocol.md`) — "Accept this fix?" options: `Accept`, `Reject`. One tool call per finding. Do NOT render accept/reject as a markdown question.
3. On accept: apply fix, stage the change
4. On reject: follow up with one `AskUserQuestion` call carrying two questions — (a) free-text "Reason?" and (b) "Promote to general KB rule?" `Yes`/`No`. Write to `$WF_GENERAL_KB/` only if Yes.
5. After all agent findings are resolved, commit accepted fixes (if any) with message referencing the agent review

## Phase 2: Human PR Comments — Classify & Address Loop

This phase reads PR comments, classifies each (`question | task | nit | already-addressed`), executes them, and posts threaded `[claude]` replies on the original comment thread. Addressed comments are marked with an `eyes` reaction (by the current `gh` user) so re-running `/pr-review` only picks up new comments.

### 1. Resolve the PR

- Get PR number: `gh pr view --json number,state,isDraft` from the task branch.
- If not on a task branch, fall back to the task's `pr_url` frontmatter (per Prerequisites step 2).
- Fail-fast checks (each fatal, with explicit message):
  - `gh auth status` — if not authenticated, exit with "Run `gh auth login` first."
  - PR state not `OPEN` → exit with "PR is <state>. Nothing to address."

### 2. Fetch comments (review + issue)

```bash
PR=<number>
OWNER_REPO=<owner/repo>  # gh repo view --json nameWithOwner --jq .nameWithOwner
gh api "repos/$OWNER_REPO/pulls/$PR/comments" > /tmp/pr-review-comments.json
gh api "repos/$OWNER_REPO/issues/$PR/comments" > /tmp/pr-issue-comments.json
ME=$(gh api user --jq .login)
```

Review comments (`pulls/.../comments`) have `path`, `line`, `in_reply_to_id`. Issue comments (`issues/.../comments`) are PR-wide, no file/line.

### 3. Filter already-addressed

For each comment, check reactions:

```bash
# review comments
gh api "repos/$OWNER_REPO/pulls/comments/<id>/reactions" --jq '.[] | select(.user.login == env.ME and .content == "eyes")'
# issue comments
gh api "repos/$OWNER_REPO/issues/comments/<id>/reactions" --jq '.[] | select(.user.login == env.ME and .content == "eyes")'
```

If a matching reaction exists → skip. Also skip comments whose `user.login == $ME` (don't reply to own threads) and comments whose body starts with `[claude]`.

### 4. LLM-classify remaining comments

Spawn one classification sub-agent (general-purpose) with:
- The unaddressed comment list (id, body, file, line, hunk diff context)
- The task file (scope, ground_rules)
- The PR diff (`git -C "$WF_TASK_REPO_PATH" diff <base>...HEAD`)

Agent output (YAML):
```yaml
- id: <comment_id>
  kind: review | issue        # which API endpoint it came from
  type: question | task | nit | already-addressed
  summary: <one-line>
  proposed_action: <answer text for questions | change description for tasks/nits | commit ref for already-addressed>
```

### 5. User confirmation

Print the classification table. Then invoke `AskUserQuestion` (per `~/.claude/scripts/ask-user-protocol.md`) — one tool call per comment with options `Apply as classified`, `Re-classify`, `Skip`. On `Re-classify`, follow up with options `question`, `task`, `nit`, `skip`.

### 6. Execute per confirmed item

Reply endpoint depends on `kind`:
- `review` comments → threaded reply: `gh api repos/$OWNER_REPO/pulls/$PR/comments -f body="[claude] …" -F in_reply_to=<id>`
- `issue` comments → top-level reply quoting original: `gh pr comment $PR --body "[claude] re: <short-quote>\n\n<reply body>"`

Reaction endpoint also depends on `kind`:
- `review` → `gh api repos/$OWNER_REPO/pulls/comments/<id>/reactions -f content=eyes`
- `issue` → `gh api repos/$OWNER_REPO/issues/comments/<id>/reactions -f content=eyes`

Actions:

- **`question`**: compose an answer (LLM, grounded in code). Post threaded reply:
  ```
  [claude] <direct answer in 1-3 sentences>.
  Source: <file:line> | spec section <id> | (none — design choice)
  ```
  React `eyes` on original. Emit `pr_comment_answered`.

- **`task`**: apply code change (Edit/Write), stage, commit with message `pr-review: address comment <id>`, push to task branch. Then reply:
  ```
  [claude] addressed in <short-sha>.
  What: <bullet list of changes>
  How: <one-line technique / approach>
  ```
  React `eyes`. Emit `pr_comment_task_applied`.

- **`nit`**: same path as `task` (apply + reply with sha) OR defer:
  ```
  [claude] nit acknowledged, deferred — <reason>.
  ```
  React `eyes`. Emit `pr_comment_task_applied` or `pr_comment_skipped`.

- **`already-addressed`**: reply `[claude] already addressed in <short-sha>` (sha from `git log --oneline -S "<keyword>"` or user-provided). React `eyes`. Emit `pr_comment_skipped`.

Use `~/.claude/scripts/monitor.sh log_event $ARGUMENTS <event> <task-id> '{"comment_id":"<id>","type":"<type>"}'` for each.

### 7. Tail

After loop:
- If any remaining unaddressed comments (user chose `Skip` without acting) → print: "Some comments deferred. Re-run `/pr-review $ARGUMENTS` after addressing, or run `/validate $ARGUMENTS` to proceed regardless."
- Else → print: "All comments addressed. Run `/validate $ARGUMENTS` next."

Never auto-invoke the next command.
