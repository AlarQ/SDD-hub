---
name: explore
description: Explore and clarify requirements for a new feature
agent: 'agent'
argument-hint: "feature name (optional)"
---

Explore and clarify requirements for a new feature or change.

## Prerequisites
1. Check that `knowledge-base/` directory exists — if not, refuse and instruct the user to run `/bootstrap` first

## Steps
1. Read `knowledge-base/_index.md` to understand available ground rules
2. Ask the user to describe the feature or change
3. Ask clarifying questions **one at a time** — wait for the user's answer before moving to the next question. Cover these areas in order:
   1. Scope: what's in, what's out
   2. Affected domains and modules
   3. Security implications (auth, data handling, input validation)
   4. Integration points (APIs, databases, external services)
   5. Testing expectations (unit, integration, e2e)
   6. Performance or scalability constraints
   Skip questions the user already answered in their feature description. If an area isn't relevant, skip it and move on.
4. Identify which `knowledge-base/` rule files are relevant to this feature
5. Summarize understanding and list applicable ground rules
6. Optionally save as `specs/<feature-name>/prd.md` if the user provides a feature name

This is conversational — no artifacts are generated yet. The goal is alignment on what needs to be built. Continue refining until the user is satisfied with the PRD.
