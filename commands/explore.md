Explore and clarify requirements for a new feature or change.

## Prerequisites
1. Check that `~/.claude/knowledge-base/` (general) exists — if not, refuse and say: "General knowledge base not found. Run `setup.sh` from the dev-workflow repo first."
2. Check that `knowledge-base/` (project) exists — if not, refuse and instruct the user to run `/bootstrap` first

## Steps
1. Read both `~/.claude/knowledge-base/_index.md` (general rules) and `knowledge-base/_index.md` (project rules) to understand available ground rules
2. Ask the user to describe the feature or change
3. **Establish the user perspective first** — before diving into technical areas, clarify:
   - Who benefits from this feature? (user role, persona)
   - What problem does it solve for them?
   - What is the shortest path to delivering that value?
4. Ask clarifying questions **one at a time** — do NOT present all questions at once. Pick the single most important unknown area, ask about it, wait for the answer, then move to the next area. This is a conversation, not a questionnaire. Cover these areas in order:
   1. Scope: what's in, what's out
   2. Affected domains and modules
   3. Security implications (auth, data handling, input validation)
   4. Integration points (APIs, databases, external services)
   5. Testing expectations (unit, integration, e2e)
   6. Performance or scalability constraints
   Skip questions the user already answered in their feature description. If an area isn't relevant, skip it and move on.
5. **Scope decisions**: when you identify a point where the feature could go two ways or has an unclear boundary:
   - Present the options clearly with trade-offs for each
   - Wait for the user to decide — do NOT assume or choose a direction
   - Only proceed after the user confirms the scope
6. Identify which rule files from both knowledge bases are relevant to this feature — general rules from `~/.claude/knowledge-base/` and project rules from `knowledge-base/`
7. Summarize understanding and list applicable ground rules (using `general:` and `project:` prefixes)
8. Optionally save as `specs/$ARGUMENTS/prd.md` if the user provides a feature name

This is conversational — no artifacts are generated yet. The goal is alignment on what needs to be built. Continue refining until the user is satisfied with the PRD.
