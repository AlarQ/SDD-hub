# Project Instructions

## Workflow
This project uses a custom spec-driven development workflow with validation gates.

### Flow
0. `/bootstrap` — create `.workflow.yml` with inline `gate_pool:` (once per project)
1. `/explore` — investigate and clarify requirements
2. `/propose <name>` — generate spec, design, tasks with KB rules
3. Human reviews artifacts, requests changes conversationally (edits to existing files)
4. `/implement <name>` — implement tasks one at a time (one branch per task)
5. `/validate <name>` — run validation gates (security, code-quality, architecture, compliance, testing)
6. `/review-and-ship <name>` — human accepts/rejects each finding, then the task ships inline (commit, push, PR ready). A clean `/validate` ships the task itself with no findings step.
7. `/learn-from-reports <name>` — mine reports for general-KB rules (task already shipped); use `/pr-review` for agent-powered review and comment-driven fixes on the open PR
8. Merge the task PR, then `/implement` the next task. When all tasks done, final PR from feature branch -> main

<!-- State machine canonical source: scripts/task-manager.sh + plan.md. Keep in sync when editing. -->
### Task States
`blocked` -> `todo` -> `in-progress` -> `implemented` -> `review` -> `done`

- `implemented` means code is written but not yet validated
- `review` means findings exist and need human review
- `done` means validated and all findings resolved
- A task cannot start if any other task is `implemented` or `review` (enforce validation-first)
- When a task reaches `done`, all tasks blocked by it are checked and unblocked if ready

### Single Knowledge Base
One knowledge base (ADR-0002 in the dev-workflow repo collapsed the old dual layer):

- **General KB** (`$WF_GENERAL_KB/`) — all KB rules. Path is configured per-repo via `general_kb_path` in `.workflow.yml` (required key, no default) and exported by `scripts/config-loader.sh`. Typically points at a master-brain / shared vault. Contains security, architecture, testing, style, plus learned language/convention rules. There is no per-repo `knowledge-base/` directory.

Read by all commands. The feedback loop (`/review-and-ship`, `/learn-from-reports`, `/capture-rule`) writes learned rules here.

#### ground_rules Paths
The `ground_rules` field on each task is **bare `$WF_GENERAL_KB`-relative paths** (e.g. `security/general.md`, `languages/rust.md`). Legacy `general:`/`project:`/`repo:<name>:` prefixes are stripped by a migration shim (one-time per-process deprecation warning) and resolved under `$WF_GENERAL_KB`.

### Rule Selection
- The `ground_rules` field on each task is the single source of truth for which knowledge-base rules apply during `/implement` and `/validate`
- Rules are selected during `/propose` and reviewed by human during spec review

### Validation
- Gates in `.workflow.yml gate_pool:` with `blocking: true` are mandatory for matching `ground_rules` — every gate must run
- Deterministic tool findings (`source: tool`) are high-confidence
- Agent-based analysis findings (`source: llm`) are advisory — human decides
- All findings go through `/review-and-ship` where human is final authority

### Agent-Powered Validation Gates
`/validate` spawns specialized agents in parallel for advisory analysis:
- **security** → `Security Engineer` agent — OWASP, CWE, secrets, input validation (checks general-KB security rules)
- **code-quality** → `Code Quality Pragmatist` agent — over-engineering, DRY, modularity (checks general-KB style rules)
- **architecture** → `Software Architect` agent (read-only) — DDD, layering, coupling (checks general-KB architecture rules)
- **compliance** → `CLAUDE.md Compliance Checker` agent — CLAUDE.md + general-KB conventions and languages

Agents run alongside deterministic tools. Agent findings are advisory; tool findings are hard gates.

### Agent-Assisted Proposal
`/propose` spawns the `Software Architect` agent during design.md generation:
- Evaluates trade-offs for each major architectural decision
- Produces Architecture Decision Records (ADRs) embedded in design.md
- Flags architectural risks and patterns that may not scale
- Main command still owns spec.md and task decomposition

### Agent-Assisted Implementation
`/implement` integrates two agents into the implementation flow:
- **On error/test failure** → auto-spawns `Ultrathink Debugger` agent with error context for root cause analysis and fix proposals
- **Post-implementation** → spawns `Code Quality Pragmatist` agent for a pre-validation sanity check; high/critical issues go through human accept/reject before marking task as implemented

### Agent-Powered PR Review
`/pr-review` spawns the `Code Reviewer` agent to proactively analyze the PR diff before responding to human comments:
- Reviews for correctness, security, maintainability, performance, and testing gaps
- Findings are presented to human for accept/reject before applying fixes
- Human PR comments are handled separately after agent review

### Ground Rules
- All KB rules live in `$WF_GENERAL_KB/` — single knowledge base
- `$WF_GENERAL_KB` must resolve — commands refuse to run without it (loader exit 2)
- Rejected validation findings may become new rules in `$WF_GENERAL_KB/`
- New rules go to the general KB (no project-KB layer)
- Every line of code must be reviewable by human — keep tasks small (max 20 files)
- AI explains architectural decisions against ground rules
- TDD/BDD: human defines test case names, AI implements test bodies
