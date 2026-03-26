---
name: propose
description: Generate specification, design, and tasks for a feature
agent: 'agent'
argument-hint: "feature name"
---

Generate specification, design, and tasks for a feature.

The user should provide the feature name in their message.

## Prerequisites
1. Check that `knowledge-base/` directory exists — if not, refuse and instruct the user to run `/bootstrap` first

## Steps
1. Read `specs/<feature>/prd.md` if it exists, otherwise use conversation context
2. Read `knowledge-base/_index.md` and identify all applicable rules
3. Read the applicable rule files

## Generate Artifacts

### specs/<feature>/spec.md
- Detailed functional specification
- All scenarios in BDD format: Given / When / Then
- Edge cases and error scenarios explicitly listed
- Reference applicable `knowledge-base/` rules

### specs/<feature>/design.md

#### Architecture Review

Before writing design.md, invoke `@software-architect` with the following context:
- The spec.md content (already generated above)
- All applicable `knowledge-base/architecture/` rules
- The project's CLAUDE.md or copilot-instructions.md

Use this directive: "Evaluate the proposed architecture in the spec against the provided architecture rules. For each major architectural decision, produce a trade-off analysis and an ADR. Flag any patterns that introduce irreversible coupling, scaling risks, or that the team is unlikely to sustain. Use the Proposal Output format defined in your agent definition."

##### Agent Output Contract
The `@software-architect` agent returns findings using its structured format:
1. **Trade-off analysis** — for each major decision: decision name, options considered, chosen option, what is gained, what is given up
2. **ADRs** — one Architecture Decision Record per significant decision, using the ADR template
3. **Risk flags** — severity, description, and mitigation for each architectural concern

If the agent errors or is unavailable, proceed with design.md generation without agent input and note the limitation.

##### Embedding Agent Output
Incorporate the agent's trade-off analysis and ADRs directly into design.md:

- Architectural decisions with explicit references to `knowledge-base/architecture/` rules
- Explain WHY each decision was made against the ground rules
- Include agent-generated ADRs in an `## Architecture Decision Records` section
- Include agent trade-off analysis alongside each architectural decision
- Module boundaries, dependency direction, data flow
- Reference `knowledge-base/languages/` for language-specific patterns

### specs/<feature>/tasks/NNN-{task-name}.md
- Split implementation into small tasks
- Each task's `ground_rules` field lists the specific knowledge-base files that apply — this becomes the single source of truth for `/implement` and `/validate`
- Set `status: blocked` with `blocked_by` IDs for tasks with dependencies
- Set `status: todo` for tasks with no dependencies

## Constraints
- Max 20 files per task
- Each task references applicable `knowledge-base/` rules in the `ground_rules` field
- Each task includes natural-language test cases (human defines names, AI implements bodies later)
- Tasks ordered by dependency (`blocked_by` fields)
- AI explains architectural decisions against ground rules, not just outputs code
- Tasks must be small enough for meaningful human code review

Present all generated artifacts for human review before proceeding to implementation.
