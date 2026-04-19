---
id: "002"
name: "Implement scripts/config-loader.sh sourced loader"
status: done
blocked_by: ["001"]
max_files: 7
estimated_files:
  - scripts/config-loader.sh
  - tests/test-config-loader.sh
  - tests/fixtures/config/README.md
  - tests/fixtures/config/workflow-vault.yml
  - tests/fixtures/config/spec-config-valid.yml
  - tests/fixtures/config/spec-config-unknown-gate.yml
  - tests/fixtures/config/billion-laughs.yml
test_cases:
  - "Loader exports WF_SPEC_STORAGE from valid .workflow.yml"
  - "Missing .workflow.yml fails closed with exit 2, naming repo root and instructing the user to run /bootstrap; no silent defaults, no WF_* exports partially written"
  - "Malformed gates.yml fails closed with exit 3"
  - "Unknown spec gate ID fails closed with exit 4 naming the missing ID"
  - "spec_storage path traversal (../../etc) fails closed with exit 2"
  - "yq timeout on billion-laughs fixture exits 5 within 5 seconds"
  - "Double-source is idempotent (second wf_load_config call is no-op)"
  - "config-loader.sh export emits evaluable KEY=VAL lines"
  - "Uncommitted gates.yml prints warning to stderr but loader still succeeds"
  - "CI grep guard: loader contains no source reference to any workflow script"
  - "--spec sets WF_SPEC_GATES, WF_SPEC_AGENTS_<PHASE>, WF_SPEC_HAS_CONFIG"
  - "Missing per-spec config.yml when --spec provided fails closed with exit 4; no partial WF_* exports written"
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

Sourced shell loader that parses `.workflow.yml`, `gates.yml`, and (optionally) `specs/<feature>/config.yml` once per process. (Implements ADR-006: sourced loader with a strict one-way dependency on `config-paths.sh`; loader sources no other workflow script.) Validates against the schemas in `design.md §Backend Design`. Exports `WF_*` env vars. Provides `export` CLI mode for git hooks that cannot source.

`.workflow.yml` is **required**: the loader fails closed (exit 2) when the file is absent. No missing-with-defaults path. Per-field defaults in the schema apply only to fields missing **inside a present file**.

## Public API

- `wf_load_config [--spec <feature>] [--no-defaults]` — main entry point.
- `config-loader.sh export` — CLI mode: prints `KEY=VAL` lines to stdout, suitable for `eval`.
- `WF_CONFIG_LOADED=1` guard prevents double-parse on re-source.

## Exports (full list in design.md §config-loader API)

`WF_CONFIG_LOADED`, `WF_REPO_ROOT`, `WF_SPEC_STORAGE`, `WF_GATE_POOL`, `WF_AGENT_POOL`, `WF_CONFIG_FILE`, `WF_SPEC_CONFIG_FILE`, `WF_SPEC_GATES`, `WF_SPEC_AGENTS_<PHASE>`, `WF_SPEC_HAS_CONFIG`.

## Return Codes

| Code | Meaning |
|---|---|
| 0 | OK (file present and valid) |
| 2 | `.workflow.yml` missing OR invalid path in it (error distinguishes the two; missing case points at `/bootstrap`) |
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

### Decisions made during T002 implementation

- **Portable timeout:** macOS ships without GNU `timeout`. Added `wf__timeout` helper that prefers `timeout`/`gtimeout` and falls back to a Perl `alarm` fork/exec that returns rc 124 on timeout. Keeps the single 5-second budget promise without hard-requiring coreutils.
- **yq coalescing:** mikefarah/yq rejects the jq-style `// empty` token. Use `.gates[]?` / `.agents.<phase>[]?` (returns no output on missing) instead. `wf__json_get` uses a literal sentinel `__WF_NULL__` for default handling since the `//` operator needs a quoted expression.
- **Exit-code mapping:** `.workflow.yml` malformed → 2 (per spec table: "invalid path in it"); `gates.yml` malformed → 3; per-spec `config.yml` missing/malformed/unknown-id → 4; any `yq` timeout → 5; yq binary missing → 6.
- **Spec-storage validation order:** literal `..` rejection first (catches `../../etc` before realpath), then `realpath_safe`, then directory-existence check. Matches T001's `realpath_safe` contract.
- **Agent-phase exports:** `WF_SPEC_AGENTS_<PHASE>` uses `tr '[:lower:]-' '[:upper:]_'` so `pr-review` → `PR_REVIEW`. Only phases in the ADR-004 allowlist (`explore|propose|implement|validate|pr-review`) are accepted; unknown phases fail closed with exit 4.
- **Partial unset on error:** every failure path calls `wf__unset_partials` before `return`, which also unsets `WF_SPEC_AGENTS_*` via `compgen`. Guarantees "no partial `WF_*` exports" contract from spec row for `WF_SPEC_HAS_CONFIG`.
