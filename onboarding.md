# Spec-Driven Dev Workflow: Onboarding Guide

A file-based, spec-driven development workflow for Claude Code that adds validation gates, interactive finding review, and a knowledge-base feedback loop on top of standard AI-assisted coding. One external dependency: `yq` for YAML parsing.

## Prerequisites

Install these before running setup:

| Tool | Install | Purpose |
|------|---------|---------|
| `yq` | `brew install yq` | YAML parsing in task-manager.sh |
| `gh` | `brew install gh` | GitHub CLI for PRs and `/pr-review` |
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
- 13 slash commands to `~/.claude/commands/`:
  `bootstrap`, `explore`, `propose`, `implement`, `validate`, `review-findings`, `ship`, `quick-ship`, `pr-review`, `spec-status`, `workflow-summary`, `continue-task`, `research`
- 2 scripts to `~/.claude/scripts/`:
  `task-manager.sh` (task state machine), `pre-commit-hook.sh` (commit-time validation)
- 35+ agent definitions to `~/.claude/agents/`

These are global — they work across every project that has a knowledge-base bootstrapped.

Verify:
```bash
ls ~/.claude/commands/*.md
~/.claude/scripts/task-manager.sh help
```

## Per-Project Setup

Do these steps once in each project you want to use the workflow with.

### 1. Bootstrap the knowledge-base

Open the project in Claude Code and run:
```
/bootstrap
```

This creates the project-specific `knowledge-base/` with:
- `languages/` — per-language validation tool definitions (asks which languages the project uses)
- `conventions/` — empty directory for project-specific rules discovered over time

General rules (security, architecture, testing, style) are already installed globally at `~/.claude/knowledge-base/` by `setup.sh`. The `/bootstrap` command only creates project-specific content.

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

Check `knowledge-base/languages/` for which tools are listed in `validation_tools` frontmatter, then install them. Examples:

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
├── knowledge-base/
│   ├── _index.md                    # project-specific rule index
│   ├── languages/                   # project-specific language files
│   └── conventions/                 # project-specific conventions
├── specs/           (created later by /propose)
└── .git/hooks/pre-commit
```

## Workflow Walkthrough

The workflow has 10 core stages (plus `/spec-status`, `/workflow-summary`, `/continue-task`, `/quick-ship`, and `/research` available anytime). Each stage produces specific artifacts and has a clear next step.

### Stage 0: `/bootstrap` (once per project)

**What it does:** Creates the project-specific `knowledge-base/` with language files and a `conventions/` directory. General rules (security, architecture, testing, style) are already installed globally by `setup.sh`. Asks which languages the project uses and generates language files with `validation_tools` frontmatter.

**Produces:** `knowledge-base/` directory with `_index.md`, `languages/`, and `conventions/`.

**Next:** `/explore`

### Stage 1: `/explore` (requirements)

**What it does:** Conversational requirements gathering. Reads both general and project `_index.md` files to know which rules exist, then asks clarifying questions about scope, security, integrations, testing, and performance.

**Produces:** Shared understanding of what to build. Optionally saves a PRD to `specs/<name>/prd.md`.

**Requires:** `knowledge-base/` must exist.

**Next:** `/propose <name>`

### Stage 2: `/propose <name>` (spec generation)

**What it does:** Generates the full spec package from the PRD (or conversation context). Reads applicable knowledge-base rules and references them throughout.

**Produces:**
- `specs/<name>/spec.md` — functional spec with BDD scenarios (Given/When/Then)
- `specs/<name>/design.md` — architectural decisions with rule references and rationale
- `specs/<name>/tasks/NNN-task-name.md` — task files with `ground_rules`, `test_cases`, `blocked_by`, status (`todo` or `blocked`)

**Requires:** `knowledge-base/` must exist.

**Next:** Spec review (stage 3)

### Stage 3: Spec review (conversational)

**What it does:** You read the generated spec, design, and tasks. Request changes conversationally — Claude edits the existing files directly. No command to run.

**What to check:**
- Are the right `ground_rules` assigned to each task?
- Are test cases comprehensive?
- Do architectural decisions make sense against the rules?
- Are task boundaries and dependencies correct?
- Is `max_files` reasonable (max 20)?

**Next:** `/implement <name>`

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

**Requires:** `knowledge-base/`, no unvalidated tasks.

**Next:** `/validate <name>` — do NOT skip this step.

### Stage 5: `/validate <name>` (automated validation)

**What it does:**
1. **Phase 1 — Deterministic tools (hard gates):** Reads `validation_tools` from language file frontmatter, runs every listed tool. Skipping a tool is not allowed. Missing tools are reported as error findings.
2. **Phase 2 — LLM analysis (advisory):** Checks code against `ground_rules` for architecture compliance, DRY violations, test quality, and rule violations tools can't catch. All LLM findings marked `source: llm`.

**Produces:** YAML reports in `specs/<name>/reports/NNN-gate.yaml` for each gate.

**4 gates:**
- **security** — semgrep + language audit tools + LLM (general + project security rules)
- **code-quality** — language lint tools + LLM (general + project style rules)
- **architecture** — LLM only (general + project architecture rules)
- **testing** — language test/coverage tools + LLM (test quality)

**Status update:**
- Findings exist -> task moves to `review`
- Zero findings -> task moves to `done`, blocked tasks are checked and unblocked

**Next:** `/review-findings <name>` if findings exist, otherwise `/ship <name>`.

### Stage 6: `/review-findings <name>` (interactive review)

**What it does:** Partitions findings into **actionable** (severity: critical/high/medium/low) and **informational** (severity: info). Walks through actionable findings one-by-one for review, then displays informational findings as a compact summary list.

- **Actionable findings** — presented individually with severity, title, description, code snippet, fix proposal, and source. You decide: Accept or Reject.
  - **Accept:** Fix is applied (files re-read between fixes to avoid conflicts). `review_status` set to `accepted`.
  - **Reject:** You provide reasoning. `review_status` set to `rejected` with `review_notes`. Optionally creates a new rule in the project `knowledge-base/` (sets `rule_added: true`).
- **Informational findings** — auto-acknowledged with `review_status: noted`. Displayed as a summary list (title, file, description) at the end. No action required.

**Status update:**
- Fixes applied -> task returns to `implemented` (re-run `/validate <name>`)
- No fixes applied (all rejected) -> task moves to `done`, blocked tasks unblocked

**Next:** `/validate <name>` if fixes were applied, otherwise `/ship <name>`.

### Stage 7: `/ship <name>` (commit, push, PR)

**What it does:** Ships a completed task — commits all changes, pushes the task branch, and creates a PR targeting the integration branch (`feat/<name>`).

1. Finds the lowest-numbered `done` task without a PR yet
2. Stages and commits changes using conventional commit format: `type(task-id): {task-title}`
3. Pushes the task branch
4. Creates PR: `gh pr create --base feat/<name>`
5. Saves the PR URL to the task file frontmatter as `pr_url`

**Produces:** A PR from the task branch into the integration branch.

**Requires:** `knowledge-base/`, at least one `done` task without a PR.

**Key detail:** `/ship` does NOT merge the PR — you review and merge it manually. The previous task's PR must be merged before `/implement` will start the next task.

**Next:** Merge the PR, then `/pr-review` if the PR gets review comments, or `/implement <name>` for the next task.

### Stage 8: `/pr-review` (PR comment loop)

**What it does:** Fetches unresolved PR comments via `gh`, reads referenced files and applicable knowledge-base rules, generates fix proposals. You accept or reject each proposal. Accepted fixes are committed with a reference to the comment.

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

## Task Lifecycle

### State machine

> Canonical source: `scripts/task-manager.sh` enforces transitions. Detailed docs in `plan.md` § Task State Machine.

```
blocked -> todo -> in-progress -> implemented -> review -> done
                                              \-> done (zero findings)
                                  review -> implemented (fixes applied, re-validate)
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
  - general:architecture/general.md
  - general:testing/principles.md
  - project:languages/rust.md
---

## Description
Implement the user repository trait and Postgres implementation.

## Ground Rules Applied
- general:architecture/general.md — domain layer owns the trait, infrastructure implements
- general:testing/principles.md — BDD test structure, Given/When/Then

## Implementation Notes
(AI fills this in during /implement)
```

Required fields: `id`, `name`, `status`, `ground_rules`, `test_cases`, `blocked_by`, `max_files`, `estimated_files`.

## Validation Gates

### 4 gates

| Gate | Deterministic tools | LLM analysis |
|------|-------------------|--------------|
| **security** | semgrep, language audit tools | general + project security rules |
| **code-quality** | language lint tools | general + project style rules |
| **architecture** | none | general + project architecture rules |
| **testing** | test runner, coverage tools | test quality, missing edge cases |

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

### Dual Knowledge Base

Two knowledge bases work together:

**General KB** — universal rules installed globally at `~/.claude/knowledge-base/` by `setup.sh`. Contains: security, architecture, testing, style, documentation, code-review, and language rules.

**Project KB** — project-specific rules at `knowledge-base/`:
- Created by `/bootstrap`
- Contains: `languages/` (validation tools), `conventions/` (project-specific rules)

### Structure

```
~/.claude/knowledge-base/        # General KB (global)
├── _index.md
├── security/general.md
├── architecture/
│   ├── general.md
│   ├── api-design.md
│   └── code-analysis.md
├── testing/principles.md
├── style/general.md
├── documentation/general.md
├── code-review/general.md
└── languages/
    ├── rust.md
    ├── typescript.md
    ├── nextjs.md
    └── scala.md

knowledge-base/                  # Project KB (per-repo)
├── _index.md
├── languages/rust.md            # with validation_tools frontmatter
└── conventions/                 # grows via /review-findings feedback
```

### ground_rules Prefix Convention

Task `ground_rules` use prefixes to reference rules from either KB:
- `general:security/general.md` → resolves to general KB
- `project:languages/rust.md` → resolves to project KB
- Unprefixed paths default to `project:` (backward compatibility)

### Rule flow

1. **`setup.sh`** — installs general rules globally (security, architecture, testing, style, documentation, code-review, languages)
2. **`/bootstrap`** — creates project-specific rules (languages, conventions)
3. **`/explore`** — reads both `_index.md` files to identify relevant rules conversationally
4. **`/propose`** — selects rules from both KBs and writes them into each task's `ground_rules` field with prefixes
5. **`/implement` + `/validate`** — `ground_rules` is the single source of truth for which rules apply
6. **`/review-findings`** — rejected findings can become new rules in the **project** KB (feedback loop)

The project knowledge base grows organically. General rules are shared across all projects; project rules capture conventions unique to the codebase.

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

Accept findings in `/review-findings`. Fixes are applied, task returns to `implemented`. Re-run `/validate` to confirm the fixes pass.

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
| `/explore` | Start of new feature | Both KBs |
| `/propose <name>` | After requirements clear | Both KBs |
| `/implement <name>` | After spec review | Both KBs, no unvalidated tasks, previous PR merged |
| `/validate <name>` | After each implementation | Both KBs, task at `implemented` |
| `/review-findings <name>` | After validation with findings | Both KBs, task at `review` |
| `/ship <name>` | After task reaches `done` | `done` task without PR |
| `/pr-review` | After PR gets comments | Active PR on current branch |
| `/spec-status <name>` | Anytime | `specs/<name>/tasks/` |
| `/workflow-summary` | Anytime | None |
| `/continue-task <name>` | Resume interrupted work | Active task in `specs/<name>/tasks/` |
| `/quick-ship` | Ship without workflow | Git repo with changes |
| `/research` | Bug investigation, API review | None |
