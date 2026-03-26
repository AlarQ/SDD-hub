---
applyTo: "specs/*/tasks/*.md"
---

# Task File Format

Task files use YAML frontmatter with these required fields:

## Required Scalar Fields
- `id` — unique task identifier (e.g., "001")
- `name` — kebab-case task name (e.g., "implement-user-repository")
- `status` — one of: blocked, todo, in-progress, implemented, review, done
- `max_files` — maximum files this task can change (must be <= 20)

## Required Array Fields
- `ground_rules` — list of knowledge-base file paths that apply to this task
- `test_cases` — natural-language test case names (human defines, AI implements bodies)
- `blocked_by` — list of task IDs that must be done before this task can start (empty array if none)
- `estimated_files` — list of file paths that will be changed

## Valid Status Transitions
```
blocked -> todo
todo -> in-progress
in-progress -> implemented
implemented -> review, done
review -> implemented, done
done -> (terminal)
```

## Rules
- Never edit YAML frontmatter directly — use `./scripts/task-manager.sh set-status` for status changes
- If status is `blocked`, `blocked_by` must not be empty
- `ground_rules` paths must point to existing knowledge-base files
- `max_files` must be a number <= 20
