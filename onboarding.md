# Spec-Driven Dev Workflow: Onboarding Guide

A file-based, spec-driven development workflow for Claude Code that adds validation gates, interactive finding review, and a knowledge-base (single general KB) feedback loop on top of standard AI-assisted coding. One external dependency: `yq` for YAML parsing.

## Prerequisites

Install these before running setup:

| Tool | Install | Purpose |
|------|---------|---------|
| `yq` | `brew install yq` | YAML parsing in task-manager.sh |
| `gh` | `brew install gh` | GitHub CLI for PRs and `/pr-review` |
| `perl` | ships with macOS | macOS fallback for GNU `timeout`/`gtimeout` in `scripts/config-loader.sh::wf__timeout`; not needed on Linux (GNU coreutils `timeout` is preferred there) |
| Claude Code | [claude.ai/claude-code](https://claude.ai/claude-code) | Slash command host |

Language-specific validation tools (linters, test runners, semgrep) are installed later, after `/bootstrap` creates language files for your project.

Verify prerequisites:
```bash
yq --version
gh --version
```

## Installation

Run from the dev-workflow repository root:

```bash
./setup.sh
```

This installs:
- Slash commands to `~/.claude/commands/`:
  `bootstrap`, `explore`, `propose`, `implement`, `validate`, `validate-impl`, `review-findings`, `learn-from-reports`, `ship`, `quick-ship`, `pr-review`, `spec-status`, `workflow-summary`, `continue-task`, `research`, `fix`, `promote-tier`
- 2 scripts to `~/.claude/scripts/`:
  `task-manager.sh` (task state machine), `pre-commit-hook.sh` (commit-time validation)
- 35+ agent definitions to `~/.claude/agents/`

These are global — they work across every project that has been bootstrapped with `/bootstrap`.

Verify:
```bash
ls ~/.claude/commands/*.md
~/.claude/scripts/task-manager.sh help
```

## Per-Project Setup

Do these steps once in each project you want to use the workflow with.

### 1. Bootstrap the workflow config

Open the project in Claude Code and run:
```
/bootstrap
```

This writes `.workflow.yml` with an inline `gate_pool:` array (asks which
languages the project uses to seed the gates). There is no per-repo
`knowledge-base/` directory — all KB rules (security, architecture, testing,
style, plus learned rules) live in the single general KB at `$WF_GENERAL_KB`
(see ADR-0002).

### 2. Add project instructions

Copy `templates/CLAUDE.md` from this repo to your project root. It tells Claude Code about the workflow conventions (task states, rule selection, validation gates).

### 3. Install the pre-commit hook

Add the task validation script to your husky pre-commit hook:

```bash
echo '~/.claude/scripts/pre-commit-hook.sh' >> .husky/pre-commit
```

If `.husky/pre-commit` doesn't exist yet, create it first:
```bash
echo '~/.claude/scripts/pre-commit-hook.sh' > .husky/pre-commit
```

This runs `task-manager.sh validate` on any changed task files at commit time, catching invalid structure or status transitions.

### 4. Install language validation tools

Check the `command` fields in `.workflow.yml gate_pool` for which tools the gates invoke, then install them. Examples:

**Rust:**
```bash
rustup component add clippy
cargo install cargo-tarpaulin cargo-audit cargo-deny
pip install semgrep
```

**TypeScript:**
```bash
npm install -D eslint jest
pip install semgrep
```

### Resulting project structure

```
project-root/
├── CLAUDE.md
├── .workflow.yml                    # config + inline gate_pool: array
├── specs/           (created later by /propose)
└── .git/hooks/pre-commit
```

## Workflow Walkthrough

The workflow has 10 core stages (plus `/spec-status`, `/workflow-summary`, `/continue-task`, `/quick-ship`, and `/research` available anytime). Each stage produces specific artifacts and has a clear next step.

**Tier branching.** After `/explore` step 0 sets `tier:` in `config.yml`, the path forks: `small` skips Phase-2 agent gates and `/validate-impl`; `medium`/`large` run the full flow. See [Tiered specs](#tiered-specs).

**`/fix` bypass.** Bug fixes use `/fix <slug>` and skip `/explore`, `/propose`, `/validate-impl`, and tiering. See [Bug-fix flow (`/fix`)](#bug-fix-flow-fix).

### Stage 0: `/bootstrap` (once per project)

**What it does:** Writes `.workflow.yml` at the repo root — the config layer entry point — with an inline `gate_pool:` array. Asks which languages the project uses to seed the gate pool. All KB rules live in the single general KB at `$WF_GENERAL_KB` (ADR-0002); no per-repo `knowledge-base/`.

**Produces:**
- `.workflow.yml` at repo root (`spec_storage`, inline `gate_pool:`, `agent_pool`, `validate_scope`)

**Idempotent:** On an existing repo with `.workflow.yml` already present, `/bootstrap` prints the current config and exits without modifying it.

**Next:** `/explore`

### Stage 0b: Config layer overview (first-time)

The configurable-workflow feature adds a three-file config layer that controls which gates and agents run per spec. Understanding it once makes everything downstream clear.

| File | Written by | Purpose |
|------|-----------|---------|
| `.workflow.yml` | `/bootstrap` | Repo-wide defaults: `spec_storage`, inline `gate_pool:`, `agent_pool`, `validate_scope` |
| `.workflow.yml gate_pool:` | `/bootstrap` | Inline gate registry: array of `id`, `command`, `applies_to`, `blocking` |
| `specs/<name>/config.yml` | `/explore` step 0 | Per-spec ceiling: which gates + which agents per phase |

**Ceiling semantics:** `config.yml gates:` is the *ceiling* — the eligible gate set. Per task, `/validate` computes `ceiling ∩ gates applicable to task ground_rules` (the *effective set*). Gates outside the ceiling are skipped and emit `gate_skip` events. This means a spec about Rust auth never accidentally runs a Go linter, even if the gate registry has one.

**`validate_scope`:** Controls validation cadence per spec:
- `per-task` (default) — `/validate` runs after every task
- `per-spec` — per-task `/validate` is skipped; one union-gate run happens inside `/validate-impl` when all tasks are done
- `both` — runs both per-task and the final union

Set at repo level in `.workflow.yml`; override per-spec in `config.yml`.

See `CLAUDE.md §Configurable Workflow` and `specs/configurable-workflow/design.md` for full schema and ADR detail.

### Stage 1: `/explore` (requirements)

**What it does:** Two sub-steps run before any conversation:

**Step 0 — Config inferencer (automatic):**
1. Spawns `config-inferencer` agent with repo signal files (`Cargo.toml`, `package.json`, etc.), `.workflow.yml gate_pool`, `agents/` listing, and spec description.
2. Displays a one-screen summary: proposed gates (ceiling) + agents per phase + reasoning.
3. You press a single key to approve, or run `/config <name>` to edit manually.
4. Writes `specs/<name>/config.yml` and emits `config_inferred` + `config_approved` monitor events.
5. If the inferencer times out, falls back to a manual-entry prompt; a default template is used if you skip.

**Step 1+ — Requirements gathering:**
Reads both `_index.md` files, then asks clarifying questions about scope, security, integrations, testing, and performance.

**Produces:**
- `specs/<name>/config.yml` — per-spec ceiling and agent roster
- Shared understanding of what to build
- Optionally `specs/<name>/prd.md`

**Requires:** `.workflow.yml` must exist (run `/bootstrap` first).

**Next:** `/propose <name>`

### Stage 2: `/propose <name>` (spec generation)

**What it does:** Generates the full spec package from the PRD (or conversation context). Reads applicable KB rules from `$WF_GENERAL_KB` and references them throughout.

**Produces:**
- `specs/<name>/spec.md` — functional spec with BDD scenarios (Given/When/Then)
- `specs/<name>/design.md` — architectural decisions with rule references and rationale
- `specs/<name>/tasks/NNN-task-name.md` — task files with `ground_rules`, `test_cases`, `blocked_by`, status (`todo` or `blocked`)
- `specs/<name>/reports/spec-consistency.yaml` — final spec-coherence audit by the `Spec Reviewer` subagent (`engineering-spec-reviewer`). Runs on every tier and track. Findings hard-block `/propose` from returning success; resolved via `/review-findings <name>` (no `/propose` re-run — go straight to `/implement`).

**Requires:** `.workflow.yml` must exist.

**Next:** Spec review (stage 3) — or `/review-findings <name>` first if spec-consistency produced findings.

### Stage 3: Spec review (conversational)

**What it does:** You read the generated spec, design, and tasks. Request changes conversationally — Claude edits the existing files directly. No command to run.

**What to check:**
- Are the right `ground_rules` assigned to each task?
- Are test cases comprehensive?
- Do architectural decisions make sense against the rules?
- Are task boundaries and dependencies correct?
- Is `max_files` reasonable (max 20)?

**Next:** `/implement <name>`

> **Per-task sequence:** Each command is invoked explicitly. After `/implement` finishes, the user runs `/validate`; after `/validate`, the user runs `/review-findings` (if findings) or `/learn-from-reports` (if zero findings); after `/learn-from-reports`, the user runs `/ship`. Every command prints the next command to run when it exits.

### Stage 4: `/implement <name>` (one task at a time)

**What it does:**
1. Checks no task is stuck at `implemented` or `review` (enforces validation-first)
2. Picks the next `todo` task (by file order)
3. Creates the integration branch `feat/<name>` if it's the first task (from `main`)
4. Creates a task branch `feat/<name>/NNN-task-name` (from integration)
5. Reads the task's `ground_rules` + spec + design
6. Implements code and test bodies (human defined test names, AI writes implementations)
7. Sets task status to `implemented`

**Produces:** Code changes on a task branch, task status updated to `implemented`.

**Requires:** `.workflow.yml`, no unvalidated tasks.

**Next:** the user runs `/validate <name>` — do NOT skip this step.

### Stage 5: `/validate <name>` (automated validation)

**What it does:**
1. **Phase 1 — Deterministic tools (hard gates):** Reads `validation_tools` from language file frontmatter, runs every listed tool. Skipping a tool is not allowed. Missing tools are reported as error findings.
2. **Phase 2 — LLM analysis (advisory):** Checks code against `ground_rules` for architecture compliance, DRY violations, test quality, and rule violations tools can't catch. All LLM findings marked `source: llm`.
3. **Phase 3 — Per-task coverage audit (advisory):** Reuses the **Odium** agent to verify the task diff covers the task's own acceptance criteria (`## Acceptance` + `## Implements` FR refs; `technical_acceptance:` on the technical track). Gaps become `source: llm` findings in `reports/<task-id>-coverage.yaml`. Skipped (first match) on `small` tier, `coverage_audit: false`, the `Skip advisory agents` choice, or `validate_scope: per-spec`. Emits `coverage_audit_start` / `coverage_audit_done` (skips emit `gate_skip` with `gate: coverage`).

**Produces:** YAML reports in `specs/<name>/reports/NNN-gate.yaml` for each gate (plus `<task-id>-coverage.yaml` when Phase 3 runs).

**5 gates:**
- **security** — semgrep + language audit tools + `Security Engineer` agent (KB security rules)
- **code-quality** — language lint tools + `code-quality-pragmatist` agent (DRY, function size, modularity)
- **architecture** — `Software Architect` agent (KB architecture rules)
- **compliance** — `claude-md-compliance-checker` agent (CLAUDE.md + general KB conventions)
- **testing** — language test/coverage tools (deterministic only — no agent gate)

**Status update:**
- Findings exist -> task moves to `review`
- Zero findings -> task moves to `done`, blocked tasks are checked and unblocked

**Next:** if findings exist, the user runs `/review-findings <name>`; otherwise the user runs `/learn-from-reports <name>` and then `/ship <name>`.

### Stage 6: `/review-findings <name>` (interactive review)

**What it does:** Partitions findings into **actionable** (severity: critical/high/medium/low) and **informational** (severity: info). Walks through actionable findings one-by-one for review, then displays informational findings as a compact summary list.

- **Actionable findings** — presented individually with severity, title, description, code snippet, fix proposal, and source. You decide: Accept or Reject.
  - **Accept:** Fix is applied (files re-read between fixes to avoid conflicts). `review_status` set to `accepted`.
  - **Reject:** You provide reasoning. `review_status` set to `rejected` with `review_notes`. Optionally creates a new rule in the general KB at `$WF_GENERAL_KB` (sets `rule_added: true`).
- **Informational findings** — auto-acknowledged with `review_status: noted`. Displayed as a summary list (title, file, description) at the end. No action required.

**Status update:**
- Findings processed (any mix of accepted/rejected) -> task moves to `done`, blocked tasks unblocked. The user runs `/learn-from-reports <name>` then `/ship <name>`. No revalidation — PR review + (medium/large) `/validate-impl` are the downstream safety nets.

**Next:** the user invokes the next command per the status update above.

### Stage 7: `/ship <name>` (commit, push, PR)

**What it does:** Ships a completed task — commits all changes, pushes the task branch, and creates a PR targeting the integration branch (`feat/<name>`).

1. Finds the lowest-numbered `done` task without a PR yet
2. Stages and commits changes using conventional commit format: `type(task-id): {task-title}`
3. Pushes the task branch
4. Creates PR: `gh pr create --base feat/<name>`
5. Saves the PR URL to the task file frontmatter as `pr_url`

**Produces:** A PR from the task branch into the integration branch.

**Requires:** `.workflow.yml`, at least one `done` task without a PR.

**Key detail:** `/ship` does NOT merge the PR — you review and merge it manually. The previous task's PR must be merged before `/implement` will start the next task.

**Next:** Merge the PR, then `/pr-review` if the PR gets review comments, or `/implement <name>` for the next task.

### Stage 8: `/pr-review` (PR comment loop)

**What it does:** Fetches unresolved PR comments via `gh`, reads referenced files and applicable KB rules from `$WF_GENERAL_KB`, generates fix proposals. You accept or reject each proposal. Accepted fixes are committed with a reference to the comment.

**Key detail:** PR review fixes do NOT trigger re-validation. The PR reviewer is the safety net at this stage. Task status stays `done`.

**Next:** Merge the PR, then `/implement <name>` for the next task, or final PR if all tasks are done.

### Stage 9: `/spec-status <name>` (dashboard — use anytime)

**What it does:** Shows a comprehensive status dashboard for a feature's tasks. Not a sequential stage — use it anytime to check progress.

**Displays:**
- Task summary table (ID, name, status)
- Progress overview with counts and percentage
- Dependency graph
- Health diagnostics (stuck tasks, deadlocks, orphan dependencies, circular deps)
- Suggested next action

**Requires:** `specs/<name>/tasks/` must exist.

### `/continue-task <name>` (resume work — use anytime)

**What it does:** Resumes work on whatever task is currently in flight. Detects the active task's phase by checking status and existing artifacts (reports, branches, PR state), then tells you exactly what to do next.

**Phase detection:**
- `in-progress` with no commits → continue implementing
- `in-progress` with code changes → continue coding/testing
- `implemented` with no reports → remind to run `/validate`
- `review` with pending findings → remind to run `/review-findings`
- `done` without PR → remind to run `/ship`
- `done` with open PR → remind to merge

**Requires:** `specs/<name>/tasks/` with at least one task in an active state.

### `/quick-ship` (standalone — use anytime)

**What it does:** Ships current changes without the spec-driven workflow. Works in any git repo. Commits, pushes, and creates a PR in one step.

- If on `main`/`master`, creates a feature branch first
- Stages all changes, generates a commit message from the diff
- Pushes and creates a PR targeting the default branch
- Scans for sensitive files before committing

**Requires:** Git repository with shippable changes.

### `/research` (mode toggle — use anytime)

**What it does:** Activates anti-hallucination research mode with three constraints: epistemic honesty (say "I don't know"), citation discipline (every claim needs a source), and quote-grounded responses. Stays active until you say "exit research mode".

Useful for bug investigation, API contract review, and any situation where accuracy matters more than speed.

**Requires:** None.

### Final PR

When all tasks reach `done`:
```bash
gh pr create --base main --head feat/<name>
```

This is the full feature review — all task branches have been merged into the integration branch.

## Tiered specs

Specs are tiered to right-size flow ceremony — `/explore` → `/propose` → `/implement` is too heavy for trivial changes. Tier is inferred at `/explore` step 0 by `engineering-config-inferencer`, approved by the user (single key), and written to `specs/<feature>/config.yml` as `tier:`.

| Tier | Threshold (defaults) | Flow shape |
|------|----------------------|------------|
| `small`  | ≤5 tasks, ≤10 files | `/propose` writes tasks/ only (skip spec.md, design.md, test-strategy.md). `/validate` runs lint+tests only — Phase-2 agent gates are skipped per `WF_TIER_AGENT_SKIP`. Skip `/validate-impl` Odium audit. |
| `medium` | ≤10 tasks, ≤30 files | `/propose` writes spec.md + tasks/ (skip design.md + test-strategy.md). Full per-task gates. `/validate-impl` runs. |
| `large`  | unbounded            | Full unchanged flow. |

Defaults live in `.workflow.yml` under `tiers:`. Per-spec override via `tier_ceiling:` in `specs/<feature>/config.yml`.

**Hard rules force ≥`medium`:** auth, crypto, secrets, DB migrations, public API contract changes, cross-service interactions. Encoded in the inferencer rubric — these never tier as `small`.

**Tier breach.** `/implement` step 0 runs `scripts/tier-check.sh <feature>`. Exit 9 → user picks:
- `Continue` — acknowledge, proceed at current tier.
- `Abort` — run `/promote-tier <feature>`. Re-runs `/propose` at next tier (`small → medium`, `medium → large`) for remaining scope only; `done`/`implemented` tasks are preserved.

Loader exports `WF_SPEC_TIER`, `WF_TIER_TASK_CEILING`, `WF_TIER_FILE_CEILING`, `WF_TIER_AGENT_SKIP` (canonical contract: `scripts/config-loader.contract.md`). Monitor events: `tier_inferred`, `tier_approved`, `tier_breach`, `tier_promoted`, `validate_impl_skipped`.

## Bug-fix flow (`/fix`)

Standalone command for production bugs, regressions, and hotfixes. Skips `/explore`, `/propose`, `/validate-impl`, and the tier system entirely.

**When to use vs the feature flow.** Use `/fix` when there is a known broken behavior to repro and patch. Use the feature flow when scope is open-ended or design choices remain.

**Artifact.** `specs/fixes/<slug>/fix.md` (frontmatter `type: fix`). Sections:
- **Repro** — BDD `Given / When / Then-broken`.
- **Root Cause** — written from `ultrathink-debugger` output.
- **Fix Plan** — minimal change set.
- **Regression Test** — pre-fix must fail; post-fix must pass.

Scaffold via `task-manager.sh init-fix <slug>`.

**Step list.**
1. BDD repro captured into `fix.md`.
2. Spawn `ultrathink-debugger` for root cause.
3. Write `fix.md` (Root Cause + Fix Plan + Regression Test).
4. Pre-fix test must fail (recorded).
5. Apply fix.
6. Regression test must pass.
7. Lint + ground-rule-matched gates run. Phase-2 agent gates are skipped by default unless the diff touches auth/crypto/migrations.
8. `/ship` with PR title prefix `fix:`.

**Not run:** `/explore`, `/propose`, `/validate-impl`, `/learn-from-reports` (the last only runs if a rejected finding warrants a new general-KB rule).

Monitor events: `fix_started`, `fix_root_cause`, `fix_shipped`.

## Multi-repo specs (vault mode)

When specs live in a master-brain Obsidian vault and span multiple code repos (e.g. frontend + backend), use `spec_storage_mode: vault` in the vault's `.workflow.yml`. Per-spec `config.yml` declares `repos[]` (logical name → absolute path → role). Loader exports `WF_REPO_NAMES` + `WF_REPO_PATHS` and validates each is a git work tree (exit 7 on failure).

**Setup.** Run `/bootstrap` from inside the vault directory (which must not itself be a git repo). Pick `vault` mode and add bindings (`name`, `path`, `role`) for each code repo. Default bindings land in `default_repos[]` and pre-populate every new spec's `repos[]`.

**Per-task `repo:` field.** Hard rule: one task = one repo. `task-manager.sh validate` enforces membership in `repos[].name`. Cross-repo work splits into sibling tasks under the same spec. `ground_rules` are bare `$WF_GENERAL_KB`-relative paths (legacy prefixes stripped + deprecation-warned). Each command (`/implement`, `/validate`, `/ship`, `/pr-review`, `/fix`) resolves `WF_TASK_REPO_PATH` per `scripts/multi-repo-resolution.md` and runs git/gates/PR creation inside that path.

**Gate filter.** Gates may set `applies_to_repos: [<name>, …]` to restrict to specific repos (e.g. `eslint` only on `frontend`). Default = applies everywhere.

**`/quick-ship`** in vault mode requires `--repo <name>`. **`/validate-impl`** runs Odium with per-repo diff sections.

Monitor events: `repo_bound`, `repo_missing`, `gate_repo_switch`.

## Task Lifecycle

### State machine

> Canonical source: `scripts/task-manager.sh` enforces transitions. Detailed docs in `plan.md` § Task State Machine.

```
blocked -> todo -> in-progress -> implemented -> review -> done
                                              \-> done (zero findings)
```

| Status | Set by | Meaning |
|--------|--------|---------|
| `blocked` | `/propose` | Dependencies not met (`blocked_by` lists task IDs) |
| `todo` | `/propose` or unblock | Ready to start |
| `in-progress` | `/implement` | Currently being implemented |
| `implemented` | `/implement` | Code written, awaiting validation |
| `review` | `/validate` | Findings exist, awaiting human review |
| `done` | `/validate` or `/review-findings` | Complete |

### Serialization

Only one task can be in flight at a time. `/implement` refuses to start if any task is `implemented` or `review`. This enforces: implement -> validate -> review -> next task.

### Unblocking

When a task reaches `done`, `task-manager.sh unblock` checks all `blocked` tasks. If every ID in a task's `blocked_by` list is `done`, that task moves to `todo`.

### Error recovery

**Stuck at `in-progress`** (crash, cancelled): Manually edit the task file's YAML frontmatter to reset `status: todo`, then clean up the partial branch.

**Stuck at `review`** (want to skip remaining findings): Run `/review-findings` and reject all pending findings.

### Task file schema

```yaml
---
id: "001"
name: "implement-user-repository"
status: "todo"
blocked_by: []
max_files: 15
estimated_files:
  - "src/domain/user/repository.rs"
  - "src/domain/user/repository_test.rs"
test_cases:
  - "should return user by ID when user exists"
  - "should return error when user not found"
ground_rules:
  - architecture/general.md
  - testing/principles.md
  - languages/rust.md
---

## Description
Implement the user repository trait and Postgres implementation.

## Ground Rules Applied
- architecture/general.md — domain layer owns the trait, infrastructure implements
- testing/principles.md — BDD test structure, Given/When/Then

## Implementation Notes
(AI fills this in during /implement)
```

Required fields: `id`, `name`, `status`, `ground_rules`, `test_cases`, `blocked_by`, `max_files`, `estimated_files`.

## Validation Gates

### 5 gates

| Gate | Deterministic tools | LLM analysis (agent) |
|------|-------------------|--------------|
| **security** | semgrep, language audit tools | KB security rules (`Security Engineer`) |
| **code-quality** | language lint tools | DRY, function size, modularity (`code-quality-pragmatist`) |
| **architecture** | none | KB architecture rules (`Software Architect`) |
| **compliance** | none | CLAUDE.md + general KB conventions (`claude-md-compliance-checker`) |
| **testing** | test runner, coverage tools | none (deterministic only) |

### Source types

- `source: tool` — deterministic, high-confidence. Hard gate.
- `source: llm` — advisory. Human decides via `/review-findings`.

Both types go through `/review-findings` where you are the final authority.

### Language file `validation_tools`

The `validation_tools` frontmatter in language files defines mandatory tools:

```yaml
---
validation_tools:
  lint: "cargo clippy -- -D warnings"
  test: "cargo test"
  coverage: "cargo tarpaulin --out json"
  audit: "cargo audit"
  security: "semgrep --config auto --json"
---
```

Every listed tool must run. Missing or failing tools are reported as error findings. Coverage is advisory only (`severity: info`).

### Report schema (condensed)

```yaml
gate: security
task_id: "001"
status: "findings"          # pass | findings | error
findings:
  - id: "SEC-001"
    severity: "high"        # critical | high | medium | low | info
    category: "sql-injection"
    title: "Unparameterized query"
    file: "src/infrastructure/postgres/user_repo.rs"
    lines: { start: 42, end: 45 }
    code_snippet: "..."
    fix_proposal: { description: "...", code_snippet: "..." }
    review_status: "pending"  # pending | accepted | rejected | noted
    source: "tool"            # tool | llm
```

## Branching Strategy

```
main
 └── feat/<feature>                         # integration branch
      ├── feat/<feature>/001-task-name      # task branch -> PR into feat/<feature>
      ├── feat/<feature>/002-task-name      # task branch -> PR into feat/<feature>
      └── feat/<feature>/003-task-name      # task branch -> PR into feat/<feature>
                                             # final PR: feat/<feature> -> main
```

- **Integration branch** (`feat/<feature>`): Created from `main` when the first task starts
- **Task branches** (`feat/<feature>/NNN-task-name`): Created from integration branch
- **Task PRs**: Each task branch PRs into `feat/<feature>` after reaching `done`
- **Final PR**: `feat/<feature>` -> `main` when all tasks complete
- **Serial**: Only one task branch active at a time
- **Max 20 files** per task PR

## Knowledge Base

### Single Knowledge Base (ADR-0002)

One knowledge base — the dual Project KB / General KB layer was collapsed.
See `docs/adr/0002-collapse-to-single-knowledge-base.md`.

**General KB** — all rules live at `$WF_GENERAL_KB` (path configured by
`general_kb_path`; recommended: the master-brain vault). Contains: security,
architecture, testing, style, documentation, code-review, language rules, and
learned convention rules. There is no per-repo `knowledge-base/` directory.

### Structure

```
$WF_GENERAL_KB/
├── _index.md
├── security/general.md
├── architecture/{general.md, api-design.md, code-analysis.md}
├── testing/principles.md
├── style/general.md
├── documentation/general.md
├── code-review/general.md
├── languages/
│   ├── rust/{_index.md, …topic files}
│   ├── typescript/{_index.md, type-safety.md, patterns.md, …}
│   ├── nextjs/{_index.md, …}
│   ├── scala/{_index.md, idioms.md, error-handling.md, …}
│   └── shell/{_index.md, tooling.md, module-api.md}
└── conventions/                 # grows via /review-findings feedback
```

### ground_rules — bare paths

Task `ground_rules` are bare `$WF_GENERAL_KB`-relative paths:
- `security/general.md` → resolves under `$WF_GENERAL_KB`
- `languages/rust.md` → resolves under `$WF_GENERAL_KB`
- Legacy `general:`/`project:`/`repo:<name>:` prefixes are stripped by a
  migration shim with a one-time per-process deprecation warning.

### Rule flow

1. **General KB** — single KB at `$WF_GENERAL_KB` (security, architecture, testing, style, documentation, code-review, languages, conventions)
2. **`/explore`** — reads `$WF_GENERAL_KB/_index.md` to identify relevant rules conversationally
3. **`/propose`** — selects rules and writes bare paths into each task's `ground_rules` field
4. **`/implement` + `/validate`** — `ground_rules` is the single source of truth for which rules apply
5. **`/review-findings`, `/learn-from-reports`, `/capture-rule`** — rejected findings / mined patterns become new rules in the **general** KB (feedback loop)

The general knowledge base grows organically and is shared across all projects.

### Language files

Language files include `validation_tools` in YAML frontmatter. These define the mandatory tool commands that `/validate` runs. The markdown body contains language-specific coding rules.

## Common Scenarios

### New feature end-to-end

```
/explore -> /propose my-feature -> review spec -> /implement my-feature ->
/validate my-feature -> /review-findings my-feature -> /ship my-feature ->
merge PR -> /pr-review (if comments) -> repeat for remaining tasks -> final PR
```

### Spec changes after review

Edit spec/design/task files conversationally during stage 3. No need to re-run `/propose` — just modify the existing files.

### Validation finds real issues

Accept findings in `/review-findings`. Fixes are applied and the task moves to `done`. No revalidation — PR review + (medium/large) `/validate-impl` are the safety nets.

### Validation false positives

Reject findings in `/review-findings` with reasoning. Optionally create a knowledge-base rule to prevent the same false positive in future tasks.

### Stuck task recovery

- **`in-progress`**: Edit task file frontmatter manually, set `status: todo`, delete partial branch.
- **`review`**: Run `/review-findings`, reject all pending findings. Task moves to `done`.

### PR review changes

Run `/pr-review` to fetch comments. Accept/reject fix proposals. No re-validation — the PR reviewer is the safety net.

### Final feature PR

After all tasks are `done` and merged into `feat/<feature>`:
```bash
gh pr create --base main --head feat/<feature>
```

## Quick Reference

| Command | When | Requires |
|---------|------|----------|
| `/bootstrap` | Once per project | General KB installed (`setup.sh`), `yq` |
| `/explore` | Start of new feature | General KB |
| `/propose <name>` | After requirements clear | General KB |
| `/implement <name>` | After spec review | General KB, no unvalidated tasks, previous PR merged |
| `/validate <name>` | After each implementation | General KB, task at `implemented` |
| `/review-findings <name>` | After validation with findings | General KB, task at `review` |
| `/ship <name>` | After task reaches `done` | `done` task without PR |
| `/pr-review` | After PR gets comments | Active PR on current branch |
| `/spec-status <name>` | Anytime | `specs/<name>/tasks/` |
| `/workflow-summary` | Anytime | None |
| `/continue-task <name>` | Resume interrupted work | Active task in `specs/<name>/tasks/` |
| `/quick-ship` | Ship without workflow | Git repo with changes |
| `/research` | Bug investigation, API review | None |
| `/fix <slug>` | Production bug / regression / hotfix | `.workflow.yml`, git repo |
| `/promote-tier <name>` | After tier-breach abort at `/implement` step 0 | `specs/<name>/config.yml` with current tier < `large` |
