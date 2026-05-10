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
   f. Track which files each group touches (needed for file exclusivity in step 5).
4. **Snippet hydration** — before rendering any card, walk every actionable finding and ensure `code_snippet` has content:
   - If `code_snippet` is non-empty (after trimming whitespace), keep agent-provided text as-is.
   - Else if `file` and `lines` are both present:
     - Parse `lines` as `<start>-<end>` (single int → start=end).
     - Read `file` with `offset=<start>` and `limit=min(<end>-<start>+1, 40)`.
     - In vault/multi-repo mode, resolve relative `file` against the owning task's `WF_TASK_REPO_PATH` first (per `~/.claude/scripts/multi-repo-resolution.md`).
     - Use the read content as `code_snippet`. If the original range exceeded 40 lines, append a final line `… (truncated, <N> more lines)` where N = `<end>-<start>+1 - 40`.
     - On Read error (file missing, path outside repo): set `code_snippet` to `(snippet unavailable: <reason>)`.
   - Else: set `code_snippet` to `(no file:lines on finding)`.
   - This is render-time only — do NOT write hydrated snippets back to the report YAML.
5. Present **one group at a time**. Show a progress header: "Group 1 of G (N total findings)".
   For each group:
   - List all findings in the group as structured cards. Visually separate findings within the group (horizontal rule between cards) but present them as one review unit. Card format per finding:

     ```
     [<severity>] <title>  (gate: <gate>, source: <tool|llm>[, confidence: <high|medium|low>])
     File: <file>:<lines>

     What:    <description>
     Why:     <rationale OR "(not provided — pick Elaborate for deeper analysis)">
     Impact:  <impact OR "(not provided)">
     Code:
       <code_snippet>
     Fix:
       <fix_proposal>
     References: <comma-joined references>   # omit line entirely if empty
     ```

     Finding schema (including `rationale`, `impact`, `references`, `confidence`) lives in `~/.claude/scripts/report-schema.md`.
   - If the group has multiple findings, show a brief note: "These N findings target the same code region in `<file>` and are grouped for a single decision."
   - Invoke the `AskUserQuestion` tool (per `~/.claude/scripts/ask-user-protocol.md`) with one question per group: **"Accept, reject, or elaborate this group?"** options: `Accept all`, `Reject all`, `Elaborate`. Do NOT offer partial accept within a group — the fixes are interrelated. Do NOT render the prompt as a plain markdown question.
   - **Stop and wait for the tool result before continuing to the next group.**
   - If Elaborate: spawn a foreground sub-agent (Agent tool, `subagent_type: "general-purpose"`, `model: "sonnet"`) with the full group findings YAML and target file paths. Sub-agent prompt MUST request: read each cited file around the line range; for each finding produce (1) deeper rationale — root cause + principle violated, (2) concrete impact — what breaks, who notices, (3) one alternative fix worth considering, (4) any KB rule / CWE / doc references found. Return a markdown report; do NOT modify files. Print the report to the user verbatim, then re-invoke `AskUserQuestion` for the same group with options `Accept all` / `Reject all` (Elaborate is single-use per group to keep flow bounded).
   - If Accept:
     - Spawn a sub-agent (using the Agent tool with `run_in_background: true` and `model: "sonnet"`) to apply all fixes in this group. The `model: "sonnet"` parameter is mandatory — do not omit it and do not use a different model. Sub-agent instructions:
       1. Re-read the target file before editing.
       2. Apply all `fix_proposal`s in the group in reverse line order (highest line number first) to avoid offset drift.
       3. After all fixes applied, update `review_status` to `"accepted"` on each finding in the group's report YAML file.
       4. **Multi-repo (vault mode):** if the group's `file` paths are relative, resolve them against the owning task's `WF_TASK_REPO_PATH` (per `~/.claude/scripts/multi-repo-resolution.md`). Pass `WF_TASK_REPO_PATH` to the sub-agent in its prompt so edits land inside the bound repo, not the vault.
     - **File exclusivity rule:** Before spawning, check if another sub-agent is currently editing the same file. If so, wait for that sub-agent to complete first, then spawn. Groups targeting different files spawn immediately (parallel).
     - Do NOT wait for the sub-agent to finish before presenting the next group (unless the next group targets the same file — in that case, wait for the previous sub-agent first).
   - If Reject: invoke `AskUserQuestion` again with two questions in one call — (a) free-text "Reason for rejecting this group?" (open-ended), and (b) "Add reject reasoning as project KB rule?" with options `Yes`/`No`. Use answers to set review_notes on ALL findings in the group; review_status → "rejected".
   - If the KB-rule answer was `Yes`: create/update the relevant file in the **project** knowledge-base (per `knowledge-base-rules.md`) and update `knowledge-base/_index.md`, set rule_added: true on the relevant finding(s).
   - After processing, show running tally: "X accepted, Y rejected so far (Z fixes in progress)"
6. After all groups have been reviewed, wait for any in-flight fix sub-agents to complete. Report: "All N fix sub-agents completed." If any sub-agent errored, report which group/file failed and ask the user whether to retry or skip that fix (set review_status back to "pending" if retry, or "rejected" if skip).
7. Set review_status to "noted" on all informational findings
8. Display informational summary — compact list: title, file, and one-line description for each
9. Report summary: X groups accepted (N findings), Y groups rejected (M findings), Z noted (informational), W new rules added

## Status Update

Reports are NOT deleted here — `/learn-from-reports` mines them first and owns deletion.

- If any fixes were applied (accepted actionable findings — informational findings do not count): invoke `AskUserQuestion` (per `~/.claude/scripts/ask-user-protocol.md`) — "Re-run validation now?" options: `Re-validate`, `Skip and proceed to mining`.
  - If user wants re-validation: archive existing reports out of the active path so `/validate` regenerates fresh ones without losing the prior batch (mining input). Run `mv specs/$ARGUMENTS/reports specs/$ARGUMENTS/reports.archived-$(date +%s)`. Do **not** `rm -rf` — report deletion is owned solely by `/learn-from-reports`. Then run `~/.claude/scripts/task-manager.sh set-status <task-file> implemented`. Stop and instruct the user: "Fixes applied. Run `/validate $ARGUMENTS` next."
  - If user wants to skip: run `~/.claude/scripts/task-manager.sh set-status <task-file> done`, then run `~/.claude/scripts/task-manager.sh unblock specs/$ARGUMENTS/tasks/`. Stop and instruct the user: "Run `/learn-from-reports $ARGUMENTS` next."
- If no fixes were applied (all findings rejected or already clean): run `~/.claude/scripts/task-manager.sh set-status <task-file> done`, then run `~/.claude/scripts/task-manager.sh unblock specs/$ARGUMENTS/tasks/`. Stop and instruct the user: "Run `/learn-from-reports $ARGUMENTS` next."
