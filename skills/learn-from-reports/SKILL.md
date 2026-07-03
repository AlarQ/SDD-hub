---
name: learn-from-reports
description: Mine validation reports for patterns worth promoting into the general knowledge base.
disable-model-invocation: true
args:
  - name: feature
    description: Feature name (used as $1 in body)
    required: true
  - name: task-id
    description: Task id, optional (used as $2 in body)
    required: false
---

Feature name: $1
Task id: $2 (optional)

## Purpose

Cross-finding pattern mining that complements `/review-and-ship` step 4 (inline rule creation on reject). This command runs **after the task is already shipped** — after `/review-and-ship` addresses findings and ships, or after `/validate` passes clean and ships. It is the final manual step of the per-task flow: it writes KB rules to `$WF_GENERAL_KB` only and **never touches the task PR diff** (the PR is already ready by the time this runs). Reports are **retained** (local audit trail); this command mines them in place. It surfaces rule candidates the user did not flag in-flow: repeated categories, clustered LLM findings, rejection reasoning worth codifying, and accepted fixes describing a generalizable convention. Accepted candidates become new general knowledge-base rules so the same class of finding does not recur in future tasks.

## Prerequisites
1. Read and follow `$WF_GENERAL_KB/_rules.md` for knowledge base prerequisites and resolution rules.
2. Read `$WF_GENERAL_KB/_index.md` to understand existing rule coverage before proposing new rules.
3. Read and follow `~/.claude/scripts/universal-rule-authoring.md` — all candidate rules MUST conform to its phrasing, snippet, and rejection criteria.

## Steps

1. **Load reports.** Load only the current task's per-task reports — `specs/$1/reports/<task-id>-*.yaml`. Resolve `<task-id>` from arg `$2`; if absent, fall back to the `task_id` of the most-recently-modified per-task report in `specs/$1/reports/` (exclude spec-level reports `spec-audit-*`/`spec-consistency.yaml`, which carry no task-id prefix). If no per-task reports exist, skip to step 6.

2. **Collect findings.** Flatten all findings across all report files. Annotate each with its source report path and gate. Skip findings where `rule_added: true` (already handled inline by `/review-and-ship`). Also skip findings where `auto_accepted: true` — these are mechanical auto-bucket fixes (style/formatting/unused-import/dry-violation/coverage), low-signal for KB-rule mining.

3. **Mine rule candidates.** Generate candidates from the following signals:
   - **Rejected + reasoned:** `review_status: rejected` with a non-empty `review_notes`. The reasoning often describes a convention that should be explicit. One candidate per distinct reasoning.
   - **Recurring category:** ≥2 findings sharing the same `category` (regardless of `review_status`). One candidate per category cluster.
   - **Recurring LLM source:** ≥2 findings with `source: llm` whose `title` or `description` describe the same class of issue (same agent flagging the same thing repeatedly). One candidate per cluster.
   - **Accepted with generalizable fix:** `review_status: accepted` where the `fix_proposal` reads as a reusable convention rather than a one-off bug fix. Be conservative — default to skipping unless the fix clearly generalizes.
   - **Zero-findings path:** if all gates passed, still scan `source: llm` advisory notes (any borderline observations an agent recorded even without flagging) for convention signals.

4. **Present candidates as a single batched review.** Draft each candidate per `~/.claude/scripts/universal-rule-authoring.md` (universal phrasing, synthetic-only snippets, snippet-inclusion criterion, pre-write checklist). For each candidate, display:
   - Signal type (rejected-reasoning / recurring-category / recurring-llm / accepted-generalizable)
   - Source findings: id, file, lines, severity, one-line description each (shown for user context only — these tokens MUST NOT leak into the rule body or snippet)
   - Proposed general KB file path (use `knowledge-base-rules.md` resolution: `$WF_GENERAL_KB/<category>/<file>.md`)
   - Proposed rule text (concise, imperative, fits the existing KB voice; no repo-specific names/paths/symbols)
   - Optional synthetic code snippet (include only for code-pattern rules per the snippet policy; generic identifiers only, never derived from source findings)
   - **Universal-check:** one line — `pass` or a list of specific concerns from re-auditing the draft against the guidance doc
   - Invoke `AskUserQuestion` (per `~/.claude/scripts/ask-user-protocol.md`) — "Add this candidate as a general KB rule?" options: `Accept`, `Reject`, `Edit`. One tool call per candidate.
     - **Accept:** apply in step 5
     - **Reject:** discard candidate, move on
     - **Edit:** follow up with an open-ended `AskUserQuestion` for revised rule text / target file, then apply as accepted
   - **Stop and wait for the tool result between candidates.**
   - If no candidates were generated, report: "No new rule candidates found." and continue to step 6.

5. **Apply accepted rules.** For each accepted candidate:
   - Create or append to the target general KB file at `$WF_GENERAL_KB/<category>/<file>.md` (per `knowledge-base-rules.md`).
   - Update `$WF_GENERAL_KB/_index.md` with the new or updated rule entry.
   - Set `rule_added: true` on all source findings in their report YAML files (use `yq` to preserve schema).

> **Reports are retained.** Nothing is deleted here (or anywhere) — reports persist on disk as a local audit trail for the spec's lifetime. Mining is scoped to the resolved task-id via the step 1 load filter, not enforced by deletion.

6. **Report summary.** "Mined N findings: C candidates proposed, A accepted, R rejected, E edited."

## Next Step

After step 6 completes, stop and instruct the user: "Mining done. This task is already shipped (PR ready). Merge the PR, then run `/implement $1` for the next task."
