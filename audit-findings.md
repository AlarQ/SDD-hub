# Workflow Audit — Findings

Date: 2026-04-14
Scope: `/Users/ernestbednarczyk/Desktop/projects/dev-workflow` — commands, agents, hooks, scripts, KB, docs.

## Critical

### Gate count mismatch ✅ DONE
- `commands/validate.md:82` defines **5 gates** (adds `compliance`).
- `CLAUDE.md:95` + `onboarding.md:364` document **4 gates**.
- Triple-gate rule ambiguous under conflict.
- **Fix:** Standardized on 5 gates. Updated `onboarding.md:185,364`, `plan.md:424`, `templates/CLAUDE.md:12`.

### Auto-chain contradiction ✅ DONE
- `CLAUDE.md:66` claims `/implement` auto-chains `validate → review-findings → ship`.
- `commands/implement.md:75` said "Do NOT proceed automatically" — actually meant "next task", not "next phase"; wording ambiguous.
- `onboarding.md` described manual flow, contradicting actual auto-chain.
- **Fix:** Clarified `implement.md:74-76` IMPORTANT block (task vs phase). Updated `onboarding.md` Stage 4-6 to describe auto-chain. Added historical-snapshot note before `plan.md:343` code block.

### Direct YAML edit loophole ✅ DONE
- `commands/implement.md:79` + `commands/spec-status.md:42` instruct manual frontmatter edits to reset status.
- Violates `CLAUDE.md:64` ("never edit YAML frontmatter directly").
- Bypasses pre-commit validation. Should route through `/continue-task`.
- **Fix:** Replaced manual-edit instructions with `/continue-task` redirect + `task-manager.sh set-status` fallback in both `implement.md` and `spec-status.md`. Explicit "never hand-edit frontmatter" warning added.

### Triple-gate rule not code-enforced ⏭️ SKIPPED
- `task-manager.sh` validates transitions only, not gate reports.
- `/validate` command logic is sole enforcer — if command drifts, invalid tasks reach `done`.
- **Decision:** Skipped. Command-layer enforcement accepted as sufficient for now.

## High

### Review-findings grouping logic unimplemented
- `commands/review-findings.md:12-29` specs line-proximity + category grouping + transitive closure + file mutex.
- No script/code implements it. Pure aspiration.

### Parallel agent mutex unimplemented
- `validate.md:30` says "spawn four concurrently".
- File-level mutual exclusion + background job tracking documented but not implemented.

### Monitor hook unwired
- `hooks/monitor-tool-calls.sh` exists and sources `monitor.sh`.
- `templates/settings.json` registers only `block-git-hook-bypass` + `block-dismissive-language`.
- Monitor never fires on install.

### review→implemented transition undocumented
- `task-manager.sh:56` permits it (for re-validation after fixes).
- `validate.md` + `review-findings.md` use it without explaining why.

## Medium

### Massive duplication
- `knowledge-base-rules` reference duplicated in 9 `commands/*.md` — move to global assumption.
- `CLAUDE.md` vs `templates/CLAUDE.md` 80-90% identical — template should be thin.
- Commit rules duplicated across `ship.md` + `quick-ship.md` (conventional format, no Co-Authored-By, sensitive-file scan) — quick-ship has more thorough patterns (drift).
- Validation gate definitions duplicated `CLAUDE.md:87` vs `validate.md:20`.
- Security Engineer invocation duplicated across `explore.md` + `propose.md` with diverging contracts.
- Report schema restated in `validate.md` + `implement.md` + `review-findings.md` — extract to schema file.

### Zero-finding path ambiguity
- `validate.md:74` chains directly to `/ship`, skipping review.
- `review-findings.md:43` routes through review.
- Unclear if `implemented → done` bypasses `review` state.

## Low

### Doc drift
- `onboarding.md:36` claims "35+ agents" — actual: 15 in `agents/` + 17 in `agents-unused/`.
- `onboarding.md:34` says "2 scripts" — actual 3 (`monitor.sh` omitted).
- `plan.md` references `/commit` — no `commands/commit.md` exists (superseded by `/ship`).

### Orphans
- `agents/karen.md` defined, never invoked by any command.

### Setup gap
- `setup.sh:287` verification loop misses `knowledge-base/languages/shell.md` (copied via wildcard but not verified).

### Missing from onboarding
- `review_status: noted` partitioning in `review-findings.md:35` not reflected in onboarding/plan.
- Test Strategist used in `propose.md` + `implement.md`, absent from onboarding.

### KB prefix examples inconsistent
- `plan.md` shows unprefixed, `onboarding.md` shows prefixed.
- Default `project:` is correct in both script + rules doc.

## Root Cause

Commands evolved independently. No single source of truth for gates, states, conventions. `onboarding.md` + `plan.md` are stale snapshots; `commands/*.md` drifted forward. No enforcement blocking rule duplication.

## Suggested Fixes (priority order)

1. Reconcile gate count — pick 4 or 5, update `CLAUDE.md` + `validate.md` + `onboarding.md` + `plan.md` together.
2. Fix auto-chain contradiction — either implement chain in `/implement` or delete the claim in `CLAUDE.md`.
3. Remove manual YAML edit instructions from `implement.md` + `spec-status.md`.
4. Wire `monitor-tool-calls.sh` into `templates/settings.json` or delete hook.
5. Implement grouping + mutex logic, or downgrade docs to "manual review, one at a time".
6. Extract `knowledge-base/conventions/{git-commits,validation-gates,validation-report}.md` — dedupe 9 commands.
7. Regenerate `templates/CLAUDE.md` from `CLAUDE.md` in `setup.sh`.
8. Delete orphan `karen.md` + `/commit` references.

## False Positives Excluded

One audit pass claimed 9 engineering/design agents missing from `agents/`. **False** — they live in subdirs (`agents/engineering/`, `agents/design/`, `agents/product/`, `agents/project-management/`) and `setup.sh` copies recursively. Verified present.
