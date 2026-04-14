---
id: "007"
name: "TUI pipeline widget for configured gates and agents"
status: blocked
blocked_by: ["006"]
max_files: 3
estimated_files:
  - workflow-tui/src/ui/pipeline.rs
  - workflow-tui/src/ui/mod.rs
  - workflow-tui/src/ui/layout.rs
test_cases:
  - "Pipeline widget renders gates in spec ceiling for a Rust task"
  - "Pipeline widget marks ceiling-skipped gates distinctly from executed gates"
  - "Empty intersection on a code task shows fail-closed indicator"
  - "Doc-only task with empty-OK declaration renders OK state"
  - "Intersection computation matches shell loader fixture for the same inputs"
  - "No other UI module computes effective gates (single source of truth)"
  - "Parity fixture: both shell loader and pipeline widget emit sorted JSON {executed:[...], skipped:[...]} and byte-compare equal for the same input fixture"
  - "Architectural test asserts ui::pipeline is the only module that computes intersection"
ground_rules:
  - general:languages/rust.md
  - general:architecture/general.md
---

## Description

New `ui/pipeline.rs` widget — sole renderer in Rust of the ceiling ∩ ground_rules intersection per ADR-003. Computes the same eligible gate set as the shell loader so the TUI display always matches what `/validate` will execute.

## Behavior

- Inputs: `&SpecConfig`, `&Task`, `&[Gate]`.
- Outputs: per-phase pipeline view showing `executed`, `skipped (not in ceiling)`, `skipped (no language match)`, and `empty intersection — fail closed` states.
- Wired into the main layout, reachable from the spec detail view.

## Implementation Notes

- Shared test fixtures with `tests/fixtures/config/` (T2) so shell and Rust intersection logic verify against the same inputs.
- No other UI module duplicates the intersection computation. Keep this widget as the only place that computes effective gates in Rust.
- Pure render function: takes references, returns `Widget` — no IO.
