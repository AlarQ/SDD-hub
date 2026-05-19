Mine validation reports for patterns worth promoting into the general knowledge base.

Feature name: $ARGUMENTS

## Purpose

Cross-finding pattern mining that complements `/review-findings` step 4 (inline rule creation on reject). This command runs after `/review-findings` completes — or after `/validate` produces zero findings — and before reports are deleted. It surfaces rule candidates the user did not flag in-flow: repeated categories, clustered LLM findings, rejection reasoning worth codifying, and accepted fixes describing a generalizable convention. Accepted candidates become new general knowledge-base rules so the same class of finding does not recur in future tasks.

## Prerequisites
1. Read and follow `$WF_GENERAL_KB/_rules.md` for knowledge base prerequisites and resolution rules.
2. Read `$WF_GENERAL_KB/_index.md` to understand existing rule coverage before proposing new rules.

## Steps

1. **Load reports.** Read all YAML files in `specs/$ARGUMENTS/reports/`. If the directory is missing or empty, skip to step 6 (deletion is still centralized here).

2. **Collect findings.** Flatten all findings across all report files. Annotate each with its source report path and gate. Skip findings where `rule_added: true` (already handled inline by `/review-findings`).

3. **Mine rule candidates.** Generate candidates from the following signals:
   - **Rejected + reasoned:** `review_status: rejected` with a non-empty `review_notes`. The reasoning often describes a convention that should be explicit. One candidate per distinct reasoning.
   - **Recurring category:** ≥2 findings sharing the same `category` (regardless of `review_status`). One candidate per category cluster.
   - **Recurring LLM source:** ≥2 findings with `source: llm` whose `title` or `description` describe the same class of issue (same agent flagging the same thing repeatedly). One candidate per cluster.
   - **Accepted with generalizable fix:** `review_status: accepted` where the `fix_proposal` reads as a reusable convention rather than a one-off bug fix. Be conservative — default to skipping unless the fix clearly generalizes.
   - **Zero-findings path:** if all gates passed, still scan `source: llm` advisory notes (any borderline observations an agent recorded even without flagging) for convention signals.

4. **Present candidates as a single batched review.** For each candidate, display:
   - Signal type (rejected-reasoning / recurring-category / recurring-llm / accepted-generalizable)
   - Source findings: id, file, lines, severity, one-line description each
   - Proposed general KB file path (use `knowledge-base-rules.md` resolution: `$WF_GENERAL_KB/<category>/<file>.md`)
   - Proposed rule text (concise, imperative, fits the existing KB voice)
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

6. **Delete reports.** `rm -rf specs/$ARGUMENTS/reports/` — deletion is centralized here so that both the `/review-findings` path and the `/validate` zero-findings path converge through mining first.

   **Guard.** If the reports dir was already missing or empty on entry to step 1 (i.e., this command had nothing to mine), warn before deleting: `WARNING: reports/ was empty on entry — possible rogue deletion upstream (only /learn-from-reports may delete reports). Check git/archived dirs before continuing.` Still proceed with the (no-op) cleanup, but surface the anomaly so the user can investigate.

7. **Report summary.** "Mined N findings: C candidates proposed, A accepted, R rejected, E edited. Reports deleted."

## Next Step

After step 7 completes, stop and instruct the user: "Mining done. Run `/ship $ARGUMENTS` next."
