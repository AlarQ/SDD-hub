Generate specification, design, and tasks for a feature.

Feature name: $ARGUMENTS

## Prerequisites
1. Check that `knowledge-base/` directory exists — if not, refuse and instruct the user to run `/bootstrap` first

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
