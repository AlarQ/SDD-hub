# Project Instructions

## Workflow
This project uses a custom spec-driven development workflow with validation gates. Slash commands are available as Copilot prompt files (type `/` in chat). Specialized agents are available via `@agent-name`.

### Flow
0. `/bootstrap` — create project-specific knowledge-base (once per project)
1. `/explore` — investigate and clarify requirements (user-centric discovery)
2. `/propose <name>` — generate spec, design, tasks with knowledge-base rules
3. Human reviews artifacts, requests changes conversationally (edits to existing files)
4. `/implement <name>` — implement tasks one at a time (one branch per task)
5. `/validate <name>` — run validation gates (security, quality, architecture, testing)
6. `/review-findings <name>` — human accepts/rejects each finding
7. `/ship <name>` — commit, push, and create PR (task PR -> feature branch), use `/pr-review` for agent-powered review
8. When all tasks done, final PR from feature branch -> main

### Utility Commands
- `/continue-task <name>` — resume interrupted work (detects phase by artifacts)
- `/research` — anti-hallucination mode with citation discipline (epistemic honesty, quote-grounded responses)

<!-- State machine canonical source: scripts/task-manager.sh + plan.md. Keep in sync when editing. -->
### Task States
`blocked` -> `todo` -> `in-progress` -> `implemented` -> `review` -> `done`

- `implemented` means code is written but not yet validated
- `review` means findings exist and need human review
- `done` means validated and all findings resolved
- A task cannot start if any other task is `implemented` or `review` (enforce validation-first)
- When a task reaches `done`, all tasks blocked by it are checked and unblocked if ready

### Dual Knowledge Base
Two knowledge bases work together:

- **General KB** (`knowledge-base/_general/`) — universal rules installed by `setup-copilot.sh`. Contains security, architecture, testing, and style rules that apply to all projects.
- **Project KB** (`knowledge-base/`) — project-specific rules created via `/bootstrap`. Contains language files (with `validation_tools`) and conventions discovered via the feedback loop.

Both are read by all commands. Project rules override general rules on the same topic.

#### ground_rules Prefix Convention
The `ground_rules` field on each task uses prefixes to reference rules from either KB:
- `general:security/general.md` → resolves to `knowledge-base/_general/security/general.md`
- `project:languages/rust.md` → resolves to `knowledge-base/languages/rust.md`
- Unprefixed paths default to `project:` for backward compatibility

### Rule Selection
- The `ground_rules` field on each task is the single source of truth for which knowledge-base rules apply during `/implement` and `/validate`
- Rules are selected during `/propose` and reviewed by human during spec review

### Validation
- `validation_tools` in language file frontmatter are mandatory — every tool must run
- Deterministic tool findings (`source: tool`) are high-confidence
- Agent-based analysis findings (`source: llm`) are advisory — human decides
- All findings go through `/review-findings` where human is final authority

### Agent-Powered Validation Gates
`/validate` invokes specialized agents for advisory analysis:
- **security** -> `@security-engineer` — OWASP, CWE, secrets, input validation (checks both general and project security rules)
- **code-quality** -> `@code-quality` — over-engineering, DRY, modularity (checks both general and project style rules)
- **architecture** -> `@software-architect` (read-only) — DDD, layering, coupling (checks both general and project architecture rules)
- **compliance** -> `@compliance-checker` — project instructions + knowledge-base conventions and languages

Agents run alongside deterministic tools. Agent findings are advisory; tool findings are hard gates.

### Triple-Gate Rule
ALL validation gates must produce a report with `status: pass` before a task can move to `done`:
- If any gate has `status: error` (agent errored or unavailable), it must be re-run
- If any gate has `status: findings` with unresolved items, the task stays at `review`
- Each agent gate operates independently — no agent trusts or defers to another's results
- `/ship` also checks for unresolved gate findings as a safety net

### Agent-Assisted Proposal
`/propose` invokes `@software-architect` during design.md generation:
- Evaluates trade-offs for each major architectural decision
- Produces Architecture Decision Records (ADRs) embedded in design.md
- Flags architectural risks and patterns that may not scale
- Main prompt still owns spec.md and task decomposition

### Agent-Assisted Implementation
`/implement` integrates two agents into the implementation flow:
- **On error/test failure** -> invoke `@ultrathink-debugger` with error context for root cause analysis and fix proposals
- **Post-implementation** -> invoke `@code-quality` for a pre-validation sanity check; high/critical issues go through human accept/reject before marking task as implemented

### Agent-Powered PR Review
`/pr-review` invokes `@code-reviewer` to proactively analyze the PR diff before responding to human comments:
- Reviews for correctness, security, maintainability, performance, and testing gaps
- Findings are presented to human for accept/reject before applying fixes
- Human PR comments are handled separately after agent review

### Ground Rules
- General rules live in `knowledge-base/_general/` — universal across all projects
- Project rules live in `knowledge-base/` — specific to this repository
- Both must exist — commands refuse to run without either
- Rejected validation findings may become new rules in project knowledge-base/
- New rules always go to the project KB, never the general KB
- Every line of code must be reviewable by human — keep tasks small (max 20 files)
- AI explains architectural decisions against ground rules
- TDD/BDD: human defines test case names, AI implements test bodies

### Task State Machine Script
Task status changes go through `./scripts/task-manager.sh`:
- `./scripts/task-manager.sh set-status <task-file> <status>` — change task status
- `./scripts/task-manager.sh next <tasks-dir>` — find next eligible task
- `./scripts/task-manager.sh unblock <tasks-dir>` — unblock tasks whose dependencies are done
- `./scripts/task-manager.sh status <tasks-dir>` — show dashboard with health diagnostics
- Never edit task YAML frontmatter directly — always use the script

### Branching Strategy
```
main
 └── feat/<feature>                      # integration branch
      ├── feat/<feature>/001-task-name   # task PR -> feat/<feature>
      ├── feat/<feature>/002-task-name
      └── ...                            # final PR: feat/<feature> -> main
```
