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
7. Create PR (task PR -> feature branch), use `/pr-review` for comment-driven fixes
8. When all tasks done, final PR from feature branch -> main

### Task States
`blocked` -> `todo` -> `in-progress` -> `implemented` -> `review` -> `done`

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
- Agent-based analysis findings (`source: llm`) are advisory — human decides
- All findings go through `/review-findings` where human is final authority

### Agent-Powered Validation Gates
`/validate` spawns specialized agents in parallel for advisory analysis:
- **security** → `Security Engineer` agent — OWASP, CWE, secrets, input validation
- **code-quality** → `code-quality-pragmatist` agent — over-engineering, DRY, modularity
- **architecture** → `Software Architect` agent (read-only) — DDD, layering, coupling
- **compliance** → `claude-md-compliance-checker` agent — CLAUDE.md + knowledge-base rules

Agents run alongside deterministic tools. Agent findings are advisory; tool findings are hard gates.

### Ground Rules
- All rules live in `knowledge-base/` — AI must reference these during spec generation and implementation
- `knowledge-base/` must exist — commands refuse to run without it
- Rejected validation findings may become new rules in knowledge-base/
- Every line of code must be reviewable by human — keep tasks small (max 20 files)
- AI explains architectural decisions against ground rules
- TDD/BDD: human defines test case names, AI implements test bodies
