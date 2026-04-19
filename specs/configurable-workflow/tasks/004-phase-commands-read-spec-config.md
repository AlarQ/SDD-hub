---
id: "004"
name: "Phase commands read spec config and apply ceiling semantics"
status: blocked
blocked_by: ["002", "003"]
max_files: 6
estimated_files:
  - commands/propose.md
  - commands/implement.md
  - commands/validate.md
  - commands/pr-review.md
  - commands/review-findings.md
  - commands/ship.md
test_cases:
  - "/validate runs intersection of spec ceiling and ground_rules eligible gates"
  - "/validate emits gate_skip event for ground_rules gate outside spec ceiling"
  - "/validate empty intersection on code task fails closed and blocks transition to done"
  - "/validate (and every active phase command) with missing config.yml exits non-zero (loader exit 4), names the spec and expected path, executes no gate, spawns no agent"
  - "/implement snapshots spec config at task start and /ship detects mid-task drift"
  - "Unknown agent ID in spec config causes phase command to exit non-zero (no silent fallback)"
  - "Doc-only task with empty-OK declaration succeeds with zero gates"
  - "Snapshot drift uses normalized JSON of effective fields (gates[], agents map), not raw YAML"
  - "Whitespace-only edit to config.yml does NOT trigger drift"
  - "Gate removed or added to config.yml DOES trigger drift"
  - "Integration seam: phase command composes loader --spec output with task ground_rules into intersection"
ground_rules:
  - general:security/general.md
  - general:architecture/general.md
  - general:testing/principles.md
  - general:code-review/general.md
  - general:documentation/general.md
---

## Description

Update the five phase commands to source the loader with `--spec`, read the agent list from `WF_SPEC_AGENTS_<PHASE>`, and (for `/validate`) compute the ceiling intersection per ADR-003.

## Ceiling Semantics

`/validate` runs the intersection of:
1. Spec-eligible gates from `WF_SPEC_GATES` (the ceiling)
2. Gates eligible for the task's `ground_rules` (language + category match against `gates.yml::applies_to`)

Skipped gates emit `gate_skip` monitor events with explicit reason (`not in spec ceiling`, `empty intersection`).

**Failure mode:** empty intersection on a code-bearing task → fail closed → block transition to `done`. Doc-only tasks may declare `empty_intersection_ok: true` in task frontmatter.

## Snapshot for tamper detection

`/implement` snapshots the resolved spec config at task start (writes to `.monitor-context` or task state); `/ship` re-reads `config.yml`, compares against snapshot, refuses to proceed on drift until config is re-approved or restored.

## Mandatory spec config — no fallback

`config.yml` is required for every active phase command. Loader `--spec <feature>` against a spec without `config.yml` returns exit 4; phase commands propagate the non-zero exit, print an explicit error naming the spec and expected path, and do not execute any gate or spawn any agent. There is no hardcoded-default fallback. Pre-existing done specs (shipped before this feature) are not processed by active commands and are out of scope. No TUI work in this spec.

## Implementation Notes

- All five command markdown files document the loader-source step at the top.
- Unknown agent IDs in `config.yml` exit non-zero — no silent fallback.
- Reviewer should diff all five files together for consistency.

## Scope Phasing (out-of-scope for this task)

T004 implements the **per-task cadence only**. `WF_VALIDATE_SCOPE` does **not** exist yet — it is introduced by T013 and consumed by T016, which later layers the `per-spec` skip branch on top of `commands/validate.md`. For all T004 tests, assume `scope=per-task` (the default). T004 must not read `WF_VALIDATE_SCOPE` nor reference `validate_scope` anywhere. The T004 ↔ T016 hand-off on `commands/validate.md` is additive: T016 wraps T004's ceiling-intersection logic with a scope check; T004 tests continue to pass unchanged after T016 ships.
