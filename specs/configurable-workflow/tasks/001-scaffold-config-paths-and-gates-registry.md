---
id: "001"
name: "Scaffold config-paths.sh and gates.yml registry"
status: todo
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
