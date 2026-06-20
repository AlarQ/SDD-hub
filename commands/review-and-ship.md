Walk through validation findings interactively, then ship the task.

Feature name: $ARGUMENTS

When the current task is at status `review`, this command **ships it inline** at
the tail (single commit covering the applied fixes → push → PR ready) via the
shared `~/.claude/scripts/ship-procedure.md`. Reused at the spec level by
`/propose` (spec-consistency findings) and `/validate-impl` (spec-audit reopen
findings), where no task is in `review` — there the ship tail is a no-op.

## Prerequisites
1. Read and follow `$WF_GENERAL_KB/_rules.md` for knowledge base prerequisites and resolution rules
2. Read and follow `~/.claude/scripts/universal-rule-authoring.md` — any rule written to the general KB from the reject path MUST conform to its phrasing, snippet, and rejection criteria

## Step 0 — Load Spec Config

Load the spec config before processing any report (substitute actual feature name for `$ARGUMENTS`). Load the vars the inline ship tail needs (`WF_SPEC_GATES`, `WF_BRANCH_STRATEGY`, storage mode) so the ship-procedure precondition contract is satisfied without re-loading:

```bash
bash -c 'source ~/.claude/scripts/config-loader.sh && wf_load_config --spec $ARGUMENTS && printf "WF_SPEC_CONFIG_FILE=%s\nWF_SPEC_GATES=%s\nWF_BRANCH_STRATEGY=%s\nWF_SPEC_STORAGE_MODE=%s\n" "${WF_SPEC_CONFIG_FILE:-}" "$WF_SPEC_GATES" "${WF_BRANCH_STRATEGY:-per-task}" "${WF_SPEC_STORAGE_MODE:-repo}"'
```

> See `~/.claude/scripts/step0-load-config.md` for canonical invocation and remediation. The finding-triage flow does not consume the `agents` map; the listed vars feed the conditional ship tail (see **Status Update**).

### Multi-repo resolution (only needed for the ship tail)

If the current task will reach the ship tail (it is at status `review`), resolve its bound repo per `~/.claude/scripts/multi-repo-resolution.md` → sets `WF_TASK_REPO_PATH`. The shared ship procedure requires it. Spec-level reuse by `/propose` / `/validate-impl` (no task in `review`) skips this — the ship tail is a no-op there.

## Steps
1. Read all pending reports from `specs/$ARGUMENTS/reports/`. Report and finding schema: `~/.claude/scripts/report-schema.md` (canonical) — `review_status` enum, severity enum, source enum, and the spec-audit markdown contract live there. **Spec-audit reports** (filename pattern `spec-audit-*.md`, produced by `/validate-impl`) are recognized here:
   - Frontmatter and FR-matrix contract per `~/.claude/scripts/report-schema.md §Spec-audit reports`. Refuse to process if frontmatter is missing required fields or `verdict` is outside the allowed set.
   - Each `missing` or `partial` FR row becomes one review unit (synthetic finding: `source: llm`, severity `high` for missing, `medium` for partial).
   - On **Accept** of a missing/partial FR review unit: invoke `~/.claude/scripts/task-manager.sh create-followup "$ARGUMENTS" "<FR-id>" "<FR description>"`. This subcommand validates the FR id against `spec.md` (fail-closed on unknown ids) and inherits `ground_rules` from the spec's `## Applicable Ground Rules` section.
   - On **Reject**: the finding remains in the report so `/learn-from-reports` can mine it as a general-KB rule candidate (no inline rule creation needed for spec-audit findings).
2. Partition findings: separate `severity: info` findings (informational) from all others (actionable).

2a. **Partition actionable → AUTO | MANUAL.** Before grouping, classify each actionable finding into the **AUTO bucket** (fix applied by a spawned agent *before* the human is asked) or the **MANUAL bucket** (today's exact card + `Accept/Reject/Elaborate` flow). The human's backstop for AUTO fixes is the already-open **draft PR diff** — no new approval gate, no commits here.

   A finding is **AUTO** iff either:
   - **Mechanical:** `category` ∈ the allowlist **AND** `severity` ∈ {`info`, `low`, `medium`} **AND** `fix_proposal` is present (non-empty); **or**
   - **Coverage:** `category` == `coverage` (exempt from the severity cap **and** the `fix_proposal` requirement — auto at any severity, with or without a `fix_proposal`).

   Otherwise the finding is **MANUAL**.

   - **Allowlist (hardcoded here, editable in this command):** `style`, `formatting`, `unused-import`, `dry-violation`, `coverage`. Matching is **your judgment** against each finding's free-form `category` string — there is no closed enum and no parser change. Treat near-synonyms sensibly (e.g. `unused_import`, `lint:unused-import` match `unused-import`; `code-style` matches `style`).
   - **Severity cap:** `critical` / `high` mechanical findings always go MANUAL. Coverage ignores the cap.
   - **`interaction` (afk/hitl) is NOT consulted** — same partition for all tasks.
   - **spec-audit synthetic findings are out of scope** — the `missing`/`partial` FR review units synthesized in step 1 are NEVER auto-accepted (they create follow-up tasks, not code fixes). They always go MANUAL with their existing handling.

2b. **Process the AUTO bucket** (skip this step entirely if the AUTO bucket is empty). For each AUTO finding, spawn a background fix agent reusing the existing accept-path spawn pattern (Agent tool, `run_in_background: true`, `model: "sonnet"` — mandatory, do not omit or change the model) and the **file-exclusivity rule** (step 5: same-file edits serialized, different files parallel). Multi-repo: resolve relative `file` paths against the owning task's `WF_TASK_REPO_PATH` (per `~/.claude/scripts/multi-repo-resolution.md`) and pass it to the agent so edits land in the bound repo.

   Per finding, the agent:
   - **`coverage` finding:** generate the missing/partial test from the gap description / acceptance criterion (no `fix_proposal` needed). Then run the bound repo's **test gate** — the `gate_pool` test gate command for `WF_TASK_REPO_PATH` (the same test command `/validate` runs). If the test is **green**, keep it. If it **won't go green**, discard the new test and **demote the finding to MANUAL** (it joins the manual bucket as a standard card).
   - **Mechanical finding:** re-read the target file, then apply the `fix_proposal` (reverse line order if multiple on one file, to avoid offset drift).
   - **On success:** set `review_status: accepted` **and** `auto_accepted: true` on the finding in its report YAML (use `yq` to preserve schema).
   - **On error** (agent fails, edit doesn't apply, test won't go green): discard the attempt, leave the file unchanged, and **demote the finding to MANUAL** — nothing is silently lost.

   Wait for all AUTO agents to complete, fold any demotions into the MANUAL bucket, then print a **read-only** summary:

   ```
   AUTO-FIXED (N)
   - <title>  (<file>)  — review in PR diff
   - …
   ```

   **No Keep/Revert, no commits.** Edits stay uncommitted in the working tree exactly like today's accept-path fixes; the inline ship tail (**Status Update** below) commits them in one commit. The draft PR diff + `/pr-review` are the backstop.

3. Group **MANUAL-bucket** actionable findings before presenting them (AUTO findings are already fixed and excluded; demoted findings are included):
   a. Sort all actionable findings by file path, then by start line.
   b. **Pass 1 — Line proximity:** For findings targeting the same `file`, merge into one group if their `lines` ranges overlap or are within 5 lines of each other. Apply transitive closure: if finding C overlaps with B which is already grouped with A, C joins the {A, B} group.
   c. **Pass 2 — Same-file category match:** For still-ungrouped findings in the same file that share an identical `category` value, merge them into one group.
   d. Remaining ungrouped findings each become a singleton group.
   e. Sort groups by: highest severity within the group (critical > high > medium > low), then file path alphabetically.
   f. Track which files each group touches (needed for file exclusivity in step 5).
4. **Snippet hydration** — before rendering any card, walk every MANUAL-bucket actionable finding and ensure `code_snippet` has content:
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

     [<severity>] <title>  (gate: <gate>, source: <tool|llm>[, confidence: <high|medium|low>])
     File: <file>:<lines>

     What:    <description>
     Why:     <rationale OR "(not provided — pick Elaborate for deeper analysis)">
     Impact:  <impact OR "(not provided)">
     Code:
     ```<lang>
     <code_snippet>
     ```
     Fix:                                    # omit Fix: label + block entirely if fix_proposal empty/absent
     ```<lang>
     <fix_proposal>
     ```
     References: <comma-joined references>   # omit line entirely if empty

     Finding schema (including `rationale`, `impact`, `references`, `confidence`) lives in `~/.claude/scripts/report-schema.md`.

     **`<lang>` inference** — derive from the finding's `file` extension (case-insensitive). Use the same `<lang>` for both `Code:` and `Fix:` blocks since `fix_proposal` targets the same file. Mapping:

     | Extension | `<lang>` |
     |-----------|----------|
     | `.rs` | `rust` |
     | `.ts`, `.tsx` | `ts` |
     | `.js`, `.jsx`, `.mjs`, `.cjs` | `js` |
     | `.py` | `python` |
     | `.sh`, `.bash` | `bash` |
     | `.go` | `go` |
     | `.md` | `markdown` |
     | `.yml`, `.yaml` | `yaml` |
     | `.json` | `json` |
     | `.toml` | `toml` |
     | anything else / no extension / no `file` | `text` |

     **Sentinel & empty handling** — fenced blocks are for code only:
     - If `code_snippet` equals one of the hydration sentinels (`(snippet unavailable: …)` or `(no file:lines on finding)`), render it as a plain italicised line (e.g. `Code:    _(snippet unavailable: …)_`) — do **not** wrap in a fenced block.
     - If `fix_proposal` is empty/absent, omit the `Fix:` label and block entirely — do not emit an empty fence.
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
   - If Reject: invoke `AskUserQuestion` again with two questions in one call — (a) free-text "Reason for rejecting this group?" (open-ended), and (b) "Add reject reasoning as general KB rule?" with options `Yes`/`No`. Use answers to set review_notes on ALL findings in the group; review_status → "rejected".
   - If the KB-rule answer was `Yes`: draft the rule per `~/.claude/scripts/universal-rule-authoring.md` (universal phrasing, synthetic-only snippets if any, pre-write checklist). Before writing, show a preview with the proposed target path, rule text, optional synthetic snippet, and a **Universal-check** line (`pass` or specific concerns). On confirm, create/update the relevant file at `$WF_GENERAL_KB/<category>/<file>.md` (per `knowledge-base-rules.md`) and update `$WF_GENERAL_KB/_index.md`, set rule_added: true on the relevant finding(s). If the draft cannot be made universal, drop it and apply the rejection criterion guidance (suggest repo-local capture).
   - After processing, show running tally: "X accepted, Y rejected so far (Z fixes in progress)"
6. After all groups have been reviewed, wait for any in-flight fix sub-agents to complete. Report: "All N fix sub-agents completed." If any sub-agent errored, report which group/file failed and ask the user whether to retry or skip that fix (set review_status back to "pending" if retry, or "rejected" if skip).
7. Set review_status to "noted" on all informational findings
8. Display informational summary — compact list: title, file, and one-line description for each
9. Report summary: A auto-fixed (auto bucket), X groups accepted (N findings), Y groups rejected (M findings), Z noted (informational), W new rules added

## Status Update

Reports are NOT deleted here — reports are retained (local audit trail); nothing deletes them anywhere. `/learn-from-reports` mines them in place.

1. Wait for all fix sub-agents to finish (step 6 above) — the working tree now holds every applied fix, uncommitted.
2. **The ship-tail gate is the `review` determination already made in Step 0** (was-the-task-at-`review` vs spec-level reuse), captured *before* step 3 mutates the status. Do NOT re-read status after step 3 — by then it is `done` for every path and the gate would always fail. (Step 0 is the only safe read point.)
3. Run `~/.claude/scripts/task-manager.sh set-status <task-file> done`, then run `~/.claude/scripts/task-manager.sh unblock specs/$ARGUMENTS/tasks/`.
4. **Conditional ship tail**, branching on the Step-0 `review` determination from step 2:
   - **If the task was at status `review`** (the normal per-task finding flow): run the shared `~/.claude/scripts/ship-procedure.md` inline against `<task-file>` / `<task-id>` / `<task-title>` (config + multi-repo already resolved in Step 0). It makes **one** commit covering all applied fixes, pushes, and marks the PR ready. Then stop and instruct the user: "Findings addressed and task shipped (PR ready). Run `/learn-from-reports $ARGUMENTS <task-id>` next."
   - **If the task was NOT at status `review`** (spec-level reuse by `/propose` spec-consistency or `/validate-impl` spec-audit reopen): the ship tail is a **no-op** — skip the ship procedure entirely. Spec-audit Accepts already created follow-up tasks; return control to the calling command's flow.
