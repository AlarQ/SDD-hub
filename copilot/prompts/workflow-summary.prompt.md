---
name: workflow-summary
description: Print a short summary of the spec-driven development workflow
agent: 'ask'
---

Print a short summary of the spec-driven development workflow rules.

This command takes no arguments. It does NOT read any project files — it prints a static reference card from memory.

## Output

Print the following reference card exactly:

---

## Spec-Driven Workflow — Quick Reference

### Commands
| # | Command | Purpose |
|---|---------|---------|
| 0 | `/bootstrap` | Create project knowledge-base (once per project) |
| 1 | `/explore` | Clarify requirements conversationally |
| 2 | `/propose <name>` | Generate spec, design, and tasks |
| 3 | *(conversation)* | Human reviews artifacts, requests changes |
| 4 | `/implement <name>` | Implement next eligible task (one at a time) |
| 5 | `/validate <name>` | Run validation gates (tools + agent analysis) |
| 6 | `/review-findings <name>` | Accept/reject each finding |
| 7 | `/ship <name>` | Commit, push, and PR into feature branch |
| 8 | `/pr-review` | Address PR review comments |
| 9 | `/spec-status <name>` | Dashboard: progress, dependencies, health |

<!-- State machine canonical source: scripts/task-manager.sh + plan.md. Keep in sync when editing. -->
### Task States
```
blocked -> todo -> in-progress -> implemented -> review -> done
```
- Only one task in-flight at a time — validate before starting the next
- `implemented` = code written, needs `/validate`
- `review` = findings exist, needs `/review-findings`
- `done` = validated and all findings resolved; needs `/ship`, then merge PR before next task

### Dual Knowledge Base
- **General KB** (`knowledge-base/_general/`) — universal rules (security, architecture, testing, style) installed via `setup-copilot.sh`
- **Project KB** (`knowledge-base/`) — project-specific rules (languages, conventions) created via `/bootstrap`
- Both are read by all commands; project rules override general rules on same topic
- `ground_rules` prefix convention: `general:security/general.md`, `project:languages/rust.md`
- Unprefixed paths default to `project:` (backward compatibility)
- New rules from `/review-findings` always go to the project KB

### Key Rules
- **Both knowledge bases are mandatory** — commands refuse without either
- **`ground_rules` on each task** = single source of truth for which rules apply
- **`validation_tools` in language files** = mandatory tools (every tool must run)
- **Tool findings** (`source: tool`) are high-confidence; **Agent findings** (`source: llm`) are advisory
- **Human is final authority** on all findings via `/review-findings`
- **Rejected findings can become new rules** in project knowledge-base (feedback loop)
- **Max 20 files per task** — keep PRs reviewable
- **TDD/BDD** — human names test cases, AI implements bodies

### Branching
```
main
 └── feat/<feature>                      # integration branch
      ├── feat/<feature>/001-task-name   # task PR -> feat/<feature>
      ├── feat/<feature>/002-task-name
      └── ...                            # final PR: feat/<feature> -> main
```

---
