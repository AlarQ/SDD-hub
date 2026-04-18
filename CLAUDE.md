# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

A file-based, spec-driven development workflow for Claude Code. Slash commands, scripts, agents, and a general knowledge base get installed globally to `~/.claude/` via `setup.sh`. Target projects get a project-specific `knowledge-base/` and `specs/` via `/bootstrap`. One external dependency: `yq` for YAML parsing.

**This repo is not a typical codebase** — it's markdown command definitions, shell scripts, and a Rust TUI dashboard. No application code lives here.

## Project Structure

- `commands/*.md` — Slash command definitions (bootstrap, explore, propose, implement, validate, review-findings, learn-from-reports, ship, quick-ship, pr-review, spec-status, workflow-summary, continue-task, research, promote-rules)
- `knowledge-base/` — General knowledge base (security, architecture, testing, style rules). Installed globally to `~/.claude/knowledge-base/` by `setup.sh`.
- `knowledge-base-rules.md` — Shared KB prerequisites, prefix convention, and resolution rules. Installed to `~/.claude/knowledge-base-rules.md` by `setup.sh`. Referenced by all workflow commands instead of duplicating KB instructions inline.
- `scripts/task-manager.sh` — Task state machine (validate, set-status, unblock, next, check-unvalidated, status). Requires `yq`.
- `scripts/pre-commit-hook.sh` — Commit-time task validation
- `scripts/monitor.sh` — Event logger for spec implementation monitoring; appends JSONL events to `specs/<feature>/.monitor.jsonl`
- `hooks/` — Claude Code hook scripts for enforcement and monitoring (block-git-hook-bypass, block-dismissive-language, monitor-tool-calls). Installed to `~/.claude/hooks/` by `setup.sh`.
- `agents/` — Specialized agent definitions for validation gates and workflow assistance. Installed to `~/.claude/agents/` by `setup.sh`.
- `templates/` — CLAUDE.md template, settings.json hook wiring template for target projects
- `workflow-tui/` — Rust TUI dashboard for viewing spec/task status
- `onboarding.md` — Full workflow documentation
- `plan.md` — Original design document

## Build & Run

### Setup (install commands + general KB globally)

```bash
./setup.sh          # install to ~/.claude/ (commands, agents, hooks, templates, knowledge-base)
./setup.sh --force  # overwrite existing files
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
- Auto-chained flow per task: `/implement` automatically chains into validate -> review-findings (if findings) -> learn-from-reports -> ship. The user only types `/implement` and interacts during finding review and rule-candidate review. Individual commands (`/validate`, `/review-findings`, `/learn-from-reports`, `/ship`) remain available for edge cases.
- Serial execution only — one task in flight at a time

## Dual Knowledge Base

Two-layer knowledge base architecture:

- **General KB** — lives in this repo at `knowledge-base/`, installed globally to `~/.claude/knowledge-base/` by `setup.sh`. Contains universal rules: security, architecture, testing, style.
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
- `/review-findings` groups related findings (same file + overlapping/nearby lines, or same file + same category) into review units for single accept/reject decisions — reduces redundant decisions across gates
- Accepted finding groups spawn background sub-agents for parallel fix application; file-level mutual exclusion prevents concurrent edits to the same file
- Rejected findings can become new project knowledge-base rules (feedback loop) — never modify the general KB
- `/learn-from-reports` runs after `/review-findings` (or after `/validate` zero-findings) and mines reports for cross-finding patterns — recurring categories, clustered LLM findings, rejection reasoning, generalizable accepted fixes — proposing new project-KB rules in a single batched review. Report deletion is centralized in this command so both paths converge through mining before `/ship`. Complements inline rule creation in `/review-findings` (which catches one-off rules) by catching patterns that span findings.
- PreToolUse hook blocks `--no-verify` and `--no-gpg-sign` — enforces fixing failing hooks rather than bypassing them
- Stop hook blocks dismissive language ("pre-existing", "not our code") and bypass language ("temporarily disable", "skip the hook") — forces unconditional issue resolution
- Triple-gate rule: ALL validation gates must report `status: pass` before a task can move to `done`. Errored gates must be re-run — no shipping with incomplete validation
- `/continue-task` detects resume phase by checking task status and existing artifacts (reports, branches, PR state)
- `/research` activates anti-hallucination mode with citation discipline — useful for bug investigation and API contract review
- Flow changes (command chain, task state machine, validation gates, agent spawns, hooks, artifact flow) MUST trigger review of `docs/workflow-diagram.md` — update affected Mermaid diagrams in the same change. Minor wording tweaks exempt; any structural/edge/node change is not.
