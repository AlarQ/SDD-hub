Run validation gates on implemented code for a feature.

Feature name: $ARGUMENTS

## Prerequisites
1. Check that `knowledge-base/` directory exists — if not, refuse and instruct the user to run `/bootstrap` first
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
- If any findings exist across any gate: run `~/.claude/scripts/task-manager.sh set-status <task-file> review`
- If zero findings across all gates: run `~/.claude/scripts/task-manager.sh set-status <task-file> done`, then run `~/.claude/scripts/task-manager.sh unblock specs/$ARGUMENTS/tasks/`

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
