---
id: "014"
name: "/validate-impl command + Karen wrapper prompt"
status: done
blocked_by: []
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
  - "Union gate failure path: blocking gate exit non-zero forces audit verdict=reopen AND Karen still spawned with failing-gate output embedded in wrapper prompt as additional evidence"
  - "Non-blocking gate failure is recorded in audit report but does not force verdict=reopen"
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
- Monitor event categories `spec_audit_start` and `spec_audit_done` must be added to `scripts/monitor.sh` accept-list alongside FR-9's existing categories. The remaining FR-9 categories (`spec_complete`, `spec_reopened`, `spec_last_task_done`, `spec_reaudit_requested`) are owned by T015/T017 per the FR-9 ownership table.
- Gate execution (union mode) is NOT in this task — T016 owns scope-dependent gate invocation. `/validate-impl` calls into T016's helper once it exists.
- Fixture spec under `tests/fixtures/spec-audit/sample-spec/` with 3 FRs and 2 tasks — used for end-to-end smoke without hitting real Karen; stub agent invocation to return a canned report for tests.

## Implementation Notes (T014)

- Karen invocation is the slash-command's responsibility (Agent tool, `subagent_type: karen`); shell helpers in `scripts/validate-impl.sh` cover everything else and are unit-testable without spawning the agent.
- Helpers split: `wf_vi_parse_frs` (FR allowlist), `wf_vi_build_prompt` (wrapper), `wf_vi_write_report` (frontmatter + body), `wf_vi_set_spec_shipped` (yq `--front-matter=process` to edit only the YAML block of a Markdown file — honours the `no awk hacks for YAML` shell rule), `wf_vi_emit_*` (monitor events).
- Monitor allowlist (`scripts/monitor-validators.sh`): added `spec_audit_start`, `spec_audit_done`, `spec_complete`, `spec_reopened`. Test cases 7/8 require the command to emit `spec_complete`/`spec_reopened`, so they ship in T014's allowlist; the remaining FR-9 categories (`spec_last_task_done`, `spec_reaudit_requested`) are deferred to T015.
- T016 owns the union-gate executor; `commands/validate-impl.md` Step 2 is documented but inert until that helper lands. Blocking-gate failure forces `verdict=reopen` AND still spawns Karen with failing output as additional evidence — `wf_vi_build_prompt` accepts an `extra_evidence` file argument so the contract is exercised today (`test_build_prompt_includes_extra_evidence`).
