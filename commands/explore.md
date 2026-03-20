Explore and clarify requirements for a new feature or change.

## Prerequisites
1. Check that `knowledge-base/` directory exists — if not, refuse and instruct the user to run `/bootstrap` first

## Steps
1. Read `knowledge-base/_index.md` to understand available ground rules
2. Ask the user to describe the feature or change
3. Ask clarifying questions about:
   - Scope: what's in, what's out
   - Affected domains and modules
   - Security implications (auth, data handling, input validation)
   - Integration points (APIs, databases, external services)
   - Testing expectations (unit, integration, e2e)
   - Performance or scalability constraints
4. Identify which `knowledge-base/` rule files are relevant to this feature
5. Summarize understanding and list applicable ground rules
6. Optionally save as `specs/$ARGUMENTS/prd.md` if the user provides a feature name

This is conversational — no artifacts are generated yet. The goal is alignment on what needs to be built. Continue refining until the user is satisfied with the PRD.
