# Workflow Audit Findings

**Date:** 2026-04-05
**Scope:** Full workflow analysis — commands, scripts, hooks, agents, templates, Copilot integration, knowledge base, setup scripts

---

## CRITICAL

### 1. `ground_rules` prefix resolution never implemented in task-manager.sh

**Location:** `scripts/task-manager.sh` lines 128-134

Tasks use prefixed paths per the convention (`general:security/general.md`, `project:languages/rust.md`), but `task-manager.sh` validates them as literal file paths:
```bash
[ -f "$rule_path" ]
```
This always fails because `general:security/general.md` is not a real file path. The actual file lives at `~/.claude/knowledge-base/security/general.md` (Claude Code) or `knowledge-base/_general/security/general.md` (Copilot).

**Impact:** Every `ground_rules` validation warns falsely or silently skips rules.

**Fix:** Implement prefix resolution in `task-manager.sh` — strip prefix, map `general:` to the configured general KB path, map `project:` (or unprefixed) to `knowledge-base/`.


## HIGH

### 6. No per-gate status tracking for validation

**Location:** `commands/validate.md`, `scripts/task-manager.sh`

`/validate` defines 4 independent gates (security, code-quality, architecture, compliance), each producing a separate report. But `task-manager.sh` only tracks a single `status` field per task. There is no mechanism to:
- Know which gates passed vs failed vs errored
- Re-run only a failed gate
- Track partial validation completion

**Impact:** After a partial validation failure, `/validate` must re-run all gates, wasting time and potentially producing different results for previously-passing gates.

**Fix:** Either track per-gate status in task frontmatter (e.g., `gate_results: {security: pass, code-quality: error}`) or use report file existence as the tracking mechanism and document this explicitly.

---

### 7. Multi-agent failure mode contradicts itself

**Location:** `commands/validate.md` lines 56-68

Two contradictory instructions:
- "If an agent errors or times out, record a single error finding for that gate (do not block other gates)"
- "If any gate has `status: error`, that gate must be re-run before proceeding. Do not allow shipping with an incomplete gate."

If 3 agents pass and 1 errors: the task has findings (error) so it goes to `review`, but the error gate needs re-running which requires `/validate` — which requires `implemented` status. The task is now at `review` and can't go back to `implemented` for re-validation without manual intervention.

**Impact:** Errored gates create a dead-end in the workflow.

**Fix:** Clarify the flow: either errored gates keep the task at `implemented` (so `/validate` can be re-run), or add a `review -> implemented` transition for re-validation.

---

### 8. Agent naming mismatch between Claude Code and Copilot

**Location:** `agents/engineering/*.md`, `copilot/agents/*.agent.md`, `setup-copilot.sh` lines 202-208

| Claude Code identifier | Copilot agent name | Copilot file |
|---|---|---|
| `engineering-software-architect` | `@software-architect` | `software-architect.agent.md` |
| `engineering-security-engineer` | `@security-engineer` | `security-engineer.agent.md` |
| `engineering-code-reviewer` | `@code-reviewer` | `code-reviewer.agent.md` |
| `code-quality-pragmatist` | `@code-quality` | `code-quality.agent.md` |
| `claude-md-compliance-checker` | `@compliance-checker` | `compliance-checker.agent.md` |

Templates reference Claude Code names; `setup-copilot.sh` verifies Copilot names. No mapping documented.

**Impact:** Cross-referencing between platforms fails. Template CLAUDE.md installed by Copilot contains wrong agent names.

**Fix:** Standardize naming or add an explicit mapping table to documentation. Update `templates/CLAUDE.md` to use platform-appropriate names, or make it a template with placeholders.

---

### 9. Commands hardcode `~/.claude/scripts/` paths

**Location:** `commands/implement.md`, `commands/validate.md`, `commands/review-findings.md`, `commands/ship.md`

All commands reference `~/.claude/scripts/task-manager.sh`. Copilot users have scripts at `./scripts/` (project-local, installed by `setup-copilot.sh`). No environment variable override exists.

**Impact:** Copilot prompts must duplicate every command with different paths, or Copilot users hitting Claude Code docs will fail.

**Fix:** Use a variable or resolution step: "Locate `task-manager.sh` — check `./scripts/` first, then `~/.claude/scripts/`". Or define `TASK_MANAGER` env var.

---

### 10. Knowledge base path inconsistency between platforms

**Location:** `setup.sh` line 14, `setup-copilot.sh` line 164, `commands/validate.md` line 34

Claude Code general KB: `~/.claude/knowledge-base/`. Copilot general KB: `knowledge-base/_general/`. Commands hardcode the Claude Code path (e.g., `validate.md`: "`~/.claude/knowledge-base/security/`").

**Impact:** Copilot prompt files must rewrite all KB path references. Drift between the two sets is inevitable.

**Fix:** Commands should reference KB paths through the prefix convention only (`general:security/general.md`), never as absolute paths. Let prefix resolution handle platform differences.

---

### 11. Severity semantics differ across commands

**Location:** `commands/implement.md`, `commands/validate.md`, `commands/review-findings.md`

| Severity | `/implement` behavior | `/validate` behavior | `/review-findings` behavior |
|---|---|---|---|
| critical/high | Block, present to user | Task -> `review` | Actionable, must accept/reject |
| medium | Log, don't block | Task -> `review` | Actionable, must accept/reject |
| low | Log, don't block | Task -> `review` | Actionable, must accept/reject |
| info | Log, don't block | Task -> `review` | Display compactly, no action needed |

Medium findings block in `/validate` but not in `/implement`'s pre-validation check.

**Impact:** Same finding at medium severity has different consequences depending on which command produced it.

**Fix:** Define a single severity policy table and reference it from all commands. Decide: does medium block or not?

---

### 12. PR state checking asymmetry between `/implement` and `/ship`

**Location:** `commands/implement.md` step 2, `commands/ship.md` prerequisites

`/implement` checks that all done tasks' PRs are merged (refuses if any OPEN). `/ship` doesn't check if a PR already exists and is open before creating a new one.

**Impact:** User could accidentally create duplicate PRs for the same task.

**Fix:** Add PR existence check to `/ship` prerequisites.

---

### 13. `/quick-ship` can bypass the entire validation workflow

**Location:** `commands/quick-ship.md`

No guard prevents using `/quick-ship` on `feat/<feature>/<task>` branches that are part of the spec-driven workflow. A user could ship unvalidated code by calling the wrong command.

**Impact:** Validation gates rendered optional by accident.

**Fix:** Add a guard: if current branch matches `feat/*/` pattern and a `specs/` directory exists, warn and refuse (or require `--force`).

---

## MEDIUM

### 14. Report deletion timing and race conditions

**Location:** `commands/review-findings.md`, `commands/validate.md`, `commands/continue-task.md`, `commands/ship.md`

Multiple commands read or delete `specs/<feature>/reports/`:
- `/review-findings` deletes all reports after processing
- `/validate` deletes reports before creating new ones
- `/continue-task` reads reports to detect current phase
- `/ship` checks reports are clean

No atomic operation or ordering guarantee. If `/review-findings` crashes mid-deletion, reports are partially deleted.

**Impact:** Inconsistent report state could confuse `/continue-task` or `/ship`.

**Fix:** Define report lifecycle explicitly: created by `/validate`, consumed by `/review-findings`, verified absent by `/ship`. Add a cleanup step to `/continue-task` for orphaned reports.

---

### 15. No error recovery for abandoned implementation

**Location:** `commands/implement.md`, `commands/continue-task.md`

If `/implement` crashes mid-task, the task is stuck at `in-progress`. The only recovery is manually editing YAML frontmatter. No guidance on which branch to delete or what partial changes to discard.

**Impact:** Stuck tasks require manual intervention with no documented procedure.

**Fix:** Either add a `/reset-task <feature> <task-id>` command, or extend `/continue-task` to detect stale `in-progress` tasks (e.g., no commits for N minutes) and offer to reset.

---

### 16. Missing sync step between `/ship` and next `/implement`

**Location:** `commands/ship.md`, `commands/implement.md`

After a task PR is merged into `feat/<feature>`, the local feature branch may be stale. `/implement` does `git checkout feat/<feature> && git pull`, but doesn't handle merge conflicts or specify rebase strategy.

**Impact:** Next task branch could be based on stale code, leading to merge conflicts later.

**Fix:** Add explicit sync instructions to `/implement`: pull with `--ff-only`, fail if not fast-forwardable, instruct user to resolve.

---

### 17. Orphan dependencies silently block forever

**Location:** `scripts/task-manager.sh` `cmd_unblock`

If `blocked_by` references a non-existent task ID, `cmd_unblock` silently fails to find it — the task never unblocks. Status dashboard detects orphan dependencies but only warns.

**Impact:** Tasks can be permanently stuck with no error.

**Fix:** Fail hard on orphan dependencies during `cmd_validate`, or auto-unblock tasks whose dependencies all either don't exist or are `done`.

---

### 18. Cycle detection doesn't prevent cycles

**Location:** `scripts/task-manager.sh` lines 406-443

Circular dependencies are detected in the status report but not prevented during `cmd_set_status`. A task can be created or modified to form a cycle.

**Impact:** Circular dependencies permanently block affected tasks.

**Fix:** Add cycle prevention check in `cmd_set_status` and `cmd_validate` — reject task files that would create cycles.

---

### 19. Pre-commit hook degrades gracefully when task-manager.sh is missing

**Location:** `scripts/pre-commit-hook.sh` lines 10-13

If `task-manager.sh` is not found, the hook prints a warning and exits 0 (allows the commit).

**Impact:** Invalid tasks can be committed when the workflow tools aren't installed.

**Fix:** Exit 1 if task-manager.sh is missing and task files are being committed. Only exit 0 if no task files are in the changeset.

---

### 20. Agent output format not canonically defined

**Location:** `commands/validate.md`, `commands/implement.md`, `commands/pr-review.md`

Three different output contracts referenced:
- "YAML list matching the report schema" (`validate.md`)
- "YAML validation-gate output format" (`implement.md`)
- "Code Reviewer agent definition output section" (`pr-review.md`)

No single canonical schema document exists.

**Impact:** Agents may produce inconsistent formats. Parsing logic must handle variations.

**Fix:** Create a single `report-schema.md` documenting the canonical YAML schema. Reference it from all agent-spawning commands and agent definitions.

---

### 21. No deduplication or conflict resolution for multi-agent findings

**Location:** `commands/validate.md`, `commands/review-findings.md`

Multiple agents can flag the same issue differently (e.g., security agent requires a pattern, code-quality agent flags it as over-engineering). No deduplication logic exists.

**Impact:** User wastes time reviewing duplicate or conflicting findings.

**Fix:** Add a deduplication step after agent completion: merge findings with same file + line range. For conflicts, present both with a note that agents disagree.

---

### 22. `gitignore-additions.txt` referenced in setup.sh verification but missing

**Location:** `setup.sh` line 244, `templates/`

`setup.sh` verification checks for `templates/gitignore-additions.txt`, but the file doesn't exist.

**Impact:** Setup verification fails or warns unnecessarily.

**Fix:** Either create the file or remove it from verification.

---

## LOW

### 23. Knowledge base reading logic duplicated in 6+ commands

**Location:** `commands/explore.md`, `commands/propose.md`, `commands/implement.md`, `commands/validate.md`, `commands/review-findings.md`, `commands/pr-review.md`

Same KB reading and prefix resolution pattern repeated in every command. If KB format or prefix convention changes, all commands must update.

**Fix:** Extract into a shared preamble section referenced by all commands, or create a `resolve-ground-rules.sh` utility.

---

### 24. State machine defined in 3+ places

**Location:** `scripts/task-manager.sh`, `CLAUDE.md`, `copilot/copilot-instructions.md`, `copilot/instructions/task-files.instructions.md`, `commands/workflow-summary.md`

High drift risk — if one copy is updated, others may not be.

**Fix:** Define the state machine once (in `task-manager.sh` or a dedicated doc) and reference it everywhere else.

---

### 25. `/explore` -> `/propose` ordering not enforced

**Location:** `commands/explore.md`, `commands/propose.md`

Either command can be called first. `/explore` optionally saves `prd.md`, but `/propose` doesn't require it. No validation that requirements were clarified before proposing.

**Fix:** Document that `/explore` is optional but recommended. `/propose` should note when `prd.md` doesn't exist.

---

### 26. Copilot missing `karen` and `ui-ux-reviewer` agents

**Location:** `agents/karen.md`, `agents/ui-ux-reviewer.md`, `copilot/agents/`

These Claude Code agents have no Copilot equivalents.

**Fix:** Add Copilot equivalents if these agents are part of the workflow, or document them as Claude Code-only.

---

### 27. `knowledge-base-rules.md` doesn't fully explain path resolution

**Location:** `knowledge-base-rules.md` lines 10-17

Missing: explicit examples of how `general:security/general.md` resolves to actual file paths on each platform.

**Fix:** Add resolution examples for both Claude Code (`~/.claude/knowledge-base/security/general.md`) and Copilot (`knowledge-base/_general/security/general.md`).
