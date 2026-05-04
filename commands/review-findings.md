Walk through validation findings interactively.

Feature name: $ARGUMENTS

## Prerequisites
1. Read and follow `~/.claude/knowledge-base-rules.md` for knowledge base prerequisites and resolution rules

## Step 0 — Load Spec Config

Load the spec config before processing any report (substitute actual feature name for `$ARGUMENTS`):

```bash
bash -c 'source ~/.claude/scripts/config-loader.sh && wf_load_config --spec $ARGUMENTS'
```

> See `~/.claude/scripts/step0-load-config.md` for canonical invocation and remediation. Runs solely to validate config existence — `/review-findings` does not consume the `agents` map.

## Steps
1. Read all pending reports from `specs/$ARGUMENTS/reports/`. Report and finding schema: `~/.claude/scripts/report-schema.md` (canonical) — `review_status` enum, severity enum, source enum, and the spec-audit markdown contract live there. **Spec-audit reports** (filename pattern `spec-audit-*.md`, produced by `/validate-impl`) are recognized here:
   - Frontmatter and FR-matrix contract per `~/.claude/scripts/report-schema.md §Spec-audit reports`. Refuse to process if frontmatter is missing required fields or `verdict` is outside the allowed set.
   - Each `missing` or `partial` FR row becomes one review unit (synthetic finding: `source: llm`, severity `high` for missing, `medium` for partial).
   - On **Accept** of a missing/partial FR review unit: invoke `~/.claude/scripts/task-manager.sh create-followup "$ARGUMENTS" "<FR-id>" "<FR description>"`. This subcommand validates the FR id against `spec.md` (fail-closed on unknown ids) and inherits `ground_rules` from the spec's `## Applicable Ground Rules` section.
   - On **Reject**: the finding remains in the report so `/learn-from-reports` can mine it as a project-KB rule candidate (no inline rule creation needed for spec-audit findings).
2. Partition findings: separate `severity: info` findings (informational) from all others (actionable)
3. Group actionable findings before presenting them:
   a. Sort all actionable findings by file path, then by start line.
   b. **Pass 1 — Line proximity:** For findings targeting the same `file`, merge into one group if their `lines` ranges overlap or are within 5 lines of each other. Apply transitive closure: if finding C overlaps with B which is already grouped with A, C joins the {A, B} group.
   c. **Pass 2 — Same-file category match:** For still-ungrouped findings in the same file that share an identical `category` value, merge them into one group.
   d. Remaining ungrouped findings each become a singleton group.
   e. Sort groups by: highest severity within the group (critical > high > medium > low), then file path alphabetically.
   f. Track which files each group touches (needed for file exclusivity in step 4).
4. Present **one group at a time**. Show a progress header: "Group 1 of G (N total findings)".
   For each group:
   - List all findings in the group: for each, show severity, title, gate (source report), description, code snippet, and fix proposal. Visually separate findings within the group but present them as one review unit.
   - If the group has multiple findings, show a brief note: "These N findings target the same code region in `<file>` and are grouped for a single decision."
   - Ask: **Accept all / Reject all?** Do NOT offer partial accept within a group — the fixes are interrelated.
   - **Stop and wait for user response before continuing to the next group.**
   - If Accept:
     - Spawn a sub-agent (using the Agent tool with `run_in_background: true` and `model: "sonnet"`) to apply all fixes in this group. The `model: "sonnet"` parameter is mandatory — do not omit it and do not use a different model. Sub-agent instructions:
       1. Re-read the target file before editing.
       2. Apply all `fix_proposal`s in the group in reverse line order (highest line number first) to avoid offset drift.
       3. After all fixes applied, update `review_status` to `"accepted"` on each finding in the group's report YAML file.
     - **File exclusivity rule:** Before spawning, check if another sub-agent is currently editing the same file. If so, wait for that sub-agent to complete first, then spawn. Groups targeting different files spawn immediately (parallel).
     - Do NOT wait for the sub-agent to finish before presenting the next group (unless the next group targets the same file — in that case, wait for the previous sub-agent first).
   - If Reject: ask for reasoning, update review_status to "rejected" and set review_notes on ALL findings in the group.
   - If Reject + new rule needed: create/update the relevant file in the **project** knowledge-base (per `knowledge-base-rules.md`) and update `knowledge-base/_index.md`, set rule_added: true on the relevant finding(s).
   - After processing, show running tally: "X accepted, Y rejected so far (Z fixes in progress)"
5. After all groups have been reviewed, wait for any in-flight fix sub-agents to complete. Report: "All N fix sub-agents completed." If any sub-agent errored, report which group/file failed and ask the user whether to retry or skip that fix (set review_status back to "pending" if retry, or "rejected" if skip).
6. Set review_status to "noted" on all informational findings
7. Display informational summary — compact list: title, file, and one-line description for each
8. Report summary: X groups accepted (N findings), Y groups rejected (M findings), Z noted (informational), W new rules added

## Status Update

Reports are NOT deleted here — `/learn-from-reports` mines them first and owns deletion.

- If any fixes were applied (accepted actionable findings — informational findings do not count): ask the user whether they want to re-run validation or skip re-validation and proceed to mining + shipping.
  - If user wants re-validation: archive existing reports out of the active path so `/validate` regenerates fresh ones without losing the prior batch (mining input). Run `mv specs/$ARGUMENTS/reports specs/$ARGUMENTS/reports.archived-$(date +%s)`. Do **not** `rm -rf` — report deletion is owned solely by `/learn-from-reports`. Then run `~/.claude/scripts/task-manager.sh set-status <task-file> implemented`. Stop and instruct the user: "Fixes applied. Run `/validate $ARGUMENTS` next."
  - If user wants to skip: run `~/.claude/scripts/task-manager.sh set-status <task-file> done`, then run `~/.claude/scripts/task-manager.sh unblock specs/$ARGUMENTS/tasks/`. Stop and instruct the user: "Run `/learn-from-reports $ARGUMENTS` next."
- If no fixes were applied (all findings rejected or already clean): run `~/.claude/scripts/task-manager.sh set-status <task-file> done`, then run `~/.claude/scripts/task-manager.sh unblock specs/$ARGUMENTS/tasks/`. Stop and instruct the user: "Run `/learn-from-reports $ARGUMENTS` next."
