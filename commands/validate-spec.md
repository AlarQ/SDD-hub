Validate a feature specification for internal coherence, logic gaps, and repo alignment — before implementation begins.

Feature name: $ARGUMENTS

## Purpose

Pre-implementation spec-coherence gate. Catches contract gaps, missing pieces, logic gaps, and repo misalignment in `specs/$ARGUMENTS/` so they are fixed in the spec rather than discovered at implementation or validation time.

Distinct from `/validate-impl` (post-implementation Karen audit of claimed-vs-actual completion) and `/validate` (per-task code gates).

## Prerequisites

1. Read and follow `~/.claude/knowledge-base-rules.md` for knowledge base prerequisites and resolution rules
2. Verify `specs/$ARGUMENTS/` exists. If absent, report: "No spec directory at `specs/$ARGUMENTS/`. Run `/propose $ARGUMENTS` first." and stop.
3. Verify `specs/$ARGUMENTS/spec.md` exists. If absent, report: "Spec bundle incomplete — `spec.md` missing." and stop.
4. Ensure `specs/$ARGUMENTS/reports/` exists (create if missing).

## Phase 1: Spawn Spec Reviewer

Spawn the `Spec Reviewer` agent (`engineering-spec-reviewer`) using the Agent tool. The agent receives:

- The feature path: `specs/$ARGUMENTS/`
- General KB path: `~/.claude/knowledge-base/`
- Project KB path: `knowledge-base/`
- The project's `CLAUDE.md`
- The repository root for grep/glob verification of referenced paths and symbols

Instruct the agent with this directive:

> "Audit `specs/$ARGUMENTS/` before implementation starts. Inspect every artifact under the directory (prd.md, spec.md, design.md, test-strategy.md, config.yml, tasks/*.md) and surface findings across four pillars: contract directions, logic gaps, missing pieces (traceability: FR→scenario→task→test), and repo misalignment (every file path, function reference, reuse target, and ground_rules prefix must resolve against the actual repo via Glob / `git ls-files` / Grep). Additional checks: knowledge-base rule compliance against both knowledge bases, task graph sanity (DAG, ground_rules prefix convention, ordering), ambiguity (undefined terms used before glossary), testability of acceptance criteria, and traceability of Security Scenarios to a STRIDE threat (if a threat model is present).
>
> Output findings as a YAML list matching the report schema below. Every finding MUST include a concrete `fix_proposal` that patches spec/design/tasks files — never the code. If the spec is clean, return `findings: []`. Mark all findings `source: llm`."

## Phase 2: Emit Report

Write one YAML report to `specs/$ARGUMENTS/reports/spec-review.yaml` with this schema:

```yaml
gate: spec-review
status: pass | findings | error
findings:
  - id: spec-review-<n>
    severity: critical | high | medium | low | info
    category: contract | logic-gap | missing-piece | repo-misalignment | kb-compliance | task-graph | ambiguity | testability | traceability
    title: <short>
    description: <detail>
    file: specs/$ARGUMENTS/<file>
    lines: "<start>-<end>"
    code_snippet: <exact quoted text from the spec artifact>
    fix_proposal: <concrete patch to the spec/design/tasks — not the code>
    review_status: pending
    source: llm
```

- `status: pass` iff `findings` is empty.
- `status: findings` iff at least one finding exists.
- `status: error` iff the agent timed out or crashed — in that case re-run `/validate-spec $ARGUMENTS` before proceeding.

## Phase 3: Auto-Chain

- If `status: pass`: print the approval summary and stop. `/implement` is now unblocked.
- If `status: findings`: auto-chain into `/review-findings` — read and follow `~/.claude/commands/review-findings.md` with the same $ARGUMENTS value. Accepted findings spawn background sub-agents that apply the `fix_proposal` patches to the spec/design/tasks files (same mechanism `/review-findings` already uses for code fixes).
- After `/review-findings` resolves all findings, re-run `/validate-spec $ARGUMENTS` exactly once to confirm `status: pass`. If findings remain after that single re-run, stop and surface them — further iterations require an explicit manual `/validate-spec` invocation (loop guard).
- If `status: error`: surface the error and instruct the user to re-run `/validate-spec $ARGUMENTS`.

## Blocking Semantics

`/implement` must refuse to start a task unless `specs/$ARGUMENTS/reports/spec-review.yaml` exists with `status: pass`. The preflight check in `commands/implement.md` enforces this. The error message points the user back here.

## Standalone vs Auto-Chained Use

- `/propose` auto-chains into `/validate-spec` at the end of spec generation — the user sees findings immediately.
- Standalone invocation remains supported for re-runs after manual edits to `spec.md` / `design.md` / `tasks/`.
