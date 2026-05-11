---
id: "011"
name: "Retire workflow-tui crate"
status: blocked
blocked_by: ["010"]
max_files: 6
estimated_files:
  - Cargo.toml
  - CLAUDE.md
  - README.md
  - .cargo/config.toml
  - workflow-tui
  - docs/workflow-diagram.md
test_cases:
  - "workflow-tui directory removed from working tree"
  - "Cargo.toml workspace members no longer reference workflow-tui"
  - "cargo check --workspace passes after removal"
  - "cargo test --workspace passes after removal"
  - "CLAUDE.md contains no references to workflow-tui"
  - "CLAUDE.md Build & Run section reflects workflow-web only"
  - "README references workflow-web as the dashboard"
  - "workflow-core still builds standalone (no TUI-only code leaked into core)"
  - "git history preserves prior TUI source (no force-push)"
ground_rules:
  - general:architecture/general.md
  - project:languages/rust.md
---

## Description

Final task per FR-24. Delete `workflow-tui/` crate. Update workspace, CLAUDE.md, README, cargo aliases, and `docs/workflow-diagram.md` to reflect the new dashboard surface. Verifies `workflow-core` remains UI-agnostic.

## Implementation Notes

- Pure deletion + doc updates; no behavior change in `workflow-web` or `workflow-core`.
- Remove `tui` alias from `.cargo/config.toml`.
- Update `docs/workflow-diagram.md` if it references the TUI.
