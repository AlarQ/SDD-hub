Explore and clarify requirements for a new feature or change.

## Prerequisites
1. Read and follow `~/.claude/knowledge-base-rules.md` for knowledge base prerequisites and resolution rules

## Steps
1. Read both knowledge base indexes (per `~/.claude/knowledge-base-rules.md`) to understand available ground rules
2. Ask the user to describe the feature or change
3. **Establish the user perspective first** — before diving into technical areas, clarify:
   - Who benefits from this feature? (user role, persona)
   - What problem does it solve for them?
   - What is the shortest path to delivering that value?

   **Agent — UX Researcher**: After the user answers all three perspective questions, spawn the `UX Researcher` agent (`design-ux-researcher`) using the Agent tool. Pass the feature description and the user's perspective answers. Instruct: "Identify assumptions to validate, edge-case user segments, and whether the shortest-path framing risks missing important user needs. Output 3-5 concise bullet points." Present the agent's output as a labeled advisory block. If the agent errors, note: *"UX Researcher analysis unavailable — will be addressed in /propose."*
4. Ask clarifying questions **one at a time** — do NOT present all questions at once. Pick the single most important unknown area, ask about it, wait for the answer, then move to the next area. This is a conversation, not a questionnaire. Cover these areas in order:
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

   - Present the options clearly with trade-offs for each
   - Wait for the user to decide — do NOT assume or choose a direction
   - Only proceed after the user confirms the scope
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
