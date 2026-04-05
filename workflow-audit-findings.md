# Workflow Audit Findings

**Date:** 2026-04-05
**Scope:** Full workflow analysis — commands, scripts, hooks, agents, templates, Copilot integration, knowledge base, setup scripts
---

### 24. ~~State machine defined in 3+ places~~ ✅ Resolved

**Location:** `scripts/task-manager.sh`, `CLAUDE.md`, `copilot/copilot-instructions.md`, `copilot/instructions/task-files.instructions.md`, `commands/workflow-summary.md`

High drift risk — if one copy is updated, others may not be.

**Fix:** Designated `scripts/task-manager.sh` as executable source of truth and `plan.md` as detailed docs. Added canonical-source pointers to all 9 files that mention the state machine. Installed files (templates/, copilot/, commands/) use HTML comments; repo-internal files use inline references.
