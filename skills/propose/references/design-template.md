# Embedding Agent Output in design.md

This file is the authoritative statement of the spec.md ↔ design.md boundary.

## Anti-duplication rule (read first)

**MUST reference spec.md's FR-N / EP-* / Data Model tables by id. MUST NOT restate endpoint bodies or re-declare schema/DDL that spec.md's Data Model owns. design.md owns the WHY — rationale, trade-offs, ADRs, module boundaries — and references wire detail by id.**

## ADR sub-template

The ADR sub-template to use for the `## Architecture Decision Records` section lives at `agents/engineering/engineering-software-architect.md` (the "Architecture Decision Record Template" section, ~lines 129–145). Reference it as the authority; do not copy it here.

## Embedding Agent Output in design.md

Incorporate all agent outputs directly into design.md:

- Architectural decisions with explicit references to knowledge-base rules
- Explain WHY each decision was made against the ground rules
- Include Software Architect ADRs in an `## Architecture Decision Records` section
- Include trade-off analysis alongside each architectural decision
- Include Backend Architect schema and API contracts in a `## Backend Design` section (if spawned)
- Include UX Architect component hierarchy and layout in a `## Frontend Architecture` section (if spawned)
- Include UI Designer component specs in a `## UI Specifications` section (if spawned)
- Include AI Engineer model/pipeline design in a `## AI/ML Architecture` section (if spawned)
- Module boundaries, dependency direction, data flow
- Reference `$WF_GENERAL_KB/languages/` for language-specific patterns

## Embedding Mermaid Diagrams in design.md (large tier)

Embed every Mermaid block emitted by an agent verbatim under the section that holds the corresponding text:
- Software Architect's architecture `graph TB` → new `## Architecture Overview` section at the top of design.md (before ADRs).
- Software Architect's `stateDiagram-v2` → adjacent to the ADR that motivates it.
- Backend Architect's `erDiagram` and `sequenceDiagram` → inside the `## Backend Design` section, next to the schema and API contracts they describe.
- UX Architect's component-tree `graph TD` and user-flow `sequenceDiagram` → inside the `## Frontend Architecture` section.

Style: follow `docs/workflow-diagram.md` (solid arrows direct, dashed async/human, subgraph clusters). Every node/entity label MUST correspond to a term defined in spec.md or design.md prose — no orphan nodes.
