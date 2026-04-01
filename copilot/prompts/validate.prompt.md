---
name: validate
description: Run validation gates on implemented code for a feature
agent: 'agent'
argument-hint: "feature name"
---

Run validation gates on implemented code for a feature.

The user should provide the feature name in their message.

## Prerequisites
1. Check that `knowledge-base/_general/` (general) exists — if not, refuse and say: "General knowledge base not found. Run `setup-copilot.sh` from the dev-workflow repo first."
2. Check that `knowledge-base/` (project) exists with project-specific files — if not, refuse and instruct the user to run `/bootstrap` first
3. Read tasks from `specs/<feature>/tasks/` — find tasks with `status: implemented`
   - If no tasks have `status: implemented`, report and stop
   - If more than one task has `status: implemented`, report an error: "Multiple tasks are at `implemented` status — only one task should be in flight at a time. Check task state integrity."
   - Validate exactly one task

## Ground Rules Resolution
Resolve `ground_rules` paths using the prefix convention:
- `general:` prefix → read from `knowledge-base/_general/`
- `project:` prefix → read from `knowledge-base/`
- Unprefixed paths → default to `project:` (backward compatibility)

## Phase 1: Deterministic Tools (hard gates)
For each task with `status: implemented`:
1. Read the task's `ground_rules` to identify language files (project KB `languages/` only — tools are project-specific)
2. Extract `validation_tools` from the frontmatter of each referenced language file
3. Run **every** listed tool — skipping a tool is not allowed
   - If a tool is missing or fails to install, report it as an error finding
4. Collect all tool outputs and convert findings into the report schema

## Phase 2: Agent-Powered Analysis (advisory)
After deterministic tools complete, invoke specialized agents to analyze code against knowledge-base rules. Each agent receives:
- The task file path and changed files (from `estimated_files` or git diff)
- All `ground_rules` files referenced in the task (resolved from both KBs using prefix convention)
- The project's CLAUDE.md or copilot-instructions.md and relevant knowledge-base files from both general and project KBs

### Independent Verification Rule
Each agent gate operates independently. No agent should trust or defer to another agent's results. If the security agent says code is safe, the architecture agent must still independently verify security-relevant architectural decisions. If code-quality says a function is well-structured, compliance must still independently check it against project instructions. Redundant findings are acceptable — missed findings are not.

### Agent Gates
Invoke each agent one at a time (Copilot does not support parallel agent invocation):

1. **security** — Invoke `@security-engineer`
   - Analyze code for OWASP Top 10, CWE Top 25, input validation, secrets exposure
   - Check against `knowledge-base/_general/security/` rules AND `knowledge-base/security/` rules (if project has security overrides)
   - Each finding must include: severity, file, lines, description, fix_proposal

2. **code-quality** — Invoke `@code-quality`
   - Check for over-engineering, unnecessary complexity, DRY violations, function size, modularity
   - Check against `knowledge-base/_general/style/` rules AND `knowledge-base/style/` rules (if project has style overrides)
   - Each finding must include: severity, file, lines, description, fix_proposal

3. **architecture** — Invoke `@software-architect` (read-only)
   - Verify structural compliance, DDD boundaries, hexagonal layering, module coupling
   - Check against `knowledge-base/_general/architecture/` rules AND `knowledge-base/architecture/` rules (if project has architecture overrides)
   - Each finding must include: severity, file, lines, description, fix_proposal

4. **compliance** — Invoke `@compliance-checker`
   - Verify code adheres to project CLAUDE.md / copilot-instructions and knowledge-base conventions
   - Check language-specific rules from `knowledge-base/languages/` and project conventions from `knowledge-base/conventions/`
   - Each finding must include: severity, file, lines, description, fix_proposal

### Agent Output Contract
Each agent must return findings in the report schema (below). When constructing the prompt for each agent, instruct it to output findings as a YAML list matching the report schema. Mark all agent findings with `source: llm`.

### Collecting Results
After all agents complete, merge their findings into per-gate YAML reports. If an agent errors or is unavailable, record a single `error` finding for that gate (do not block other gates).

## Output
One YAML report per gate to `specs/<feature>/reports/{task-id}-{gate}.yaml`

## Gate Aggregation (Triple-Gate Rule)
Before determining the final status, verify ALL gates produced a report:
- If any gate has `status: error` (agent errored or was unavailable), that gate must be re-run before proceeding. Do not allow shipping with an incomplete gate.
- If any gate has `status: findings` with unresolved items, the task goes to `review`.
- Only when ALL gates report `status: pass` (zero findings each) is the task eligible for `done`.

## Status Update
- If any gate has `status: error`: report which gate(s) failed and instruct: "Re-run `/validate <feature>` to retry the failed gate(s)."
- If any findings exist across any gate: run `./scripts/task-manager.sh set-status <task-file> review`
- If zero findings across all gates and all gates have `status: pass`:
  1. Run `./scripts/task-manager.sh set-status <task-file> done`
  2. Run `./scripts/task-manager.sh unblock specs/<feature>/tasks/`
  3. Delete all reports (`rm -rf specs/<feature>/reports/`)
  4. Remind user to run `/ship <feature>` to commit, push, and create the PR

Report schema:
- gate: <gate-name>
- task_id: <id>
- status: pass | findings | error
- findings: list of {id, severity, category, title, description, file, lines, code_snippet, fix_proposal, review_status: pending, source: tool|llm}

Gates:
- **security**: semgrep + language audit tools + `@security-engineer` agent for general and project security rules
- **code-quality**: language lint tools + `@code-quality` agent for DRY, function size, modularity
- **architecture**: `@software-architect` agent (read-only, check against general and project architecture rules)
- **compliance**: `@compliance-checker` agent (check against project instructions + knowledge-base conventions and languages)
- **testing**: language test/coverage tools (deterministic only — no agent gate)
