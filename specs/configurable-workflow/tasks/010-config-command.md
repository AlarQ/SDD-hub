---
id: "010"
name: "/config command for editing and regenerating spec config"
status: blocked
blocked_by: ["008", "009"]
max_files: 1
empty_intersection_ok: true
estimated_files:
  - commands/config.md
test_cases:
  - "/config <feature> opens current config.yml for edit"
  - "/config <feature> --regenerate re-runs inferencer and shows diff"
  - "Approval overwrites config.yml; rejection leaves file untouched"
  - "Re-resolution rejects gate IDs no longer present in gates.yml"
  - "Re-resolution rejects agent IDs no longer present in agent_pool"
  - "Documents that direct YAML edits are discouraged (mirrors task-manager pattern)"
ground_rules:
  - general:security/general.md
  - general:code-review/general.md
  - general:documentation/general.md
---

## Description

New `commands/config.md` slash command for editing or regenerating an existing `specs/<feature>/config.yml`. Supports re-running the inferencer and showing a diff against the current file before overwrite.

## Subcommands

- `/config <feature>` — open current config for guided edit.
- `/config <feature> --regenerate` — re-run `config-inferencer`, show diff against current, require approval to overwrite.

## Implementation Notes

- Re-resolves all referenced gate and agent IDs against current `gates.yml` and `agent_pool` — fails closed listing missing IDs.
- Documents that direct YAML edits are discouraged; users should route through this command for the same reason task frontmatter goes through `task-manager.sh`.
- Single-file slash command markdown.
