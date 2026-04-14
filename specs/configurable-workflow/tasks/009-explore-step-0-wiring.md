---
id: "009"
name: "Wire config-inferencer into /explore step 0"
status: blocked
blocked_by: ["003", "004", "008"]
max_files: 1
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
