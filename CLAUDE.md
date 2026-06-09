# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Status — LIVE, slated for deprecation

This repo is the **currently-running** bash/markdown spec-driven workflow. It is
actively used and maintained for now. It will be **deprecated** once its
successor — the Rust binary `flowctl` + per-target adapters in the parent
**Bondsmith** project (`future-proof-oss/`, see that repo's `CLAUDE.md` and
`docs/src/adr/`) — reaches parity. ADR-0006 (parent) treats this repo as the
behaviour checklist the rewrite must match.

Implications while it is still live:
- Bug fixes and small improvements here are fine.
- Architectural friction found here (config-resolution god script, duplicated
  repo-root/yq/escape helpers, scanner clones, command-prose duplication) is
  also the **salvage checklist** for the Rust rewrite — name it, don't let it
  silently reappear in `flowctl`.
- Do not start large new feature surfaces here; build those in the successor.

## What This Repo Is

A file-based, spec-driven development workflow for Claude Code. Slash commands, scripts, agents, hooks, and templates get installed globally to `~/.claude/` via `setup.sh`. Target projects get a `.workflow.yml` (with an inline `gate_pool:`) and `specs/` via `/bootstrap`. One external dependency: `yq` for YAML parsing.

**This repo is not a typical codebase** — it's markdown command definitions, shell scripts, and a Rust web dashboard. No application code lives here.

## Project Structure

- `commands/*.md` — Slash command definitions (bootstrap, config, explore, propose, implement, validate, validate-impl, review-findings, learn-from-reports, ship, quick-ship, pr-review, fix, spec-status, workflow-summary, continue-task, research, promote-tier, capture-rule)
- `skills/` — Reusable skill prompts (e.g. `bash-scripting/SKILL.md`). Installed to `~/.claude/skills/` by `setup.sh`.
- `tests/` — Bash test suite for scripts (task-manager, config-loader, monitor, validate-impl, tier-check, etc.). Run individual tests directly: `bash tests/test-task-manager.sh`.
- `scripts/knowledge-base-rules.md` — Shared KB prerequisites and single-KB resolution rules (bare `$WF_GENERAL_KB`-relative paths; legacy prefixes stripped + deprecation-warned). Installed globally to `~/.claude/scripts/` by `setup.sh`. Referenced by all workflow commands instead of duplicating KB instructions inline.
- `scripts/task-manager.sh` — Task state machine (validate, set-status, unblock, next, create-followup, check-unvalidated, status). Requires `yq`. `create-followup <feature> <fr-id> <description>` auto-generates a `status: todo` task from a `/validate-impl` spec-audit accepted finding; FR id is validated against `spec.md` (fail-closed on unknown ids) and ground_rules are inherited from the spec's `## Applicable Ground Rules` section.
- `scripts/pre-commit-hook.sh` — Commit-time task validation
- `scripts/monitor.sh` — Event logger for spec implementation monitoring; appends JSONL events to `specs/<feature>/.monitor.jsonl`
- `hooks/` — Claude Code hook scripts for enforcement and monitoring (block-git-hook-bypass, monitor-tool-calls). Installed to `~/.claude/hooks/` by `setup.sh`.
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

## Single Knowledge Base (ADR-0002)

One knowledge base. The dual (Project KB + General KB) layer was collapsed —
see `docs/adr/0002-collapse-to-single-knowledge-base.md`.

- **General KB** — lives at the path configured by `general_kb_path` in each repo's `.workflow.yml`, exported as `$WF_GENERAL_KB` by `scripts/config-loader.sh`. Recommended location: a master-brain / Obsidian vault (e.g. `~/Desktop/projects/master-brain/general-knowledge-base/`). Contains all KB rules: security, architecture, testing, style, plus learned language/convention rules. Key is **required** — loader exits 2 if missing.

The feedback loop (`/review-findings`, `/learn-from-reports`, `/capture-rule`)
writes learned rules **to the general KB**. There is no per-repo `knowledge-base/`
directory and no project-KB override layer.

Task `ground_rules` are **bare `$WF_GENERAL_KB`-relative paths** (e.g.
`security/general.md`). Legacy `general:`/`project:`/`repo:<name>:` prefixes are
stripped by a migration shim in `resolve_ground_rule_path` (one-time
per-process deprecation warning) and resolved under `$WF_GENERAL_KB`. Missing
`$WF_GENERAL_KB` → exit 7.

## Configurable Workflow

The configurable-workflow feature externalizes gate and agent selection into YAML config. Three files form the config layer:

- **`.workflow.yml`** (repo root in repo mode; vault root in vault mode) — `spec_storage`, inline `gate_pool:` array, `agent_pool`, `validate_scope`. In vault mode it is a **thin pointer**: no `gate_pool` (absent/ignored — gates resolve per-task from each bound repo's own `.workflow.yml gate_pool`), plus `spec_storage_mode: vault` + `default_repos:`. A bound code repo gets a thin `.workflow.yml` (`kind: repo-gate-pool`, only `gate_pool:`). Required for any active invocation. Missing → loader exit 2; run `/bootstrap`.
- **`.workflow.yml gate_pool:`** (inline gate registry) — array of deterministic gates with `id`, `command`, `applies_to`, `category`, `blocking`. Sole source of truth for executable gates; no standalone `gates.yml`.
- **`specs/<feature>/config.yml`** (per-spec config) — `tags`, `gates` (the **ceiling**), and `agents` per phase. Written by `/explore` step 0 after inferencer approval. Required on all active processing paths; missing → exit 4.

**Key terms.** Canonical definitions of **ceiling**, **effective-set**, **spec-union** live in `scripts/workflow-glossary.md` (installed to `~/.claude/scripts/workflow-glossary.md`). Commands link there. One additional cadence term defined here:

- **`validate_scope`** — cadence control: `per-task` (default), `per-spec` (skip per-task validate; spec-union runs at `/validate-impl`), or `both`.
- **`coverage_audit`** — per-spec toggle (`true` default | `false`) in `config.yml`. Drives `/validate` **Phase 3** (per-task Odium coverage audit of the task's own acceptance criteria). `false` = escape hatch to skip for this spec. Also skipped independently on `small` tier and under `validate_scope: per-spec`. Loader exports `WF_COVERAGE_AUDIT` (see `scripts/config-loader.contract.md`).

**Config loader (`scripts/config-loader.sh`):**
- Walks up from CWD to find `.workflow.yml`; single `timeout 5 yq` parse
- Leaf module — sources nothing from workflow scripts (no circular dep)
- **Canonical contract (exported env vars + exit codes): `scripts/config-loader.contract.md`.** All commands link there instead of inlining partial lists.

**`/explore` step 0:** Before normal explore flow, spawns `config-inferencer` agent, shows one-screen summary, accepts single-key approval or `/config` override, writes `config.yml`, emits `config_inferred` + `config_approved` monitor events.

**`/validate` ceiling semantics:** Executes intersection of spec-eligible gates ∩ gates applicable to task `ground_rules`. Skipped gates emit `gate_skip` events.

**`/validate` Phase 3 (per-task coverage audit):** After Phase-2 agent gates, reuses **Odium** (`agents/odium.md`, not edited) to verify the task diff covers the task's own acceptance criteria (`## Acceptance` + `## Implements` FR refs on feature track; `technical_acceptance:` on technical track). Advisory — gaps become `source: llm` findings in `reports/<task-id>-coverage.yaml` flowing through the normal `/review-findings` pipeline; no new hard-block. Skipped (first match) when: `WF_SPEC_TIER == small` (`tier_small`), `WF_COVERAGE_AUDIT == false` (`config_off`), `Skip advisory agents` chosen (`user_skipped`), `WF_VALIDATE_SCOPE == per-spec` (`scope=per-spec`). Emits `coverage_audit_start`, `coverage_audit_done` monitor events; skips emit `gate_skip` (`gate: coverage`).

**`/validate-impl`:** Runs once when all spec tasks reach `done`. Spawns Odium with spec FR list, prd.md scope, task list, and git diff range. Verdict `complete` → spec shipped; verdict `reopen` → `/review-findings` spawns follow-up tasks.

See `specs/configurable-workflow/design.md` for full ADR detail and schema definitions.

## Tier System (small | medium | large)

Specs are tiered to right-size flow ceremony. Tier is inferred at `/explore` step 0 by `engineering-config-inferencer` and approved by the user; written to `specs/<feature>/config.yml` as `tier:`.

| Tier | Target tasks | Ceiling tasks | Ceiling files | Flow shape |
|------|--------------|---------------|---------------|------------|
| `small`  | 2–4         | 5             | 10            | `/explore` (incl. Step −1 grill pass) → `/propose` (tasks/ only — skip spec.md, design.md, test-strategy.md) → `/implement` → `/validate` (lint+tests only; skip Phase-2 agent gates per `WF_TIER_AGENT_SKIP`) → `/ship`. Skip `/validate-impl` Odium audit. |
| `medium` | 4–7         | 10            | 30            | `/explore` (incl. Step −1 grill pass) → `/propose` (spec.md + tasks/, skip design.md + test-strategy.md) → full per-task gates → `/validate-impl` runs. |
| `large`  | 7–12 typical | unbounded    | unbounded     | `/explore` (incl. Step −1 grill pass) → full unchanged flow. |

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

| Track | `/propose` artifacts | Rationale source | Grill pass (in `/explore` Step −1) |
|-------|----------------------|------------------|----------|
| `feature` (default) | spec.md/design.md/test-strategy.md per tier + tasks/ | spec.md / design.md | runs; ADRs optional |
| `technical` | **tasks/ only at every tier** (no spec.md/design.md/test-strategy.md) | `docs/adr/` + `CONTEXT.md` | runs; ≥1 ADR **mandatory** for `medium`/`large` (enforced by `/propose` hard-refuse) |

- Inferred by `engineering-config-inferencer` at `/explore` step 0 (Track
  Inference Rubric), user-approved; `/explore --technical` forces it. Written to
  `specs/<feature>/config.yml` as `track:`. Absent → `feature`.
- `/propose` technical mode: only the Senior Project Manager spawns (no
  Security/Architect/Test-Strategist agents). PM reads `docs/adr/`+`CONTEXT.md`
  in place of spec.md/design.md and emits a per-task `technical_acceptance`
  list (refactor tasks lead with a characterization assertion). **Grill gate:**
  `medium`/`large` technical specs hard-refuse `/propose` if `docs/adr/` is
  empty — re-run `/explore` (its Step −1 grill pass produces ADRs); `small`
  is exempt (not ADR-worthy).
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

## Branch Strategy (per-task | single-branch)

`branch_strategy` is a per-spec axis **orthogonal to tier/track**, in
`specs/<feature>/config.yml` (sibling of `tier`/`track`/`validate_scope`).
Inferred at `/explore` step 0, user-approved. Absent → `per-task`.

| Strategy | Branch model | Per-task PR | PR base |
|----------|--------------|-------------|---------|
| `per-task` (default) | `feat/$FEATURE` integration branch + `feat/$FEATURE/{task}` sub-branch per task | one draft PR per task | `feat/$FEATURE` |
| `single-branch` | one `feat/$FEATURE` off `main`; no sub-branch; commits accumulate | none — review deferred | `main` |

- `per-task` = exactly today's behavior; fully backward compatible.
- `single-branch` = one branch for tightly-coupled refactors/spikes where
  per-task PR overhead is unwanted. No per-task draft PR; one spec PR
  opened/readied at the **final** `/ship` (last task), base `main`. TDD
  red/green/refactor commits preserved on the shared branch (no squash).
- Serial gate on `single-branch`: `/implement` preflight is "immediately-preceding
  task status == done" (not "previous PR merged").
- `task_base_sha` (git rev-parse HEAD at task start, written to task frontmatter
  via `task-manager.sh set-base-sha`) is the linchpin for `single-branch`
  start-vs-mid detection (`/continue-task`) and quality/test-strategist diff
  ranges (`${task_base_sha}..HEAD`).
- `/pr-review` mid-spec on `single-branch` is a clean dead-end: with no PR open
  yet it just reports "No PR found for this branch" (review is deferred to the
  spec PR opened at the final `/ship`).
- Multi-repo: one `feat/$FEATURE` per bound repo, no sub-branches; the spec PR
  fans out per bound repo at the last task.
- Loader exports `WF_BRANCH_STRATEGY` (see `scripts/config-loader.contract.md`);
  included in the config snapshot so `/ship` drift check catches a mid-spec flip.
- See `docs/adr/0003-branch-strategy.md`.

## Multi-Repo Specs (Vault Mode)

**Vault mode is the going-forward path** (all specs live in the master-brain vault). `.workflow.yml spec_storage_mode: vault` makes the vault `.workflow.yml` a **thin pointer**: it owns workflow settings + `general_kb_path` only — **no `gate_pool` in the vault** (except the self-hosting exception: a `repos[]` entry pointing at the vault dir itself). Each target code repo owns a thin `.workflow.yml` (`kind: repo-gate-pool`, only an inline `gate_pool:`), created once by `/bootstrap` repo-gate-init inside that repo (vault itself: `/bootstrap` vault-init, once). There is **no "primary repo for config"** — `role: primary` only selects default git/PR context.

`spec_storage` uses a `{project}` token (e.g. `projects/{project}/specs`) → specs at `<vault>/projects/<proj>/specs/<feature>/`. Project segment comes from `--project` (first `/explore`) or per-spec `config.yml project:`; loader exports `WF_SPEC_PROJECT`, exit 4 on mismatch/unresolved. Per-spec `config.yml repos[]` maps `name → path → role`; loader exports `WF_REPO_NAMES`/`WF_REPO_PATHS` (empty `WF_GATE_POOL`); helpers `wf_repo_path`/`wf_for_each_repo`. Spec `gates:` validated against the **union** of bound repos' `.workflow.yml gate_pool` (exit 4 unknown id). Gate/KB commands pass `--require-spec` (no-spec under vault → exit 4). Exit 7 on bad repo path.

Per-task `repo:` required when `repos[]` has 2+ entries; optional for a single-repo spec. `task-manager.sh validate` enforces membership. Hard rule: one task = one repo. `ground_rules` are bare `$WF_GENERAL_KB`-relative paths (legacy prefixes stripped + deprecation-warned). `multi-repo-resolution.md` also exports `WF_TASK_GATE_POOL` (bound repo's `.workflow.yml`) consumed by `gate-ceiling.sh`/`validate-impl.sh`.

`/implement`, `/validate`, `/ship`, `/fix`, `/quick-ship` resolve `WF_TASK_REPO_PATH` per `scripts/multi-repo-resolution.md` and run git/gates/PR creation against that path. (`/pr-review` is the exception — it carries no multi-repo resolution and operates on the current branch's PR via `gh` in the working directory.) `/validate-impl` emits per-repo diff sections for Odium. Gates may declare `applies_to_repos: [<name>,…]` to scope.

Monitor events: `repo_bound`, `repo_missing`, `gate_repo_switch`.

## Bug-Fix Flow (/fix)

Standalone command for production bugs/regressions. Skips `/explore` and `/propose` entirely. Artifact: `specs/fixes/<slug>/fix.md` (frontmatter `type: fix`, sections: Repro, Root Cause, Fix Plan, Regression Test).

Flow: `/fix <slug>` → BDD repro → spawn `ultrathink-debugger` for root cause → write `fix.md` → **test-driven via the `tdd` skill** (RED: pre-fix test must fail → GREEN: minimal fix, regression test must pass → refactor) → lint + ground-rule-matched gates (skip Phase-2 agent gates by default unless diff touches auth/crypto/migrations) → `/ship` (PR title prefix `fix:`). Steps 4–5 follow the `tdd` skill (`~/.claude/skills/tdd/SKILL.md`) by path-pointer, same mechanism as `/implement`; a bug is single-behavior so the regression test is the tracer bullet — no multi-behavior backlog or planning gate.

No `design.md`, no `test-strategy`, no `/validate-impl`, no tier system. Use `task-manager.sh init-fix <slug>` to scaffold the artifact.

Monitor events: `fix_started`, `fix_root_cause`, `tdd_red`, `tdd_green`, `fix_shipped`.

## Domain Docs (`CONTEXT.md` / `docs/adr/`)

The grill pass is **Step −1 of `/explore`** and runs unconditionally for
every spec. It invokes the canonical `grill-with-docs` skill (vendored at
`skills/grill-with-docs/`, installed to `~/.claude/skills/` by `setup.sh`),
which runs a relentless one-question-at-a-time domain interview that
sharpens terminology into a repo-root `CONTEXT.md` glossary (or per-context
files via `CONTEXT-MAP.md`) and records durable decisions as
`docs/adr/NNNN-*.md`. It writes no spec artifacts. There is no separate
`/grill` command — substance lives in the skill, workflow coupling lives
in `commands/explore.md` Step −1. Emits monitor event `grill_completed`.

**ADR-home split:** `docs/adr/` = durable, cross-spec, repo-level
domain/architecture decisions. `specs/<feature>/design.md
## Architecture Decision Records` = spec-scoped decisions for one feature.
`/propose` (and its Software Architect agent) reads `docs/adr/` + `CONTEXT.md`,
references existing ADRs by id instead of duplicating them, and uses canonical
glossary terms. `/explore` reads both as inputs. `/propose` treats
`docs/adr/` as authoritative — a `design.md` ADR that references an existing
`docs/adr/` entry by id is correct, not a gap; `CONTEXT.md` terms count as
defined.

## Key Design Decisions

- `/ship` is separate from `/implement` — commit/push/PR creation happens after validation
- `/implement` checks for unmerged PRs — previous task's PR must be merged before starting next
- Gates listed in `.workflow.yml gate_pool` with `blocking: true` are mandatory for tasks whose `ground_rules` match — skipping is not allowed
- **Gate trust boundary**: a `gate_pool` entry's `command` is executed verbatim (`bash -c`) by every gate runner (`/validate`, `/validate-impl`, `gate-ceiling`). Gate commands are therefore **trusted code**. In vault/multi-repo mode the active pool is the bound repo's own `.workflow.yml` (`WF_TASK_GATE_POOL`) — only ever bind/run the workflow against repos you trust. Running it against an untrusted bound repo grants that repo arbitrary local code execution. There is no command sandbox by design.
- `/validate` Phase 2 spawns specialized agents in parallel (security, code-quality, architecture, compliance) instead of inline LLM analysis
- `/validate` Phase 3 runs a per-task **coverage audit** (reuses Odium) — advisory finding when the diff misses the task's own acceptance criteria; gated by `coverage_audit`/tier/scope/user-skip (see "Configurable Workflow"). Report `reports/<task-id>-coverage.yaml` is just another gate report
- Agent findings are advisory (`source: llm`), tool findings are high-confidence (`source: tool`); both go through `/review-findings`
- `/propose` spawns `Software Architect` agent during design.md generation for trade-off analysis and ADR production; main command still owns spec.md and task decomposition
- `/propose` ends with a `Spec Reviewer` subagent (`engineering-spec-reviewer`) consistency pass on every tier and track — audits doc↔doc consistency, FR→task traceability, task-graph sanity, and repo alignment; writes `specs/<feature>/reports/spec-consistency.yaml`. Findings hard-block `/propose` from returning success; resolved via `/review-findings`. `/propose` does NOT re-run the subagent after review — once findings are resolved the user runs `/implement` directly. `setup.sh` prunes orphan global files (per-file `yes` confirmation; `--no-prune` to skip) so removed agents/commands don't linger in `~/.claude/`.
- `/explore` Step −1 grill pass (runs unconditionally; invokes the canonical `grill-with-docs` skill) sharpens the domain model into `CONTEXT.md` + repo-level `docs/adr/` before requirements work — see "Domain Docs" above
- Senior Project Manager decomposition uses a **tracer-bullet lens**: each task is the thinnest slice that still ships end-to-end demoable behavior (balanced against the grouping bias, not a contradiction). Every task carries an `interaction: hitl|afk` frontmatter field — `hitl` needs a human-in-the-loop decision, `afk` is autonomously implementable+mergeable (prefer `afk`). `task-manager.sh` validates the value; absent → defaults to `afk` (backward compatible). Surfaced as a badge in the workflow web dashboard.
- `to-issues` (external tracer-bullet skill) is intentionally **not** wired as a tracker command: redundant with the Senior PM task decomposition and incompatible with the file-based, no-tracker, PR-first flow. Its genuinely-new ideas (tracer-bullet thin-slice lens + HITL/AFK classification) were harvested into the `project-manager-senior` agent + the `interaction` task field instead.
- `/implement` is **test-driven** (governed by the `tdd` skill at `~/.claude/skills/tdd/SKILL.md`): steps 9–11 are pre-loop backlog settle (Test Strategist refinement moved *before* code; HITL interface/priority approval only for `interaction: hitl` tasks — `afk` treats spec.md BDD + test-strategy.md as pre-approval) → red-green-refactor loop (one failing test → minimal code → repeat, vertical slices; horizontal "all tests then all code" prohibited) → post-loop refactor. Per-cycle `tdd_red`/`tdd_green` monitor events (inline/`generalist` path only — skipped on the delegated path). Applies to **all tiers, no exemption**. `/validate-impl` Step 3a appends per-task TDD evidence; tasks lacking a red→green pair get an **advisory** finding (does not by itself force `reopen`)
- **Per-task implementer delegation (ADR-0004)**: after step 9 settles the backlog, `/implement` branches on the task's `implementer:` frontmatter field. `generalist` or absent → the main session runs the red-green-refactor loop inline (today's exact behavior). A resolvable agent-pool id (e.g. `engineering/frontend-developer`, `engineering/backend-architect`) → a specialist subagent owns the whole TDD loop in its own context (method injected by `/implement`: a pointer to the `tdd` skill + settled backlog + scope + ground_rule/design **paths**), edits `WF_TASK_REPO_PATH`, debugs inline, and returns `complete` (→ step 12 writes its `impl_notes`) or `blocked` (→ main surfaces the diagnosis and pauses). Set by the Senior Project Manager at `/propose`; validated by `task-manager.sh` (`generalist` or resolvable id; unresolvable → fail-closed; absent → legacy grace). Keeps main context flat regardless of task size.
- `/implement` auto-spawns `Ultrathink Debugger` on errors/test failures (inside the GREEN phase) for root cause analysis — **inline/`generalist` path only** (delegated specialists debug within their own loop, no sub-sub-agent); spawns `Code Quality Pragmatist` post-implementation for pre-validation sanity check on the diff (both paths; high/critical issues go through human accept/reject)
- Monitor events: `tdd_red`, `tdd_green` (one pair per behavior cycle in `/implement` — inline path only; absent on the delegated path)
- `/review-findings` groups related findings (same file + overlapping/nearby lines, or same file + same category) into review units for single accept/reject decisions — reduces redundant decisions across gates
- `/review-findings` cards render `rationale`, `impact`, `references`, and (for LLM findings) `confidence` alongside `description` / `code_snippet` / `fix_proposal` so users can decide without follow-up prompts. Per-group `Elaborate` option spawns a sub-agent that reads the cited files and returns deeper analysis on demand (single-use per group to bound the flow)
- Accepted finding groups spawn background sub-agents for parallel fix application; file-level mutual exclusion prevents concurrent edits to the same file
- Rejected findings can become new general knowledge-base rules (feedback loop writes to `$WF_GENERAL_KB`)
- `/learn-from-reports` runs after `/review-findings` (or after `/validate` zero-findings) and mines reports for cross-finding patterns — recurring categories, clustered LLM findings, rejection reasoning, generalizable accepted fixes — proposing new general-KB rules in a single batched review. Reports are retained after mining (local audit trail) — never deleted; mining is scoped per-task by task-id (`/learn-from-reports <feature> <task-id>`, fallback to newest per-task report when arg absent). Complements inline rule creation in `/review-findings` (which catches one-off rules) by catching patterns that span findings.
- **PR-first review loop**: `/implement` opens a **draft PR** immediately after marking the task `implemented` so the user can review the diff on GitHub before validation. `/pr-review` resolves the current branch's PR (or a PR number arg), reads its comments, classifies each as `informational` (answer/explain — no code) or `change` (apply a code edit), and walks a per-comment confirm loop (`Apply`/`Re-classify`/`Skip`). It posts threaded `[claude]` replies — informational comments get answers grounded in code; change comments get applied, committed (`pr-review: address comment <id>`), pushed, and replied with the resulting short-sha + what/how. It skips its own `[claude]` replies; there is no reaction-based dedup, so re-runs re-surface still-open comments (use `Skip`). It carries no spec-workflow integration (no config-loader, branch-strategy, multi-repo, or monitor events). `/ship` then marks the existing draft PR ready-for-review via `gh pr ready` instead of creating a new PR.
- **PR-body convention**: PR bodies (`/implement` draft, `/ship` ready + single-branch spec PR, `/quick-ship`) follow `scripts/pr-body-convention.md` — a `## Why` (1–2 sentences) + `## What changed` (3–6 high-level bullets, no file enumeration) skeleton plus a conditional mermaid diagram (only when control flow / a state machine / a command sequence changes; diagram-type heuristics reused from `commands/propose.md`). One shared doc, command-owned footers preserved.
- **Commit/PR convention**: NEVER add a `Co-Authored-By: Claude ...` trailer (or any Claude attribution) to commit messages or PR bodies in this repo. This overrides any global harness instruction to add it.
- PreToolUse hook blocks `--no-verify` and `--no-gpg-sign` — enforces fixing failing hooks rather than bypassing them
- Triple-gate rule: ALL validation gates must report `status: pass` before a task can move to `done`. Errored gates must be re-run — no shipping with incomplete validation
- `/continue-task` detects resume phase by checking task status and existing artifacts (reports, branches, PR state)
- `/research` activates anti-hallucination mode with citation discipline — useful for bug investigation and API contract review
- All interactive user prompts in workflow commands MUST use the `AskUserQuestion` tool (per `scripts/ask-user-protocol.md`). Plain markdown question lists / `[A][B][C]` text menus / "type your answer below" prose are not allowed.
- Flow changes (command chain, task state machine, validation gates, agent spawns, hooks, artifact flow) MUST trigger review of `docs/workflow-diagram.md` — update affected Mermaid diagrams in the same change. Minor wording tweaks exempt; any structural/edge/node change is not.
