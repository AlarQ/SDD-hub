# Workflow Audit Findings

**Date:** 2026-04-05
**Scope:** Full workflow analysis — commands, scripts, hooks, agents, templates, Copilot integration, knowledge base, setup scripts
---

### 24. State machine defined in 3+ places

**Location:** `scripts/task-manager.sh`, `CLAUDE.md`, `copilot/copilot-instructions.md`, `copilot/instructions/task-files.instructions.md`, `commands/workflow-summary.md`

High drift risk — if one copy is updated, others may not be.

**Fix:** Define the state machine once (in `task-manager.sh` or a dedicated doc) and reference it everywhere else.
