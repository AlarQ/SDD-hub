# Spec-Driven AI Development Workflow

## Context

This project builds a disciplined, spec-driven AI development workflow using Claude Code slash commands, CLAUDE.md, and markdown/YAML files. The entire system is file-based with one external dependency (`yq` for YAML parsing).

**Portable by design:** Slash commands live globally in `~/.claude/commands/`. Each target project provides its own `knowledge-base/` and `specs/` directories. The workflow works across any project that has a knowledge-base bootstrapped.

**This repo is plan + tutorial only** — no code lives here. The actual implementation (slash commands, scripts) goes into `~/.claude/` and target projects get `knowledge-base/` and `specs/` via `/bootstrap`.

**How this differs from existing SDD tools on the market:**
Most spec-driven tools focus on the spec generation and implementation phases. This workflow goes further — it adds automated validation gates (deterministic tools as hard gates + LLM analysis as advisory), interactive finding review with accept/reject controls, and a knowledge-base feedback loop where rejected findings become new rules. The validation and review stages are where this workflow's real value lives, and no existing tool covers them.

---

## Core Principles

1. **Every line reviewed** — no exceptions, human reviews all code (AI or human-written) at PR stage (GitHub diff). Validation gates (stages 5-6) are a pre-filter that surfaces flagged issues before the full line-by-line review.
2. **Architectural decisions at spec level** — not during implementation
3. **AI explains decisions** — against ground rules, not just outputs code
4. **TDD/BDD** — human defines test cases in natural language, AI implements
5. **Code must be testable** — dependency injection, modularity, pure functions
6. **Feedback loop** — validated findings feed back into rule context; the system learns
7. **Knowledge-base is mandatory** — all commands refuse to run if `knowledge-base/` doesn't exist in the project
8. **One task = one branch = one PR** — keeps PRs small and reviewable
9. **One task = one language** — each task is scoped to a single language/repository
10. **Strictly serial execution** — only one task in flight at a time; no parallel task implementation

---

## Workflow Stages

| Stage | Command | What It Does |
|-------|---------|--------------|
| 0. Bootstrap | `/bootstrap` | Create knowledge-base structure, seed from global rules |
| 1. Requirements | `/explore` | Clarify requirements, refine PRD, identify ground rules |
| 2. Spec Generation | `/propose <name>` | Generate spec, design, tasks with knowledge-base rules |
| 3. Spec Review | (conversational) | Human reviews artifacts, requests changes via conversation |
| 4. Implementation | `/implement <name>` | Implement one task at a time (creates branch per task) |
| 5. Automated Validation | `/validate <name>` | Run deterministic tools + LLM analysis gates |
| 6. Finding Review | `/review-findings <name>` | Human accepts/rejects each finding |
| 7. PR Creation | `/commit` + `gh` CLI | Standard Claude Code + GitHub CLI |
| 8. PR Review Loop | `/pr-review` | Fetch PR comments, propose fixes |

All commands that operate on a feature take the feature name as `$ARGUMENTS`.

---

## Task State Machine

```
blocked → todo → in-progress → implemented → review → done
                                            ↗ (fixes applied, re-validate)
```

| Status | Set By | Meaning |
|--------|--------|---------|
| `blocked` | `/propose` | Task has unmet dependencies (`blocked_by` lists task IDs) |
| `todo` | `/propose` or `/review-findings` | Ready to start (no dependencies, or all dependencies `done`) |
| `in-progress` | `/implement` | Currently being implemented |
| `implemented` | `/implement` | Code written, awaiting validation |
| `review` | `/validate` | Findings exist, awaiting human review |
| `done` | `/validate` (no findings) or `/review-findings` (all resolved) | Task complete |

**Transitions:**
- `blocked → todo`: `/review-findings` sets this when all blocking tasks reach `done`
- `todo → in-progress`: `/implement` sets this when starting work
- `in-progress → implemented`: `/implement` sets this when code is written
- `implemented → review`: `/validate` sets this when findings exist
- `implemented → done`: `/validate` sets this when all gates pass with zero findings
- `review → implemented`: `/review-findings` sets this after accepted fixes are applied (triggers re-validation)
- `review → done`: `/review-findings` sets this when all findings are resolved (accepted or rejected)

---

## Rule Selection

- **During `/explore`**: reads `knowledge-base/_index.md` (simple file listing with descriptions) to identify relevant rules conversationally
- **During `/propose`**: AI selects applicable rules and writes them into each task's `ground_rules` field; human reviews during spec review (stage 3)
- **During `/implement` and `/validate`**: the task's `ground_rules` field is the **single source of truth** — no ambiguity about which rules apply

---

## Validation Gate Types

- **Deterministic tools** (`source: tool`): Hard gates. Clippy, eslint, semgrep, cargo test, etc. Tool failures are high-confidence findings.
- **LLM analysis** (`source: llm`): Advisory layer. Architecture compliance, DRY violations, test quality. Surfaces things for human review that tools can't catch. Does not decide pass/fail on its own.
- **Both types** go through `/review-findings` where the human is the final authority.

---

## Implementation

### Step 1: Directory Structure

Slash commands are global (portable across projects):
```
~/.claude/commands/
├── bootstrap.md
├── explore.md
├── propose.md
├── implement.md
├── validate.md
├── review-findings.md
└── pr-review.md
```

Helper scripts (also global, called by slash commands):
```
~/.claude/scripts/
└── task-manager.sh          # Validates and updates task files (status, structure, schema)
```

Each target project provides:
```
project-root/
├── knowledge-base/       # Ground rules (mandatory, commands refuse without it)
│   ├── _index.md
│   ├── security/
│   ├── architecture/
│   ├── languages/
│   ├── testing/
│   └── style/
└── specs/                # Feature specs, tasks, reports
```

Validation reports are created by `/validate` and deleted after `/review-findings` resolves all findings. Everything else (`knowledge-base/`, `specs/*/prd.md`, `specs/*/spec.md`, `specs/*/design.md`, `specs/*/tasks/`) should be committed.

### Step 2: Bootstrap Knowledge Base

Start minimal — the feedback loop (rejected findings become new rules) will grow the knowledge base organically.

```
knowledge-base/
├── _index.md                          # Simple file listing with one-line descriptions
├── security/
│   ├── general.md                     # OWASP basics, input validation, secret handling
│   ├── authentication.md
│   └── data-handling.md
├── architecture/
│   ├── general.md                     # Hexagonal/DDD boundaries, dependency direction
│   └── ddd.md
├── languages/
│   ├── rust.md                        # Idiomatic patterns + validation_tools in frontmatter
│   ├── typescript.md
│   └── python.md
├── testing/
│   ├── principles.md                  # TDD/BDD ground rules, Given/When/Then, coverage
│   └── integration.md
└── style/
    └── general.md                     # Naming, module size (<100 lines), function size (<50 lines)
```

**`_index.md` format** — a flat list of files with descriptions so commands can decide what to read:
```markdown
# Knowledge Base Index

- `security/general.md` — OWASP basics, input validation, secret handling
- `security/authentication.md` — Auth patterns, token handling, session management
- `security/data-handling.md` — PII, encryption, data retention
- `architecture/general.md` — Hexagonal architecture, dependency direction, module boundaries
- `architecture/ddd.md` — Domain-driven design, aggregates, bounded contexts
- `languages/rust.md` — Idiomatic Rust, error handling, ownership, unsafe rules
- `languages/typescript.md` — Strict mode, functional patterns, no `any`
- `languages/python.md` — Type hints, virtual envs, async patterns
- `testing/principles.md` — TDD/BDD ground rules, Given/When/Then format
- `testing/integration.md` — Integration test patterns, real databases over mocks
- `style/general.md` — Naming, module size, function size
```

**Language files include validation tooling in frontmatter** — these are mandatory for `/validate`:
```yaml
# knowledge-base/languages/rust.md
---
validation_tools:
  lint: "cargo clippy -- -D warnings"
  test: "cargo test"
  coverage: "cargo tarpaulin --out json"
  audit: "cargo audit"
  license: "cargo deny check"
  security: "semgrep --config auto --json"
---

## Rules
...
```

**Source material:** Migrate relevant rules from `~/.claude/rules/code-quality.md` and `~/.claude/rules/security-patterns.md`. These already contain validated preferences and should form the initial seed.

**Target:** ~5-10 rules per file. Keep rules specific and actionable — each rule should be something a validation gate can check against.

### Step 3: Helper Scripts

#### `~/.claude/scripts/task-manager.sh`

A shell script that slash commands call to read and update task files. Provides structural guarantees that LLM-only editing cannot. Uses `yq` for YAML parsing/updating.

**Dependency:** `yq` (install via `brew install yq`)

**Capabilities:**
- **Validate task file structure** — checks required fields (`id`, `name`, `status`, `ground_rules`, `test_cases`, `blocked_by`, `max_files`, `estimated_files`), validates types, ensures `ground_rules` paths point to real files in `knowledge-base/`
- **Validate status values** — only allows: `blocked`, `todo`, `in-progress`, `implemented`, `review`, `done`
- **Validate status transitions** — enforces the state machine (e.g., can't go from `todo` directly to `done`)
- **Update status** — atomically updates the `status` field in YAML frontmatter
- **Validate `blocked_by` references** — checks that referenced task IDs exist
- **Unblock check** — scans all tasks with `status: blocked`, sets to `todo` if all `blocked_by` IDs are `done`

**Interface:**
```bash
# Validate a task file
task-manager.sh validate <task-file>

# Update task status (validates transition)
task-manager.sh set-status <task-file> <new-status>

# Run unblock check across all tasks in a directory
task-manager.sh unblock <tasks-directory>

# Get next eligible task (status: todo, not blocked)
task-manager.sh next <tasks-directory>

# Check for unvalidated work (any task with status: implemented or review)
task-manager.sh check-unvalidated <tasks-directory>
```

All slash commands use this script instead of directly editing task YAML frontmatter.

**Enforcement:** A pre-commit hook runs `task-manager.sh validate` on any changed task files. If the structure or status transition is invalid, the commit is rejected. This provides a hard guarantee that Claude cannot bypass by editing files directly.

### Step 4: Slash Commands

#### `~/.claude/commands/bootstrap.md`

Create and seed the knowledge-base for a new project.

```markdown
Bootstrap the knowledge-base for a new project.

## Steps
1. Check if `knowledge-base/` already exists — if yes, report and stop (don't overwrite)
2. Create the directory structure:
   - `knowledge-base/_index.md`
   - `knowledge-base/security/`
   - `knowledge-base/architecture/`
   - `knowledge-base/languages/`
   - `knowledge-base/testing/`
   - `knowledge-base/style/`
3. Read `~/.claude/rules/code-quality.md` and `~/.claude/rules/security-patterns.md`
4. Seed initial rule files by migrating relevant rules from the global files:
   - `security/general.md` — from security-patterns.md (OWASP, validation, secret handling)
   - `architecture/general.md` — from code-quality.md (composition, modularity, boundaries)
   - `testing/principles.md` — from code-quality.md (testability, pure functions)
   - `style/general.md` — from code-quality.md (naming, module/function size)
5. Ask the user which languages this project uses
6. Create language files with `validation_tools` frontmatter for each selected language
7. Generate `_index.md` listing all created files with descriptions
8. Report what was created

Target: ~5-10 rules per file. Rules should be specific and actionable — each rule should be something a validation gate can check against.
```

#### `~/.claude/commands/explore.md`

Clarify and refine requirements before spec work begins.

```markdown
Explore and clarify requirements for a new feature or change.

## Prerequisites
1. Check that `knowledge-base/` directory exists — if not, refuse and instruct the user to bootstrap it

## Steps
1. Read `knowledge-base/_index.md` to understand available ground rules
2. Ask the user to describe the feature or change
3. Ask clarifying questions about:
   - Scope: what's in, what's out
   - Affected domains and modules
   - Security implications (auth, data handling, input validation)
   - Integration points (APIs, databases, external services)
   - Testing expectations (unit, integration, e2e)
   - Performance or scalability constraints
4. Identify which `knowledge-base/` rule files are relevant to this feature
5. Summarize understanding and list applicable ground rules
6. Optionally save as `specs/$ARGUMENTS/prd.md` if the user provides a feature name

This is conversational — no artifacts are generated yet. The goal is alignment on what needs to be built. Continue refining until the user is satisfied with the PRD.
```

#### `~/.claude/commands/propose.md`

Generate the full spec package from a PRD.

```markdown
Generate specification, design, and tasks for a feature.

Feature name: $ARGUMENTS

## Prerequisites
1. Check that `knowledge-base/` directory exists — if not, refuse and instruct the user to bootstrap it

## Steps
1. Read `specs/$ARGUMENTS/prd.md` if it exists, otherwise use conversation context
2. Read `knowledge-base/_index.md` and identify all applicable rules
3. Read the applicable rule files

## Generate Artifacts

### specs/$ARGUMENTS/spec.md
- Detailed functional specification
- All scenarios in BDD format: Given / When / Then
- Edge cases and error scenarios explicitly listed
- Reference applicable `knowledge-base/` rules

### specs/$ARGUMENTS/design.md
- Architectural decisions with explicit references to `knowledge-base/architecture/` rules
- Explain WHY each decision was made against the ground rules
- Module boundaries, dependency direction, data flow
- Reference `knowledge-base/languages/` for language-specific patterns

### specs/$ARGUMENTS/tasks/NNN-{task-name}.md
- Split implementation into small tasks
- Each task's `ground_rules` field lists the specific knowledge-base files that apply — this becomes the single source of truth for `/implement` and `/validate`
- Set `status: blocked` with `blocked_by` IDs for tasks with dependencies
- Set `status: todo` for tasks with no dependencies

## Constraints
- Max 20 files per task
- Each task references applicable `knowledge-base/` rules in the `ground_rules` field
- Each task includes natural-language test cases (human defines names, AI implements bodies later)
- Tasks ordered by dependency (`blocked_by` fields)
- AI explains architectural decisions against ground rules, not just outputs code
- Tasks must be small enough for meaningful human code review

Present all generated artifacts for human review before proceeding to implementation.
```

#### `~/.claude/commands/implement.md`

Implement one task at a time.

```markdown
Implement the next task for a feature.

Feature name: $ARGUMENTS

## Prerequisites
1. Check that `knowledge-base/` directory exists — if not, refuse and instruct the user to bootstrap it
2. Run `task-manager.sh check-unvalidated specs/$ARGUMENTS/tasks/` — if any task is `implemented` or `review`, refuse and say: "Task [ID] is awaiting validation. Run `/validate $ARGUMENTS` first."
3. Run `task-manager.sh next specs/$ARGUMENTS/tasks/` to find the next eligible task
   - If no eligible task found, report which tasks are blocked and by which task IDs

## Steps
1. Run `task-manager.sh set-status <task-file> in-progress`
2. Ensure the feature integration branch exists: `feat/$ARGUMENTS` (create from `main` if first task)
3. Create task branch from the integration branch: `feat/$ARGUMENTS/{task-id}-{task-name}`
4. Read the task's `ground_rules` files from `knowledge-base/`
5. Read `specs/$ARGUMENTS/spec.md` and `specs/$ARGUMENTS/design.md` for context
6. Implement the code changes following the spec and ground rules:
   - Follow architectural decisions from design.md
   - Follow language-specific patterns from knowledge-base/languages/
   - Apply security rules from knowledge-base/security/
7. Implement test bodies for the natural-language test cases defined in the task
   - Human wrote test case names in the task file
   - AI writes the test implementations
   - Use Given/When/Then structure from knowledge-base/testing/
8. Add implementation notes to the task file explaining decisions made
9. Run `task-manager.sh set-status <task-file> implemented`

IMPORTANT:
- Do NOT proceed to the next task automatically
- Remind the user to run `/validate $ARGUMENTS` before continuing
- Human must review and validate before the next task starts

## Error Recovery
If implementation is aborted mid-task (crash, user cancels), the task is stuck at `in-progress`. The user can manually edit the task file's YAML frontmatter to reset `status` back to `todo` and clean up the partial branch.
```

#### `~/.claude/commands/validate.md`

Run all validation gates after implementation.

```markdown
Run validation gates on implemented code for a feature.

Feature name: $ARGUMENTS

## Prerequisites
1. Check that `knowledge-base/` directory exists — if not, refuse and instruct the user to bootstrap it
2. Read tasks from `specs/$ARGUMENTS/tasks/` — find all tasks with `status: implemented`
   - If no tasks have `status: implemented`, report and stop

## Phase 1: Deterministic Tools (hard gates)
For each task with `status: implemented`:
1. Read the task's `ground_rules` to identify language files
2. Extract `validation_tools` from the frontmatter of each referenced language file
3. Run **every** listed tool — skipping a tool is not allowed
   - If a tool is missing or fails to install, report it as an error finding
4. Collect all tool outputs and convert findings into the report schema

## Phase 2: LLM Analysis (advisory)
Read all `ground_rules` files referenced in the tasks. For each gate, analyze code against rules for issues tools can't catch:
- **Architecture**: Structural compliance, DDD boundaries, hexagonal layering
- **Code quality**: DRY violations, function reuse, module coupling
- **Testing**: Test quality, missing edge cases, BDD format compliance
- **Knowledge-base compliance**: Any rule violations not caught by tools

Mark all LLM findings with `source: llm`.

## Output
One YAML report per gate to `specs/$ARGUMENTS/reports/{task-id}-{gate}.yaml`

## Status Update
- If any findings exist across any gate: run `task-manager.sh set-status <task-file> review`
- If zero findings across all gates: run `task-manager.sh set-status <task-file> done`, then run `task-manager.sh unblock specs/$ARGUMENTS/tasks/`

Report schema:
- gate: <gate-name>
- task_id: <id>
- status: pass | findings | error
- findings: list of {id, severity, category, title, description, file, lines, code_snippet, fix_proposal, review_status: pending, source: tool|llm}

Gates:
- **security**: semgrep + language audit tools + LLM for knowledge-base/security/ rules
- **code-quality**: language lint tools + LLM for DRY, function size, modularity
- **architecture**: LLM-only (check against knowledge-base/architecture/)
- **testing**: language test/coverage tools + LLM for test quality review
```

#### `~/.claude/commands/review-findings.md`

Interactive finding review with accept/reject and feedback loop.

```markdown
Walk through validation findings interactively.

Feature name: $ARGUMENTS

## Prerequisites
1. Check that `knowledge-base/` directory exists — if not, refuse and instruct the user to bootstrap it

## Steps
1. Read all pending reports from `specs/$ARGUMENTS/reports/`
2. For each finding with review_status: pending:
   - Present: severity, title, description, code snippet, fix proposal, source (tool/llm)
   - Ask: Accept or Reject?
   - If Accept: apply the fix, **re-read the file** before applying the next fix (sequential apply to avoid conflicts), update review_status to "accepted"
   - If Reject: ask for reasoning, update review_status to "rejected", set review_notes
   - If Reject + new rule needed: create/update the relevant knowledge-base/ file and update `knowledge-base/_index.md`, set rule_added: true
3. Report summary: X accepted, Y rejected, Z new rules added

## Status Update
- If any fixes were applied (accepted findings): run `task-manager.sh set-status <task-file> implemented` and remind user to re-run `/validate $ARGUMENTS`
- If no fixes were applied (all findings rejected or already clean): run `task-manager.sh set-status <task-file> done`, then run `task-manager.sh unblock specs/$ARGUMENTS/tasks/`
```

#### `~/.claude/commands/pr-review.md`

Fetch PR comments and generate structured fix proposals.

```markdown
Fetch and respond to PR review comments.

**Note:** PR review fixes do NOT trigger re-validation. The PR reviewer is the safety net at this stage. Task status remains `done` — if a PR reviewer finds an issue, it is handled entirely within the PR, no task state change needed.

## Prerequisites
1. Check that `knowledge-base/` directory exists — if not, refuse and instruct the user to bootstrap it

## Steps
1. Get current branch and PR number via `gh pr view --json number`
2. Fetch comments via `gh api repos/{owner}/{repo}/pulls/{number}/comments`
3. For each unresolved comment:
   - Read the referenced file and lines
   - Read applicable knowledge-base/ rules
   - Generate a fix proposal with: description, code_snippet, status: pending
4. Present each proposal for human accept/reject
5. On accept: apply fix, commit with reference to comment
6. On reject: note reasoning, optionally update knowledge-base/
```

### Step 5: Schemas

#### Task File (`tasks/NNN-{task-name}.md`)

```yaml
---
id: "001"
name: "implement-user-repository"
status: "todo"                        # blocked | todo | in-progress | implemented | review | done
blocked_by: []                        # list of task IDs
max_files: 15
estimated_files:
  - "src/domain/user/repository.rs"
  - "src/domain/user/repository_test.rs"
  - "src/infrastructure/postgres/user_repo.rs"
test_cases:
  - "should return user by ID when user exists"
  - "should return error when user not found"
  - "should persist new user with all required fields"
ground_rules:
  - knowledge-base/architecture/ddd.md
  - knowledge-base/testing/principles.md
  - knowledge-base/languages/rust.md
---

## Description

Implement the user repository trait and Postgres implementation.

## Ground Rules Applied

- knowledge-base/architecture/ddd.md — domain layer owns the trait, infrastructure implements
- knowledge-base/testing/principles.md — BDD test structure, Given/When/Then
- knowledge-base/languages/rust.md — idiomatic error handling, no unwrap in production code

## Implementation Notes

AI explains decisions made during implementation here.
```

#### Language File Frontmatter (`knowledge-base/languages/rust.md`)

```yaml
---
validation_tools:
  lint: "cargo clippy -- -D warnings"
  test: "cargo test"
  coverage: "cargo tarpaulin --out json"
  audit: "cargo audit"
  license: "cargo deny check"
  security: "semgrep --config auto --json"
---
```

All tools listed in `validation_tools` are **mandatory** — `/validate` must run every one. If a tool is unavailable or fails to install, it is reported as an error finding. Coverage tools are **advisory only** — output is included as a finding with `severity: info` for human review, no threshold is enforced.

#### Validation Report (`reports/{task-id}-{gate}.yaml`)

```yaml
gate: security
task_id: "001"
task_name: "implement-user-repository"
timestamp: "2026-03-19T14:30:00Z"
status: "findings"                     # pass | findings | error
summary: "2 findings, 0 critical"

findings:
  - id: "SEC-001"
    severity: "high"                   # critical | high | medium | low | info
    category: "sql-injection"
    title: "Unparameterized query in user lookup"
    description: "Raw string interpolation used in SQL query, vulnerable to injection."
    file: "src/infrastructure/postgres/user_repo.rs"
    lines:
      start: 42
      end: 45
    code_snippet: |
      let query = format!("SELECT * FROM users WHERE id = '{}'", user_id);
      client.query(&query, &[]).await?;
    fix_proposal:
      description: "Use parameterized query instead of string interpolation."
      code_snippet: |
        let query = "SELECT * FROM users WHERE id = $1";
        client.query(query, &[&user_id]).await?;
    review_status: "pending"           # pending | accepted | rejected
    review_notes: ""                   # human adds reasoning on reject
    rule_added: false                  # true if rejection led to new knowledge-base rule
    source: "tool"                     # tool | llm

  - id: "SEC-002"
    severity: "medium"
    category: "error-exposure"
    title: "Internal error details leaked in response"
    description: "Database error message returned directly to caller without sanitization."
    file: "src/infrastructure/postgres/user_repo.rs"
    lines:
      start: 58
      end: 60
    code_snippet: |
      Err(e) => Err(ApiError::new(500, format!("DB error: {}", e)))
    fix_proposal:
      description: "Return generic error to caller, log detailed error internally."
      code_snippet: |
        Err(e) => {
            tracing::error!("Database error in user lookup: {}", e);
            Err(ApiError::internal("Failed to retrieve user"))
        }
    review_status: "pending"
    review_notes: ""
    rule_added: false
    source: "tool"
```

#### PR Comment Fix Proposal

```yaml
pr_number: 42
comment_responses:
  - comment_id: "gh-comment-12345"
    author: "ernestbednarczyk"
    original_comment: "This error handling swallows the context, we need to preserve the chain"
    file: "src/domain/user/service.rs"
    lines:
      start: 30
      end: 35
    current_code: |
      .map_err(|_| ServiceError::Internal)?
    fix_proposal:
      description: "Preserve error chain using .context() from anyhow"
      code_snippet: |
        .map_err(|e| ServiceError::Internal(e.context("failed to fetch user in service layer")))?
    status: "pending"                  # pending | accepted | rejected
    rule_added: false
```

### Step 6: CLAUDE.md Configuration

This goes in each target project's `CLAUDE.md`:

```markdown
# Project Instructions

## Workflow
This project uses a custom spec-driven development workflow with validation gates.

### Flow
0. `/bootstrap` — create and seed knowledge-base (once per project)
1. `/explore` — investigate and clarify requirements
2. `/propose <name>` — generate spec, design, tasks with knowledge-base rules
3. Human reviews artifacts, requests changes conversationally (edits to existing files)
4. `/implement <name>` — implement tasks one at a time (one branch per task)
5. `/validate <name>` — run validation gates (security, quality, architecture, testing)
6. `/review-findings <name>` — human accepts/rejects each finding
7. Create PR (task PR → feature branch), use `/pr-review` for comment-driven fixes
8. When all tasks done, final PR from feature branch → main

### Task States
`blocked` → `todo` → `in-progress` → `implemented` → `review` → `done`

- `implemented` means code is written but not yet validated
- `review` means findings exist and need human review
- `done` means validated and all findings resolved
- A task cannot start if any other task is `implemented` or `review` (enforce validation-first)
- When a task reaches `done`, all tasks blocked by it are checked and unblocked if ready

### Rule Selection
- The `ground_rules` field on each task is the single source of truth for which knowledge-base rules apply during `/implement` and `/validate`
- Rules are selected during `/propose` and reviewed by human during spec review

### Validation
- `validation_tools` in language file frontmatter are mandatory — every tool must run
- Deterministic tool findings (`source: tool`) are high-confidence
- LLM analysis findings (`source: llm`) are advisory — human decides
- All findings go through `/review-findings` where human is final authority

### Ground Rules
- All rules live in `knowledge-base/` — AI must reference these during spec generation and implementation
- `knowledge-base/` must exist — commands refuse to run without it
- Rejected validation findings may become new rules in knowledge-base/
- Every line of code must be reviewable by human — keep tasks small (max 20 files)
- AI explains architectural decisions against ground rules
- TDD/BDD: human defines test case names, AI implements test bodies
```

---

## Branching Strategy

```
main
 └── feat/<feature>                         # integration branch (created by first /implement)
      ├── feat/<feature>/001-task-name      # task branch (PR → feat/<feature>)
      ├── feat/<feature>/002-task-name      # task branch (PR → feat/<feature>)
      └── feat/<feature>/003-task-name      # task branch (PR → feat/<feature>)
                                             # final PR: feat/<feature> → main
```

- **Feature integration branch**: `feat/<feature>` — created from `main` when the first task starts
- **Task branches**: `feat/<feature>/<task-id>-<task-name>` — branched from `feat/<feature>`
- **Task PRs**: each task branch gets a PR into `feat/<feature>` after reaching `done` status
- **Final PR**: `feat/<feature>` → `main` when all tasks are complete
- **Strictly serial**: only one task branch is active at a time (enforced by `/implement` refusing to start if any task is `implemented` or `review`)
- Max 20 files per task PR

---

## Example Session

```
# 0. Bootstrap (once per project)
You: /bootstrap
     → Creates knowledge-base/ structure
     → Seeds rules from ~/.claude/rules/
     → Asks which languages, creates language files with validation_tools

# 1. Explore the problem
You: /explore
     "I need to add JWT authentication to the API"
     [conversation continues until requirements are clear]

# 2. Create specs
You: /propose add-jwt-auth

# 3. Review generated artifacts (spec, design, tasks)
You: [read and discuss, request changes conversationally — edits to existing files]

# 4. Implement first task
You: /implement add-jwt-auth
     → Creates integration branch feat/add-jwt-auth (from main)
     → Creates task branch feat/add-jwt-auth/001-jwt-token-service (from integration)
     → Implements task 001, sets status to `implemented`

# 5. Validate
You: /validate add-jwt-auth
     → Runs all mandatory tools from language file frontmatter
     → Runs LLM analysis gates
     → Generates reports/001-security.yaml, reports/001-code-quality.yaml, etc.
     → Sets task status to `review` (or `done` if clean)

# 6. Review findings
You: /review-findings add-jwt-auth
     → Accept fix for SQL injection finding → status back to `implemented`
     → Re-run /validate add-jwt-auth → clean → status to `done`
     → Blocked task 002 is now unblocked → set to `todo`

# 7. Create PR for task 001 (into feature branch)
You: /commit
You: gh pr create --base feat/add-jwt-auth

# 8. PR review loop
You: /pr-review
     → Fixes applied directly, no re-validation needed (reviewer handles it)

# 9. Next task
You: /implement add-jwt-auth
     → Picks task 002 (now `todo`), creates new branch from feat/add-jwt-auth

# 10. [repeat steps 4-9 for remaining tasks]

# 11. Final PR
You: gh pr create --base main --head feat/add-jwt-auth
     → Complete feature review
```

---

## Pre-Commit Hook

Each target project should have a pre-commit hook that validates any changed task files. This enforces `task-manager.sh` usage — even if Claude edits task files directly, invalid structure or transitions will be caught at commit time.

```bash
#!/usr/bin/env bash
# .git/hooks/pre-commit (or via pre-commit framework)

TASK_MANAGER="$HOME/.claude/scripts/task-manager.sh"

# Find changed task files (specs/*/tasks/*.md)
changed_tasks=$(git diff --cached --name-only --diff-filter=ACM | grep -E '^specs/.*/tasks/.*\.md$')

if [ -z "$changed_tasks" ]; then
  exit 0
fi

for task_file in $changed_tasks; do
  if ! "$TASK_MANAGER" validate "$task_file"; then
    echo "ERROR: Invalid task file: $task_file"
    echo "Task files must be updated via task-manager.sh"
    exit 1
  fi
done
```

---

## Setup Tutorial

### Part 1: Global Setup (once per machine)

These steps install the workflow tools that work across all projects.

#### 1. Install `yq`
```bash
brew install yq
```

#### 2. Create the slash commands
```bash
mkdir -p ~/.claude/commands
```

Create each command file in `~/.claude/commands/`:
- `bootstrap.md`
- `explore.md`
- `propose.md`
- `implement.md`
- `validate.md`
- `review-findings.md`
- `pr-review.md`

(Contents defined in Step 4 of this plan.)

#### 3. Create the helper script
```bash
mkdir -p ~/.claude/scripts
# Create ~/.claude/scripts/task-manager.sh (contents defined in Step 3 of this plan)
chmod +x ~/.claude/scripts/task-manager.sh
```

#### 4. Verify global setup
```bash
# Check yq is available
yq --version

# Check commands exist
ls ~/.claude/commands/*.md

# Check script is executable
~/.claude/scripts/task-manager.sh --help
```

### Part 2: Per-Project Setup (once per project)

These steps bootstrap the workflow in a target project.

#### 1. Run `/bootstrap` inside Claude Code
```
You: /bootstrap
```

This creates:
- `knowledge-base/` with seeded rules from `~/.claude/rules/`
- Language files with `validation_tools` frontmatter
- `_index.md` listing all rule files

#### 2. Add the CLAUDE.md
Copy the CLAUDE.md configuration from Step 6 of this plan into the project root.

#### 3. Set up the pre-commit hook
Copy the pre-commit hook (above) into `.git/hooks/pre-commit` and make it executable:
```bash
chmod +x .git/hooks/pre-commit
```

Or if using a pre-commit framework, add the equivalent configuration.

#### 5. Install validation tools
Check which languages were configured in `knowledge-base/languages/` and install the tools listed in their `validation_tools` frontmatter. For example:

**Rust:**
```bash
rustup component add clippy
cargo install cargo-tarpaulin cargo-audit cargo-deny
pip install semgrep  # or brew install semgrep
```

**TypeScript:**
```bash
npm install -D eslint jest
pip install semgrep
```

#### 6. Verify project setup
```bash
# Check knowledge-base exists
ls knowledge-base/_index.md

# Check CLAUDE.md exists
cat CLAUDE.md

# Check pre-commit hook
ls -la .git/hooks/pre-commit

# Test a validation tool
# (run one of the tools from your language file's validation_tools)
```

#### 7. Start working
```
You: /explore
     "I need to add [feature description]"
```

Follow the workflow stages from there.

---

## Verification

1. Run `/explore` and confirm it checks for knowledge-base, identifies relevant rules
2. Run `/propose test-feature` and confirm spec, design, tasks are generated with `ground_rules` references and correct initial statuses (`todo` / `blocked`)
3. Run `/implement test-feature` and confirm it: checks for unvalidated tasks, picks the right task, creates branch, sets status to `implemented`
4. Run `/validate test-feature` and confirm: all mandatory tools run, YAML reports appear in `specs/test-feature/reports/`, status set to `review` or `done`
5. Run `/review-findings test-feature` and confirm: accept/reject flow, status transitions, unblock check, knowledge-base updates
