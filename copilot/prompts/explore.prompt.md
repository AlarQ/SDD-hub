---
name: explore
description: Explore and clarify requirements for a new feature
agent: 'agent'
argument-hint: "feature name (optional)"
---

Explore and clarify requirements for a new feature or change.

## Prerequisites
1. Check that `knowledge-base/_general/` (general) exists — if not, refuse and say: "General knowledge base not found. Run `setup-copilot.sh` from the dev-workflow repo first."
2. Check that `knowledge-base/` (project) exists with project-specific files — if not, refuse and instruct the user to run `/bootstrap` first

## Steps
1. Read both `knowledge-base/_general/_index.md` (general rules) and `knowledge-base/_index.md` (project rules) to understand available ground rules
2. Ask the user to describe the feature or change
3. **Establish the user perspective first** — before diving into technical areas, clarify:
   - Who benefits from this feature? (user role, persona)
   - What problem does it solve for them?
   - What is the shortest path to delivering that value?

   **UX Researcher analysis**: After the user answers all three perspective questions, perform a brief UX research analysis. Identify assumptions to validate, edge-case user segments, and whether the shortest-path framing risks missing important user needs. Present as 3-5 concise bullet points in an advisory block.
4. Ask clarifying questions **one at a time** — do NOT present all questions at once. Pick the single most important unknown area, ask about it, wait for the answer, then move to the next area. This is a conversation, not a questionnaire. Cover these areas in order:
   1. Scope: what's in, what's out
   2. Affected domains and modules
   3. Security implications (auth, data handling, input validation)

      **Security analysis**: After the user answers the security question, produce a lightweight threat surface checklist: top 3-5 STRIDE categories most relevant to this feature, one sentence each. Early flagging for the PRD, not a full threat model. Present as an advisory block.
   4. Integration points (APIs, databases, external services)

      **Conditional analysis — Backend / UI architecture**: After the user answers the integration-points question, check the conversation context:
      - If backend-related keywords appear (`database`, `DB`, `schema`, `migration`, `API`, `endpoint`, `REST`, `GraphQL`, `infrastructure`, `server`, `backend`, `queue`, `cache`), perform a backend architecture analysis: flag data-flow risks, schema concerns, or API design considerations for the PRD. Output 3-5 bullet points.
      - If UI-related keywords appear (`UI`, `frontend`, `component`, `layout`, `CSS`, `design system`, `responsive`, `mobile`, `page`, `screen`, `form`, `modal`, `dashboard`), perform a UX architecture analysis: flag component-architecture, responsive design, or design-system concerns for the PRD. Output 3-5 bullet points.
      - Present each analysis as a labeled advisory block.
   5. Testing expectations (unit, integration, e2e)
   6. Performance or scalability constraints
   Skip questions the user already answered in their feature description. If an area isn't relevant, skip it and move on.
5. **Scope decisions**: when you identify a point where the feature could go two ways or has an unclear boundary:

   **Architecture trade-off analysis**: Before presenting scope options, analyze each identified scope fork from a software architecture perspective. For each decision point, produce a brief trade-off analysis: 2-3 options with pros/cons. Keep concise — requirements phase, not design. Incorporate into the scope options presented to the user.

   **Conditional — Feedback analysis**: If the conversation context contains feedback-related keywords (`feedback`, `user complaint`, `support ticket`, `churn`, `NPS`, `survey`, `user request`, `feature request`), also analyze what feedback signals should influence the scope decision and which option best addresses root user pain. Output 3-5 bullet points as a separate advisory block.

   - Present the options clearly with trade-offs for each
   - Wait for the user to decide — do NOT assume or choose a direction
   - Only proceed after the user confirms the scope
6. Identify which rule files from both knowledge bases are relevant to this feature — general rules from `knowledge-base/_general/` and project rules from `knowledge-base/`
7. Summarize understanding and list applicable ground rules (using `general:` and `project:` prefixes)
8. Optionally save as `specs/<feature-name>/prd.md` if the user provides a feature name. When saving, include an `## Agent Insights (Explore Phase)` section after the ground-rules listing containing all analysis outputs collected during the conversation, labeled by analysis type. Mark as advisory. Omit analyses that were not triggered.

## Advisory Block Format

Present all analysis outputs using this format between conversation turns:

```
---
**[Analysis Name] perspective:**
- Bullet 1
- Bullet 2
- Bullet 3
---
```

Analysis insights are advisory — they enrich the conversation but the user makes all decisions.

This is conversational — no artifacts are generated yet. The goal is alignment on what needs to be built. Continue refining until the user is satisfied with the PRD.
