Walk through validation findings interactively.

Feature name: $ARGUMENTS

## Prerequisites
1. Check that `~/.claude/knowledge-base/` (general) exists — if not, refuse and say: "General knowledge base not found. Run `setup.sh` from the dev-workflow repo first."
2. Check that `knowledge-base/` (project) exists — if not, refuse and instruct the user to run `/bootstrap` first

## Steps
1. Read all pending reports from `specs/$ARGUMENTS/reports/`
2. For each finding with review_status: pending:
   - Present: severity, title, description, code snippet, fix proposal, source (tool/llm)
   - Ask: Accept or Reject?
   - If Accept: apply the fix, **re-read the file** before applying the next fix (sequential apply to avoid conflicts), update review_status to "accepted"
   - If Reject: ask for reasoning, update review_status to "rejected", set review_notes
   - If Reject + new rule needed: create/update the relevant file in the **project** knowledge-base (`knowledge-base/`) and update `knowledge-base/_index.md`, set rule_added: true. Never modify the general knowledge base (`~/.claude/knowledge-base/`).
3. Report summary: X accepted, Y rejected, Z new rules added

## Status Update
- If any fixes were applied (accepted findings): ask the user whether they want to re-run `/validate $ARGUMENTS` or skip re-validation and proceed to shipping.
  - If user wants re-validation: delete all reports (`rm -rf specs/$ARGUMENTS/reports/`), run `~/.claude/scripts/task-manager.sh set-status <task-file> implemented` and remind user to run `/validate $ARGUMENTS`
  - If user wants to skip: run `~/.claude/scripts/task-manager.sh set-status <task-file> done`, then run `~/.claude/scripts/task-manager.sh unblock specs/$ARGUMENTS/tasks/`, then delete all reports (`rm -rf specs/$ARGUMENTS/reports/`), then remind user to run `/ship $ARGUMENTS`
- If no fixes were applied (all findings rejected or already clean): run `~/.claude/scripts/task-manager.sh set-status <task-file> done`, then run `~/.claude/scripts/task-manager.sh unblock specs/$ARGUMENTS/tasks/`, then delete all reports (`rm -rf specs/$ARGUMENTS/reports/`), then remind user to run `/ship $ARGUMENTS`
