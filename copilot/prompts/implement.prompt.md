---
name: implement
description: Implement the next task for a feature
agent: 'agent'
argument-hint: "feature name"
---

Implement the next task for a feature.

The user should provide the feature name in their message.

## Prerequisites
1. Check that `knowledge-base/_general/` (general) exists — if not, refuse and say: "General knowledge base not found. Run `setup-copilot.sh` from the dev-workflow repo first."
2. Check that `knowledge-base/` (project) exists with project-specific files — if not, refuse and instruct the user to run `/bootstrap` first
3. Run `./scripts/task-manager.sh check-unvalidated specs/<feature>/tasks/` — if any task is `implemented` or `review`, refuse and say: "Task [ID] is awaiting validation. Run `/validate <feature>` first."
4. Run `./scripts/task-manager.sh next specs/<feature>/tasks/` to find the next eligible task
   - If no eligible task found, report which tasks are blocked and by which task IDs
5. Check if any `done` tasks have an unmerged PR:
   - For each task with `status: done` and a `pr_url` in frontmatter, check: `gh pr view <pr_url> --json state --jq .state`
   - If any PR state is `OPEN`, refuse and say: "Task [ID] PR is not yet merged into `feat/<feature>`. Merge it before starting the next task."
   - If any `done` task has no `pr_url`, refuse and say: "Task [ID] is done but has no PR. Run `/ship <feature>` first."

## Ground Rules Resolution
Resolve `ground_rules` paths using the prefix convention:
- `general:` prefix → read from `knowledge-base/_general/` (e.g., `general:security/general.md`)
- `project:` prefix → read from `knowledge-base/` (e.g., `project:languages/rust.md`)
- Unprefixed paths → default to `project:` (backward compatibility)

## Steps
1. Run `./scripts/task-manager.sh set-status <task-file> in-progress`
2. Ensure the feature integration branch exists: `feat/<feature>` (create from `main` if first task and push to remote: `git push -u origin feat/<feature>`)
3. Pull latest feature branch: `git checkout feat/<feature> && git pull`
4. Check if task branch already exists: `git rev-parse --verify feat/<feature>/{task-id}-{task-name}`
   - If it exists, ask the user: "Task branch `feat/<feature>/{task-id}-{task-name}` already exists (likely from a previous aborted attempt). Delete it and start fresh, or continue on the existing branch?"
   - If starting fresh: delete the branch (`git branch -D feat/<feature>/{task-id}-{task-name}`) and create a new one
   - If continuing: checkout the existing branch and proceed
5. Create task branch from the integration branch: `feat/<feature>/{task-id}-{task-name}`
6. Read the task's `ground_rules` files from both knowledge bases (resolving prefixes per the convention above)
7. Read `specs/<feature>/spec.md` and `specs/<feature>/design.md` for context
8. Implement the code changes following the spec and ground rules:
   - Follow architectural decisions from design.md
   - Follow language-specific patterns from knowledge-base/languages/
   - Apply security rules from `knowledge-base/_general/security/` and project security rules (if any)
   - **On error or test failure** — invoke `@ultrathink-debugger` with the error output, relevant source files, and task context. The agent returns structured diagnosis with root cause and proposed fix. Present the agent's diagnosis and proposed fix to the user. On accept: apply the fix and continue. On reject or if the agent cannot resolve the issue: report the failure to the user and pause for guidance.
9. If `specs/<feature>/test-strategy.md` exists, invoke `@test-strategist` (if available) before writing test bodies. Provide:
   - The test-strategy.md content
   - The current task file (with test_cases)
   - Existing test files from completed tasks (check files changed in merged task branches on `feat/<feature>`)
   
   Directive: "Review this task's test cases against the test strategy and existing test coverage from completed tasks. For each test case, determine: keep, skip (already covered), or modify. Add any missing integration seam tests assigned to this task. List shared fixtures available from completed tasks. Use the Implementation Refinement Output format."
   
   Apply the output: skip covered tests, modify as directed, add missing integration tests, reuse shared fixtures.
   
   If the agent is unavailable or test-strategy.md does not exist, implement all test cases from the task file as-is.
10. Implement test bodies for the (filtered) test cases
   - Use the refined test list from step 9 if available, otherwise use the task file's test_cases as-is
   - AI writes the test implementations
   - Use Given/When/Then structure from `knowledge-base/_general/testing/`
11. Add implementation notes to the task file explaining decisions made

## Post-Implementation Quality Check
After all code and tests are written (before setting status to `implemented`), invoke `@code-quality` for a pre-validation sanity check. Provide:
- All changed files (`git diff --name-only --diff-filter=ACMR feat/<feature>...HEAD`)
- The task file (scope, ground rules)
- The project's CLAUDE.md or copilot-instructions.md

Instruct the agent to use its YAML validation-gate output format so findings have structured severity levels. Mark all findings with `source: llm`.

If the agent returns findings with **high or critical** severity:
1. Present each issue to the user with the agent's recommendation
2. On accept: apply the fix before marking the task as implemented
3. On reject: note the reasoning and proceed

Low and medium severity findings are logged but do not block — `/validate` will catch them.

If the agent errors or is unavailable, proceed without the quality check and note the limitation.

This is a lightweight pre-flight check — `/validate` remains the authoritative validation step.

12. Run `./scripts/task-manager.sh set-status <task-file> implemented`

IMPORTANT:
- Do NOT proceed to the next task automatically
- Remind the user to run `/validate <feature>` before continuing
- Human must review and validate before the next task starts

## Error Recovery
If implementation is aborted mid-task (crash, user cancels), the task is stuck at `in-progress`. The user can manually edit the task file's YAML frontmatter to reset `status` back to `todo` and clean up the partial branch. If the post-implementation quality check was in progress, any accepted fixes will already be on the branch.
