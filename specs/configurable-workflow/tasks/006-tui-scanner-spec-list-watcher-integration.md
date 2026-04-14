---
id: "006"
name: "TUI scanner, spec_list, and watcher integration"
status: blocked
blocked_by: ["005"]
max_files: 5
estimated_files:
  - workflow-tui/src/parse/scanner.rs
  - workflow-tui/src/model/spec.rs
  - workflow-tui/src/ui/spec_list.rs
  - workflow-tui/src/watcher.rs
  - workflow-tui/src/app.rs
test_cases:
  - "Scanner picks up specs from non-default spec_storage path"
  - "TUI renders legacy spec without config.yml using a 'no config' indicator"
  - "Editing .workflow.yml triggers single reload within debounce window"
  - "Parse error keeps last-good config and surfaces ParseWarning (non-fatal)"
  - "Spec.config field is None when per-spec config.yml is absent"
  - "App holds WorkflowConfig at top of state tree; UI receives immutable refs"
ground_rules:
  - general:languages/rust.md
  - general:architecture/general.md
---

## Description

Wire the new parsers from T5 into the TUI state tree. Replace the hardcoded `"specs/"` in `parse/scanner.rs` with the configured `spec_storage`. Extend the file watcher to react to `.workflow.yml` changes with ≥100 ms debounce. Add `config: Option<SpecConfig>` to `model::Spec`.

## Changes

- `parse/scanner.rs:7` (and any other hardcoded `specs/` reference) → use `WorkflowConfig.spec_storage` resolved at app start.
- `model/spec.rs` → add `pub config: Option<SpecConfig>` field; populated by scanner via `parse::spec_config::parse`.
- `ui/spec_list.rs` → read `WorkflowConfig.spec_storage` (no IO); render "no config" indicator for legacy specs.
- `watcher.rs` → also watch `.workflow.yml`; debounce events ≥100 ms to coalesce editor save bursts.
- `app.rs` → hold `WorkflowConfig` at top of state tree; pass immutable references to UI modules.

## Implementation Notes

- Parse failures surface as non-fatal `ParseWarning`; TUI keeps last-good config and continues rendering.
- UI never calls `parse::*` directly; `app.rs` orchestrates load → state → re-render.
- Single source of truth for spec_storage path: `parse::workflow_config::load`. No other module locates `.workflow.yml`.
