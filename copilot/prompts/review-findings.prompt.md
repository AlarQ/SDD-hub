---
name: review-findings
description: Walk through validation findings interactively
agent: 'agent'
argument-hint: "feature name"
---

Walk through validation findings interactively.

The user should provide the feature name in their message.

## Prerequisites
1. Check that `knowledge-base/_general/` (general) exists — if not, refuse and say: "General knowledge base not found. Run `setup-copilot.sh` from the dev-workflow repo first."
2. Check that `knowledge-base/` (project) exists with project-specific files — if not, refuse and instruct the user to run `/bootstrap` first

## Steps
1. Read all pending reports from `specs/<feature>/reports/`
2. Partition findings: separate `severity: info` findings (informational) from all others (actionable)
3. Group actionable findings before presenting them:
   a. Sort all actionable findings by file path, then by start line.
   b. **Pass 1 — Line proximity:** For findings targeting the same `file`, merge into one group if their `lines` ranges overlap or are within 5 lines of each other. Apply transitive closure: if finding C overlaps with B which is already grouped with A, C joins the {A, B} group.
   c. **Pass 2 — Same-file category match:** For still-ungrouped findings in the same file that share an identical `category` value, merge them into one group.
   d. Remaining ungrouped findings each become a singleton group.
   e. Sort groups by: highest severity within the group (critical > high > medium > low), then file path alphabetically.
4. Present **one group at a time**. Show a progress header: "Group 1 of G (N total findings)".
   For each group:
   - List all findings in the group: for each, show severity, title, gate (source report), description, code snippet, and fix proposal. Visually separate findings within the group but present them as one review unit.
   - If the group has multiple findings, show a brief note: "These N findings target the same code region in `<file>` and are grouped for a single decision."
   - Ask: **Accept all / Reject all?** Do NOT offer partial accept within a group — the fixes are interrelated.
   - **Stop and wait for user response before continuing to the next group.**
   - If Accept: apply the fix, **re-read the file** before applying the next fix (sequential apply to avoid conflicts), apply fixes in reverse line order (highest line number first) to avoid offset drift, update review_status to "accepted" on all findings in the group
   - If Reject: ask for reasoning, update review_status to "rejected" and set review_notes on ALL findings in the group.
   - If Reject + new rule needed: create/update the relevant file in the **project** knowledge-base (`knowledge-base/`) and update `knowledge-base/_index.md`, set rule_added: true on the relevant finding(s). Never modify the general knowledge base (`knowledge-base/_general/`).
   - After processing, show running tally: "X accepted, Y rejected so far"

   > **Note:** The Claude Code version of this command spawns background sub-agents for accepted fixes, enabling parallel fix application. Copilot lacks the Agent tool, so fixes are applied inline sequentially here.

5. Set review_status to "noted" on all informational findings
6. Display informational summary — compact list: title, file, and one-line description for each
7. Report summary: X groups accepted (N findings), Y groups rejected (M findings), Z noted (informational), W new rules added

## Status Update
- If any fixes were applied (accepted actionable findings — informational findings do not count): ask the user whether they want to re-run `/validate <feature>` or skip re-validation and proceed to shipping.
  - If user wants re-validation: delete all reports (`rm -rf specs/<feature>/reports/`), run `./scripts/task-manager.sh set-status <task-file> implemented` and remind user to run `/validate <feature>`
  - If user wants to skip: run `./scripts/task-manager.sh set-status <task-file> done`, then run `./scripts/task-manager.sh unblock specs/<feature>/tasks/`, then delete all reports (`rm -rf specs/<feature>/reports/`), then remind user to run `/ship <feature>`
- If no fixes were applied (all findings rejected or already clean): run `./scripts/task-manager.sh set-status <task-file> done`, then run `./scripts/task-manager.sh unblock specs/<feature>/tasks/`, then delete all reports (`rm -rf specs/<feature>/reports/`), then remind user to run `/ship <feature>`
