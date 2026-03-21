Implement the next task for a feature.

Feature name: $ARGUMENTS

## Prerequisites
1. Check that `knowledge-base/` directory exists — if not, refuse and instruct the user to run `/bootstrap` first
2. Run `~/.claude/scripts/task-manager.sh check-unvalidated specs/$ARGUMENTS/tasks/` — if any task is `implemented` or `review`, refuse and say: "Task [ID] is awaiting validation. Run `/validate $ARGUMENTS` first."
3. Run `~/.claude/scripts/task-manager.sh next specs/$ARGUMENTS/tasks/` to find the next eligible task
   - If no eligible task found, report which tasks are blocked and by which task IDs

## Steps
1. Run `~/.claude/scripts/task-manager.sh set-status <task-file> in-progress`
2. Ensure the feature integration branch exists: `feat/$ARGUMENTS` (create from `main` if first task and push to remote: `git push -u origin feat/$ARGUMENTS`)
3. Create task branch from the integration branch: `feat/$ARGUMENTS/{task-id}-{task-name}`
4. Read the task's `ground_rules` files from `knowledge-base/`
5. Read `specs/$ARGUMENTS/spec.md` and `specs/$ARGUMENTS/design.md` for context
6. Implement the code changes following the spec and ground rules:
   - Follow architectural decisions from design.md
   - Follow language-specific patterns from knowledge-base/languages/
   - Apply security rules from knowledge-base/security/
7. Implement test bodies for the natural-language test cases defined in the task
   - Human wrote test case names in the task file
   - AI writes the test implementations
   - Use Given/When/Then structure from knowledge-base/testing/
8. Add implementation notes to the task file explaining decisions made
9. Run `~/.claude/scripts/task-manager.sh set-status <task-file> implemented`

IMPORTANT:
- Do NOT proceed to the next task automatically
- Remind the user to run `/validate $ARGUMENTS` before continuing
- Human must review and validate before the next task starts

## Error Recovery
If implementation is aborted mid-task (crash, user cancels), the task is stuck at `in-progress`. The user can manually edit the task file's YAML frontmatter to reset `status` back to `todo` and clean up the partial branch.
