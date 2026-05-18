# `/implement` is a test-driven red-green-refactor loop

Status: accepted

`/implement` previously wrote code first (step 9) then test bodies after (step 11) — test-after, contradicting the project's `tdd` skill, which mandates vertical red→green→refactor slices and explicitly bans "all tests then all code". We replaced steps 9–11 with: a pre-loop backlog-settle (Test Strategist refinement moved *before* code; interface/priority approval prompted only for `interaction: hitl` tasks so AFK autonomy is preserved), a per-behavior RED→GREEN loop emitting `tdd_red`/`tdd_green` monitor events, then a post-loop refactor. It applies to all tiers with no small-tier exemption, and `/validate-impl` raises an advisory (non-blocking) finding when a done task lacks red→green evidence.

## Considered Options

- **Opt-in/tier-gated/augment-only** — rejected: weaker enforcement, leaves test-after as a legal path and the skill contradiction unresolved.
- **Always prompt for approval before the loop** — rejected: full TDD fidelity but breaks the workflow's AFK-bias (autonomous implement + merge). HITL-gating the prompt to `interaction: hitl` tasks keeps fidelity where a human is already in the loop.

## Consequences

- The RED→GREEN evidence is auditable per behavior via `.monitor.jsonl`; absence is surfaced advisory-only so the spec-completion gate is not newly blocking.
- Reversing this (back to test-after) means rewriting `/implement` and the monitor-evidence audit — meaningful cost, hence this record.
