Walk through validation findings interactively.

Feature name: $ARGUMENTS

## Prerequisites
1. Read and follow `~/.claude/knowledge-base-rules.md` for knowledge base prerequisites and resolution rules

## Steps
1. Read all pending reports from `specs/$ARGUMENTS/reports/`
2. Partition findings: separate `severity: info` findings (informational) from all others (actionable)
3. For each **actionable** finding (severity != info) with review_status: pending:
   - Present: severity, title, description, code snippet, fix proposal, source (tool/llm)
   - Ask: Accept or Reject?
   - If Accept: apply the fix, **re-read the file** before applying the next fix (sequential apply to avoid conflicts), update review_status to "accepted"
   - If Reject: ask for reasoning, update review_status to "rejected", set review_notes
   - If Reject + new rule needed: create/update the relevant file in the **project** knowledge-base (`knowledge-base/`) and update `knowledge-base/_index.md`, set rule_added: true. Never modify the general knowledge base (`~/.claude/knowledge-base/`).
4. Set review_status to "noted" on all informational findings
5. Display informational summary — compact list: title, file, and one-line description for each
6. Report summary: X accepted, Y rejected, Z noted (informational), W new rules added

## Status Update
- If any fixes were applied (accepted actionable findings — informational findings do not count): ask the user whether they want to re-run `/validate $ARGUMENTS` or skip re-validation and proceed to shipping.
  - If user wants re-validation: delete all reports (`rm -rf specs/$ARGUMENTS/reports/`), run `~/.claude/scripts/task-manager.sh set-status <task-file> implemented` and remind user to run `/validate $ARGUMENTS`
  - If user wants to skip: run `~/.claude/scripts/task-manager.sh set-status <task-file> done`, then run `~/.claude/scripts/task-manager.sh unblock specs/$ARGUMENTS/tasks/`, then delete all reports (`rm -rf specs/$ARGUMENTS/reports/`), then remind user to run `/ship $ARGUMENTS`
- If no fixes were applied (all findings rejected or already clean): run `~/.claude/scripts/task-manager.sh set-status <task-file> done`, then run `~/.claude/scripts/task-manager.sh unblock specs/$ARGUMENTS/tasks/`, then delete all reports (`rm -rf specs/$ARGUMENTS/reports/`), then remind user to run `/ship $ARGUMENTS`
