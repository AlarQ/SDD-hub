---
id: "005"
name: "Restructure TUI layout to sidebar + 2x2 grid"
status: done
pr_url: https://github.com/AlarQ/SDD-hub/pull/15
blocked_by: []
max_files: 5
estimated_files:
  - workflow-tui/src/ui/layout.rs
  - workflow-tui/src/ui/mod.rs
  - workflow-tui/src/app.rs
  - workflow-tui/src/ui/spec_list.rs
  - workflow-tui/src/ui/styles.rs
test_cases:
  - "build_layout returns sidebar rect and 4 grid rects"
  - "sidebar width is approximately 25% of terminal width"
  - "grid panels divide remaining 75% into 2x2"
  - "panel cycle includes all 5 panels"
  - "existing panels render without errors in new layout"
  - "SpecList renders correctly in narrow sidebar dimensions"
  - "tab navigation cycles through all panels"
  - "scroll behavior works correctly for each panel"
ground_rules:
  - project:languages/rust.md
  - general:architecture/general.md
  - general:style/general.md
---

## Description

Restructure the TUI layout from a 2x2 grid to a left sidebar (SpecList) + right 2x2 grid (DepGraph, Reports, Progress, Monitor).

This is the highest-risk task — it touches every UI module. Implement and verify all 4 existing panels render correctly before adding Monitor.

## Changes

### `ui/layout.rs`
- Replace `build_grid(area: Rect) -> [Rect; 4]` with `build_layout(area: Rect) -> DashboardLayout`
- `DashboardLayout` struct: `sidebar: Rect`, `grid: [Rect; 4]`

### `app.rs`
- Add `Panel::Monitor` variant
- Update `next()`/`prev()` to cycle through all 5 panels
- SpecList is now always rendered (sidebar) but Tab still cycles to it for active selection

### `ui/mod.rs`
- Update `render()` to use `DashboardLayout`
- Render SpecList in sidebar, other 4 panels in grid cells
- Add placeholder for Monitor panel (actual rendering in task 006)

### `ui/spec_list.rs`
- May need width adjustments for narrow sidebar rendering

## Implementation Notes

- `build_grid` replaced with `build_layout` returning `DashboardLayout { sidebar, grid: [Rect; 4] }` — sidebar ~25%, grid ~75%
- `Panel::Monitor` added to enum with full `next()`/`prev()` cycle: SpecList → DepGraph → Reports → Progress → Monitor → SpecList
- Monitor panel renders a placeholder ("coming in task 006") — actual event rendering deferred to task 006
- `spec_list.rs` needed no changes — List widget handles narrow sidebar width gracefully at 25% (~20 cols on 80-wide, ~50 cols on 200-wide)
- `styles.rs`: added `#[allow(dead_code)]` to `event_category_color` which was added in task 004 but is used in task 006
- Git branch uses `--` separator (`feat/spec-implementation-monitor--005-tui-layout-sidebar`) because git disallows a branch name that is a prefix path of an existing branch
- All 8 test cases implemented across `ui/layout.rs` (5 tests) and `app.rs` (3 tests)
