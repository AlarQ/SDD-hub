Print a short summary of the spec-driven development workflow rules.

This command takes no arguments. It does NOT read any project files — it prints a static reference card from memory.

## Output

Print the following reference card exactly:

---

## Spec-Driven Workflow — Quick Reference

### Commands
| # | Command | Purpose |
|---|---------|---------|
| 0 | `/bootstrap` | Create knowledge-base (once per project) |
| 1 | `/explore` | Clarify requirements conversationally |
| 2 | `/propose <name>` | Generate spec, design, and tasks |
| 3 | *(conversation)* | Human reviews artifacts, requests changes |
| 4 | `/implement <name>` | Implement next eligible task (one at a time) |
| 5 | `/validate <name>` | Run validation gates (tools + LLM analysis) |
| 6 | `/review-findings <name>` | Accept/reject each finding |
| 7 | `/commit` + `gh pr create` | PR per task into feature branch |
| 8 | `/pr-review` | Address PR review comments |
| 9 | `/spec-status <name>` | Dashboard: progress, dependencies, health |

### Task States
```
blocked → todo → in-progress → implemented → review → done
```
- Only one task in-flight at a time — validate before starting the next
- `implemented` = code written, needs `/validate`
- `review` = findings exist, needs `/review-findings`
- `done` = validated and all findings resolved; unblocks dependent tasks

### Key Rules
- **Knowledge-base is mandatory** — all commands refuse without `knowledge-base/`
- **`ground_rules` on each task** = single source of truth for which rules apply
- **`validation_tools` in language files** = mandatory tools (every tool must run)
- **Tool findings** (`source: tool`) are high-confidence; **LLM findings** (`source: llm`) are advisory
- **Human is final authority** on all findings via `/review-findings`
- **Rejected findings can become new rules** in knowledge-base (feedback loop)
- **Max 20 files per task** — keep PRs reviewable
- **TDD/BDD** — human names test cases, AI implements bodies

### Branching
```
main
 └── feat/<feature>                      # integration branch
      ├── feat/<feature>/001-task-name   # task PR → feat/<feature>
      ├── feat/<feature>/002-task-name
      └── ...                            # final PR: feat/<feature> → main
```

---
