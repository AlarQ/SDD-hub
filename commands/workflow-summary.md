Print a short summary of the spec-driven development workflow rules.

This command takes no arguments. It does NOT read any project files — it prints a static reference card from memory.

## Output

Print the following reference card exactly:

---

## Spec-Driven Workflow — Quick Reference

### Commands
| # | Command | Purpose |
|---|---------|---------|
| 0 | `/bootstrap` | Create `.workflow.yml` with inline `gate_pool:` (once per project) |
| 1 | `/explore` | Clarify requirements conversationally |
| 2 | `/propose <name>` | Generate spec, design, and tasks |
| 3 | *(conversation)* | Human reviews artifacts, requests changes |
| 4 | `/implement <name>` | Implement next eligible task (one at a time) |
| 5 | `/validate <name>` | Run validation gates (tools + LLM analysis) |
| 6 | `/review-findings <name>` | Accept/reject each finding |
| 7 | `/ship <name>` | Commit, push, and PR into feature branch |
| 8 | `/pr-review` | Address PR review comments |
| 9 | `/spec-status <name>` | Dashboard: progress, dependencies, health |

<!-- State machine canonical source: scripts/task-manager.sh + plan.md. Keep in sync when editing. -->
### Task States
```
blocked → todo → in-progress → implemented → review → done
```
- Only one task in-flight at a time — validate before starting the next
- `implemented` = code written, needs `/validate`
- `review` = findings exist, needs `/review-findings`
- `done` = validated and all findings resolved; needs `/ship`, then merge PR before next task

### Single Knowledge Base (ADR-0002)
- **General KB** (`$WF_GENERAL_KB/`) — all KB rules (security, architecture, testing, style, learned languages/conventions); path from `general_kb_path` in `.workflow.yml`
- Read by all commands; no per-repo `knowledge-base/` directory
- `ground_rules` are bare `$WF_GENERAL_KB`-relative paths (e.g. `security/general.md`); legacy `general:`/`project:`/`repo:<name>:` prefixes stripped + deprecation-warned
- New rules from `/review-findings`, `/learn-from-reports`, `/capture-rule` all go to the general KB

### Key Rules
- **`$WF_GENERAL_KB` is mandatory** — commands refuse without it (loader exit 2)
- **`ground_rules` on each task** = single source of truth for which rules apply
- **Gates in `.workflow.yml gate_pool:`** with `blocking: true` = mandatory for matching `ground_rules` (every gate must run)
- **Tool findings** (`source: tool`) are high-confidence; **LLM findings** (`source: llm`) are advisory
- **Human is final authority** on all findings via `/review-findings`
- **Rejected findings can become new rules** in the general KB (feedback loop)
- **Max 20 files per task** — keep PRs reviewable
- **TDD red-green-refactor** — `/implement` writes one failing test (RED) → minimal code (GREEN) → repeat, then refactor; per-cycle `tdd_red`/`tdd_green` monitor events. Behavior backlog from spec.md BDD + test-strategy.md (human-named scenarios, AI bodies)
- **Tracks** — `track: feature` (default) = normal spec/design flow. `track: technical` (refactor/decouple/tracing/deploy/tech-debt) = `/propose` writes **tasks/ only** at every tier; rationale from `docs/adr/`+`CONTEXT.md` (`/grill` mandatory for medium/large, optional small); per-task `technical_acceptance` drives the TDD loop. Inferred at `/explore` step 0 or forced via `/explore --technical`

### Branching
```
main
 └── feat/<feature>                      # integration branch
      ├── feat/<feature>/001-task-name   # task PR → feat/<feature>
      ├── feat/<feature>/002-task-name
      └── ...                            # final PR: feat/<feature> → main
```

---
