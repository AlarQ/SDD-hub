Generate specification, design, and tasks for a feature.

Feature name: $ARGUMENTS

## Prerequisites
1. Read and follow `~/.claude/knowledge-base-rules.md` for knowledge base prerequisites and resolution rules

## Steps
1. Read `specs/$ARGUMENTS/prd.md` if it exists, otherwise use conversation context
2. Read both knowledge base indexes (per `~/.claude/knowledge-base-rules.md`) — identify all applicable rules from both
3. Read the applicable rule files from both knowledge bases

## Generate Artifacts

### specs/$ARGUMENTS/spec.md

#### Agent — Security Engineer (before spec generation)
Before writing spec.md, spawn the `Security Engineer` agent (`engineering-security-engineer`) using the Agent tool. The agent receives:
- The prd.md content (or conversation context)
- All applicable security rules from both knowledge bases
- The project's `CLAUDE.md`

Instruct the agent with this directive: "Produce a full STRIDE threat model for this feature. For each relevant STRIDE category, describe the threat, its severity, and recommended mitigation. Identify authentication, authorization, data-handling, and input-validation requirements. Output structured findings."

##### Security Agent Output Contract
The agent must return:
1. **STRIDE threat model** — category, threat description, severity, mitigation for each relevant threat
2. **Security requirements** — authentication, authorization, data-handling, and input-validation requirements
3. **Security ground rules** — specific knowledge-base security rules that must be referenced in task `ground_rules`

If the agent errors or times out, proceed with spec.md generation without security input and note: *"Security Engineer analysis unavailable — security scenarios may be incomplete."*

##### Embedding Security Output in spec.md
- Generate spec.md content:
  - Detailed functional specification
  - All scenarios in BDD format: Given / When / Then
  - Edge cases and error scenarios explicitly listed
  - Reference applicable rules from both knowledge bases
- Incorporate security agent findings as BDD scenarios for auth, input validation, and data handling
- Add a `## Security Scenarios` section with Given/When/Then for each threat mitigation

### specs/$ARGUMENTS/design.md

#### Agent-Assisted Architecture & Design Review

Before writing design.md, spawn agents in parallel using the Agent tool. All agents receive the spec.md content (already generated above), all applicable rules from both knowledge bases, and the project's `CLAUDE.md`.

##### Always spawn:

**Software Architect** (`engineering-software-architect`): Instruct: "Evaluate the proposed architecture in the spec against the provided architecture rules. For each major architectural decision, produce a trade-off analysis and an ADR. Flag any patterns that introduce irreversible coupling, scaling risks, or that the team is unlikely to sustain. Use the Proposal Output format defined in your agent definition."

##### Conditionally spawn (in parallel with Software Architect):

Check the spec.md content and prd.md for keyword matches:

**Backend Architect** (`engineering-backend-architect`) — spawn if backend-related keywords appear (`database`, `DB`, `schema`, `migration`, `API`, `endpoint`, `REST`, `GraphQL`, `infrastructure`, `server`, `backend`, `queue`, `cache`). Instruct: "Design the backend architecture for this feature: database schema, API contracts, service boundaries, data-flow diagrams. Flag scaling risks and integration concerns. Reference applicable architecture and language rules."

**UX Architect** (`design-ux-architect`) — spawn if UI-related keywords appear (`UI`, `frontend`, `component`, `layout`, `CSS`, `design system`, `responsive`, `mobile`, `page`, `screen`, `form`, `modal`, `dashboard`). Instruct: "Design the component architecture, layout framework, and CSS system for this feature. Define the component hierarchy, responsive breakpoints, and design-system integration. Provide developer-ready specifications."

**UI Designer** (`design-ui-designer`) — spawn alongside UX Architect when UI keywords are detected. Instruct: "Define design system specifications for this feature: component states and variations, responsive behavior, visual hierarchy, and accessibility requirements. Pair with UX Architect output for a complete UI foundation."

**AI Engineer** (`engineering-ai-engineer`) — spawn if ML/AI keywords appear (`model`, `ML`, `machine learning`, `AI`, `training`, `inference`, `embeddings`, `neural`, `LLM`, `fine-tune`, `dataset`). Instruct: "Design the ML/AI architecture for this feature: model selection, data pipeline design, training/inference infrastructure, and integration patterns. Flag data requirements and scaling considerations."

If multiple conditions are met, spawn all matching agents concurrently (they are independent). If an agent errors or times out, proceed without its input and note the failure.

##### Agent Output Contracts

**Software Architect** must return:
1. **Trade-off analysis** — for each major decision: decision name, options considered, chosen option, what is gained, what is given up
2. **ADRs** — one Architecture Decision Record per significant decision, using the ADR template
3. **Risk flags** — severity, description, and mitigation for each architectural concern

**Backend Architect** must return:
1. **Database schema** — tables/collections, relationships, indexes, migration strategy
2. **API contracts** — endpoints, request/response shapes, error codes
3. **Service boundaries** — module decomposition, dependency direction, data flow

**UX Architect** must return:
1. **Component hierarchy** — tree of components, props/state ownership
2. **Layout framework** — grid system, responsive breakpoints, CSS architecture
3. **Design-system integration** — which existing tokens/components to reuse, what's new

**UI Designer** must return:
1. **Component specs** — states (default, hover, active, disabled, error), variations
2. **Visual hierarchy** — spacing, typography scale, color usage
3. **Accessibility specs** — ARIA roles, keyboard navigation, contrast requirements

**AI Engineer** must return:
1. **Model architecture** — model type, input/output schemas, performance targets
2. **Data pipeline** — data sources, preprocessing, storage, versioning
3. **Integration design** — API surface, latency requirements, fallback behavior

##### Embedding Agent Output in design.md
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
- Reference `knowledge-base/languages/` for language-specific patterns

### specs/$ARGUMENTS/tasks/NNN-{task-name}.md

#### Agent — Senior Project Manager (before task generation)
Before generating task files, spawn the `Senior Project Manager` agent (`project-manager-senior`) using the Agent tool. The agent receives:
- The spec.md content
- The design.md content (with all embedded agent outputs)
- The project's `CLAUDE.md`

Instruct the agent with this directive: "Analyze the spec and design, then produce a task breakdown: ordered list of implementation tasks with acceptance criteria, dependency relationships, and estimated file counts. Flag any tasks that exceed 20 files or that have unclear scope. Stay true to the spec — do not add scope."

##### PM Agent Output Contract
The agent must return:
1. **Task list** — ordered tasks with: name, description, acceptance criteria, dependencies, estimated file count
2. **Dependency graph** — which tasks block which
3. **Scope flags** — any tasks that risk scope creep or exceed the 20-file limit

If the agent errors or times out, proceed with task generation using your own analysis and note: *"Senior PM analysis unavailable — task breakdown generated without PM review."*

##### Using PM Output for Task Files
Use the PM agent's task breakdown as input for generating the final task files:
- Split implementation into small tasks following the PM's ordering and grouping
- Each task's `ground_rules` field lists the specific knowledge-base files that apply using the prefix convention — this becomes the single source of truth for `/implement` and `/validate`
- Include Security Engineer's security ground rules on relevant tasks
- Set `status: blocked` with `blocked_by` IDs for tasks with dependencies (per PM dependency graph)
- Set `status: todo` for tasks with no dependencies

#### Agent — Test Strategist (after task generation)
After all task files have been generated, spawn the `Test Strategist` agent (`engineering-test-strategist`) using the Agent tool. The agent receives:
- The spec.md content (with BDD scenarios)
- The design.md content (with architecture and module boundaries)
- All generated task files (with their test_cases fields)

Instruct the agent with this directive: "Analyze the spec scenarios, design boundaries, and task test cases. Produce a cross-task test strategy: assign test ownership per task, identify integration seams, flag duplication risks, and map every spec scenario to exactly one task. Use the Proposal Output format defined in your agent definition."

##### Test Strategist Output Contract
The agent must return:
1. **Task test responsibilities** — per-task: test theme, what it owns, what it must not test, integration seams, shared fixtures
2. **Spec coverage map** — every BDD scenario mapped to exactly one owning task
3. **Integration test plan** — seam descriptions with owning task and rationale
4. **Risk flags** — testing concerns with severity and mitigation

If the agent errors or times out, proceed without the test strategy and note: *"Test Strategist analysis unavailable — test strategy not generated."*

##### Saving Test Strategy Output
Save the agent's full output as `specs/$ARGUMENTS/test-strategy.md`.

##### Updating Task Files with Strategy
After saving test-strategy.md, update each task file's `test_cases` field:
- Add integration seam tests assigned to that task
- Remove test cases that the strategy assigns to a different task
- Add shared fixture creation responsibilities to the earliest task that needs them

## Constraints
- Max 20 files per task
- Each task references applicable rules in the `ground_rules` field (per `knowledge-base-rules.md`)
- Each task includes natural-language test cases (human defines names, AI implements bodies later)
- Tasks ordered by dependency (`blocked_by` fields)
- AI explains architectural decisions against ground rules, not just outputs code
- Tasks must be small enough for meaningful human code review

Present all generated artifacts for human review before proceeding to implementation.

## Auto-Chain: Spec Coherence Gate

After artifacts are presented, auto-chain into `/validate-spec` — read and follow `~/.claude/commands/validate-spec.md` with the same $ARGUMENTS value. The gate validates internal coherence, logic gaps, and repo alignment of the generated spec bundle before `/implement` is allowed to start. Findings flow through `/review-findings` and patch the spec/design/tasks files.
