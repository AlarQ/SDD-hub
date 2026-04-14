Implement the next task for a feature.

Feature name: $ARGUMENTS

## Prerequisites
1. Read and follow `~/.claude/knowledge-base-rules.md` for knowledge base prerequisites and resolution rules
2. Run `~/.claude/scripts/task-manager.sh next specs/$ARGUMENTS/tasks/` to find the next eligible task
   - If no eligible task found, report which tasks are blocked and by which task IDs
   - If any task has `status: in-progress`, warn: "Task [ID] is stuck at in-progress (likely from a crashed session). Run `/continue-task $ARGUMENTS` to resume or manually reset its status."
3. Check if any `done` tasks have an unmerged PR:
   - For each task with `status: done` and a `pr_url` in frontmatter, check: `gh pr view <pr_url> --json state --jq .state`
   - If any PR state is `OPEN`, refuse and say: "Task [ID] PR is not yet merged into `feat/$ARGUMENTS`. Merge it before starting the next task."
   - If any `done` task has no `pr_url`, refuse and say: "Task [ID] is done but has no PR. Run `/ship $ARGUMENTS` first."
   - **Important**: In bash scripts, never use `status` as a variable name — it is read-only in zsh. Use `task_status` instead.

## Steps
1. Run `~/.claude/scripts/task-manager.sh set-status <task-file> in-progress`
2. Set monitor context: run `$HOME/.claude/scripts/monitor.sh set_context "$ARGUMENTS" "<task-id>"` (replace `<task-id>` with the numeric ID from the prerequisite step, e.g. `001`)
3. Ensure the feature integration branch exists: `feat/$ARGUMENTS` (create from `main` if first task and push to remote: `git push -u origin feat/$ARGUMENTS`)
4. Pull latest feature branch: `git checkout feat/$ARGUMENTS && git pull`
5. Check if task branch already exists: `git rev-parse --verify feat/$ARGUMENTS/{task-id}-{task-name}`
   - If it exists, ask the user: "Task branch `feat/$ARGUMENTS/{task-id}-{task-name}` already exists (likely from a previous aborted attempt). Delete it and start fresh, or continue on the existing branch?"
   - If starting fresh: delete the branch (`git branch -D feat/$ARGUMENTS/{task-id}-{task-name}`) and create a new one
   - If continuing: checkout the existing branch and proceed
6. Create task branch from the integration branch: `feat/$ARGUMENTS/{task-id}-{task-name}`
7. Read the task's `ground_rules` files (per `knowledge-base-rules.md`)
8. Read `specs/$ARGUMENTS/spec.md` and `specs/$ARGUMENTS/design.md` for context
9. Implement the code changes following the spec and ground rules:
   - Follow architectural decisions from design.md
   - Follow language-specific patterns from knowledge-base/languages/
   - Apply security rules from both knowledge bases
   - **On error or test failure** → spawn the `Ultrathink Debugger` agent (`ultrathink-debugger`) with the error output, relevant source files, and task context. The agent must return its findings in the structured format defined in the agent's "Implementation Fix Output" section. Present the agent's diagnosis and proposed fix to the user. On accept: apply the fix and continue. On reject or if the agent cannot resolve the issue: report the failure to the user with the agent's diagnosis and pause for guidance.
10. If `specs/$ARGUMENTS/test-strategy.md` exists, spawn the `Test Strategist` agent (`engineering-test-strategist`) using the Agent tool before writing test bodies. The agent receives:
   - The test-strategy.md content
   - The current task file (with test_cases)
   - List of existing test files from completed tasks (find test files in the task branches already merged to `feat/$ARGUMENTS`)
   
   Instruct the agent with this directive: "Review this task's test cases against the test strategy and existing test coverage from completed tasks. For each test case, determine: keep, skip (already covered), or modify. Add any missing integration seam tests assigned to this task. List shared fixtures available from completed tasks. Use the Implementation Refinement Output format defined in your agent definition."
   
   Apply the agent's output:
   - Skip test cases marked as `skip` (already covered by completed tasks)
   - Modify test cases as directed
   - Add new integration tests the agent identifies
   - Reuse shared fixtures instead of recreating test data
   
   If the agent errors or times out, or if test-strategy.md does not exist, proceed with all test cases from the task file as-is and note: *"Test Strategist refinement unavailable — implementing all test cases from task file."*
11. Implement test bodies for the (filtered) test cases
   - Use the refined test list from step 10 if available, otherwise use the task file's test_cases as-is
   - AI writes the test implementations
   - Use Given/When/Then structure from testing knowledge-base rules
12. Add implementation notes to the task file explaining decisions made

## Post-Implementation Quality Check
After all code and tests are written (before setting status to `implemented`), spawn the `Code Quality Pragmatist` agent (`code-quality-pragmatist`) for a pre-validation sanity check. The agent receives:
- All changed files (`git diff --name-only --diff-filter=ACMR feat/$ARGUMENTS...HEAD`)
- The task file (scope, ground rules)
- The project's `CLAUDE.md`

Instruct the agent to use its YAML validation-gate output format (not the standalone prose format) so findings have structured severity levels. Mark all findings with `source: llm`.

If the agent returns findings with **high or critical** severity:
1. Present each issue to the user with the agent's recommendation
2. On accept: apply the fix before marking the task as implemented
3. On reject: note the reasoning and proceed

Low and medium severity findings are logged but do not block — `/validate` will catch them.

If the agent errors or times out, proceed without the quality check and note the failure.

This is a lightweight pre-flight check — `/validate` remains the authoritative validation step.

13. Run `~/.claude/scripts/task-manager.sh set-status <task-file> implemented`

IMPORTANT:
- Do NOT start the next task automatically — serial execution, one task in flight at a time.
- DO auto-chain into validation for the current task: read and follow `~/.claude/commands/validate.md` with the same $ARGUMENTS value. `/validate` then chains into `/review-findings` (if findings) or `/ship` (zero findings).

## Error Recovery
If implementation is aborted mid-task (crash, user cancels), the task is stuck at `in-progress`. The user can manually edit the task file's YAML frontmatter to reset `status` back to `todo` and clean up the partial branch. If the post-implementation quality check was in progress, any accepted fixes will already be on the branch.
