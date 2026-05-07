# Knowledge Base Rules

These rules apply to all spec-driven workflow commands that use the dual knowledge base.

## Prerequisites

1. Check that `~/.claude/knowledge-base/` (general knowledge base) exists — if not, refuse and say: "General knowledge base not found. Run `setup.sh` from the dev-workflow repo first."
2. Check that `knowledge-base/` (project knowledge base) exists — if not, refuse and instruct the user to run `/bootstrap` first.

## Ground Rules Prefix Convention

When resolving `ground_rules` paths referenced in task files, use these prefixes:

- `general:` — resolves to `~/.claude/knowledge-base/` (e.g., `general:security/general.md`)
- `project:` — resolves to `knowledge-base/` (e.g., `project:languages/rust.md`)
- `repo:<name>:` — resolves to `<bound-repo-path>/knowledge-base/` (e.g., `repo:frontend:languages/ts.md`). `<name>` must match a `repos[].name` entry in `specs/<feature>/config.yml`.
- Unprefixed paths default to `project:` for backward compatibility (single-repo flow only).
- **Vault mode (`spec_storage_mode: vault`):** bare `project:` (and unprefixed) paths are rejected. Specs hosted in a vault have no `knowledge-base/` next to them — every rule must come from `general:` or `repo:<name>:`. `task-manager.sh validate` enforces this at task-validation time.

### Resolution Examples

| Prefix path | Resolves to |
|---|---|
| `general:security/general.md` | `~/.claude/knowledge-base/security/general.md` |
| `project:languages/rust.md` | `knowledge-base/languages/rust.md` |
| `repo:frontend:languages/ts.md` | `<repos[name=frontend].path>/knowledge-base/languages/ts.md` |
| `languages/go.md` (unprefixed) | `knowledge-base/languages/go.md` |

## Reading Knowledge Bases

To identify applicable rules, read every applicable index file:

- `~/.claude/knowledge-base/_index.md` — general rules (security, architecture, testing, style)
- `knowledge-base/_index.md` — project-specific rules (languages, conventions). Skipped under `spec_storage_mode: vault` (no project KB lives next to the vault).
- For each entry in the spec's `repos[]`: `<repos[i].path>/knowledge-base/_index.md` — repo-specific rules. Multi-repo specs union all of these.

Project (or repo-specific) rules override general rules on the same topic. Repo-specific rules apply only to tasks whose `repo:` field matches that binding.

## Important Rules

- **Never modify the general knowledge base** (`~/.claude/knowledge-base/`). New rules from `/review-findings` or rejected PR findings always go to the project knowledge base (`knowledge-base/`). The sole exception is `/promote-rules`, which is explicitly designed to graduate project rules to the general KB.
- **Both knowledge bases are mandatory** — commands that depend on ground rules must refuse to proceed if either is missing.
- **`ground_rules` on each task is the single source of truth** for which rules apply during `/implement` and `/validate`.
