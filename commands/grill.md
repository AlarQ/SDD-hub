Stress-test a feature plan against the project's domain model before requirements gathering, sharpening terminology and capturing durable decisions.

`/grill` is an **optional pre-`/explore` step**. It produces no spec artifacts —
it sharpens the domain language (`CONTEXT.md`) and records hard-to-reverse,
cross-spec decisions (`docs/adr/`) so every later phase (`/explore`, `/propose`)
speaks one vocabulary. Skip it for `small`-tier work or when the domain is
already well understood.

## Prerequisites

1. Read and follow `$WF_GENERAL_KB/_rules.md` for knowledge base prerequisites and resolution rules.
2. `$ARGUMENTS` is the feature name (free-form description also accepted). No spec directory is required — `/grill` runs before `/explore`.

## Domain awareness

Before grilling, explore the repo for existing domain documentation:

- **Single context (most repos):** one `CONTEXT.md` at the repo root; ADRs in `docs/adr/`.
- **Multiple contexts:** a `CONTEXT-MAP.md` at the repo root points to per-context `CONTEXT.md` files and their `docs/adr/`.
- If `CONTEXT-MAP.md` exists, read it to find the relevant context. If only a root `CONTEXT.md` exists, single context. If neither exists, create a root `CONTEXT.md` lazily when the first term is resolved.

Create files lazily — only when there is something to write. Read any existing `CONTEXT.md` and `docs/adr/` first so the session builds on, not duplicates, prior decisions.

## The grilling session

Interview the user relentlessly about every aspect of the plan until you reach shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

- **Ask one question at a time**, via the `AskUserQuestion` tool (per `~/.claude/scripts/ask-user-protocol.md`) — wait for the answer before continuing. Provide best-guess options plus an `Other` escape.
- If a question can be answered by exploring the codebase, explore the codebase instead of asking.

During the session:

- **Challenge against the glossary.** When the user uses a term that conflicts with the existing language in `CONTEXT.md`, call it out immediately: *"Your glossary defines 'cancellation' as X, but you seem to mean Y — which is it?"*
- **Sharpen fuzzy language.** When the user uses vague or overloaded terms, propose a precise canonical term: *"You're saying 'account' — do you mean the Customer or the User? Those are different things."*
- **Discuss concrete scenarios.** Stress-test domain relationships with specific edge-case scenarios that force precision about boundaries between concepts.
- **Cross-reference with code.** When the user states how something works, check whether the code agrees. Surface contradictions: *"Your code cancels entire Orders, but you just said partial cancellation is possible — which is right?"*
- **Update `CONTEXT.md` inline.** When a term is resolved, update `CONTEXT.md` right there — don't batch. `CONTEXT.md` is a glossary and nothing else: totally devoid of implementation details, not a spec or scratch pad. Use the format in `~/.claude/skills/grill-with-docs/CONTEXT-FORMAT.md`.
- **Offer ADRs sparingly.** Only offer to create an ADR in `docs/adr/` when **all three** are true: (1) hard to reverse, (2) surprising without context, (3) the result of a real trade-off. If any is missing, skip it. Use the format in `~/.claude/skills/grill-with-docs/ADR-FORMAT.md`.

## ADR home (coordination with `/propose`)

`docs/adr/NNNN-*.md` is the home for **durable, cross-spec, repo-level**
domain/architecture decisions. Spec-scoped decisions for one feature belong in
that feature's `design.md ## Architecture Decision Records` (written later by
`/propose`). `/propose` reads `docs/adr/` and references existing ADRs by id
rather than duplicating them — so record cross-cutting decisions here, not
feature-local ones.

## Completion

Summarize the resolved terms and any ADRs created. The session output is the
updated `CONTEXT.md` (+ optional `docs/adr/` entries), not a spec artifact.

Next: run `/explore $ARGUMENTS` — requirements gathering will use the sharpened glossary.
