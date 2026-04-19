---
id: "013"
name: "validate_scope field + loader export"
status: blocked
blocked_by: ["002"]
max_files: 5
estimated_files:
  - scripts/config-loader.sh
  - scripts/config-paths.sh
  - templates/workflow.yml.template
  - templates/spec-config.yml.template
  - tests/test-config-loader.sh
test_cases:
  - "config-loader.sh exports WF_VALIDATE_SCOPE=per-task when .workflow.yml omits the field"
  - "config-loader.sh exports WF_VALIDATE_SCOPE=per-spec when .workflow.yml sets per-spec"
  - "config-loader.sh --spec <f> uses spec config.yml override when both repo and spec declare scope"
  - "config-loader.sh rejects validate_scope=disabled with exit 2 and names the enum"
  - "templates/workflow.yml.template documents validate_scope with commented default"
  - "templates/spec-config.yml.template includes optional validate_scope override example"
  - "grep guard: no workflow script sources config-loader.sh before exporting WF_VALIDATE_SCOPE"
ground_rules:
  - general:languages/shell.md
  - general:security/general.md
  - general:architecture/general.md
---

## Description

Add `validate_scope` cadence knob to the config loader chain. Extends `.workflow.yml` (repo default) and `specs/<feature>/config.yml` (per-spec override) with an enum field controlling whether `/validate` fires per-task, per-spec, or both. Loader validates enum and exports `WF_VALIDATE_SCOPE`.

## Public API delta

- `config-loader.sh` — parse + validate `validate_scope` against allowlist `{per-task, per-spec, both}`; export `WF_VALIDATE_SCOPE`; spec override wins when `--spec` loaded; fail closed on unknown values (exit 2, same code as invalid-path failures).
- `scripts/config-paths.sh` — add `validate_scope_enum_check` helper (reusable from Rust parser parity tests via shared fixtures).

## Implementation Notes

- Default = `per-task` when field absent in both repo and spec configs (back-compat).
- Spec override wins when both declare the field.
- `WF_VALIDATE_SCOPE` emitted alongside existing `WF_*` vars; CLI `export` mode emits it too.
- Update `templates/workflow.yml.template` with commented-out default documenting all three values.
- Update `templates/spec-config.yml.template` to show optional override example.
- Fixture additions under `tests/fixtures/config/` (no new top-level directories): `workflow-scope-per-task.yml`, `workflow-scope-per-spec.yml`, `workflow-scope-invalid.yml`, `spec-config-scope-override.yml`.
- Loader does NOT invoke `/validate-impl` — it only exposes the field. Cadence enforcement lives in T016.
