Fetch and respond to PR review comments.

Feature name: $ARGUMENTS

**Note:** PR review fixes do NOT trigger re-validation. The PR reviewer is the safety net at this stage. Task status remains `done` — if a PR reviewer finds an issue, it is handled entirely within the PR, no task state change needed.

## Prerequisites
1. Check that `knowledge-base/` directory exists — if not, refuse and instruct the user to run `/bootstrap` first
2. Identify the task: extract task ID from the current branch name (`feat/$ARGUMENTS/{task-id}-{task-name}`) and read the matching task file from `specs/$ARGUMENTS/tasks/`
   - If not on a task branch, check if `$ARGUMENTS` was provided and look for `done` tasks with a `pr_url` — use the most recently shipped one
   - If no task can be identified, refuse and say: "Cannot determine which task this PR belongs to. Run from a task branch or provide the feature name."
3. Read the task's `ground_rules` to know which knowledge-base rules apply

## Steps
1. Get current branch and PR number via `gh pr view --json number`
   - If no PR exists for the current branch, try using the task's `pr_url` from frontmatter
2. Fetch comments via `gh api repos/{owner}/{repo}/pulls/{number}/comments`
3. For each unresolved comment:
   - Read the referenced file and lines
   - Read the task's `ground_rules` files from knowledge-base/
   - Generate a fix proposal with: description, code_snippet, status: pending
4. Present each proposal for human accept/reject
5. On accept: apply fix, commit with reference to comment
6. On reject: note reasoning, optionally update knowledge-base/
