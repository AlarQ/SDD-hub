Explore and clarify requirements for a new feature or change.

## Prerequisites
1. Read and follow `~/.claude/knowledge-base-rules.md` for knowledge base prerequisites and resolution rules

## Step 0 — Config Inference (runs before explore conversation)

Run this step before asking the user any questions. It is non-blocking: failure routes to manual entry, never aborts explore.

### 0a. Resolve spec storage

Source the config loader to get `WF_SPEC_STORAGE`:

```bash
source ~/.claude/scripts/config-loader.sh
# WF_SPEC_STORAGE is now set (default: specs/)
```

If sourcing fails (loader not found, exit non-zero), set `WF_SPEC_STORAGE=specs/` and continue.

### 0b. Spawn config-inferencer

If `$ARGUMENTS` is non-empty (feature name provided), spawn the `Config Inferencer` agent (`engineering-config-inferencer`) using the Agent tool. Pass:
- The feature name (`$ARGUMENTS`)
- Any PRD or description already available at `$WF_SPEC_STORAGE/$ARGUMENTS/prd.md` (read if it exists; omit if not)
- The full contents of `knowledge-base/gates.yml` (if it exists)
- A listing of all agent files under the configured `agent_pool` directory
- The project's `CLAUDE.md`

Instruct: "Infer a draft `config.yml` for this spec. Use the Output Contract defined in your agent definition. Return REASONING block and YAML block."

**On success:** emit `config_inferred` monitor event now (before showing the approval summary):
```bash
$HOME/.claude/scripts/monitor.sh log_event "<feature>" "config_inferred" "" \
  "$(printf '{"source":"inferencer","reasoning":"%s"}' "<REASONING block>")"
```
If monitor.sh is not found or exits non-zero, log a warning and continue.

**On timeout or agent error:** skip to step 0d (manual-entry prompt). Show: *"Config Inferencer unavailable — falling back to manual entry."* Do not emit `config_inferred`.

### 0c. Render approval summary

Print the reasoning + draft YAML as plain output (status, no prompt):

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Config Inference — <feature-name>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  <REASONING block from agent — trimmed to ≤ 10 lines>

  Draft config.yml:
  <YAML block from agent>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Then invoke the `AskUserQuestion` tool (per `~/.claude/scripts/ask-user-protocol.md`) with one question:
- **question:** "Approve draft config?"
- **options:**
  - `Approve` — save YAML as-is
  - `Edit` — paste an edited version
  - `Manual` — enter config manually (or accept default template)
  - `Skip` — do not write config.yml now

Use the user's selection (Approve/Edit/Manual/Skip) to drive step 0d.

### 0d. Handle user response

**A — Approve:** write the YAML block exactly as returned by the agent to `$WF_SPEC_STORAGE/$ARGUMENTS/config.yml` (create parent dirs if needed). Emit `config_approved` event (see 0e). Proceed to step 1.

**E — Edit:** print the draft YAML in a fenced code block and tell the user: "Paste your edited version below." Wait for the user to provide the full edited YAML, then write it to `$WF_SPEC_STORAGE/$ARGUMENTS/config.yml`. Emit `config_approved` event (with edited YAML as payload). Proceed to step 1.

**M — Manual entry / inferencer unavailable:** tell the user: "Enter your `config.yml` content below, or press Enter to write the default template." If the user provides content, write it. If the user presses Enter (empty input), copy `templates/spec-config.yml.template` to `$WF_SPEC_STORAGE/$ARGUMENTS/config.yml`. Emit `config_approved` event. Proceed to step 1.

**S — Skip:** do not write `config.yml`. Note: *"config.yml skipped — run `/config $ARGUMENTS` later to configure gates and agents."* Do NOT emit any monitor events. Proceed to step 1.

If `$ARGUMENTS` is empty (no feature name given yet), skip step 0 entirely and proceed to step 1. Config inference requires a feature name.

### 0e. Emit config_approved event

After writing `config.yml` (A, E, or M paths):

```bash
$HOME/.claude/scripts/monitor.sh log_event "<feature>" "config_approved" "" \
  "$(printf '{"config_path":"%s"}' "$WF_SPEC_STORAGE/<feature>/config.yml")"
```

If monitor.sh is not found or exits non-zero, log a warning and continue — event emission is best-effort and must not block the explore flow.

Event summary:
- `config_inferred` — fires in step 0b immediately after the agent returns output (before user sees approval summary)
- `config_approved` — fires in step 0e after config.yml is written (A, E, or M paths only; S path emits nothing)
- `tier_inferred` — fires in step 0b alongside `config_inferred`, payload `{"tier":"<value>"}` extracted from agent YAML
- `tier_approved` — fires in step 0e alongside `config_approved`, payload `{"tier":"<final value>"}`

### 0f. Tier — required field

The agent's YAML must include `tier: small|medium|large`. If the YAML lacks `tier`, treat as agent error and route to manual entry. The tier drives downstream flow shape:

- `small` → `/propose` writes only `tasks/`. `/validate-spec` early-exits. `/validate` skips Phase-2 agent gates listed in `WF_TIER_AGENT_SKIP`. `/validate-impl` early-exits.
- `medium` → `/propose` writes `spec.md` + `tasks/` (no `design.md`/`test-strategy.md`). `/validate-spec` audits `spec.md` only.
- `large` → unchanged full flow.

If the agent picked `small` and the spec keywords include `auth`, `security`, `migration`, `api`, `schema`, or `crypto`, override to `medium` and note the override in reasoning. The user can override via `Edit` path.

## Steps
1. Read both knowledge base indexes (per `~/.claude/knowledge-base-rules.md`) to understand available ground rules
2. Ask the user to describe the feature or change
3. **Establish the user perspective first** — before diving into technical areas, clarify:
   - Who benefits from this feature? (user role, persona)
   - What problem does it solve for them?
   - What is the shortest path to delivering that value?

   **Agent — UX Researcher**: After the user answers all three perspective questions, spawn the `UX Researcher` agent (`design-ux-researcher`) using the Agent tool. Pass the feature description and the user's perspective answers. Instruct: "Identify assumptions to validate, edge-case user segments, and whether the shortest-path framing risks missing important user needs. Output 3-5 concise bullet points." Present the agent's output as a labeled advisory block. If the agent errors, note: *"UX Researcher analysis unavailable — will be addressed in /propose."*
4. Ask clarifying questions **one at a time via the `AskUserQuestion` tool** (per `~/.claude/scripts/ask-user-protocol.md`) — one tool call per question. Do NOT present all questions at once and do NOT render them as a markdown list expecting typed replies. Provide best-guess options on each call plus an `Other` escape for free-form answers. Cover these areas in order:
   1. Scope: what's in, what's out
   2. Affected domains and modules
   3. Security implications (auth, data handling, input validation)

      **Agent — Security Engineer**: After the user answers the security question, spawn the `Security Engineer` agent (`engineering-security-engineer`) using the Agent tool. Pass the feature description, all conversation context so far, and applicable knowledge-base rules. Instruct: "Produce a lightweight threat surface checklist: top 3-5 STRIDE categories most relevant to this feature, one sentence each. Early flagging for the PRD, not a full threat model." Present as a labeled advisory block. If the agent errors, note: *"Security Engineer analysis unavailable — will be addressed in /propose."*
   4. Integration points (APIs, databases, external services)

      **Conditional agents — Backend Architect / UX Architect**: After the user answers the integration-points question, check the conversation context:
      - If backend-related keywords appear (`database`, `DB`, `schema`, `migration`, `API`, `endpoint`, `REST`, `GraphQL`, `infrastructure`, `server`, `backend`, `queue`, `cache`), spawn the `Backend Architect` agent (`engineering-backend-architect`). Pass the feature description, integration-points answer, and domain/module context. Instruct: "Flag data-flow risks, schema concerns, or API design considerations for the PRD. Output 3-5 bullet points."
      - If UI-related keywords appear (`UI`, `frontend`, `component`, `layout`, `CSS`, `design system`, `responsive`, `mobile`, `page`, `screen`, `form`, `modal`, `dashboard`), spawn the `UX Architect` agent (`design-ux-architect`). Pass the feature description, scope, and domain answers. Instruct: "Flag component-architecture, responsive design, or design-system concerns for the PRD. Output 3-5 bullet points."
      - If both conditions are met, spawn both agents concurrently (parallel) since they are independent.
      - Present each agent's output as a labeled advisory block. If an agent errors, note the failure and proceed.
   5. Testing expectations (unit, integration, e2e)
   6. Performance or scalability constraints
   Skip questions the user already answered in their feature description. If an area isn't relevant, skip it and move on.
5. **Scope decisions**: when you identify a point where the feature could go two ways or has an unclear boundary:

   **Agent — Software Architect**: Before presenting scope options, spawn the `Software Architect` agent (`engineering-software-architect`) using the Agent tool. Pass the feature description, all conversation context, identified scope forks, and applicable knowledge-base rules. Instruct: "For each scope decision point, produce a brief trade-off analysis: 2-3 options with pros/cons. Keep concise — requirements phase, not design." Incorporate the agent's trade-off analysis into the scope options presented to the user.

   **Conditional agent — Feedback Synthesizer**: If the conversation context contains feedback-related keywords (`feedback`, `user complaint`, `support ticket`, `churn`, `NPS`, `survey`, `user request`, `feature request`), also spawn the `Feedback Synthesizer` agent (`product-feedback-synthesizer`) concurrently with the Software Architect. Instruct: "Identify what feedback signals should influence the scope decision and which option best addresses root user pain. Output 3-5 bullet points." Present as a separate advisory block alongside the scope options.

   If an agent errors, proceed with scope presentation without agent input and note the failure.

   - Present the trade-offs as a labeled advisory block, then invoke `AskUserQuestion` (per `~/.claude/scripts/ask-user-protocol.md`) with each scope fork as one question — `options` are the 2–3 architect-proposed directions plus `Other` for a custom answer.
   - Wait for the tool result — do NOT assume or choose a direction
   - Only proceed after the user has selected an option for every scope fork
6. Identify which rule files from both knowledge bases are relevant to this feature
7. Summarize understanding and list applicable ground rules (using prefix convention per `knowledge-base-rules.md`)
8. Optionally save as `specs/$ARGUMENTS/prd.md` if the user provides a feature name. When saving, include an `## Agent Insights (Explore Phase)` section after the ground-rules listing containing all agent outputs collected during the conversation, labeled by agent name. Mark as advisory. Omit agents that were not spawned or that errored.

## Agent Advisory Block Format

Present all agent outputs using this format between conversation turns:

```
---
**[Agent Name] perspective:**
- Bullet 1
- Bullet 2
- Bullet 3
---
```

Agent insights are advisory — they enrich the conversation but the user makes all decisions. Each agent receives:
- Feature description (from step 2)
- All Q&A pairs accumulated so far
- Applicable knowledge-base rules identified so far
- Project's `CLAUDE.md`

This is conversational — no artifacts are generated yet. The goal is alignment on what needs to be built. Continue refining until the user is satisfied with the PRD.
