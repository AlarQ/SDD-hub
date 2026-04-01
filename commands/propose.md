Generate specification, design, and tasks for a feature.

Feature name: $ARGUMENTS

## Prerequisites
1. Check that `~/.claude/knowledge-base/` (general) exists — if not, refuse and say: "General knowledge base not found. Run `setup.sh` from the dev-workflow repo first."
2. Check that `knowledge-base/` (project) exists — if not, refuse and instruct the user to run `/bootstrap` first

## Steps
1. Read `specs/$ARGUMENTS/prd.md` if it exists, otherwise use conversation context
2. Read both `~/.claude/knowledge-base/_index.md` (general rules) and `knowledge-base/_index.md` (project rules) — identify all applicable rules from both
3. Read the applicable rule files from both knowledge bases

## Ground Rules Prefix Convention
When referencing knowledge-base rules in `ground_rules` fields, use prefixes:
- `general:` — resolves to `~/.claude/knowledge-base/` (e.g., `general:security/general.md`)
- `project:` — resolves to `knowledge-base/` (e.g., `project:languages/rust.md`)
- Unprefixed paths default to `project:` for backward compatibility

## Generate Artifacts

### specs/$ARGUMENTS/spec.md
- Detailed functional specification
- All scenarios in BDD format: Given / When / Then
- Edge cases and error scenarios explicitly listed
- Reference applicable rules from both knowledge bases

### specs/$ARGUMENTS/design.md

#### Agent-Assisted Architecture Review
Before writing design.md, spawn the `Software Architect` agent (`engineering-software-architect`) using the Agent tool. The agent receives:
- The spec.md content (already generated above)
- All applicable architecture rules from both `~/.claude/knowledge-base/architecture/` and `knowledge-base/architecture/` (if exists)
- The project's `CLAUDE.md`

Instruct the agent with this directive: "Evaluate the proposed architecture in the spec against the provided architecture rules. For each major architectural decision, produce a trade-off analysis and an ADR. Flag any patterns that introduce irreversible coupling, scaling risks, or that the team is unlikely to sustain. Use the Proposal Output format defined in your agent definition."

##### Agent Output Contract
The agent must return findings using the structured format defined in the `Software Architect` agent definition (`Proposal Output` section):
1. **Trade-off analysis** — for each major decision: decision name, options considered, chosen option, what is gained, what is given up
2. **ADRs** — one Architecture Decision Record per significant decision, using the ADR template
3. **Risk flags** — severity, description, and mitigation for each architectural concern

If the agent errors or times out, proceed with design.md generation without agent input and note the failure.

##### Embedding Agent Output
Incorporate the agent's trade-off analysis and ADRs directly into design.md:

- Architectural decisions with explicit references to knowledge-base rules (both general and project)
- Explain WHY each decision was made against the ground rules
- Include agent-generated ADRs in an `## Architecture Decision Records` section
- Include agent trade-off analysis alongside each architectural decision
- Module boundaries, dependency direction, data flow
- Reference `knowledge-base/languages/` for language-specific patterns

### specs/$ARGUMENTS/tasks/NNN-{task-name}.md
- Split implementation into small tasks
- Each task's `ground_rules` field lists the specific knowledge-base files that apply using the prefix convention (`general:` / `project:`) — this becomes the single source of truth for `/implement` and `/validate`
- Set `status: blocked` with `blocked_by` IDs for tasks with dependencies
- Set `status: todo` for tasks with no dependencies

## Constraints
- Max 20 files per task
- Each task references applicable rules from both knowledge bases in the `ground_rules` field using prefix convention
- Each task includes natural-language test cases (human defines names, AI implements bodies later)
- Tasks ordered by dependency (`blocked_by` fields)
- AI explains architectural decisions against ground rules, not just outputs code
- Tasks must be small enough for meaningful human code review

Present all generated artifacts for human review before proceeding to implementation.
