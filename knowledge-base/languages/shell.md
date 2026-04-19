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
- `perl` — macOS-only fallback for GNU `timeout`/`gtimeout` in `scripts/config-loader.sh::wf__timeout`; macOS ships perl by default so this is zero-install on the primary target platform; not needed on Linux where GNU coreutils `timeout` is preferred
- No new runtime dependencies without updating `onboarding.md` prerequisites

## Conventions

- Scripts are invoked from repo root — use paths relative to repo root, not script location
- **Exception — sourced library scripts:** Sourced library scripts (e.g. `scripts/config-loader.sh`, `scripts/config-paths.sh`) that are `source`d from multiple callers with unpredictable cwd (hooks, slash commands) MAY resolve sibling scripts via `$(dirname "${BASH_SOURCE[0]}")` — the repo-root-relative rule does not apply to intra-library sourcing. This matches ADR-006's one-way-dependency direction: the loader must reach its leaf without a `WF_REPO_ROOT` bootstrap, because the loader itself produces `WF_REPO_ROOT`.
- Event logging via `scripts/monitor.sh` for spec implementation events (JSONL to `specs/<feature>/.monitor.jsonl`)
