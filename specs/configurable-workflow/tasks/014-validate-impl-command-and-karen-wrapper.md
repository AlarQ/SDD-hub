---
id: "014"
name: "/validate-impl command + Karen wrapper prompt"
status: blocked
blocked_by: ["013"]
max_files: 4
estimated_files:
  - commands/validate-impl.md
  - scripts/monitor.sh
  - tests/test-validate-impl.sh
  - tests/fixtures/spec-audit/sample-spec/
test_cases:
  - "/validate-impl sources config-loader --spec <feature> and reads WF_VALIDATE_SCOPE"
  - "/validate-impl parses ### FR-N: headings from spec.md and builds an FR id list"
  - "Karen wrapper prompt contains spec.md FR list, prd.md scope, task list, report paths, git diff range"
  - "Karen wrapper prompt instructs FR × status matrix output with {implemented, partial, missing} enum"
  - "/validate-impl writes specs/<feature>/reports/spec-audit-<ISO8601>.md with frontmatter {feature, timestamp, scope, verdict}"
  - "spec_audit_start and spec_audit_done monitor events emitted in order"
  - "Clean audit sets spec.md frontmatter status: shipped and emits spec_complete event"
  - "Audit verdict=reopen leaves spec.md status unchanged and emits spec_reopened event"
  - "Karen agent is spawned via Agent tool with subagent_type=karen (no agent definition edits)"
ground_rules:
  - general:languages/shell.md
  - general:security/general.md
  - general:architecture/general.md
  - general:testing/principles.md
  - general:documentation/general.md
---

## Description

New slash command `/validate-impl <feature>` that runs the spec-completion audit. Reuses existing Karen agent (`agents/karen.md`) unchanged per ADR-008 — all spec-specific context flows through the wrapper prompt built in this command.

## Public API

- `commands/validate-impl.md` — new command definition. Takes `$ARGUMENTS = feature`. Steps per FR-15:
  1. `source scripts/config-loader.sh --spec "$feature"`
  2. Parse FR ids from `specs/<feature>/spec.md` (regex `^### (FR-[0-9]+):`) → allowlist.
  3. Build Karen wrapper prompt with: FR list, PRD scope block, task frontmatter list, `specs/<feature>/reports/` contents, git diff range from branch-point to HEAD.
  4. Spawn Karen via the Agent tool. Instruct: produce Markdown with frontmatter + FR matrix section + orphan-code section + over-engineering flags section.
  5. Persist report to `specs/<feature>/reports/spec-audit-<ISO8601>.md`.
  6. Emit `spec_audit_start` before spawn, `spec_audit_done` after report write.
  7. On `verdict: complete` → set spec.md frontmatter `status: shipped`, emit `spec_complete`.
  8. On `verdict: reopen` → emit `spec_reopened`; downstream `/review-findings` integration lives in T017.

## Implementation Notes

- Karen wrapper prompt is the only specialization surface. Keep it as a Markdown block in `commands/validate-impl.md` so it's versioned alongside the command.
- Monitor event categories `spec_audit_start`, `spec_audit_done`, `spec_complete`, `spec_reopened`, `spec_last_task_done` must be added to `scripts/monitor.sh` accept-list alongside FR-9's existing categories.
- Gate execution (union mode) is NOT in this task — T016 owns scope-dependent gate invocation. `/validate-impl` calls into T016's helper once it exists.
- Fixture spec under `tests/fixtures/spec-audit/sample-spec/` with 3 FRs and 2 tasks — used for end-to-end smoke without hitting real Karen; stub agent invocation to return a canned report for tests.
