---
name: pr-review
description: Fetch and respond to PR review comments with agent-powered analysis
agent: 'agent'
argument-hint: "feature name"
---

Fetch and respond to PR review comments, with agent-powered code review analysis.

The user should provide the feature name in their message.

**Note:** PR review fixes do NOT trigger re-validation. The PR reviewer is the safety net at this stage. Task status remains `done` — if a PR reviewer finds an issue, it is handled entirely within the PR, no task state change needed.

## Prerequisites
1. Check that `knowledge-base/_general/` (general) exists — if not, refuse and say: "General knowledge base not found. Run `setup-copilot.sh` from the dev-workflow repo first."
2. Check that `knowledge-base/` (project) exists with project-specific files — if not, refuse and instruct the user to run `/bootstrap` first
3. Identify the task: extract task ID from the current branch name (`feat/<feature>/{task-id}-{task-name}`) and read the matching task file from `specs/<feature>/tasks/`
   - If not on a task branch, check if the feature name was provided and look for `done` tasks with a `pr_url` — use the most recently shipped one
   - If no task can be identified, refuse and say: "Cannot determine which task this PR belongs to. Run from a task branch or provide the feature name."
4. Read the task's `ground_rules` to know which knowledge-base rules apply, resolving prefixes: `general:` → `knowledge-base/_general/`, `project:` → `knowledge-base/`, unprefixed → `project:`

## Phase 1: Agent-Powered Code Review

Invoke `@code-reviewer` to analyze the PR diff proactively — before responding to human comments. Provide the agent:
- The full PR diff (`git diff <base-branch>...HEAD`)
- The task file (scope, acceptance criteria, ground rules)
- All `ground_rules` files referenced in the task (resolved from both general and project KBs)
- The project's CLAUDE.md or copilot-instructions.md

### Agent Output Contract
The agent returns findings using its structured output schema (PR Review Output section). All findings use `source: llm`.

If the agent errors or is unavailable, report the failure to the user and proceed directly to Phase 2 (human PR comments).

### Presenting Agent Findings
1. Group findings by priority: blockers first, then suggestions, then nits
2. Present each finding to the human for accept/reject
3. On accept: apply fix, stage the change
4. On reject: note reasoning, optionally add as project knowledge-base rule (`knowledge-base/`) if the rejection reveals a project convention
5. After all agent findings are resolved, commit accepted fixes (if any) with message referencing the agent review

## Phase 2: Human PR Comments

1. Get current branch and PR number via `gh pr view --json number`
   - If no PR exists for the current branch, try using the task's `pr_url` from frontmatter
2. Fetch comments via `gh api repos/{owner}/{repo}/pulls/{number}/comments`
3. For each unresolved comment:
   - Read the referenced file and lines
   - Read the task's `ground_rules` files from both knowledge bases (resolving prefixes)
   - Generate a fix proposal with: description, code_snippet, status: pending
4. Present each proposal for human accept/reject
5. On accept: apply fix, commit with reference to comment
6. On reject: note reasoning, optionally update project knowledge-base (`knowledge-base/`)
