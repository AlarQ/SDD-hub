# Knowledge Base Rules

These rules apply to all spec-driven workflow commands that use the dual knowledge base.

## Prerequisites

1. Check that `~/.claude/knowledge-base/` (general knowledge base) exists — if not, refuse and say: "General knowledge base not found. Run `setup.sh` from the dev-workflow repo first."
2. Check that `knowledge-base/` (project knowledge base) exists — if not, refuse and instruct the user to run `/bootstrap` first.

## Ground Rules Prefix Convention

When resolving `ground_rules` paths referenced in task files, use these prefixes:

- `general:` — resolves to `~/.claude/knowledge-base/` (e.g., `general:security/general.md`)
- `project:` — resolves to `knowledge-base/` (e.g., `project:languages/rust.md`)
- Unprefixed paths default to `project:` for backward compatibility

### Resolution Examples

| Prefix path | Claude Code resolves to | Copilot resolves to |
|---|---|---|
| `general:security/general.md` | `~/.claude/knowledge-base/security/general.md` | `knowledge-base/_general/security/general.md` |
| `project:languages/rust.md` | `knowledge-base/languages/rust.md` | `knowledge-base/languages/rust.md` |
| `languages/go.md` (unprefixed) | `knowledge-base/languages/go.md` | `knowledge-base/languages/go.md` |

## Reading Both Knowledge Bases

To identify applicable rules, read both index files:

- `~/.claude/knowledge-base/_index.md` — general rules (security, architecture, testing, style)
- `knowledge-base/_index.md` — project-specific rules (languages, conventions)

Project rules override general rules on the same topic.

## Important Rules

- **Never modify the general knowledge base** (`~/.claude/knowledge-base/`). New rules from `/review-findings` or rejected PR findings always go to the project knowledge base (`knowledge-base/`).
- **Both knowledge bases are mandatory** — commands that depend on ground rules must refuse to proceed if either is missing.
- **`ground_rules` on each task is the single source of truth** for which rules apply during `/implement` and `/validate`.
