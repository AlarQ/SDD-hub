# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

A file-based, spec-driven development workflow for Claude Code and GitHub Copilot. Slash commands, scripts, agents, and a general knowledge base get installed globally to `~/.claude/` via `setup.sh` (Claude Code) or per-project to `.github/` via `setup-copilot.sh` (GitHub Copilot). Target projects get a project-specific `knowledge-base/` and `specs/` via `/bootstrap`. One external dependency: `yq` for YAML parsing.

**This repo is not a typical codebase** — it's markdown command definitions, shell scripts, and a Rust TUI dashboard. No application code lives here.

## Project Structure

- `commands/*.md` — Slash command definitions (bootstrap, explore, propose, implement, validate, review-findings, ship, quick-ship, pr-review, spec-status, workflow-summary, continue-task, research)
- `knowledge-base/` — General knowledge base (security, architecture, testing, style rules). Installed globally to `~/.claude/knowledge-base/` by `setup.sh`, or to `knowledge-base/_general/` by `setup-copilot.sh`.
- `knowledge-base-rules.md` — Shared KB prerequisites, prefix convention, and resolution rules. Installed to `~/.claude/knowledge-base-rules.md` by `setup.sh`. Referenced by all workflow commands instead of duplicating KB instructions inline.
- `scripts/task-manager.sh` — Task state machine (validate, set-status, unblock, next, check-unvalidated, status). Requires `yq`.
- `scripts/pre-commit-hook.sh` — Commit-time task validation
- `hooks/` — Claude Code hook scripts for enforcement (block-git-hook-bypass, block-dismissive-language). Installed to `~/.claude/hooks/` by `setup.sh`.
- `agents/` — Specialized agent definitions for validation gates and workflow assistance. Installed to `~/.claude/agents/` by `setup.sh`.
- `copilot/` — GitHub Copilot equivalents: `.prompt.md` files (slash commands), `.agent.md` files (custom agents), `.instructions.md` files (path-specific rules), and `copilot-instructions.md` (repo-wide). Installed per-project to `.github/` by `setup-copilot.sh`.
- `templates/` — CLAUDE.md template, settings.json hook wiring template for target projects
- `workflow-tui/` — Rust TUI dashboard for viewing spec/task status
- `onboarding.md` — Full workflow documentation
- `plan.md` — Original design document

## Build & Run

### Setup — Claude Code (install commands + general KB globally)

```bash
./setup.sh          # install to ~/.claude/ (commands, agents, hooks, templates, knowledge-base)
./setup.sh --force  # overwrite existing files
```

### Setup — GitHub Copilot (install per-project)

```bash
./setup-copilot.sh /path/to/project          # install to project's .github/
./setup-copilot.sh --force /path/to/project   # overwrite existing files
```

### Workflow TUI (Rust)

```bash
cd workflow-tui
cargo build
cargo run -- /path/to/project   # project must contain specs/ directory
```

Dependencies: ratatui, crossterm, notify (file watcher), serde_yml, clap, anyhow. Edition 2024.

### Prerequisites

`yq` (`brew install yq`), `gh` (`brew install gh`)

## Workflow TUI Architecture

Elm-like architecture with file-system watching for live reload:

- `main.rs` — CLI parsing (clap), terminal setup, event loop
- `app.rs` — Application state and update logic
- `event.rs` — Event polling (keyboard, terminal resize)
- `watcher.rs` — File system watcher (notify) for live-reloading specs
- `model/` — Domain types: `spec.rs`, `task.rs`, `report.rs`
- `parse/` — File parsers: `scanner.rs` (directory scanning), `task_parser.rs`, `report_parser.rs`, `frontmatter.rs` (generic YAML frontmatter)
- `ui/` — Ratatui widgets: `layout.rs`, `spec_list.rs`, `progress.rs`, `reports.rs`, `dep_graph.rs`, `styles.rs`

## Slash Command Conventions

- Commands receive feature name via `$ARGUMENTS`
- All task status changes go through `task-manager.sh` — never edit YAML frontmatter directly
- Task state machine: `blocked -> todo -> in-progress -> implemented -> review -> done` (canonical source: `scripts/task-manager.sh`; full docs: `plan.md`)
- Auto-chained flow per task: `/implement` automatically chains into validate -> review-findings (if findings) -> ship. The user only types `/implement` and interacts during finding review. Individual commands (`/validate`, `/review-findings`, `/ship`) remain available for edge cases.
- Serial execution only — one task in flight at a time

## Dual Knowledge Base

Two-layer knowledge base architecture:

- **General KB** — lives in this repo at `knowledge-base/`, installed globally to `~/.claude/knowledge-base/` by `setup.sh` (or `knowledge-base/_general/` by `setup-copilot.sh`). Contains universal rules: security, architecture, testing, style.
- **Project KB** — created per-project by `/bootstrap` at `knowledge-base/`. Contains project-specific rules: language files (with `validation_tools`), conventions discovered via `/review-findings`.

All workflow commands read from both. Project rules override general rules on the same topic. New rules from `/review-findings` always go to the project KB.

Task `ground_rules` use prefix convention: `general:security/general.md`, `project:languages/rust.md`. Unprefixed defaults to `project:`.

## Key Design Decisions

- `/ship` is separate from `/implement` — commit/push/PR creation happens after validation
- `/implement` checks for unmerged PRs — previous task's PR must be merged before starting next
- Validation tools defined in language file frontmatter `validation_tools` are mandatory; skipping is not allowed
- `/validate` Phase 2 spawns specialized agents in parallel (security, code-quality, architecture, compliance) instead of inline LLM analysis
- Agent findings are advisory (`source: llm`), tool findings are high-confidence (`source: tool`); both go through `/review-findings`
- `/propose` spawns `Software Architect` agent during design.md generation for trade-off analysis and ADR production; main command still owns spec.md and task decomposition
- `/implement` auto-spawns `Ultrathink Debugger` on errors/test failures for root cause analysis; spawns `Code Quality Pragmatist` post-implementation for pre-validation sanity check (high/critical issues go through human accept/reject)
- `/pr-review` spawns `Code Reviewer` agent to proactively analyze PR diff before handling human comments; agent findings go through accept/reject flow
- Rejected findings can become new project knowledge-base rules (feedback loop) — never modify the general KB
- PreToolUse hook blocks `--no-verify` and `--no-gpg-sign` — enforces fixing failing hooks rather than bypassing them
- Stop hook blocks dismissive language ("pre-existing", "not our code") and bypass language ("temporarily disable", "skip the hook") — forces unconditional issue resolution
- Triple-gate rule: ALL validation gates must report `status: pass` before a task can move to `done`. Errored gates must be re-run — no shipping with incomplete validation
- `/continue-task` detects resume phase by checking task status and existing artifacts (reports, branches, PR state)
- `/research` activates anti-hallucination mode with citation discipline — useful for bug investigation and API contract review
