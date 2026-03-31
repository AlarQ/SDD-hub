Run validation gates on implemented code for a feature.

Feature name: $ARGUMENTS

## Prerequisites
1. Check that `knowledge-base/` directory exists — if not, refuse and instruct the user to run `/bootstrap` first
2. Read tasks from `specs/$ARGUMENTS/tasks/` — find tasks with `status: implemented`
   - If no tasks have `status: implemented`, report and stop
   - If more than one task has `status: implemented`, report an error: "Multiple tasks are at `implemented` status — only one task should be in flight at a time. Check task state integrity."
   - Validate exactly one task

## Phase 1: Deterministic Tools (hard gates)
For each task with `status: implemented`:
1. Read the task's `ground_rules` to identify language files
2. Extract `validation_tools` from the frontmatter of each referenced language file
3. Run **every** listed tool — skipping a tool is not allowed
   - If a tool is missing or fails to install, report it as an error finding
4. Collect all tool outputs and convert findings into the report schema

## Phase 2: Agent-Powered Analysis (advisory)
Spawn specialized agents **in parallel** to analyze code against knowledge-base rules. Each agent receives:
- The task file path and changed files (from `estimated_files` or git diff)
- All `ground_rules` files referenced in the task
- The project's `CLAUDE.md` and relevant `knowledge-base/` files

### Independent Verification Rule
Each agent gate operates independently. No agent should trust or defer to another agent's results. If the security agent says code is safe, the architecture agent must still independently verify security-relevant architectural decisions. If code-quality says a function is well-structured, compliance must still independently check it against CLAUDE.md rules. Redundant findings are acceptable — missed findings are not.

### Agent Gates
Spawn all four agents concurrently using the Agent tool:

1. **security** → `Security Engineer` agent (`engineering-security-engineer`)
   - Analyze code for OWASP Top 10, CWE Top 25, input validation, secrets exposure
   - Check against `knowledge-base/security/` rules
   - Each finding must include: severity, file, lines, description, fix_proposal

2. **code-quality** → `code-quality-pragmatist` agent
   - Check for over-engineering, unnecessary complexity, DRY violations, function size, modularity
   - Check against `knowledge-base/style/` rules
   - Each finding must include: severity, file, lines, description, fix_proposal

3. **architecture** → `Software Architect` agent (`engineering-software-architect`) — **read-only**
   - Verify structural compliance, DDD boundaries, hexagonal layering, module coupling
   - Check against `knowledge-base/architecture/` rules
   - Each finding must include: severity, file, lines, description, fix_proposal

4. **compliance** → `claude-md-compliance-checker` agent
   - Verify code adheres to project CLAUDE.md instructions and knowledge-base conventions
   - Check language-specific rules from `knowledge-base/languages/`
   - Each finding must include: severity, file, lines, description, fix_proposal

### Agent Output Contract
Each agent must return findings in the report schema (below). When constructing the prompt for each agent, instruct it to output findings as a YAML list matching the report schema. Mark all agent findings with `source: llm`.

### Collecting Results
After all agents complete, merge their findings into per-gate YAML reports. If an agent errors or times out, record a single `error` finding for that gate (do not block other gates).

## Output
One YAML report per gate to `specs/$ARGUMENTS/reports/{task-id}-{gate}.yaml`

## Gate Aggregation (Triple-Gate Rule)
Before determining the final status, verify ALL gates produced a report:
- If any gate has `status: error` (agent timed out or crashed), that gate must be re-run before proceeding. Do not allow shipping with an incomplete gate.
- If any gate has `status: findings` with unresolved items, the task goes to `review`.
- Only when ALL gates report `status: pass` (zero findings each) is the task eligible for `done`.

## Status Update
- If any gate has `status: error`: report which gate(s) failed and instruct: "Re-run `/validate $ARGUMENTS` to retry the failed gate(s)."
- If any findings exist across any gate: run `~/.claude/scripts/task-manager.sh set-status <task-file> review`
- If zero findings across all gates and all gates have `status: pass`:
  1. Run `~/.claude/scripts/task-manager.sh set-status <task-file> done`
  2. Run `~/.claude/scripts/task-manager.sh unblock specs/$ARGUMENTS/tasks/`
  3. Delete all reports (`rm -rf specs/$ARGUMENTS/reports/`)
  4. Remind user to run `/ship $ARGUMENTS` to commit, push, and create the PR

Report schema:
- gate: <gate-name>
- task_id: <id>
- status: pass | findings | error
- findings: list of {id, severity, category, title, description, file, lines, code_snippet, fix_proposal, review_status: pending, source: tool|llm}

Gates:
- **security**: semgrep + language audit tools + `Security Engineer` agent for knowledge-base/security/ rules
- **code-quality**: language lint tools + `code-quality-pragmatist` agent for DRY, function size, modularity
- **architecture**: `Software Architect` agent (read-only, check against knowledge-base/architecture/)
- **compliance**: `claude-md-compliance-checker` agent (check against CLAUDE.md + knowledge-base/languages/)
- **testing**: language test/coverage tools (deterministic only — no agent gate)
