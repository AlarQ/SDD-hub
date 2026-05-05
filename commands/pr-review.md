Fetch and respond to PR review comments, with agent-powered code review analysis.

Feature name: $ARGUMENTS

**Note:** PR review fixes do NOT trigger re-validation. The PR reviewer is the safety net at this stage. Task status remains `done` — if a PR reviewer finds an issue, it is handled entirely within the PR, no task state change needed.

## Prerequisites
1. Read and follow `~/.claude/knowledge-base-rules.md` for knowledge base prerequisites and resolution rules
2. Identify the task: extract task ID from the current branch name (`feat/$ARGUMENTS/{task-id}-{task-name}`) and read the matching task file from `specs/$ARGUMENTS/tasks/`
   - If not on a task branch, check if `$ARGUMENTS` was provided and look for `done` tasks with a `pr_url` — use the most recently shipped one
   - If no task can be identified, refuse and say: "Cannot determine which task this PR belongs to. Run from a task branch or provide the feature name."
3. Read the task's `ground_rules`, resolving prefixes per `~/.claude/knowledge-base-rules.md`

## Step 0 — Load Spec Config

Load the spec config before spawning any agent (substitute actual feature name for `$ARGUMENTS`):

```bash
bash -c 'source ~/.claude/scripts/config-loader.sh && wf_load_config --spec $ARGUMENTS && printf "WF_SPEC_AGENTS_PR_REVIEW=%s\n" "${WF_SPEC_AGENTS_PR_REVIEW:-}"'
```

> See `~/.claude/scripts/step0-load-config.md` for canonical invocation and remediation. This step uses: `WF_SPEC_AGENTS_PR_REVIEW`.

If `WF_SPEC_AGENTS_PR_REVIEW` is non-empty, spawn those agent IDs instead of the default `engineering-code-reviewer`. Resolve each ID per the Agent ID grammar in `design.md §Backend Design §Agent ID grammar`. Unknown ID → stop with error.

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
4. On reject: follow up with one `AskUserQuestion` call carrying two questions — (a) free-text "Reason?" and (b) "Promote to project KB rule?" `Yes`/`No`. Update KB only if Yes.
5. After all agent findings are resolved, commit accepted fixes (if any) with message referencing the agent review

## Phase 2: Human PR Comments

1. Get current branch and PR number via `gh pr view --json number`
   - If no PR exists for the current branch, try using the task's `pr_url` from frontmatter
2. Fetch comments via `gh api repos/{owner}/{repo}/pulls/{number}/comments`
3. For each unresolved comment:
   - Read the referenced file and lines
   - Read the task's `ground_rules` files (per `knowledge-base-rules.md`)
   - Generate a fix proposal with: description, code_snippet, status: pending
4. For each proposal: print proposal details, then invoke `AskUserQuestion` (per `~/.claude/scripts/ask-user-protocol.md`) — "Accept this proposal?" options: `Accept`, `Reject`. One tool call per proposal.
5. On accept: apply fix, commit with reference to comment
6. On reject: follow up with one `AskUserQuestion` call — free-text "Reason?" and `Yes`/`No` "Promote to project KB rule?". Update KB only if Yes.
