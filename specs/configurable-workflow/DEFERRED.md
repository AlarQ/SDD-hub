# Deferred — TUI scope cut from configurable-workflow

## What was cut

- **FR-13** (TUI Additions) — marked deferred in `spec.md`, number reserved.
- **Task 005** — `tui-config-parsers-and-models` (deleted).
- **Task 006** — `tui-scanner-spec-list-watcher-integration` (deleted).
- **Task 007** — `tui-pipeline-widget` (deleted).
- All TUI-related notes removed from `spec.md`, `prd.md`, `design.md`, `test-strategy.md`, and cross-referencing tasks (T004, T011, T016).

Task IDs 005–007 are unused; remaining tasks keep their original IDs (no renumbering).

## Why

User is reconsidering TUI investment — a web UI may replace or supplement `workflow-tui/`. Building Rust parser parity and a pipeline widget in this spec risks throwaway work. Shell-side work (config files, loader, phase-command wiring, inferencer, `/validate-impl`, spec audit) is independent and proceeds unchanged.

## What this spec still guarantees (no TUI dependency)

- `.workflow.yml`, `knowledge-base/gates.yml`, `specs/<feature>/config.yml` schemas.
- `scripts/config-loader.sh` + `scripts/config-paths.sh` + shell caller integration.
- Ceiling semantics at `/validate` (FR-7), snapshot drift detection in `/ship`.
- `/explore` step 0 inferencer, `/config`, `/bootstrap` on existing repos.
- `validate_scope` + `/validate-impl` + Karen wrapper + last-task-done trigger.
- All security scenarios (FR-level, loader-level, phase-command-level).

## What a future UI spec must pick up

Either a TUI continuation or a web UI replacement must implement:

1. **`.workflow.yml` parser** — walk-up discovery, realpath defense, same exit semantics as shell loader. (Was `workflow-tui/src/parse/workflow_config.rs`.)
2. **`specs/<feature>/config.yml` parser** — tolerates absent file for legacy/pre-existing done specs. (Was `workflow-tui/src/parse/spec_config.rs`.)
3. **`gates.yml` parser** — duplicate-ID / unknown `applies_to` / unknown `category` rejection. (Was `workflow-tui/src/parse/gates.rs`.)
4. **Scanner integration** — use resolved `spec_storage` instead of hardcoded `specs/`. (Was `workflow-tui/src/parse/scanner.rs` modification.)
5. **Pipeline widget** — sole renderer of ceiling intersection (`spec-eligible ∩ task ground_rules`). Must render `validate_scope` badge and a spec-audit column. Parity assertion against shell loader output required. (Was `workflow-tui/src/ui/pipeline.rs`.)
6. **Watcher** — reload on `.workflow.yml` edits, debounce ≥100 ms. Keep last-good config on parse error. (Was `workflow-tui/src/watcher.rs` modification.)
7. **Shared fixtures** — reuse `tests/fixtures/config/*` created by T001/T002; do not duplicate.

## Cross-references preserved

- `spec.md` §FR-13 retains a stub pointing here.
- `design.md` §"Service boundaries — Rust" reduced to a pointer here.
- `test-strategy.md` T005/T006/T007 collapsed to a pointer here.
- `prd.md` §OUT lists TUI deferral.
