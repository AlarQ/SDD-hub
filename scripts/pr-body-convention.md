# PR-Body Convention

Canonical rule for the content of every PR body written by a workflow command
(`/implement` draft PR, the shared ship procedure `~/.claude/scripts/ship-procedure.md`
ready/final + single-branch spec PR, `/quick-ship` generic PR). One skeleton, shared so the draft body read during the
`/pr-review` loop matches the final one.

## Why this exists

PR bodies drift long — they restate detail that already lives in the code. A PR
body is a **review aid**, not a changelog: state the intent and the high-level
shape of the change, and let the diff carry the line-by-line detail.

## Body skeleton

```
## Why
<1–2 sentences: the intent / problem this change solves>

## What changed
- <3–6 high-level bullets of the change's shape>
- <behavior- or capability-level, not file- or line-level>

<optional mermaid block — see "Mermaid diagram" below>
```

Rules:

1. **`## Why` = 1–2 sentences.** The motivation or problem. No restating the
   title.
2. **`## What changed` = 3–6 bullets, high-level.** Describe behavior /
   capability shifts. **No file enumeration**, no "edited X, added Y to Z",
   no line-by-line restatement — *the code is the detail*. If you're tempted to
   list files, you're too low. Collapse to the behavior they implement.
3. **Brevity beats completeness.** A reviewer reads the body to orient, then
   reads the diff. Over-specifying duplicates the diff and rots on the next edit.

## Mermaid diagram (conditional)

Include **one** mermaid block **only when** the change alters control flow, a
state machine, a command sequence, or a multi-step interaction a reviewer must
trace to understand it. **Skip** for content-only, refactor, config, or
docs-only diffs — most PRs have no diagram.

- **One diagram of the resulting flow.** Add a *before + after* pair only when
  the change **replaces** existing behavior (so the reviewer sees what moved).
- **Diagram-type selection reuses `commands/propose.md`** (its design.md
  heuristics): `sequenceDiagram` for multi-step / multi-actor interactions,
  `stateDiagram-v2` for an entity lifecycle (≥3 states), `graph TB` for
  module / dependency shape. Do not duplicate that heuristic here — follow the
  link.
- Single-branch spec-level PRs (the ship procedure, last task) are prime diagram
  candidates: they bundle a whole flow change.

## Footers are command-owned

This convention covers **body content only**. Each command appends its own
footer after the body and owns it:

- `/implement` draft → the `Pre-validation draft for human review… run
  /pr-review… run /validate` instruction.
- ship procedure (`~/.claude/scripts/ship-procedure.md`, run by `/validate` / `/review-and-ship`) → `validation: pass`.
- `/quick-ship` → **no footer** (no gates run in quick-ship).

Do not move footers into this doc; do not drop a command's footer.

## Hard rule (unchanged)

**Never** add a `Co-Authored-By` trailer or any Claude attribution to the PR
body or the commit message. This overrides any global harness instruction.
