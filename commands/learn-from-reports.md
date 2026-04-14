Mine validation reports for patterns worth promoting into the project knowledge base.

Feature name: $ARGUMENTS

## Purpose

Cross-finding pattern mining that complements `/review-findings` step 4 (inline rule creation on reject). This command runs after `/review-findings` completes — or after `/validate` produces zero findings — and before reports are deleted. It surfaces rule candidates the user did not flag in-flow: repeated categories, clustered LLM findings, rejection reasoning worth codifying, and accepted fixes describing a generalizable convention. Accepted candidates become new project knowledge-base rules so the same class of finding does not recur in future tasks.

## Prerequisites
1. Read and follow `~/.claude/knowledge-base-rules.md` for knowledge base prerequisites and resolution rules.
2. Read `knowledge-base/_index.md` (project KB) to understand existing rule coverage before proposing new rules.

## Steps

1. **Load reports.** Read all YAML files in `specs/$ARGUMENTS/reports/`. If the directory is missing or empty, skip to step 6 (deletion is still centralized here).

2. **Collect findings.** Flatten all findings across all report files. Annotate each with its source report path and gate. Skip findings where `rule_added: true` (already handled inline by `/review-findings`).

3. **Mine rule candidates.** Generate candidates from the following signals:
   - **Rejected + reasoned:** `review_status: rejected` with a non-empty `review_notes`. The reasoning often describes a project convention that should be explicit. One candidate per distinct reasoning.
   - **Recurring category:** ≥2 findings sharing the same `category` (regardless of `review_status`). One candidate per category cluster.
   - **Recurring LLM source:** ≥2 findings with `source: llm` whose `title` or `description` describe the same class of issue (same agent flagging the same thing repeatedly). One candidate per cluster.
   - **Accepted with generalizable fix:** `review_status: accepted` where the `fix_proposal` reads as a reusable convention rather than a one-off bug fix. Be conservative — default to skipping unless the fix clearly generalizes.
   - **Zero-findings path:** if all gates passed, still scan `source: llm` advisory notes (any borderline observations an agent recorded even without flagging) for convention signals.

4. **Present candidates as a single batched review.** For each candidate, display:
   - Signal type (rejected-reasoning / recurring-category / recurring-llm / accepted-generalizable)
   - Source findings: id, file, lines, severity, one-line description each
   - Proposed project KB file path (use `knowledge-base-rules.md` resolution: `knowledge-base/<category>/<file>.md`)
   - Proposed rule text (concise, imperative, fits the existing KB voice)
   - Ask: **Accept / Reject / Edit?**
     - **Accept:** apply in step 5
     - **Reject:** discard candidate, move on
     - **Edit:** prompt for revised rule text or target file, then apply as accepted
   - **Stop and wait for user response between candidates.**
   - If no candidates were generated, report: "No new rule candidates found." and continue to step 6.

5. **Apply accepted rules.** For each accepted candidate:
   - Create or append to the target project KB file (per `knowledge-base-rules.md` — never the general KB).
   - Update `knowledge-base/_index.md` with the new or updated rule entry.
   - Set `rule_added: true` on all source findings in their report YAML files (use `yq` to preserve schema).

6. **Delete reports.** `rm -rf specs/$ARGUMENTS/reports/` — deletion is centralized here so that both the `/review-findings` path and the `/validate` zero-findings path converge through mining first.

7. **Report summary.** "Mined N findings: C candidates proposed, A accepted, R rejected, E edited. Reports deleted."

## Chain

After step 7 completes, proceed to the shipping phase: read and follow `~/.claude/commands/ship.md` with the same `$ARGUMENTS` value.
