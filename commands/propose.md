Generate specification, design, and tasks for a feature.

Feature name: $ARGUMENTS

## Prerequisites
1. Read and follow `$WF_GENERAL_KB/_rules.md` for knowledge base prerequisites and resolution rules

## Step 0 — Load Spec Config

Before generating any artifact, load the spec config (substituting the actual feature name for `$ARGUMENTS`):

```bash
bash -c 'source ~/.claude/scripts/config-loader.sh && wf_load_config --spec $ARGUMENTS && printf "WF_SPEC_AGENTS_PROPOSE=%s\n" "${WF_SPEC_AGENTS_PROPOSE:-}"'
```

> See `~/.claude/scripts/step0-load-config.md` for canonical invocation and remediation. This step uses: `WF_SPEC_AGENTS_PROPOSE`, `WF_SPEC_TIER`, `WF_SPEC_TRACK`.

If `WF_SPEC_AGENTS_PROPOSE` is non-empty, it lists the agent IDs to spawn during spec/design generation (overrides the default keyword-based conditional list below). Resolve each ID per the Agent ID grammar in `design.md §Backend Design §Agent ID grammar`. Unknown ID → stop with error.

### Tier branching (artifact ceiling)

`WF_SPEC_TIER` controls which artifacts get written:

| Tier | spec.md | design.md | test-strategy.md | tasks/ | Architect/Backend/UX/UI/AI/TestStrategist agents | Mermaid diagrams |
|------|---------|-----------|------------------|--------|--------------------------------------------------|------------------|
| `small`  | skip | skip | skip | yes  | skip all | none |
| `medium` | yes  | skip | skip | yes  | skip Software Architect, Backend Architect, UX/UI, AI Engineer, Test Strategist | spec.md user-flow `sequenceDiagram` (advisory) |
| `large`  | yes  | yes  | yes  | yes  | full set per default keyword logic | spec.md user-flow + design.md architecture (required), state/ER/sequence (when applicable) |

Branch on `WF_SPEC_TIER` at the top of the generation loop. For sections "skipped" do NOT spawn the corresponding agent and do NOT write the file.

For `small`, the only generated artifact is `tasks/001-*.md` (decompose directly from prd.md/conversation context). Keep ground_rules minimal — language file + any explicitly relevant general rule.

### Track branching (technical track)

`WF_SPEC_TRACK` (`feature` default | `technical`) is orthogonal to tier and is
evaluated **after** the tier table above. When `WF_SPEC_TRACK=technical`:

- **No business artifacts at any tier.** Skip `spec.md`, `design.md`, and
  `test-strategy.md` regardless of `WF_SPEC_TIER` (technical work has no
  business case to specify — rationale lives in `docs/adr/` + `CONTEXT.md`).
  Do NOT spawn Security Engineer (spec.md), the Architecture/Backend/UX/UI/AI
  agents (design.md), or the Test Strategist (test-strategy.md). The only
  generated artifact is `tasks/NNN-*.md`.
- **Grill gate (medium/large):** if `WF_SPEC_TIER` is `medium` or `large`,
  verify a non-empty `docs/adr/` exists (≥1 `docs/adr/NNNN-*.md`). If it does
  not, **hard-refuse**: stop and print —
  *"Technical track at tier `<tier>` requires a recorded rationale. Run
  `/explore $ARGUMENTS` (its Step −1 grill pass produces docs/adr/ and
  sharpens CONTEXT.md), then re-run /propose."* Do not generate any
  artifact. For `small`, skip this check (a rename/one-span change is not
  ADR-worthy — the grill pass may produce no ADR).
- **Decomposition input:** the Senior Project Manager is the only agent
  spawned. It receives `docs/adr/` + repo-root `CONTEXT.md` (+ `prd.md`/
  conversation context) **in place of** spec.md/design.md, plus the project's
  `CLAUDE.md`. See the technical-track addendum under *Agent — Senior Project
  Manager* below.

### Multi-repo branching

If `WF_REPO_NAMES` is non-empty (loaded by Step 0 via `wf_load_config --spec`):
- Each generated task **must** declare a `repo: <name>` frontmatter field where `<name>` is one of `WF_REPO_NAMES`.
- Hard rule: one task = one repo. If a logical chunk of work spans repos, split into sibling tasks (e.g. `001-api-endpoint` with `repo: backend` + `002-ui-form` with `repo: frontend`) sharing the spec.
- The Senior Project Manager agent receives `WF_REPO_NAMES` + `WF_REPO_PATHS` and must emit per-task repo assignments using path heuristics (file paths under each repo's tree, role hints from `repos[].role`). Architect/Backend/UX agents each receive the path of the repo they advise on so file references resolve.
- When a `repo:<name>:` ground-rules prefix appears, ensure `<name>` is in `WF_REPO_NAMES` (loader rejects unknown names at validate time).

## Steps
1. Read `specs/$ARGUMENTS/prd.md` if it exists, otherwise use conversation context
2. Read both knowledge base indexes (per `$WF_GENERAL_KB/_rules.md`) — identify all applicable rules from both
3. Read the applicable rule files from both knowledge bases
4. Read the repo-root `CONTEXT.md` (or per-context files via `CONTEXT-MAP.md`) and `docs/adr/` if they exist (produced by `/explore` Step −1 grill pass). Use the canonical glossary terms in all generated artifacts. **ADR home:** `docs/adr/` holds durable, cross-spec, repo-level decisions; `design.md ## Architecture Decision Records` holds spec-scoped decisions for this feature only. When an architectural decision is already recorded in `docs/adr/`, reference it by id (e.g. "see ADR-0003") — do not restate or duplicate it in `design.md`.

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

##### User Flow Diagram (medium + large tiers)
After `## Security Scenarios`, add a `## User Flow` section containing one Mermaid `sequenceDiagram` block synthesized from the primary happy-path BDD scenario. Actor = end user; participants = the user-visible system surfaces named in spec.md (UI, API, store, external services). Every participant label MUST be a term defined elsewhere in spec.md. Style conventions per `docs/workflow-diagram.md` (solid arrows for direct flow, dashed `-->>` for async/return). Skip on `small`.

### specs/$ARGUMENTS/design.md

#### Agent-Assisted Architecture & Design Review

Before writing design.md, spawn agents in parallel using the Agent tool. All agents receive the spec.md content (already generated above), all applicable rules from both knowledge bases, and the project's `CLAUDE.md`.

**Agent selection:** If `WF_SPEC_AGENTS_PROPOSE` is non-empty (from Step 0), spawn exactly those agents — the keyword-based conditional selection below does not apply. If `WF_SPEC_AGENTS_PROPOSE` is empty, use the default keyword-based selection:

##### Always spawn (default):

**Software Architect** (`engineering-software-architect`): Pass the existing repo-root `CONTEXT.md` and `docs/adr/` contents. Instruct: "Evaluate the proposed architecture in the spec against the provided architecture rules. Read the supplied `docs/adr/` — do NOT duplicate a decision already recorded there; reference it by ADR id instead. For each major *new, spec-scoped* architectural decision, produce a trade-off analysis and an ADR for `design.md`. Flag any patterns that introduce irreversible coupling, scaling risks, or that the team is unlikely to sustain. Use the Proposal Output format defined in your agent definition."

##### Conditionally spawn (in parallel with Software Architect, default only):

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
4. **Architecture diagram** — one Mermaid `graph TB` showing modules/layers and dependency direction; subgraph clusters per logical group; `-->` for direct calls, `-.->` for async/event. Required on large tier.
5. **State diagram** — Mermaid `stateDiagram-v2` for any entity with a non-trivial lifecycle (≥3 states). Include only when ADRs reference state transitions.

**Backend Architect** must return:
1. **Database schema** — tables/collections, relationships, indexes, migration strategy
2. **API contracts** — endpoints, request/response shapes, error codes
3. **Service boundaries** — module decomposition, dependency direction, data flow
4. **ER diagram** — Mermaid `erDiagram` for any schema-touching design; include cardinality and key fields. Required when schema is in scope.
5. **Sequence diagram** — Mermaid `sequenceDiagram` for multi-service request flows or async pipelines. Required when ≥2 services interact.

**UX Architect** must return:
1. **Component hierarchy** — tree of components, props/state ownership
2. **Layout framework** — grid system, responsive breakpoints, CSS architecture
3. **Design-system integration** — which existing tokens/components to reuse, what's new
4. **Component-tree diagram** — Mermaid `graph TD` of component hierarchy with state-ownership annotations on edges.
5. **User-flow diagram** — Mermaid `sequenceDiagram` with the user as actor and UI/system as participants, covering the primary user journey.

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
- Reference `$WF_GENERAL_KB/languages/` for language-specific patterns

##### Embedding Mermaid Diagrams in design.md (large tier)
Embed every Mermaid block emitted by an agent verbatim under the section that holds the corresponding text:
- Software Architect's architecture `graph TB` → new `## Architecture Overview` section at the top of design.md (before ADRs).
- Software Architect's `stateDiagram-v2` → adjacent to the ADR that motivates it.
- Backend Architect's `erDiagram` and `sequenceDiagram` → inside the `## Backend Design` section, next to the schema and API contracts they describe.
- UX Architect's component-tree `graph TD` and user-flow `sequenceDiagram` → inside the `## Frontend Architecture` section.

Style: follow `docs/workflow-diagram.md` (solid arrows direct, dashed async/human, subgraph clusters). Every node/entity label MUST correspond to a term defined in spec.md or design.md prose — no orphan nodes.

### specs/$ARGUMENTS/tasks/NNN-{task-name}.md

#### Agent — Senior Project Manager (before task generation)
Before generating task files, spawn the `Senior Project Manager` agent (`project-manager-senior`) using the Agent tool. The agent receives:
- The spec.md content *(feature track)* — **technical track:** `docs/adr/` contents + repo-root `CONTEXT.md` instead
- The design.md content (with all embedded agent outputs) *(feature track only — omit on technical track)*
- The prd.md content or conversation context (both tracks)
- The project's `CLAUDE.md`

Instruct the agent with this directive: "Analyze the spec and design, then produce a vertical-slice task breakdown. Each task must be a tracer bullet — a thin slice cutting through all layers it touches, independently demoable/verifiable. Target task count per tier: small=2–4, medium=4–7, large=7–12. Group related work; only split when files >20, deploys are independent, or work is parallelizable across devs. Classify each task `interaction: hitl|afk` (prefer afk). Each task must justify why it isn't merged with a neighbor. Flag any spec where you cannot stay within the target without losing reviewability. Stay true to the spec — do not add scope."

**Technical-track addendum** (`WF_SPEC_TRACK=technical`) — append to the directive: "There is no spec.md/design.md. The source of intent is `docs/adr/` + `CONTEXT.md` + the change description. For **every** task, emit a `technical_acceptance` list: concrete, verifiable, behavior-level statements that prove the technical change is done and safe — e.g. `public API of module X unchanged`, `trace span 'checkout.charge' emitted with attrs order_id, amount`, `module A no longer imports module B`, `p95 of endpoint /foo unchanged within 5%`. Derive them from ADR Decision/Consequences and the stated intent. For any task that is a **refactor / behavior-preserving change**, the first `technical_acceptance` entry MUST be a characterization assertion (existing observable behavior unchanged) so `/implement` writes a characterization test first. Keep `technical_acceptance` tight — only what actually gates 'done'."

##### PM Agent Output Contract
The agent must return:
1. **Task list** — ordered tasks with: name, description, acceptance criteria, dependencies, estimated file count, `interaction` (`hitl`|`afk`), **rationale (why this task isn't merged with a neighbor)**, and — **technical track only** — a `technical_acceptance` list per task (refactor tasks lead with a characterization assertion)
2. **Dependency graph** — which tasks block which
3. **Scope flags** — any tasks that risk scope creep, exceed the 20-file limit, or breach the tier task-count target

If the agent errors or times out, proceed with task generation using your own analysis and note: *"Senior PM analysis unavailable — task breakdown generated without PM review."*

##### Using PM Output for Task Files
Use the PM agent's task breakdown as input for generating the final task files:
- Group implementation into vertical-slice tasks per PM ordering — do not further fragment what the PM grouped
- Each task's `ground_rules` field lists the specific knowledge-base files that apply using the prefix convention — this becomes the single source of truth for `/implement` and `/validate`
- Include Security Engineer's security ground rules on relevant tasks
- Set `status: blocked` with `blocked_by` IDs for tasks with dependencies (per PM dependency graph)
- Set `status: todo` for tasks with no dependencies
- Set the `interaction:` frontmatter field to the PM's `hitl`/`afk` classification (omit only if the PM analysis was unavailable — `task-manager.sh` then defaults it to `afk`)
- **Technical track:** write the PM's per-task `technical_acceptance` list into each task file's `technical_acceptance:` frontmatter array (see `scripts/task-manager.sh` schema). On the feature track this field is omitted.

#### Agent — Test Strategist (after task generation)
**Skip entirely on the technical track** (`WF_SPEC_TRACK=technical`) — there is no test-strategy.md; per-task `technical_acceptance` drives `/implement`'s TDD loop instead.

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
- Target task count per tier (see PM agent): small=2–4, medium=4–7, large=7–12. Exceeding tier ceiling triggers tier breach via `tier-check.sh`.
- Each task references applicable rules in the `ground_rules` field (per `knowledge-base-rules.md`)
- Each task includes natural-language test cases (human defines names, AI implements bodies later)
- Tasks ordered by dependency (`blocked_by` fields)
- AI explains architectural decisions against ground rules, not just outputs code
- Tasks must be small enough for meaningful human code review

Present all generated artifacts for human review before proceeding to implementation.

## Next Step

This command is complete. Run `/implement $ARGUMENTS` next.
