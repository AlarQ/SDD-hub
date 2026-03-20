# Spec-Driven AI Development Workflow

## Context

This project builds a disciplined, spec-driven AI development workflow using Claude Code slash commands, CLAUDE.md, and markdown/YAML files. The entire system is file-based with zero external dependencies.

**How this differs from existing SDD tools on the market:**
Most spec-driven tools focus on the spec generation and implementation phases. This workflow goes further — it adds automated validation gates, interactive finding review with accept/reject controls, and a knowledge-base feedback loop where rejected findings become new rules. The validation and review stages are where this workflow's real value lives, and no existing tool covers them.

---

## Core Principles

1. **Every line reviewed** — no exceptions, human reviews all code (AI or human-written) at PR stage (GitHub diff). Validation gates (stages 5-6) are a pre-filter that surfaces flagged issues before the full line-by-line review.
2. **Architectural decisions at spec level** — not during implementation
3. **AI explains decisions** — against ground rules, not just outputs code
4. **TDD/BDD** — human defines test cases in natural language, AI implements
5. **Code must be testable** — dependency injection, modularity, pure functions
6. **Feedback loop** — validated findings feed back into rule context; the system learns

---

## Workflow Stages

| Stage | Command | What It Does |
|-------|---------|--------------|
| 1. Requirements | `/explore` | Clarify requirements, refine PRD, identify ground rules |
| 2. Spec Generation | `/propose <name>` | Generate spec, design, tasks with knowledge-base rules |
| 3. Spec Review | (manual) | Human reviews generated artifacts, requests changes |
| 4. Implementation | `/implement <name>` | Implement one task at a time |
| 5. Automated Validation | `/validate <name>` | Run deterministic tools + LLM analysis gates |
| 6. Finding Review | `/review-findings <name>` | Human accepts/rejects each finding |
| 7. PR Creation | `/commit` + `gh` CLI | Standard Claude Code + GitHub CLI |
| 8. PR Review Loop | `/pr-review` | Fetch PR comments, propose fixes |

All commands that operate on a feature take the feature name as `$ARGUMENTS`.

---

## Implementation

### Step 1: Directory Structure

```
project-root/
├── .claude/
│   └── commands/         # Slash commands
├── knowledge-base/       # Ground rules (security, arch, testing, etc.)
│   ├── security/
│   ├── architecture/
│   ├── languages/
│   ├── testing/
│   └── style/
└── specs/                # Feature specs, tasks, reports
```

### Step 2: Bootstrap Knowledge Base

Start minimal — the feedback loop (rejected findings become new rules) will grow the knowledge base organically.

```
knowledge-base/
├── _index.md
├── security/
│   ├── general.md               # OWASP basics, input validation, secret handling
│   ├── authentication.md
│   └── data-handling.md
├── architecture/
│   ├── general.md               # Hexagonal/DDD boundaries, dependency direction
│   └── ddd.md
├── languages/
│   ├── rust.md                  # Idiomatic error handling, ownership, unsafe rules
│   ├── typescript.md            # Strict mode, functional patterns, no `any`
│   └── python.md
├── testing/
│   ├── principles.md            # TDD/BDD ground rules, Given/When/Then, coverage
│   └── integration.md
└── style/
    └── general.md               # Naming, module size (<100 lines), function size (<50 lines)
```

**Source material:** Migrate relevant rules from `~/.claude/rules/code-quality.md` and `~/.claude/rules/security-patterns.md`. These already contain validated preferences and should form the initial seed.

**Target:** ~5-10 rules per file. Keep rules specific and actionable — each rule should be something a validation gate can check against.

### Step 3: Slash Commands

#### `.claude/commands/explore.md`

Clarify and refine requirements before spec work begins.

```markdown
Explore and clarify requirements for a new feature or change.

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

#### `.claude/commands/propose.md`

Generate the full spec package from a PRD.

```markdown
Generate specification, design, and tasks for a feature.

Feature name: $ARGUMENTS

1. Read `specs/$ARGUMENTS/prd.md` if it exists, otherwise use conversation context
2. Read all applicable `knowledge-base/` rules (check `knowledge-base/_index.md`)

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
- Split implementation into small tasks following this schema:

```yaml
---
id: "NNN"
name: "{task-name}"
status: "todo"
blocked_by: []
max_files: 20
estimated_files: []
test_cases:
  - "should ..."
  - "should ..."
ground_rules:
  - knowledge-base/...
  - knowledge-base/...
---

## Description
[What this task implements]

## Ground Rules Applied
[List referenced knowledge-base files and why they apply]

## Implementation Notes
[AI fills this during /implement]
```

## Constraints
- Max 20 files per task
- Each task references applicable `knowledge-base/` rules
- Each task includes natural-language test cases (human defines names, AI implements bodies later)
- Tasks ordered by dependency (`blocked_by` fields)
- AI explains architectural decisions against ground rules, not just outputs code
- Tasks must be small enough for meaningful human code review

Present all generated artifacts for human review before proceeding to implementation.
```

#### `.claude/commands/implement.md`

Implement one task at a time.

```markdown
Implement the next task for a feature.

Feature name: $ARGUMENTS

1. Read `specs/$ARGUMENTS/tasks/` directory
2. Find the next task with `status: todo` whose `blocked_by` dependencies are all `done`
   - If no eligible task found, report which tasks are blocked and why
3. Update the task's status to `in-progress`
4. Read the task's referenced `knowledge-base/` rules
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
9. Update the task's status to `done`

IMPORTANT:
- Do NOT proceed to the next task automatically
- Remind the user to run `/validate $ARGUMENTS` before continuing
- Human must review and validate before the next task starts
```

#### `.claude/commands/validate.md`

Run all validation gates after implementation.

```markdown
Run validation gates on implemented code for a feature.

Feature name: $ARGUMENTS

1. Read tasks from `specs/$ARGUMENTS/tasks/` — identify recently completed tasks
2. Identify changed files and their languages (Rust / TypeScript)

## Phase 1: Deterministic Tools
Run static analysis tools and collect structured output:

### Rust files:
- `cargo clippy -- -D warnings` — lint and code quality
- `cargo audit` — dependency vulnerability scan
- `cargo deny check` — license and advisory checks
- `cargo test` — run tests, capture failures
- `cargo tarpaulin --out json` — test coverage (if available)

### TypeScript files:
- `npx eslint --format json <files>` — lint + eslint-plugin-security findings
- `npm audit --json` — dependency vulnerability scan
- `npx vitest run --reporter json` — run tests, capture failures
- `npx vitest --coverage --reporter json` — test coverage

### Cross-language:
- `semgrep --config auto --json <files>` — security patterns (OWASP, injection, etc.)

Collect all tool outputs and convert findings into the report schema.

## Phase 2: LLM Supplement
Read all applicable knowledge-base/ rules referenced in the tasks. For each gate, analyze code against rules for issues tools can't catch:
- **Architecture**: Structural compliance, DDD boundaries, hexagonal layering
- **Code quality**: DRY violations, function reuse, module coupling
- **Testing**: Test quality, missing edge cases, BDD format compliance
- **Knowledge-base compliance**: Any rule violations not caught by tools

## Output
One YAML report per gate to `specs/$ARGUMENTS/reports/{task-id}-{gate}.yaml`

Report schema:
- gate: <gate-name>
- task_id: <id>
- status: pass | findings | error
- findings: list of {id, severity, category, title, description, file, lines, code_snippet, fix_proposal, review_status: pending, source: tool|llm}

Gates:
- **security**: semgrep + cargo-audit/npm-audit + LLM for knowledge-base/security/ rules
- **code-quality**: clippy/eslint + LLM for DRY, function size, modularity
- **architecture**: LLM-only (check against knowledge-base/architecture/)
- **testing**: cargo-test/vitest + coverage tools + LLM for test quality review
```

#### `.claude/commands/review-findings.md`

Interactive finding review with accept/reject and feedback loop.

```markdown
Walk through validation findings interactively.

Feature name: $ARGUMENTS

1. Read all pending reports from `specs/$ARGUMENTS/reports/`
2. For each finding with review_status: pending:
   - Present: severity, title, description, code snippet, fix proposal
   - Ask: Accept or Reject?
   - If Accept: apply the fix, update review_status to "accepted"
   - If Reject: ask for reasoning, update review_status to "rejected", set review_notes
   - If Reject + new rule needed: create/update the relevant knowledge-base/ file, set rule_added: true
3. Re-run validation on accepted fixes to confirm they resolve the finding
4. Report summary: X accepted, Y rejected, Z new rules added
```

#### `.claude/commands/pr-review.md`

Fetch PR comments and generate structured fix proposals.

```markdown
Fetch and respond to PR review comments.

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

### Step 4: Schemas

#### Task File (`tasks/NNN-{task-name}.md`)

```yaml
---
id: "001"
name: "implement-user-repository"
status: "todo"                        # todo | in-progress | done | blocked
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
  - knowledge-base/testing/unit.md
  - knowledge-base/languages/rust.md
---

## Description

Implement the user repository trait and Postgres implementation.

## Ground Rules Applied

- knowledge-base/architecture/ddd.md
- knowledge-base/testing/unit.md
- knowledge-base/languages/rust.md

## Implementation Notes

AI explains decisions made during implementation here.
```

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

#### Task State Machine

```
todo → in-progress → [validation] → done
                   ↘ blocked (dependency not met)
                   ↘ in-progress (findings to fix, loop back)
```

### Step 5: CLAUDE.md Configuration

```markdown
# Project Instructions

## Workflow
This project uses a custom spec-driven development workflow with validation gates.

### Flow
1. `/explore` — investigate and clarify requirements
2. `/propose <name>` — generate spec, design, tasks with knowledge-base rules
3. Human reviews artifacts, requests changes conversationally
4. `/implement <name>` — implement tasks one at a time
5. `/validate <name>` — run validation gates (security, quality, architecture, testing)
6. `/review-findings <name>` — human accepts/rejects each finding
7. Create PR, use `/pr-review` for comment-driven fixes

### Ground Rules
- All rules live in `knowledge-base/` — AI must reference these during spec generation and implementation
- Rejected validation findings may become new rules in knowledge-base/
- Every line of code must be reviewable by human — keep tasks small (max 20 files)
- AI explains architectural decisions against ground rules
- TDD/BDD: human defines test case names, AI implements test bodies
```

### Step 6: Hooks Configuration

In `.claude/settings.json`:

```json
{
  "hooks": {
    "postToolCall": [
      {
        "matcher": "Edit|Write",
        "command": "echo 'Files changed — run /validate after implementation is complete'"
      }
    ]
  }
}
```

---

## Example Session

```
# 1. Explore the problem
You: /explore
     "I need to add JWT authentication to the API"
     [conversation continues until requirements are clear]

# 2. Create specs
You: /propose add-jwt-auth

# 3. Review generated artifacts (spec, design, tasks)
You: [read and discuss, request changes]

# 4. Implement
You: /implement add-jwt-auth

# 5. Validate
You: /validate add-jwt-auth
     → Generates reports/001-security.yaml, reports/001-code-quality.yaml, etc.

# 6. Review findings
You: /review-findings add-jwt-auth
     → Accept fix for SQL injection finding
     → Reject false positive, add reasoning, new rule added to knowledge-base/

# 7. Create PR
You: /commit
You: gh pr create ...

# 8. PR review loop
You: /pr-review
```

---

## Verification

1. Run `/explore` and confirm it identifies relevant knowledge-base rules
2. Run `/propose test-feature` and confirm spec, design, tasks are generated with rule references
3. Run `/implement test-feature` and confirm it picks the right task and follows the spec
4. Run `/validate test-feature` and confirm YAML reports appear in `specs/test-feature/reports/`
5. Run `/review-findings test-feature` and confirm accept/reject flow with knowledge-base updates
