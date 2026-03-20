Fetch and respond to PR review comments.

**Note:** PR review fixes do NOT trigger re-validation. The PR reviewer is the safety net at this stage. Task status remains `done` — if a PR reviewer finds an issue, it is handled entirely within the PR, no task state change needed.

## Prerequisites
1. Check that `knowledge-base/` directory exists — if not, refuse and instruct the user to run `/bootstrap` first

## Steps
1. Get current branch and PR number via `gh pr view --json number`
2. Fetch comments via `gh api repos/{owner}/{repo}/pulls/{number}/comments`
3. For each unresolved comment:
   - Read the referenced file and lines
   - Read applicable knowledge-base/ rules
   - Generate a fix proposal with: description, code_snippet, status: pending
4. Present each proposal for human accept/reject
5. On accept: apply fix, commit with reference to comment
6. On reject: note reasoning, optionally update knowledge-base/
