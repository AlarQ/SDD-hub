---
id: "016"
name: "Per-spec gate skip + union execution at /validate-impl"
status: implemented
blocked_by: []
max_files: 4
estimated_files:
  - commands/validate.md
  - commands/validate-impl.md
  - scripts/monitor.sh
  - tests/test-scope-semantics.sh
test_cases:
  - "/validate reads WF_VALIDATE_SCOPE; when per-spec, emits gate_skip with reason scope=per-spec and runs zero gates"
  - "/validate under scope=per-task runs full intersection (unchanged from T004 semantics)"
  - "/validate under scope=both runs full intersection AND allows /validate-impl to run later"
  - "/validate-impl executes union of spec-eligible gates (not per-task intersection) against cumulative diff"
  - "Union execution counts each unique gate once across the spec, not once per task"
  - "gate_skip event for per-spec-skipped tasks includes task id, feature, scope, and gate ids skipped"
  - "/implement auto-chain under scope=per-spec proceeds to /review-findings with zero findings after gate_skip"
  - "Doc-only tasks with empty_intersection_ok: true pass cleanly under all three scope modes"
  - "Union execution: blocking gate non-zero exit → audit verdict forced to reopen; failing-gate output passed to Karen wrapper as evidence"
  - "Union execution: non-blocking gate failure recorded but does not force reopen"
ground_rules:
  - general:languages/shell.md
  - general:architecture/general.md
  - general:testing/principles.md
---

## Description

Make scope semantics real. `/validate` honors `WF_VALIDATE_SCOPE` and short-circuits per-task execution when `per-spec` is chosen. `/validate-impl` computes the union of spec-eligible gates (FR-2 `applies_to` filter ∩ FR-3 spec ceiling) and runs each once against the cumulative diff.

## Public API delta

- `commands/validate.md` — first step: read `WF_VALIDATE_SCOPE`. If `per-spec`: emit `gate_skip` events for every gate in the task's intersection with `reason=scope=per-spec`, then exit zero-findings. If `per-task` or `both`: existing T004 semantics.
- `commands/validate-impl.md` — new step (inserted before Karen spawn per FR-15 step 2): if `scope ∈ {per-spec, both}`, compute union `{g | g ∈ WF_SPEC_GATES ∧ g.applies_to ∩ union(task.ground_rules_languages) ≠ ∅}`, execute each gate once against the cumulative diff range. Results are part of the audit report input.
- `scripts/monitor.sh` — accept `scope=per-spec` as a valid `gate_skip` reason string alongside existing reasons.

## Implementation Notes

### T016 delivered

- **Scope short-circuit** in `commands/validate.md` Phase 1: when `WF_VALIDATE_SCOPE=per-spec`, emits `gate_skip` with `reason=scope=per-spec` for every gate in the effective set, writes a zero-findings `*-scope-skip.yaml` report, skips Phase 2. ADR-003 fail-closed still fires before short-circuit.
- **Union runner** in `scripts/validate-impl.sh` (co-located with `/validate-impl`, keeps `monitor.sh` leaf-clean). Public helpers:
  - `wf_vi_task_languages` / `wf_vi_union_languages` — parse `ground_rules` for `languages/<x>.md` tags.
  - `wf_vi_compute_union` — `WF_SPEC_GATES ∩ {g | applies_to ∩ langs ≠ ∅ ∨ "any" ∈ applies_to}`, `sort -u` ⇒ deterministic order; gate ids dedup to once per spec.
  - `wf_vi_run_union_gates` — executes each gate once against cumulative diff. Stdout `reopen` on blocking-gate non-zero exit, rc 3 on empty union for code-bearing spec (ADR-003), `""` otherwise.
- `commands/validate-impl.md` Step 2 now calls `wf_vi_run_union_gates` directly (T014 placeholder retired).
- `scripts/monitor.sh` requires no code change: reasons aren't validated; `scope=per-spec` payload rides existing contract. `test-scope-semantics.sh` asserts round-trip.
- Sort order: union is `sort -u` over gate ids — alphabetical, unique.
- Parallelism: kept sequential in helper for deterministic log ordering / fail-closed rc; the Phase-2 advisory-agent parallelism in `/validate` is unchanged.

### Original notes

- "Cumulative diff" range = first-task branch-point → current HEAD. Same range used by Karen wrapper prompt in T014.
- Union computation is deterministic given sorted inputs — document the sort order.
- Gate execution paralysm: same parallelism model as current `/validate` (spawn agents in parallel per existing `/validate` Phase 2 pattern).
- Empty-intersection fail-closed rule (ADR-003) still applies: if the union is empty AND at least one task is code-bearing, `/validate-impl` fails closed before spawning Karen.
- Do NOT bypass fail-closed when `scope=per-spec` — an empty union on a code spec is still a bug.
