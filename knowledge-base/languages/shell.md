---
validation_tools:
  - bash -n scripts/*.sh
  - shellcheck scripts/*.sh
---

# Shell — Project-Specific Rules (scripts/)

General Shell rules live in `general:languages/shell.md`. These rules are specific to scripts in this repo.

## Task State Machine

- **Never edit task YAML frontmatter directly** — all state transitions go through `scripts/task-manager.sh`
- Valid transitions: `blocked → todo → in-progress → implemented → review → done`
- Use `task-manager.sh validate` before any status change

## Approved Dependencies

- `yq` — sole YAML parsing tool; no `python3`, `jq`, or `awk` hacks for YAML
- `gh` — GitHub CLI for PR operations
- No new runtime dependencies without updating `onboarding.md` prerequisites

## Conventions

- Scripts are invoked from repo root — use paths relative to repo root, not script location
- Event logging via `scripts/monitor.sh` for spec implementation events (JSONL to `specs/<feature>/.monitor.jsonl`)
