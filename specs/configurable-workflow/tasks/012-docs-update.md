---
id: "012"
name: "Update CLAUDE.md, workflow-diagram, and onboarding docs"
status: blocked
blocked_by: ["011"]
max_files: 3
estimated_files:
  - CLAUDE.md
  - docs/workflow-diagram.md
  - onboarding.md
test_cases:
  - "CLAUDE.md gains a Configurable Workflow section explaining three-file split, ceiling semantics, and loader"
  - "docs/workflow-diagram.md Mermaid diagrams updated for /explore step 0 and /validate intersection"
  - "onboarding.md walks through first-time bootstrap to explore to config approval flow"
  - "All three docs cross-reference each other consistently"
ground_rules:
  - general:documentation/general.md
---

## Description

Documentation-only task. Updates the three top-level docs to describe the new config layer, ceiling semantics, walk-up path resolution, three-file split, and the new `/config` command. Updates the Mermaid diagrams per the CLAUDE.md flow-change rule.

## Changes

- `CLAUDE.md` — new "Configurable Workflow" section. Cross-reference `specs/configurable-workflow/design.md` for ADR detail.
- `docs/workflow-diagram.md` — update Mermaid diagrams for `/explore` step 0 (inferencer node) and `/validate` ceiling intersection.
- `onboarding.md` — first-time walkthrough: bootstrap → explore → inferencer approval → implement → validate → ship.

## Empty-Intersection Declaration

This task is doc-only and declares `empty_intersection_ok: true` (ceiling semantics from T4): no gates apply, validation passes on doc review only.
