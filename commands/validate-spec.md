Validate a feature specification for internal coherence, logic gaps, and repo alignment — before implementation begins.

Feature name: $ARGUMENTS

## Purpose

Pre-implementation spec-coherence gate. Catches contract gaps, missing pieces, logic gaps, and repo misalignment in `specs/$ARGUMENTS/` so they are fixed in the spec rather than discovered at implementation or validation time.

Distinct from `/validate-impl` (post-implementation Odium audit of claimed-vs-actual completion) and `/validate` (per-task code gates).

## Prerequisites

1. Read and follow `$WF_GENERAL_KB/_rules.md` for knowledge base prerequisites and resolution rules
2. Verify `specs/$ARGUMENTS/` exists. If absent, report: "No spec directory at `specs/$ARGUMENTS/`. Run `/propose $ARGUMENTS` first." and stop.
3. Load tier early — `bash -c 'source ~/.claude/scripts/config-loader.sh && wf_load_config --spec $ARGUMENTS && echo $WF_SPEC_TIER'`. If `WF_SPEC_TIER == small`, print: "Spec tier is `small` — `/validate-spec` skipped. Run `/implement $ARGUMENTS` next." and exit 0. No artifacts written.
4. Verify `specs/$ARGUMENTS/spec.md` exists. If absent (and tier ≥ medium), report: "Spec bundle incomplete — `spec.md` missing." and stop.
5. Ensure `specs/$ARGUMENTS/reports/` exists (create if missing).

## Phase 1: Spawn Spec Reviewer

Spawn the `Spec Reviewer` agent (`engineering-spec-reviewer`) using the Agent tool. The agent receives:

- The feature path: `specs/$ARGUMENTS/`
- General KB path: `$WF_GENERAL_KB/` (single KB — no project-KB layer, ADR-0002)
- The project's `CLAUDE.md`
- The repository root for grep/glob verification of referenced paths and symbols
- When `WF_REPO_NAMES` is non-empty (vault mode): pass `WF_REPO_NAMES` + `WF_REPO_PATHS` so the Spec Reviewer resolves file/symbol references against each bound repo (not the vault). The reviewer must verify each task's `repo:` field is a member of `WF_REPO_NAMES` and that referenced files actually live under that repo's tree.

Instruct the agent with this directive:

> "Audit `specs/$ARGUMENTS/` before implementation starts. Inspect every artifact under the directory (prd.md, spec.md, design.md, test-strategy.md, config.yml, tasks/*.md) and surface findings across four pillars: contract directions, logic gaps, missing pieces (traceability: FR→scenario→task→test), and repo misalignment (every file path, function reference, reuse target, and ground_rules prefix must resolve against the actual repo via Glob / `git ls-files` / Grep). Additional checks: KB rule compliance against the general KB (`$WF_GENERAL_KB`; `ground_rules` are bare general-KB-relative paths), task graph sanity (DAG, ordering), ambiguity (undefined terms used before glossary), testability of acceptance criteria, and traceability of Security Scenarios to a STRIDE threat (if a threat model is present).
>
> The repo-root `docs/adr/` (and `CONTEXT.md`) are authoritative for durable, cross-spec decisions and canonical glossary terms. A `design.md` ADR that references an existing `docs/adr/` entry by id (instead of inlining it) is correct by design — do NOT flag the referenced-but-not-inlined decision as a missing piece or gap. Glossary terms defined in `CONTEXT.md` count as defined for the ambiguity check.
>
> Output findings as a YAML list matching the report schema below. Every finding MUST include a concrete `fix_proposal` that patches spec/design/tasks files — never the code. If the spec is clean, return `findings: []`. Mark all findings `source: llm`."

## Phase 2: Emit Report

Write one YAML report to `specs/$ARGUMENTS/reports/spec-review.yaml`. Schema: `~/.claude/scripts/report-schema.md` (canonical). This gate constrains:

- `gate: spec-review`
- `category` ∈ `contract | logic-gap | missing-piece | repo-misalignment | kb-compliance | task-graph | ambiguity | testability | traceability`
- All findings: `source: llm`, `review_status: pending`, `file` under `specs/$ARGUMENTS/`, and `fix_proposal` patches spec/design/tasks (never code).

On `status: error` (agent timeout/crash), re-run `/validate-spec $ARGUMENTS` before proceeding.

## Phase 3: Next Step

- If `status: pass`: print the approval summary and stop. `/implement $ARGUMENTS` is now unblocked.
- If `status: findings`: stop and instruct the user to run `/review-findings $ARGUMENTS`. Accepted findings spawn background sub-agents that apply the `fix_proposal` patches to the spec/design/tasks files (same mechanism `/review-findings` already uses for code fixes). After review, the user re-runs `/validate-spec $ARGUMENTS` to confirm `status: pass`.
- If `status: error`: surface the error and instruct the user to re-run `/validate-spec $ARGUMENTS`.

## Blocking Semantics

`/implement` must refuse to start a task unless `specs/$ARGUMENTS/reports/spec-review.yaml` exists with `status: pass`. The preflight check in `commands/implement.md` enforces this. The error message points the user back here.

`spec-review.yaml` is a **spec-level** report and persists across per-task cleanup: `/learn-from-reports` step 6 scopes its delete to per-task gate reports and preserves `spec-review.yaml` / `spec-audit-*.md`. Re-run `/validate-spec` only when `spec.md`, `design.md`, or `tasks/` are edited — not between tasks.

## Invocation

Always invoked explicitly by the user — typically right after `/propose` finishes, and again after `/review-findings` resolves spec-review findings. Re-runs after manual edits to `spec.md` / `design.md` / `tasks/` are also supported.
