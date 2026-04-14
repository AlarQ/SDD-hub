---
id: "002"
name: "Implement scripts/config-loader.sh sourced loader"
status: blocked
blocked_by: ["001"]
max_files: 3
estimated_files:
  - scripts/config-loader.sh
  - tests/test-config-loader.sh
  - tests/fixtures/config/README.md
test_cases:
  - "Loader exports WF_SPEC_STORAGE from valid .workflow.yml"
  - "Missing .workflow.yml returns 0 with default spec_storage=specs/"
  - "Malformed gates.yml fails closed with exit 3"
  - "Unknown spec gate ID fails closed with exit 4 naming the missing ID"
  - "spec_storage path traversal (../../etc) fails closed with exit 2"
  - "yq timeout on billion-laughs fixture exits 5 within 5 seconds"
  - "Double-source is idempotent (second wf_load_config call is no-op)"
  - "config-loader.sh export emits evaluable KEY=VAL lines"
  - "Uncommitted gates.yml prints warning to stderr but loader still succeeds"
  - "CI grep guard: loader contains no source reference to any workflow script"
  - "--spec sets WF_SPEC_GATES, WF_SPEC_AGENTS_<PHASE>, WF_SPEC_HAS_CONFIG"
  - "Missing per-spec config.yml sets WF_SPEC_HAS_CONFIG=0 with no error"
  - "gates.yml tracked-state warning printed when file has uncommitted modifications"
  - "Integration seam: loader composes config-paths.sh primitives under unified WF_* contract"
  - "Extends shared fixture set under tests/fixtures/config/ (workflow-vault.yml, spec-config-valid.yml, spec-config-unknown-gate.yml, billion-laughs.yml)"
ground_rules:
  - general:languages/shell.md
  - general:security/general.md
  - general:architecture/general.md
  - general:testing/principles.md
---

## Description

Sourced shell loader that parses `.workflow.yml`, `gates.yml`, and (optionally) `specs/<feature>/config.yml` once per process. Validates against the schemas in `design.md §Backend Design`. Exports `WF_*` env vars. Provides `export` CLI mode for git hooks that cannot source.

## Public API

- `wf_load_config [--spec <feature>] [--no-defaults]` — main entry point.
- `config-loader.sh export` — CLI mode: prints `KEY=VAL` lines to stdout, suitable for `eval`.
- `WF_CONFIG_LOADED=1` guard prevents double-parse on re-source.

## Exports (full list in design.md §config-loader API)

`WF_CONFIG_LOADED`, `WF_REPO_ROOT`, `WF_SPEC_STORAGE`, `WF_GATE_POOL`, `WF_AGENT_POOL`, `WF_CONFIG_FILE`, `WF_SPEC_CONFIG_FILE`, `WF_SPEC_GATES`, `WF_SPEC_AGENTS_<PHASE>`, `WF_SPEC_HAS_CONFIG`.

## Return Codes

| Code | Meaning |
|---|---|
| 0 | OK (incl. missing-with-defaults) |
| 2 | Invalid path in `.workflow.yml` |
| 3 | `gates.yml` invalid or missing when referenced |
| 4 | Spec `config.yml` invalid or unknown ID |
| 5 | `yq` timeout |
| 6 | Unexpected (yq missing, etc.) |

## Implementation Notes

- Every `yq`/`jq` call wrapped with `timeout 5`; non-zero → `ERROR: <file>: <reason>` to stderr, unset partial `WF_*` vars, return non-zero. Fail closed.
- Single parse per process: `WF_CONFIG_LOADED=1` guard. Subshells inherit via exported env — only the outermost shell parses.
- Sources `config-paths.sh` for `find_workflow_root`, `realpath_safe`, `validate_id`. Sources nothing else from the workflow tree.
- Loader writes nothing to disk; never executes values from YAML.
- `gates.yml` uncommitted-state check: `git diff --quiet -- knowledge-base/gates.yml || warn`.
- Test fixtures live under `tests/fixtures/config/` (valid, malformed, parse-bomb, traversal cases).
