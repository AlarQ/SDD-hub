# Agent Integration Plan

## Current Workflow Pipeline

```
/explore → /propose → /implement → /validate → /review-findings → /ship → /pr-review
```

## Agent Classification

### Tier 1 — Direct Workflow Stage Integration

| Agent | Workflow Stage | How It Fits |
|---|---|---|
| `engineering-software-architect` | `/propose` | Spawn during design.md generation for architectural decisions |
| `engineering-code-reviewer` | `/validate` or `/pr-review` | Replace/augment LLM analysis phase in validation gates |
| `code-quality-pragmatist` | `/validate` | Run as the code-quality LLM gate — already aligned with that gate's goals |
| `claude-md-compliance-checker` | `/validate` | New gate: compliance check against knowledge-base rules |
| `engineering-security-engineer` | `/validate` | Run as the security LLM gate |
| `ultrathink-debugger` | `/implement` | Spawn when implementation hits errors/failures |
| `karen` | `/spec-status` or new `/reality-check` | Post-feature completion audit — verify tasks are actually done |

### Tier 2 — Conditional/Domain-Specific

Useful when the target project has matching technology.

| Agent | When Relevant |
|---|---|
| `ui-ux-reviewer` | Projects with frontend UI |
| `engineering-frontend-developer` | Frontend tasks in `/implement` |
| `engineering-backend-architect` | Backend-heavy `/propose` |
| `testing-api-tester` | API validation gate |
| `testing-accessibility-auditor` | UI accessibility gate |
| `testing-performance-benchmarker` | Performance validation gate |
| `testing-reality-checker` | Evidence-based validation |
| `testing-evidence-collector` | Screenshot-based QA |

### Tier 3 — Out of Scope for Task-Level Workflow

These don't fit the `/explore → /ship` pipeline. They could live as standalone tools.

| Agents | Notes |
|---|---|
| `product-*` (4 agents) | Sprint/product planning, not task execution |
| `project-management-*` (2 agents) | Project coordination, not implementation flow |
| `design-*` (3 agents) | UX research/design phases, before specs exist |
| `engineering-devops-automator`, `engineering-sre` | Infrastructure, not feature development |
| `engineering-technical-writer`, `engineering-ai-engineer`, `engineering-mobile-app-builder` | Specialist roles, not workflow stages |
| `testing-workflow-optimizer`, `testing-tool-evaluator` | Meta-tooling |

## Integration Phases

### Phase 1: Agent-Powered Validation Gates ✅ IMPLEMENTED

The biggest win. `/validate` now spawns specialized agents per gate instead of inline LLM analysis:

- **security gate** → `Security Engineer` agent (`engineering-security-engineer`)
- **code-quality gate** → `code-quality-pragmatist` agent
- **architecture gate** → `Software Architect` agent (`engineering-software-architect`, read-only mode)
- **compliance gate** (new) → `claude-md-compliance-checker` agent

Each agent runs in parallel, returns findings in the existing report schema. The `/validate` command orchestrates them.

**Changes made:**
- `commands/validate.md` — Phase 2 rewritten to spawn agents in parallel with output contract
- `setup.sh` — Installs `agents/` directory (with subdirectories) to `~/.claude/agents/`
- `templates/CLAUDE.md` — Documents agent-powered validation gates
- `CLAUDE.md` — Updated project structure and key design decisions
- All 4 agents — Added "Validation Gate Output" section with report schema YAML format, ensuring agent output aligns with `/validate`'s expected schema

### Phase 2: Agent-Assisted `/propose`

Spawn `engineering-software-architect` during design.md generation. It evaluates trade-offs and produces ADRs that get embedded in the design doc. The main command still owns spec.md and task decomposition.

### Phase 3: Agent-Assisted `/implement`

- On error/test failure during implementation → auto-spawn `ultrathink-debugger`
- After implementation complete → spawn `code-quality-pragmatist` for a pre-validation sanity check

### Phase 4: Agent-Powered `/pr-review`

Use `engineering-code-reviewer` agent to analyze PR diff and draft review responses. More structured than the current inline approach.

### Phase 5: Reality Check Gate

New command `/reality-check` (or integrate into `/spec-status`) using `karen` agent. Runs after all tasks are shipped — verifies the feature actually works end-to-end before merging the feature branch to main.

### Phase 6: Conditional Agent Registry

Add an `agents` field to `knowledge-base/` language files (similar to `validation_tools`). Projects declare which tier-2 agents are relevant:

```yaml
# knowledge-base/languages/typescript.md frontmatter
validation_agents:
  - ui-ux-reviewer
  - testing-accessibility-auditor
  - testing-api-tester
```

## Setup Changes

1. ✅ Add `agents/` directory to `setup.sh` install flow (copy to `~/.claude/agents/`)
2. ✅ Update `/validate` command to orchestrate agent-based gates
3. ✅ Agent output contract defined — each agent instructed to output findings in report schema via prompt
4. ✅ Update CLAUDE.md template to document available agents

## What NOT to Integrate

The tier-3 agents (product, PM, design, infra) don't fit the task-level workflow. They could live as standalone tools but shouldn't be wired into the `/explore → /ship` pipeline.
