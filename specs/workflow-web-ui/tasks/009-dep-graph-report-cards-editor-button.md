---
id: "009"
name: "Dep-graph view + report finding cards + open-in-editor wiring"
status: blocked
blocked_by: ["008"]
max_files: 12
estimated_files:
  - workflow-web/src/ui/dep_graph.rs
  - workflow-web/src/ui/report_cards.rs
  - workflow-web/src/ui/finding_card.rs
  - workflow-web/src/ui/severity_ribbon.rs
  - workflow-web/src/ui/editor_button.rs
  - workflow-web/src/api/dep_graph_source.rs
  - workflow-web/style/cards.css
  - workflow-web/tests/dep_graph_render.rs
  - workflow-web/tests/report_cards_fields.rs
  - workflow-web/tests/playwright/dep_graph.spec.ts
  - workflow-web/tests/playwright/report_cards.spec.ts
  - workflow-web/tests/playwright/editor_button.spec.ts
test_cases:
  - "dep graph emits valid Mermaid graph TD source from tasks/*.md blocked_by edges"
  - "dep graph Mermaid source rendered inside the sandboxed Mermaid island"
  - "finding card renders all fields: code_snippet, fix_proposal, rationale, impact, references"
  - "finding card shows confidence field only when source=llm"
  - "finding card code_snippet is collapsed by default when > 20 lines"
  - "finding card expand toggle reveals full snippet"
  - "severity ribbon color reflects finding severity (critical/high/medium/low) with WCAG-AA contrast"
  - "editor button click navigates to vscode://file/<abs>:<line> via /api/open-in-editor"
  - "editor button href matches ^vscode://file/[^?#]+(:\\d+){0,2}$"
  - "editor button rejects line param that isn't a positive integer"
ground_rules:
  - general:security/general.md
  - general:architecture/general.md
  - general:architecture/api-design.md
  - general:languages/rust/api-layer.md
  - general:testing/principles.md
  - project:languages/rust.md
---

## Description

Final parity views: dep-graph (mermaid source generated server-side from `blocked_by` edges, rendered via island from 008), report finding cards (mirroring `/review-findings` card model with all fields), open-in-editor buttons calling `/api/open-in-editor` from 004. Implements FR-5, FR-6, FR-19, SEC-FR-10.

## Implementation Notes

- Dep graph source: walk task list, emit `<id>["<name>"]` nodes + `<from> --> <to>` edges; group by spec into subgraph.
- Finding card fields read directly from report YAML/JSON via `workflow_core::model::report`.
- Severity ribbon: 4px left border, color from `var(--<severity>-color)`.
- Editor button is a `<form action=… method=get>`-style submit OR an anchor; pre-validated href; opens in new tab.
