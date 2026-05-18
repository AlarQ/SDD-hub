# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

A file-based, spec-driven development workflow for Claude Code. Slash commands, scripts, agents, hooks, and templates get installed globally to `~/.claude/` via `setup.sh`. Target projects get a project-specific `knowledge-base/` and `specs/` via `/bootstrap`. One external dependency: `yq` for YAML parsing.

**This repo is not a typical codebase** — it's markdown command definitions, shell scripts, and a Rust web dashboard. No application code lives here.

## Project Structure

- `commands/*.md` — Slash command definitions (bootstrap, config, grill, explore, propose, validate-spec, implement, validate, validate-impl, review-findings, learn-from-reports, ship, quick-ship, pr-review, fix, spec-status, workflow-summary, continue-task, research, promote-rules, promote-tier, capture-rule)
- `skills/` — Reusable skill prompts (e.g. `bash-scripting/SKILL.md`). Installed to `~/.claude/skills/` by `setup.sh`.
- `tests/` — Bash test suite for scripts (task-manager, config-loader, monitor, validate-impl, tier-check, etc.). Run individual tests directly: `bash tests/test-task-manager.sh`.
- `knowledge-base/` — General knowledge base (security, architecture, testing, style rules). Lives in this repo; not installed globally.
- `scripts/knowledge-base-rules.md` — Shared KB prerequisites, prefix convention, and resolution rules (incl. single-repo vault implicit default). Installed globally to `~/.claude/scripts/` by `setup.sh`. Referenced by all workflow commands instead of duplicating KB instructions inline.
- `scripts/task-manager.sh` — Task state machine (validate, set-status, unblock, next, create-followup, check-unvalidated, status). Requires `yq`. `create-followup <feature> <fr-id> <description>` auto-generates a `status: todo` task from a `/validate-impl` spec-audit accepted finding; FR id is validated against `spec.md` (fail-closed on unknown ids) and ground_rules are inherited from the spec's `## Applicable Ground Rules` section.
- `scripts/pre-commit-hook.sh` — Commit-time task validation
- `scripts/monitor.sh` — Event logger for spec implementation monitoring; appends JSONL events to `specs/<feature>/.monitor.jsonl`
- `hooks/` — Claude Code hook scripts for enforcement and monitoring (block-git-hook-bypass, block-dismissive-language, monitor-tool-calls). Installed to `~/.claude/hooks/` by `setup.sh`.
- `agents/` — Specialized agent definitions for validation gates and workflow assistance. Installed to `~/.claude/agents/` by `setup.sh`.
- `templates/` — CLAUDE.md template, settings.json hook wiring template for target projects
- `Cargo.toml` — root Cargo workspace (`members = ["workflow-core", "workflow-web"]`)
- `workflow-core/` — shared Rust library: `model/`, `parse/`, `WatchSource`/`WatchEvent`
- `workflow-web/` — Rust web dashboard (Axum + Leptos SSR) for viewing spec/task status
- `onboarding.md` — Full workflow documentation
- `plan.md` — Original design document

## Build & Run

### Setup (install commands globally)

```bash
./setup.sh          # install to ~/.claude/ (commands, agents, hooks, templates)
./setup.sh --force  # overwrite existing files
```

### Workflow web dashboard (Rust)

Root Cargo workspace. Run all cargo commands with `--workspace` from the repo root.

```bash
cargo check --workspace
cargo test --workspace
cargo web -- /path/to/master-brain-root   # alias for `cargo run -p workflow-web --`
```

Edition 2024. Shared `[workspace.dependencies]`: serde, serde_yml, serde_json, anyhow, tokio, tracing.

### Prerequisites

`yq` (`brew install yq`), `gh` (`brew install gh`)

## Workspace Architecture

Two-crate Cargo workspace (ADR-001, ADR-002):

- `workflow-core/` — shared library, builds standalone (`cargo check -p workflow-core`):
  - `model/` — domain types: `spec.rs`, `task.rs`, `report.rs`, `monitor_event.rs`
  - `parse/` — file parsers: `scanner.rs`, `task_parser.rs`, `report_parser.rs`, `monitor_parser.rs`, `frontmatter.rs`, `warning.rs`
  - `watch.rs` — `WatchSource` trait + `WatchEvent` enum (notify-backed impls live in `workflow-web`)
- `workflow-web/` — web dashboard (Axum + Leptos SSR); the only `WatchSource` implementor. Consumes `workflow-core`; no terminal UI.

## Slash Command Conventions

- Commands receive feature name via `$ARGUMENTS`
- All task status changes go through `task-manager.sh` — never edit YAML frontmatter directly
- Task state machine: `blocked -> todo -> in-progress -> implemented -> review -> done` (canonical source: `scripts/task-manager.sh`; full docs: `plan.md`)
- Explicit per-step invocation: each command is invoked separately by the user. After finishing, every command prints the next command to run (e.g. `/implement` → "Draft PR opened. Run `/pr-review $ARGUMENTS` after commenting, or `/validate $ARGUMENTS` if no comments."). No command auto-invokes another. Sequence per task: `/implement` (opens draft PR) → `/pr-review` (loop until PR comments resolved; optional if none) → `/validate` → (`/review-findings` if findings) → `/learn-from-reports` → `/ship` (marks draft PR ready). After the last task transitions to `done`, the user runs `/validate-impl` for the final spec-completion audit.
- Serial execution only — one task in flight at a time

## Dual Knowledge Base

Two-layer knowledge base architecture:

- **General KB** — lives at the path configured by `general_kb_path` in each repo's `.workflow.yml`, exported as `$WF_GENERAL_KB` by `scripts/config-loader.sh`. Recommended location: a master-brain / Obsidian vault (e.g. `~/Desktop/projects/master-brain/general-knowledge-base/`). Contains universal rules: security, architecture, testing, style. Key is **required** — loader exits 2 if missing.
- **Project KB** — created by `/bootstrap` at `knowledge-base/` inside each code repo (repo mode: `repo`; vault mode: `repo-gate-init`). Never in the vault. Contains project-specific rules: language files and conventions discovered via `/review-findings`.

All workflow commands read from both. Project rules override general rules on the same topic. New rules from `/review-findings` always go to the project KB. In vault mode `WF_PROJECT_KB`/`WF_GATE_POOL` are empty; project KB + gates resolve **per task** from the bound repo (`multi-repo-resolution.md`).

Task `ground_rules` use prefix convention: `general:security/general.md` (resolves under `$WF_GENERAL_KB`), `project:languages/rust.md`, `repo:<name>:` (vault/multi-repo). Unprefixed defaults to `project:`. In vault mode: a **single** bound repo is the implicit default (unprefixed/`project:` resolve to it); **two+** bound repos require `general:` or `repo:<name>:` (bare rejected, exit 7).

## Configurable Workflow

The configurable-workflow feature externalizes gate and agent selection into YAML config. Three files form the config layer:

- **`.workflow.yml`** (repo root in repo mode; vault root in vault mode) — `spec_storage`, `gate_pool`, `agent_pool`, `validate_scope`. In vault mode it is a **thin pointer**: no `gate_pool` (absent/ignored — gates resolve per-task from each bound repo's `knowledge-base/gates.yml`), plus `spec_storage_mode: vault` + `default_repos:`. Required for any active invocation. Missing → loader exit 2; run `/bootstrap`.
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
| `small`  | 2–4         | 5             | 10            | (`/grill` optional) → `/explore` → `/propose` (tasks/ only — skip spec.md, design.md, test-strategy.md) → skip `/validate-spec` → `/implement` → `/validate` (lint+tests only; skip Phase-2 agent gates per `WF_TIER_AGENT_SKIP`) → `/ship`. Skip `/validate-impl` Odium audit. Typically skip `/grill`. |
| `medium` | 4–7         | 10            | 30            | (`/grill` optional) → `/explore` → `/propose` (spec.md + tasks/, skip design.md + test-strategy.md) → skip `/validate-spec` → full per-task gates → `/validate-impl` runs. |
| `large`  | 7–12 typical | unbounded    | unbounded     | (`/grill` optional) → full unchanged flow. |

Defaults live in `.workflow.yml` under `tiers:`. Per-spec override via `tier_ceiling:` in `specs/<feature>/config.yml`.

**Hard rules force ≥`medium`:** auth, crypto, secrets, DB migrations, public API contract changes, cross-service interactions. Encoded in inferencer rubric.

**Tier breach:** `/implement` step 0 runs `scripts/tier-check.sh <feature>`. Exit 9 → user picks `Continue` (acknowledge, proceed) or `Abort` (run `/promote-tier <feature>` — re-runs propose at next tier, preserves implemented tasks).

Loader exports: `WF_SPEC_TIER`, `WF_TIER_TASK_CEILING`, `WF_TIER_FILE_CEILING`, `WF_TIER_AGENT_SKIP` (see `scripts/config-loader.contract.md`).

Monitor events: `tier_inferred`, `tier_approved`, `tier_breach`, `tier_promoted`, `validate_impl_skipped`.

## Technical Track (feature | technical)

`track` is a per-spec axis **orthogonal to tier**, for work that is neither a
business feature nor a bug: refactors, module decoupling, tracing/observability,
deployment changes, dependency upgrades, tech-debt. It reuses the entire
tier/task/TDD/validate/validate-impl pipeline — only the *input artifacts*
change. It is not a separate command or storage namespace.

| Track | `/propose` artifacts | Rationale source | `/grill` |
|-------|----------------------|------------------|----------|
| `feature` (default) | spec.md/design.md/test-strategy.md per tier + tasks/ | spec.md / design.md | optional |
| `technical` | **tasks/ only at every tier** (no spec.md/design.md/test-strategy.md) | `docs/adr/` + `CONTEXT.md` | optional `small`; **mandatory `medium`/`large`** |

- Inferred by `engineering-config-inferencer` at `/explore` step 0 (Track
  Inference Rubric), user-approved; `/explore --technical` forces it. Written to
  `specs/<feature>/config.yml` as `track:`. Absent → `feature`.
- `/propose` technical mode: only the Senior Project Manager spawns (no
  Security/Architect/Test-Strategist agents). PM reads `docs/adr/`+`CONTEXT.md`
  in place of spec.md/design.md and emits a per-task `technical_acceptance`
  list (refactor tasks lead with a characterization assertion). **Grill gate:**
  `medium`/`large` technical specs hard-refuse `/propose` if `docs/adr/` is
  empty — run `/grill` first; `small` is exempt (not ADR-worthy).
- `/implement` prepends `technical_acceptance` to the TDD behavior backlog as
  acceptance criteria; characterization items get a behavior-preserving test
  written GREEN before the change and kept GREEN throughout. `afk` pre-approval
  on the technical track = `technical_acceptance` + `docs/adr/`.
- `/validate-impl` Step 3a emits an **advisory** finding when a done task has
  `technical_acceptance` items but no `tdd_red`/`tdd_green` evidence (does not
  force `reopen`).
- `task-manager.sh` validates optional `technical_acceptance` (YAML array;
  absent on feature track). Loader exports `WF_SPEC_TRACK` (see
  `scripts/config-loader.contract.md`).

## Multi-Repo Specs (Vault Mode)

**Vault mode is the going-forward path** (all specs live in the master-brain vault). `.workflow.yml spec_storage_mode: vault` makes the vault `.workflow.yml` a **thin pointer**: it owns workflow settings + `general_kb_path` only — **no `gate_pool`, no `knowledge-base/` in the vault**. Each target code repo owns its own `knowledge-base/` + `gates.yml`, created once by `/bootstrap` repo-gate-init inside that repo (vault itself: `/bootstrap` vault-init, once). There is **no "primary repo for config"** — `role: primary` only selects default git/PR context.

`spec_storage` uses a `{project}` token (e.g. `projects/{project}/specs`) → specs at `<vault>/projects/<proj>/specs/<feature>/`. Project segment comes from `--project` (first `/explore`) or per-spec `config.yml project:`; loader exports `WF_SPEC_PROJECT`, exit 4 on mismatch/unresolved. Per-spec `config.yml repos[]` maps `name → path → role`; loader exports `WF_REPO_NAMES`/`WF_REPO_PATHS` (empty `WF_GATE_POOL`/`WF_PROJECT_KB`); helpers `wf_repo_path`/`wf_for_each_repo`. Spec `gates:` validated against the **union** of bound repos' `gates.yml` (exit 4 unknown id). Gate/KB commands pass `--require-spec` (no-spec under vault → exit 4). Exit 7 on bad repo path.

Per-task `repo:` required when `repos[]` has 2+ entries; optional for a single-repo spec. `task-manager.sh validate` enforces membership. Hard rule: one task = one repo. Ground-rule prefix `repo:<name>:` resolves to that repo's `knowledge-base/`; single-repo spec resolves bare `project:`/unprefixed to the sole repo. `multi-repo-resolution.md` also exports `WF_TASK_GATE_POOL` (bound repo's `gates.yml`) consumed by `gate-ceiling.sh`/`validate-impl.sh`.

`/implement`, `/validate`, `/ship`, `/pr-review`, `/fix`, `/quick-ship` resolve `WF_TASK_REPO_PATH` per `scripts/multi-repo-resolution.md` and run git/gates/PR creation against that path. `/validate-impl` emits per-repo diff sections for Odium. Gates may declare `applies_to_repos: [<name>,…]` to scope.

Monitor events: `repo_bound`, `repo_missing`, `gate_repo_switch`.

## Bug-Fix Flow (/fix)

Standalone command for production bugs/regressions. Skips `/explore` and `/propose` entirely. Artifact: `specs/fixes/<slug>/fix.md` (frontmatter `type: fix`, sections: Repro, Root Cause, Fix Plan, Regression Test).

Flow: `/fix <slug>` → BDD repro → spawn `ultrathink-debugger` for root cause → write `fix.md` → capture pre-fix test failure → apply fix → regression test must pass → lint + ground-rule-matched gates (skip Phase-2 agent gates by default unless diff touches auth/crypto/migrations) → `/ship` (PR title prefix `fix:`).

No `design.md`, no `test-strategy`, no `/validate-spec`, no `/validate-impl`, no tier system. Use `task-manager.sh init-fix <slug>` to scaffold the artifact.

Monitor events: `fix_started`, `fix_root_cause`, `fix_shipped`.

## Domain Docs (`CONTEXT.md` / `docs/adr/`)

`/grill` is an **optional pre-`/explore` step** (skill vendored at
`skills/grill-with-docs/`, installed by `setup.sh`). It runs a relentless
one-question-at-a-time domain interview that sharpens terminology into a
repo-root `CONTEXT.md` glossary (or per-context files via `CONTEXT-MAP.md`) and
records durable decisions as `docs/adr/NNNN-*.md`. It writes no spec artifacts.

**ADR-home split:** `docs/adr/` = durable, cross-spec, repo-level
domain/architecture decisions. `specs/<feature>/design.md
## Architecture Decision Records` = spec-scoped decisions for one feature.
`/propose` (and its Software Architect agent) reads `docs/adr/` + `CONTEXT.md`,
references existing ADRs by id instead of duplicating them, and uses canonical
glossary terms. `/explore` reads both as inputs. `/validate-spec` treats
`docs/adr/` as authoritative — a `design.md` ADR that references an existing
`docs/adr/` entry by id is correct, not a gap; `CONTEXT.md` terms count as
defined for the ambiguity check.

## Key Design Decisions

- `/ship` is separate from `/implement` — commit/push/PR creation happens after validation
- `/implement` checks for unmerged PRs — previous task's PR must be merged before starting next
- Gates listed in `knowledge-base/gates.yml` with `blocking: true` are mandatory for tasks whose `ground_rules` match — skipping is not allowed
- `/validate` Phase 2 spawns specialized agents in parallel (security, code-quality, architecture, compliance) instead of inline LLM analysis
- Agent findings are advisory (`source: llm`), tool findings are high-confidence (`source: tool`); both go through `/review-findings`
- `/propose` spawns `Software Architect` agent during design.md generation for trade-off analysis and ADR production; main command still owns spec.md and task decomposition
- `/grill` (optional, before `/explore`) sharpens the domain model into `CONTEXT.md` + repo-level `docs/adr/` before requirements work — see "Domain Docs" above
- Senior Project Manager decomposition uses a **tracer-bullet lens**: each task is the thinnest slice that still ships end-to-end demoable behavior (balanced against the grouping bias, not a contradiction). Every task carries an `interaction: hitl|afk` frontmatter field — `hitl` needs a human-in-the-loop decision, `afk` is autonomously implementable+mergeable (prefer `afk`). `task-manager.sh` validates the value; absent → defaults to `afk` (backward compatible). Surfaced as a badge in the workflow web dashboard.
- `to-issues` (external tracer-bullet skill) is intentionally **not** wired as a tracker command: redundant with the Senior PM task decomposition and incompatible with the file-based, no-tracker, PR-first flow. Its genuinely-new ideas (tracer-bullet thin-slice lens + HITL/AFK classification) were harvested into the `project-manager-senior` agent + the `interaction` task field instead.
- `/implement` is **test-driven** (governed by the `tdd` skill at `~/.claude/skills/tdd/SKILL.md`): steps 9–11 are pre-loop backlog settle (Test Strategist refinement moved *before* code; HITL interface/priority approval only for `interaction: hitl` tasks — `afk` treats spec.md BDD + test-strategy.md as pre-approval) → red-green-refactor loop (one failing test → minimal code → repeat, vertical slices; horizontal "all tests then all code" prohibited) → post-loop refactor. Per-cycle `tdd_red`/`tdd_green` monitor events. Applies to **all tiers, no exemption**. `/validate-impl` Step 3a appends per-task TDD evidence; tasks lacking a red→green pair get an **advisory** finding (does not by itself force `reopen`)
- `/implement` auto-spawns `Ultrathink Debugger` on errors/test failures (inside the GREEN phase) for root cause analysis; spawns `Code Quality Pragmatist` post-implementation for pre-validation sanity check (high/critical issues go through human accept/reject)
- Monitor events: `tdd_red`, `tdd_green` (one pair per behavior cycle in `/implement`)
- `/pr-review` spawns `Code Reviewer` agent to proactively analyze PR diff before handling human comments; agent findings go through accept/reject flow
- `/review-findings` groups related findings (same file + overlapping/nearby lines, or same file + same category) into review units for single accept/reject decisions — reduces redundant decisions across gates
- `/review-findings` cards render `rationale`, `impact`, `references`, and (for LLM findings) `confidence` alongside `description` / `code_snippet` / `fix_proposal` so users can decide without follow-up prompts. Per-group `Elaborate` option spawns a sub-agent that reads the cited files and returns deeper analysis on demand (single-use per group to bound the flow)
- Accepted finding groups spawn background sub-agents for parallel fix application; file-level mutual exclusion prevents concurrent edits to the same file
- Rejected findings can become new project knowledge-base rules (feedback loop) — never modify the general KB
- `/learn-from-reports` runs after `/review-findings` (or after `/validate` zero-findings) and mines reports for cross-finding patterns — recurring categories, clustered LLM findings, rejection reasoning, generalizable accepted fixes — proposing new project-KB rules in a single batched review. Report deletion is centralized in this command so both paths converge through mining before `/ship`. Complements inline rule creation in `/review-findings` (which catches one-off rules) by catching patterns that span findings.
- **PR-first review loop**: `/implement` opens a **draft PR** immediately after marking the task `implemented` so the user can review the diff on GitHub before validation. `/pr-review` reads PR comments, LLM-classifies each as `question | task | nit | already-addressed`, posts threaded replies prefixed `[claude]` (questions get answers grounded in code; tasks get applied + replied with the resulting short-sha + what/how), and marks each addressed comment with an `eyes` reaction by the current `gh` user. The reaction is the idempotency token — re-running `/pr-review` only processes comments without a Claude-authored `eyes` reaction. `/ship` then marks the existing draft PR ready-for-review via `gh pr ready` instead of creating a new PR.
- PreToolUse hook blocks `--no-verify` and `--no-gpg-sign` — enforces fixing failing hooks rather than bypassing them
- Stop hook blocks dismissive language ("pre-existing", "not our code") and bypass language ("temporarily disable", "skip the hook") — forces unconditional issue resolution
- Triple-gate rule: ALL validation gates must report `status: pass` before a task can move to `done`. Errored gates must be re-run — no shipping with incomplete validation
- `/continue-task` detects resume phase by checking task status and existing artifacts (reports, branches, PR state)
- `/research` activates anti-hallucination mode with citation discipline — useful for bug investigation and API contract review
- `/validate-spec` is a pre-implementation spec-coherence gate wrapping the `Spec Reviewer` agent — audits `specs/<feature>/` for contract gaps, logic gaps, missing pieces, and repo misalignment before `/implement` is allowed to start. The user runs it explicitly after `/propose`. Findings flow through `/review-findings` and patch the spec/design/tasks files (not code). Distinct from `/validate-impl` (post-implementation Odium audit of claimed-vs-actual completion, per configurable-workflow ADR-008).
- All interactive user prompts in workflow commands MUST use the `AskUserQuestion` tool (per `scripts/ask-user-protocol.md`). Plain markdown question lists / `[A][B][C]` text menus / "type your answer below" prose are not allowed.
- Flow changes (command chain, task state machine, validation gates, agent spawns, hooks, artifact flow) MUST trigger review of `docs/workflow-diagram.md` — update affected Mermaid diagrams in the same change. Minor wording tweaks exempt; any structural/edge/node change is not.
