---
id: "011"
name: "Bootstrap, setup, and cleanup of legacy fallback"
status: blocked
blocked_by: ["004", "007", "010"]
max_files: 10
estimated_files:
  - commands/bootstrap.md
  - setup.sh
  - scripts/monitor.sh
  - scripts/task-manager.sh
  - scripts/pre-commit-hook.sh
  - knowledge-base/languages/rust.md
  - knowledge-base/languages/typescript.md
  - knowledge-base/languages/nextjs.md
  - knowledge-base/languages/scala.md
  - knowledge-base/languages/shell.md
test_cases:
  - "Fresh repo /bootstrap writes .workflow.yml at root with defaults"
  - "setup.sh --force installs config-paths.sh, config-loader.sh, /config command, and config-inferencer agent globally"
  - "E2E against non-default spec_storage=/tmp/vault goes green end-to-end"
  - "No grep 'specs/' hardcoded fallback remains in monitor/task-manager/pre-commit"
  - "All knowledge-base/languages/*.md files mark validation_tools as display-only"
  - "Existing tests still green after fallback removal"
  - "E2E step (a): /bootstrap writes .workflow.yml in throwaway repo with spec_storage=/tmp/vault"
  - "E2E step (b): /explore step 0 produces config.yml under /tmp/vault"
  - "E2E step (c): monitor events land under /tmp/vault, never ./specs"
  - "E2E step (d): TUI scanner discovers the spec at the vault path"
  - "E2E step (e): /validate runs a non-empty intersection"
  - "E2E step (f): /ship snapshot comparison succeeds"
ground_rules:
  - general:architecture/general.md
  - general:security/general.md
  - general:languages/shell.md
  - general:documentation/general.md
---

## Description

Final wiring task. Bootstrap and setup install the new files globally. Then remove the dogfood-safety fallback from T3 callers (now safe — full pipeline is green). Then downgrade `validation_tools` frontmatter in the language KB files to display-only annotations.

## Changes

- `commands/bootstrap.md` — generate `.workflow.yml` at repo root from `templates/workflow.yml.template`.
- `setup.sh` — install `scripts/config-paths.sh`, `scripts/config-loader.sh`, `commands/config.md`, `agents/engineering/engineering-config-inferencer.md` to `~/.claude/`.
- `scripts/monitor.sh`, `scripts/task-manager.sh`, `scripts/pre-commit-hook.sh` — remove the legacy hardcoded-`specs/` fallback flag introduced in T3.
- `knowledge-base/languages/*.md` (5 files) — annotate `validation_tools` frontmatter as display-only with a comment pointing at `gates.yml` as canonical.

## Gate

Before this task can ship, an E2E test must pass: fresh repo → `/bootstrap` → `/explore` → `/validate` against a non-default `spec_storage=/tmp/vault`. Documented in `tests/test-e2e-vault.sh`.

## Scope Flag

10 files — within the 20-file budget but large surface. If any language file needs more than annotation, split off a follow-up task `011b — frontmatter-downgrade`.

## Implementation Notes

- Fallback removal must be atomic with the bootstrap update: never leave a half-removed fallback that breaks fresh installs.
- Post-removal grep guard: `! grep -rn 'specs/$' scripts/monitor.sh scripts/task-manager.sh scripts/pre-commit-hook.sh`.
