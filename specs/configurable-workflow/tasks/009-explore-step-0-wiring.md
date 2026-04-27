---
id: "009"
name: "Wire config-inferencer into /explore step 0"
status: done
pr_url: https://github.com/AlarQ/SDD-hub/pull/36
blocked_by: ["003", "004", "008"]
max_files: 1
empty_intersection_ok: true
estimated_files:
  - commands/explore.md
test_cases:
  - "/explore step 0 spawns config-inferencer before normal explore flow"
  - "Approval summary fits one screen showing gates, per-phase agents, and reasoning"
  - "Single-key approval writes specs/<feature>/config.yml"
  - "Both config_inferred and config_approved monitor events emitted on approval"
  - "Inferencer timeout falls back to manual-entry prompt"
  - "User can route to /config for manual override before approval"
ground_rules:
  - general:security/general.md
  - general:documentation/general.md
  - general:code-review/general.md
---

## Description

Update `commands/explore.md` to add a step 0 that runs the `config-inferencer` agent before the existing explore flow. Render a one-screen summary, accept single-key approval, emit the two new monitor events, and write the resulting `config.yml`.

## Step 0 Flow

1. Source `config-loader.sh` to resolve `WF_SPEC_STORAGE`.
2. Spawn `config-inferencer` with the spec description / PRD as input.
3. Render approval summary: chosen gates + per-phase agents + reasoning.
4. Single-key approve → write `$WF_SPEC_STORAGE/<feature>/config.yml`.
5. Emit `config_inferred` event (raw inferencer output) and `config_approved` event (after user approval).
6. Alternative route: user invokes `/config` for manual override before approval.

## Implementation Notes

- Inferencer failure or timeout → manual-entry prompt; if skipped, write default template from `templates/spec-config.yml.template`.
- This is a single-file change to a slash command markdown definition. Reviewer should verify the step ordering and the event-emission requirement.

## Decisions Made

- Step 0 is entirely non-blocking: every failure path (loader error, agent timeout, user skip) continues to step 1.
- `[M]` manual-entry option surfaces in the approval prompt so `/config` re-routing is always available without memorizing a separate command; the summary also surfaces [M] as the inferencer-unavailable fallback path.
- Monitor events use best-effort semantics (non-zero exit is a warning, not a stop) — consistent with how other commands treat monitor.sh.
- `config_inferred` event fires after the agent returns (before approval) so a crash during approval still leaves an audit trail.
- If `$ARGUMENTS` is empty the step is skipped silently; config inference is meaningless without a feature name.
