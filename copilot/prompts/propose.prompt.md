---
name: propose
description: Generate specification, design, and tasks for a feature
agent: 'agent'
argument-hint: "feature name"
---

Generate specification, design, and tasks for a feature.

The user should provide the feature name in their message.

## Prerequisites
1. Check that `knowledge-base/_general/` (general) exists — if not, refuse and say: "General knowledge base not found. Run `setup-copilot.sh` from the dev-workflow repo first."
2. Check that `knowledge-base/` (project) exists with project-specific files — if not, refuse and instruct the user to run `/bootstrap` first

## Steps
1. Read `specs/<feature>/prd.md` if it exists, otherwise use conversation context
2. Read both `knowledge-base/_general/_index.md` (general rules) and `knowledge-base/_index.md` (project rules) — identify all applicable rules from both
3. Read the applicable rule files from both knowledge bases

## Ground Rules Prefix Convention
When referencing knowledge-base rules in `ground_rules` fields, use prefixes:
- `general:` — resolves to `knowledge-base/_general/` (e.g., `general:security/general.md`)
- `project:` — resolves to `knowledge-base/` (e.g., `project:languages/rust.md`)
- Unprefixed paths default to `project:` for backward compatibility

## Generate Artifacts

### specs/<feature>/spec.md

#### Security Analysis (before spec generation)
Before writing spec.md, perform a full STRIDE threat model for this feature using the security rules from both `knowledge-base/_general/security/` and `knowledge-base/security/` (if exists). Produce:
1. **STRIDE threat model** — category, threat description, severity, mitigation for each relevant threat
2. **Security requirements** — authentication, authorization, data-handling, and input-validation requirements
3. **Security ground rules** — specific knowledge-base security rules that must be referenced in task `ground_rules`

If `@security-engineer` agent is available, invoke it with the prd.md content and applicable security rules. Directive: "Produce a full STRIDE threat model for this feature. For each relevant STRIDE category, describe the threat, its severity, and recommended mitigation. Identify authentication, authorization, data-handling, and input-validation requirements."

Generate spec.md content:
- Detailed functional specification
- All scenarios in BDD format: Given / When / Then
- Edge cases and error scenarios explicitly listed
- Reference applicable rules from both knowledge bases
- Incorporate security findings as BDD scenarios for auth, input validation, and data handling
- Add a `## Security Scenarios` section with Given/When/Then for each threat mitigation

### specs/<feature>/design.md

#### Architecture & Design Review

Before writing design.md, perform the following analyses. All analyses receive the spec.md content, all applicable rules from both knowledge bases, and the project's CLAUDE.md or copilot-instructions.md.

##### Always perform:

**Software Architecture analysis**: Invoke `@software-architect` (if available) or perform inline. Directive: "Evaluate the proposed architecture in the spec against the provided architecture rules. For each major architectural decision, produce a trade-off analysis and an ADR. Flag any patterns that introduce irreversible coupling, scaling risks, or that the team is unlikely to sustain. Use the Proposal Output format defined in your agent definition."

##### Conditionally perform (based on spec content):

Check the spec.md content and prd.md for keyword matches:

**Backend Architecture analysis** — if backend-related keywords appear (`database`, `DB`, `schema`, `migration`, `API`, `endpoint`, `REST`, `GraphQL`, `infrastructure`, `server`, `backend`, `queue`, `cache`). Invoke `@backend-architect` (if available) or perform inline. Directive: "Design the backend architecture for this feature: database schema, API contracts, service boundaries, data-flow diagrams. Flag scaling risks and integration concerns. Reference applicable architecture and language rules."

**UX Architecture analysis** — if UI-related keywords appear (`UI`, `frontend`, `component`, `layout`, `CSS`, `design system`, `responsive`, `mobile`, `page`, `screen`, `form`, `modal`, `dashboard`). Invoke `@ux-architect` (if available) or perform inline. Directive: "Design the component architecture, layout framework, and CSS system for this feature. Define the component hierarchy, responsive breakpoints, and design-system integration. Provide developer-ready specifications."

**UI Design analysis** — perform alongside UX Architecture when UI keywords are detected. Invoke `@ui-designer` (if available) or perform inline. Directive: "Define design system specifications for this feature: component states and variations, responsive behavior, visual hierarchy, and accessibility requirements."

**AI/ML Architecture analysis** — if ML/AI keywords appear (`model`, `ML`, `machine learning`, `AI`, `training`, `inference`, `embeddings`, `neural`, `LLM`, `fine-tune`, `dataset`). Invoke `@ai-engineer` (if available) or perform inline. Directive: "Design the ML/AI architecture for this feature: model selection, data pipeline design, training/inference infrastructure, and integration patterns. Flag data requirements and scaling considerations."

If an agent is unavailable, perform the analysis inline. Note any limitations.

##### Analysis Output Contracts

**Software Architect** output:
1. **Trade-off analysis** — for each major decision: decision name, options considered, chosen option, what is gained, what is given up
2. **ADRs** — one Architecture Decision Record per significant decision, using the ADR template
3. **Risk flags** — severity, description, and mitigation for each architectural concern

**Backend Architect** output:
1. **Database schema** — tables/collections, relationships, indexes, migration strategy
2. **API contracts** — endpoints, request/response shapes, error codes
3. **Service boundaries** — module decomposition, dependency direction, data flow

**UX Architect** output:
1. **Component hierarchy** — tree of components, props/state ownership
2. **Layout framework** — grid system, responsive breakpoints, CSS architecture
3. **Design-system integration** — which existing tokens/components to reuse, what's new

**UI Designer** output:
1. **Component specs** — states (default, hover, active, disabled, error), variations
2. **Visual hierarchy** — spacing, typography scale, color usage
3. **Accessibility specs** — ARIA roles, keyboard navigation, contrast requirements

**AI Engineer** output:
1. **Model architecture** — model type, input/output schemas, performance targets
2. **Data pipeline** — data sources, preprocessing, storage, versioning
3. **Integration design** — API surface, latency requirements, fallback behavior

##### Embedding Analysis Output in design.md
Incorporate all analysis outputs directly into design.md:

- Architectural decisions with explicit references to knowledge-base rules (both general and project)
- Explain WHY each decision was made against the ground rules
- Include ADRs in an `## Architecture Decision Records` section
- Include trade-off analysis alongside each architectural decision
- Include backend schema and API contracts in a `## Backend Design` section (if applicable)
- Include component hierarchy and layout in a `## Frontend Architecture` section (if applicable)
- Include component specs in a `## UI Specifications` section (if applicable)
- Include model/pipeline design in a `## AI/ML Architecture` section (if applicable)
- Module boundaries, dependency direction, data flow
- Reference `knowledge-base/languages/` for language-specific patterns

### specs/<feature>/tasks/NNN-{task-name}.md

#### Task Decomposition Analysis (before task generation)
Before generating task files, perform a task breakdown analysis using the spec.md and design.md content. Invoke `@project-manager-senior` (if available) or perform inline. Directive: "Analyze the spec and design, then produce a task breakdown: ordered list of implementation tasks with acceptance criteria, dependency relationships, and estimated file counts. Flag any tasks that exceed 20 files or that have unclear scope. Stay true to the spec — do not add scope."

##### Task Analysis Output Contract
1. **Task list** — ordered tasks with: name, description, acceptance criteria, dependencies, estimated file count
2. **Dependency graph** — which tasks block which
3. **Scope flags** — any tasks that risk scope creep or exceed the 20-file limit

If the agent is unavailable, perform the analysis inline and note the limitation.

##### Using Analysis Output for Task Files
Use the task breakdown as input for generating the final task files:
- Split implementation into small tasks following the analysis ordering and grouping
- Each task's `ground_rules` field lists the specific knowledge-base files that apply using the prefix convention (`general:` / `project:`) — this becomes the single source of truth for `/implement` and `/validate`
- Include security analysis ground rules on relevant tasks
- Set `status: blocked` with `blocked_by` IDs for tasks with dependencies (per dependency graph)
- Set `status: todo` for tasks with no dependencies

## Constraints
- Max 20 files per task
- Each task references applicable rules from both knowledge bases in the `ground_rules` field using prefix convention
- Each task includes natural-language test cases (human defines names, AI implements bodies later)
- Tasks ordered by dependency (`blocked_by` fields)
- AI explains architectural decisions against ground rules, not just outputs code
- Tasks must be small enough for meaningful human code review

Present all generated artifacts for human review before proceeding to implementation.
