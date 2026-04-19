---
id: "001"
name: "Scaffold config-paths.sh and gates.yml registry"
status: done
pr_url: "https://github.com/AlarQ/SDD-hub/pull/30"
blocked_by: []
max_files: 5
estimated_files:
  - scripts/config-paths.sh
  - knowledge-base/gates.yml
  - templates/workflow.yml.template
  - templates/spec-config.yml.template
  - tests/test-config-paths.sh
test_cases:
  - "find_workflow_root discovers .workflow.yml from nested subdirectory"
  - "find_workflow_root returns non-zero when no marker exists in any ancestor"
  - "realpath_safe rejects ../../etc escape"
  - "realpath_safe rejects path with symlink ancestor outside repo or HOME"
  - "validate_id accepts rust-clippy"
  - "validate_id rejects ; rm -rf ~"
  - "validate_id rejects 65-character ID"
  - "gates.yml parses with yq and every entry has id, command, applies_to, category, blocking"
  - "gates.yml IDs are unique within file"
  - "config-paths.sh contains no source of any workflow script"
  - "Shared fixtures created under tests/fixtures/config/ (workflow-valid.yml, gates-valid.yml, gates-duplicate-id.yml, symlink-ancestor tree, nested/deep/cwd)"
ground_rules:
  - general:languages/shell.md
  - general:security/general.md
  - general:architecture/general.md
---

## Description

Create the leaf shell helper module `scripts/config-paths.sh` and seed the canonical gate registry `knowledge-base/gates.yml`. Pure helpers — no sourcing of any workflow script. Also write the two YAML templates that `/bootstrap` and `/explore` will use later. (Implements ADR-001 three-file split: `gates.yml` is the canonical gate registry.)

## Public API (config-paths.sh)

- `find_workflow_root` — walk up from `realpath($PWD)` for `.workflow.yml`; print path on stdout, return non-zero if not found.
- `realpath_safe <path>` — normalize via `realpath`; reject paths whose ancestors are symlinks to outside `$HOME` or repo root; require absolute or relative-under-repo.
- `validate_id <string>` — match against `^[a-zA-Z0-9_-]{1,64}$`; return 0/1.

## Implementation Notes

- `set -euo pipefail`; quoted expansions; ≤150 lines (project shell module limit).
- Reuses regex from `scripts/monitor.sh:64-70`; this becomes the canonical home and `monitor.sh` will delegate later (T3).
- `gates.yml` content seeded by translating current `validation_tools` frontmatter from `knowledge-base/languages/*.md` into structured entries (`id`, `command`, `applies_to: [<lang>]`, `category`, `blocking: true`). Cross-cutting gates (e.g. semgrep) tagged `applies_to: [any]`.
- Templates contain commented defaults only — no executable values.
- This task creates files only; no edits to existing scripts. T3 will refactor callers.

## Implementation Notes (T001 delivery)

- `config-paths.sh` is 97 lines (under 150-line cap); sources no workflow script (guarded by `test_config_paths_sources_no_workflow_script`).
- `validate_id` regex: `^[a-zA-Z0-9_-]{1,64}$`. Canonical home here; `monitor.sh` delegation deferred to T003 per design.md §Caller integration.
- `realpath_safe` pre-normalize check rejects any literal `..` segment before `realpath`, then walks input-path ancestors and rejects symlinks whose resolved target escapes BOTH `$HOME` and the discovered workflow root. Two-root allowance keeps tests reproducible when `$HOME` ≠ repo root.
- `gates.yml` seeded only from actually-run `validation_tools` in `knowledge-base/languages/{rust,shell}.md`. Cross-cutting gates (semgrep) deliberately not committed — no one runs them yet — but the `applies_to: [any]` pattern is documented in test fixture `gates-valid.yml`.
- Tests sandbox under `mktemp -d`, skip (not fail) when host has stray `.workflow.yml` above `/tmp` or lacks `yq`.
- Test Strategist agent not spawned: T001 is the first task, no completed-task fixtures exist to reuse, and the task's `test_cases` already match `test-strategy.md` T001 ownership verbatim.
