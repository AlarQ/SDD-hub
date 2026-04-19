---
id: "017"
name: "Spec audit report + /review-findings integration + reopen flow"
status: blocked
blocked_by: ["014"]
max_files: 5
estimated_files:
  - commands/review-findings.md
  - commands/validate-impl.md
  - scripts/task-manager.sh
  - docs/workflow-diagram.md
  - tests/test-spec-audit-integration.sh
test_cases:
  - "/review-findings accepts a specs/<feature>/reports/spec-audit-*.md report (source: llm)"
  - "Accepted 'missing FR' finding auto-creates a follow-up task via task-manager.sh with status: todo"
  - "Follow-up task filename uses next-sequential id and name references the FR id"
  - "Follow-up task ground_rules inherit from spec.md Applicable Ground Rules section"
  - "Rejected finding is available as a project-KB rule candidate via the normal feedback loop"
  - "Unknown FR id in report (e.g. FR-99 with only FR-1..17 declared) → fail closed, no task created, error names unknown ids and the FR list consulted"
  - "Reopen flow: after follow-up tasks reach done, /validate-impl re-runs and clears the spec_audit_done idempotency guard when a deliberate re-audit is requested"
  - "Report frontmatter schema validated: {feature, timestamp, scope, verdict} required; verdict ∈ {complete, reopen}"
  - "Audit report body contains FR matrix section with explicit status per FR ∈ {implemented, partial, missing}"
  - "docs/workflow-diagram.md documents the create-followup transition and the audit → /review-findings → follow-up-task reopen loop"
ground_rules:
  - general:languages/shell.md
  - general:security/general.md
  - general:architecture/general.md
  - general:testing/principles.md
  - general:documentation/general.md
---

## Description

Close the loop: route Karen's audit output through the existing `/review-findings` accept/reject machinery (same affordance as per-task LLM findings), auto-create follow-up tasks for accepted "missing" / "partial" findings, and wire the reopen path so a spec that fails its audit does not ship.

## Public API delta

- `commands/review-findings.md` — extend the report parser to recognize `spec-audit-*.md` reports. Reuse the existing group-by-file/category grouping; each missing/partial FR is one review unit. `source: llm` (same as other agent findings).
- `commands/validate-impl.md` — on `verdict: reopen`, hand the report to `/review-findings`. On accept, invoke `task-manager.sh create-followup <feature> <fr-id> <fr-description>` (new helper). On reject, the finding remains available for the normal rule-candidate review flow.
- `scripts/task-manager.sh` — add `create-followup <feature> <fr-id> <description>` subcommand that:
  1. Validates FR id against `spec.md` heading list (FR-id allowlist per FR-17 security).
  2. Finds next sequential task id.
  3. Writes a task file with `status: todo`, `ground_rules` inherited from spec's Applicable Ground Rules section, `name` referencing the FR id.
  4. Leaves the idempotency guard in place — user must invoke `/validate-impl --reaudit` explicitly to clear it (prevents event-log churn on normal task completion cycles).

## Implementation Notes

- FR-id allowlist is the critical security boundary. Karen can hallucinate. Reject unknown FR ids loudly with the full FR list attached.
- Follow-up tasks inherit spec ground_rules rather than re-inferring — deterministic, auditable, avoids second LLM round.
- Rejected findings becoming KB rules piggybacks on the existing `/learn-from-reports` mining pass; no new code here — the report just remains in `reports/` until that command runs.
- `/validate-impl --reaudit` flag added to `commands/validate-impl.md`. Kept small. **Mechanism (append-only, no log mutation):** the flag appends a `spec_reaudit_requested` sentinel event to `.monitor.jsonl` with `{feature, requested_ts, reason}`. It does NOT truncate, rewrite, or delete any prior `spec_audit_done` event — event logs are strictly append-only and the audit trail must remain intact.
- **T015 detector rule (updated for the reaudit path):** scan `.monitor.jsonl` for the most-recent event among `{spec_audit_done, spec_reaudit_requested}` for the given feature. If the newest is `spec_reaudit_requested` (or no `spec_audit_done` exists yet), the guard is considered **clear** and the detector fires `spec_last_task_done` → `/validate-impl`. If the newest is `spec_audit_done`, the guard holds and the detector is a no-op. A fresh `spec_audit_done` emitted at the end of the next audit cycle re-closes the guard.
- After all follow-up tasks transition to `done`, the T015 trigger re-emits `spec_last_task_done` (guard considered clear because the reaudit sentinel is more recent than any prior `spec_audit_done`) and the chain runs `/validate-impl` again. Cycle converges when verdict = complete.
- New category `spec_reaudit_requested` MUST be added to monitor.sh's closed allowlist in the same PR (per T003 §New capability) — attempting to emit it without the allowlist entry will fail closed.
