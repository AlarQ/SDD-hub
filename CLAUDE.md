# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

A file-based, spec-driven development workflow for Claude Code. Slash commands, scripts, agents, hooks, and templates get installed globally to `~/.claude/` via `setup.sh`. Target projects get a project-specific `knowledge-base/` and `specs/` via `/bootstrap`. One external dependency: `yq` for YAML parsing.

**This repo is not a typical codebase** — it's markdown command definitions, shell scripts, and a Rust TUI dashboard. No application code lives here.

## Project Structure

- `commands/*.md` — Slash command definitions (bootstrap, explore, propose, validate-spec, implement, validate, review-findings, learn-from-reports, ship, quick-ship, pr-review, spec-status, workflow-summary, continue-task, research, promote-rules)
- `knowledge-base/` — General knowledge base (security, architecture, testing, style rules). Lives in this repo; not installed globally.
- `knowledge-base-rules.md` — Shared KB prerequisites, prefix convention, and resolution rules. Lives in this repo; not installed globally. Referenced by all workflow commands instead of duplicating KB instructions inline.
- `scripts/task-manager.sh` — Task state machine (validate, set-status, unblock, next, create-followup, check-unvalidated, status). Requires `yq`. `create-followup <feature> <fr-id> <description>` auto-generates a `status: todo` task from a `/validate-impl` spec-audit accepted finding; FR id is validated against `spec.md` (fail-closed on unknown ids) and ground_rules are inherited from the spec's `## Applicable Ground Rules` section.
- `scripts/pre-commit-hook.sh` — Commit-time task validation
- `scripts/monitor.sh` — Event logger for spec implementation monitoring; appends JSONL events to `specs/<feature>/.monitor.jsonl`
- `hooks/` — Claude Code hook scripts for enforcement and monitoring (block-git-hook-bypass, block-dismissive-language, monitor-tool-calls). Installed to `~/.claude/hooks/` by `setup.sh`.
- `agents/` — Specialized agent definitions for validation gates and workflow assistance. Installed to `~/.claude/agents/` by `setup.sh`.
- `templates/` — CLAUDE.md template, settings.json hook wiring template for target projects
- `workflow-tui/` — Rust TUI dashboard for viewing spec/task status
- `onboarding.md` — Full workflow documentation
- `plan.md` — Original design document

## Build & Run

### Setup (install commands globally)

```bash
./setup.sh          # install to ~/.claude/ (commands, agents, hooks, templates)
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
- Explicit per-step invocation: each command is invoked separately by the user. After finishing, every command prints the next command to run (e.g. `/implement` → "Run `/validate $ARGUMENTS` next"). No command auto-invokes another. Sequence per task: `/implement` → `/validate` → (`/review-findings` if findings) → `/learn-from-reports` → `/ship`. After the last task transitions to `done`, the user runs `/validate-impl` for the final spec-completion audit.
- Serial execution only — one task in flight at a time

## Dual Knowledge Base

Two-layer knowledge base architecture:

- **General KB** — lives in this repo at `knowledge-base/`. Contains universal rules: security, architecture, testing, style.
- **Project KB** — created per-project by `/bootstrap` at `knowledge-base/`. Contains project-specific rules: language files and conventions discovered via `/review-findings`.

All workflow commands read from both. Project rules override general rules on the same topic. New rules from `/review-findings` always go to the project KB.

Task `ground_rules` use prefix convention: `general:security/general.md`, `project:languages/rust.md`. Unprefixed defaults to `project:`.

## Configurable Workflow

The configurable-workflow feature externalizes gate and agent selection into YAML config. Three files form the config layer:

- **`.workflow.yml`** (repo root) — `spec_storage`, `gate_pool`, `agent_pool`, `validate_scope`. Required for any active invocation. Missing → loader exit 2; run `/bootstrap`.
- **`knowledge-base/gates.yml`** (gate registry) — canonical list of deterministic gates with `id`, `command`, `applies_to`, `category`, `blocking`. Sole source of truth for executable gates.
- **`specs/<feature>/config.yml`** (per-spec config) — `tags`, `gates` (the **ceiling**), and `agents` per phase. Written by `/explore` step 0 after inferencer approval. Required on all active processing paths; missing → exit 4.

**Key terms.** Canonical definitions of **ceiling**, **effective-set**, **spec-union** live in `scripts/workflow-glossary.md` (installed to `~/.claude/scripts/workflow-glossary.md`). Commands link there. One additional cadence term defined here:

- **`validate_scope`** — cadence control: `per-task` (default), `per-spec` (skip per-task validate; spec-union runs at `/validate-impl`), or `both`.

**Config loader (`scripts/config-loader.sh`):**
- Walks up from CWD to find `.workflow.yml`; single `timeout 5 yq` parse
- Leaf module — sources nothing from workflow scripts (no circular dep)
- **Canonical contract (exported env vars + exit codes): `scripts/config-loader.contract.md`.** All commands link there instead of inlining partial lists.

**`/explore` step 0:** Before normal explore flow, spawns `config-inferencer` agent, shows one-screen summary, accepts single-key approval or `/config` override, writes `config.yml`, emits `config_inferred` + `config_approved` monitor events.

**`/validate` ceiling semantics:** Executes intersection of spec-eligible gates ∩ gates applicable to task `ground_rules`. Skipped gates emit `gate_skip` events.

**`/validate-impl`:** Runs once when all spec tasks reach `done`. Spawns Odium with spec FR list, prd.md scope, task list, and git diff range. Verdict `complete` → spec shipped; verdict `reopen` → `/review-findings` spawns follow-up tasks.

See `specs/configurable-workflow/design.md` for full ADR detail and schema definitions.

## Tier System (small | medium | large)

Specs are tiered to right-size flow ceremony. Tier is inferred at `/explore` step 0 by `engineering-config-inferencer` and approved by the user; written to `specs/<feature>/config.yml` as `tier:`.

| Tier | Target tasks | Ceiling tasks | Ceiling files | Flow shape |
|------|--------------|---------------|---------------|------------|
| `small`  | 2–4         | 5             | 10            | `/explore` → `/propose` (tasks/ only — skip spec.md, design.md, test-strategy.md) → skip `/validate-spec` → `/implement` → `/validate` (lint+tests only; skip Phase-2 agent gates per `WF_TIER_AGENT_SKIP`) → `/ship`. Skip `/validate-impl` Odium audit. |
| `medium` | 4–7         | 10            | 30            | `/explore` → `/propose` (spec.md + tasks/, skip design.md + test-strategy.md) → skip `/validate-spec` → full per-task gates → `/validate-impl` runs. |
| `large`  | 7–12 typical | unbounded    | unbounded     | Full unchanged flow. |

Defaults live in `.workflow.yml` under `tiers:`. Per-spec override via `tier_ceiling:` in `specs/<feature>/config.yml`.

**Hard rules force ≥`medium`:** auth, crypto, secrets, DB migrations, public API contract changes, cross-service interactions. Encoded in inferencer rubric.

**Tier breach:** `/implement` step 0 runs `scripts/tier-check.sh <feature>`. Exit 9 → user picks `Continue` (acknowledge, proceed) or `Abort` (run `/promote-tier <feature>` — re-runs propose at next tier, preserves implemented tasks).

Loader exports: `WF_SPEC_TIER`, `WF_TIER_TASK_CEILING`, `WF_TIER_FILE_CEILING`, `WF_TIER_AGENT_SKIP` (see `scripts/config-loader.contract.md`).

Monitor events: `tier_inferred`, `tier_approved`, `tier_breach`, `tier_promoted`, `validate_impl_skipped`.

## Multi-Repo Specs (Vault Mode)

`.workflow.yml spec_storage_mode: vault` enables vault-hosted specs that bind one or more code repos. Per-spec `config.yml repos[]` maps `name → path → role`. Loader exports `WF_REPO_NAMES` + `WF_REPO_PATHS`; helpers `wf_repo_path` / `wf_for_each_repo`. Exit 7 on bad path.

Per-task `repo:` required when `repos[]` non-empty; `task-manager.sh validate` enforces membership. Hard rule: one task = one repo. Ground-rule prefix `repo:<name>:` resolves to that repo's `knowledge-base/`.

`/implement`, `/validate`, `/ship`, `/pr-review`, `/fix`, `/quick-ship` resolve `WF_TASK_REPO_PATH` per `scripts/multi-repo-resolution.md` and run git/gates/PR creation against that path. `/validate-impl` emits per-repo diff sections for Odium. Gates may declare `applies_to_repos: [<name>,…]` to scope.

Monitor events: `repo_bound`, `repo_missing`, `gate_repo_switch`.

## Bug-Fix Flow (/fix)

Standalone command for production bugs/regressions. Skips `/explore` and `/propose` entirely. Artifact: `specs/fixes/<slug>/fix.md` (frontmatter `type: fix`, sections: Repro, Root Cause, Fix Plan, Regression Test).

Flow: `/fix <slug>` → BDD repro → spawn `ultrathink-debugger` for root cause → write `fix.md` → capture pre-fix test failure → apply fix → regression test must pass → lint + ground-rule-matched gates (skip Phase-2 agent gates by default unless diff touches auth/crypto/migrations) → `/ship` (PR title prefix `fix:`).

No `design.md`, no `test-strategy`, no `/validate-spec`, no `/validate-impl`, no tier system. Use `task-manager.sh init-fix <slug>` to scaffold the artifact.

Monitor events: `fix_started`, `fix_root_cause`, `fix_shipped`.

## Key Design Decisions

- `/ship` is separate from `/implement` — commit/push/PR creation happens after validation
- `/implement` checks for unmerged PRs — previous task's PR must be merged before starting next
- Gates listed in `knowledge-base/gates.yml` with `blocking: true` are mandatory for tasks whose `ground_rules` match — skipping is not allowed
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
- `/validate-spec` is a pre-implementation spec-coherence gate wrapping the `Spec Reviewer` agent — audits `specs/<feature>/` for contract gaps, logic gaps, missing pieces, and repo misalignment before `/implement` is allowed to start. The user runs it explicitly after `/propose`. Findings flow through `/review-findings` and patch the spec/design/tasks files (not code). Distinct from `/validate-impl` (post-implementation Odium audit of claimed-vs-actual completion, per configurable-workflow ADR-008).
- All interactive user prompts in workflow commands MUST use the `AskUserQuestion` tool (per `scripts/ask-user-protocol.md`). Plain markdown question lists / `[A][B][C]` text menus / "type your answer below" prose are not allowed.
- Flow changes (command chain, task state machine, validation gates, agent spawns, hooks, artifact flow) MUST trigger review of `docs/workflow-diagram.md` — update affected Mermaid diagrams in the same change. Minor wording tweaks exempt; any structural/edge/node change is not.
