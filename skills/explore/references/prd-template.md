# PRD template

The PRD lives at the **WHY** altitude — problem, value, scope, decisions. It defers all HOW (wire detail, endpoint contracts, schema, ADR bodies, BDD scenarios) to `spec.md` / `design.md`, referencing them by id rather than restating them.

## Required section order

A PRD contains exactly these sections, in this order:

- `## Problem` — what hurts today and why it matters. No solution detail.
- `## User & Value` — who this is for and the value delivered to them.
- `## Scope` — with `### In` and `### Out` subsections. What this feature does and explicitly does not cover.
- `## Decisions Captured` — one `D-<id>` bullet per decision, one line each. Reference any relevant `docs/adr/` decision **by id** (e.g. `see ADR-0007`); do NOT restate ADR content. NO ADR bodies.
- `## Open Questions for /propose` — unresolved forks handed forward to the design phase.
- `## Agent Insights (Explore Phase)` — all agent outputs collected during the conversation, labeled by agent name, marked **advisory**. Omit agents that were not spawned or that errored.

## Hard boundary

**MUST NOT contain: endpoint contracts, status codes, request/response JSON, DDL, schema tables, ADR bodies, BDD scenarios → name them and defer to spec.md / design.md by id.**

This negative rule is the enforcement mechanism: if a HOW-level artifact would appear in the PRD, name the thing and point at where it belongs, don't inline it. The PRD stays scannable and stable; the wire detail churns in spec.md / design.md.
