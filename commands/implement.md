Implement the next task for a feature.

Feature name: $ARGUMENTS

## Prerequisites
1. Read and follow `$WF_GENERAL_KB/_rules.md` for knowledge base prerequisites and resolution rules
2. **Spec coherence gate** — read `specs/$ARGUMENTS/reports/spec-review.yaml`. Refuse to proceed unless the file exists and has `status: pass`. If missing or `status: findings|error`, stop and instruct: "Spec coherence gate not passed. Run `/validate-spec $ARGUMENTS` and resolve any findings before starting implementation."
3. Run `~/.claude/scripts/task-manager.sh next specs/$ARGUMENTS/tasks/` to find the next eligible task
   - If no eligible task found, report which tasks are blocked and by which task IDs
   - If any task has `status: in-progress`, warn: "Task [ID] is stuck at in-progress (likely from a crashed session). Run `/continue-task $ARGUMENTS` to resume or manually reset its status."
4. Check if any `done` tasks have an unmerged PR:
   - For each task with `status: done` and a `pr_url` in frontmatter, check: `gh pr view <pr_url> --json state --jq .state`
   - If any PR state is `OPEN`, refuse and say: "Task [ID] PR is not yet merged into `feat/$ARGUMENTS`. Merge it before starting the next task."
   - If any `done` task has no `pr_url`, refuse and say: "Task [ID] is done but has no PR. Run `/ship $ARGUMENTS` first."
   - **Important**: In bash scripts, never use `status` as a variable name — it is read-only in zsh. Use `task_status` instead.

## Step 0 — Load Spec Config

Before running any step, load the spec config (substituting the actual feature name for `$ARGUMENTS`):

```bash
bash -c 'source ~/.claude/scripts/config-loader.sh && wf_load_config --spec $ARGUMENTS && printf "WF_SPEC_AGENTS_IMPLEMENT=%s\nWF_SPEC_CONFIG_FILE=%s\n" "${WF_SPEC_AGENTS_IMPLEMENT:-}" "${WF_SPEC_CONFIG_FILE:-}"'
```

> See `~/.claude/scripts/step0-load-config.md` for canonical invocation and remediation. This step uses: `WF_SPEC_AGENTS_IMPLEMENT` (post-impl quality-check agents), `WF_SPEC_CONFIG_FILE` (snapshot source), `WF_SPEC_TIER`, `WF_TIER_TASK_CEILING`, `WF_TIER_FILE_CEILING`.

### Tier-Ceiling Check (hard stop on breach)

After `wf_load_config --spec $ARGUMENTS`, run:

```bash
bash ~/.claude/scripts/tier-check.sh $ARGUMENTS
```

- Exit `0` → continue.
- Exit `9` → **HARD STOP**. The script printed `WF_TIER_BREACH=<tasks>:<files>` and `CEILING=<tc>:<fc>`. Show the user the actual vs ceiling and prompt via `AskUserQuestion`:
  - **question:** "Spec exceeds `<tier>` tier ceiling (<actuals> vs <ceilings>). Continue or abort?"
  - **options:**
    - `Continue` — acknowledge breach, proceed at current tier (no re-propose). Emit `tier_breach` event with `{"resolution":"continue"}`.
    - `Abort` — stop now. Print: "Run `/promote-tier $ARGUMENTS` to re-run propose at the next tier, then re-run `/implement $ARGUMENTS`."

The `tier_breach` event was already emitted by `tier-check.sh`; the user's resolution is logged as a follow-up event with the same category.

### Multi-repo task resolution

After Step 0 + tier-check, resolve the task's bound repo per `~/.claude/scripts/multi-repo-resolution.md`. This sets `WF_TASK_REPO_PATH` (= repo root for single-repo flow, or the bound repo's path for vault flow). All subsequent `git` and edit operations in this command run against `WF_TASK_REPO_PATH`. Use `git -C "$WF_TASK_REPO_PATH" <cmd>` form throughout — every `git ...` invocation in the steps below is implicitly scoped that way.

## Steps
1. Run `~/.claude/scripts/task-manager.sh set-status <task-file> in-progress`
2. Set monitor context: run `~/.claude/scripts/monitor.sh set_context $ARGUMENTS <task-id>` (replace `<task-id>` with the numeric ID from the prerequisite step, e.g. `001`)
3. Ensure the feature integration branch exists in the task repo: `git -C "$WF_TASK_REPO_PATH" rev-parse --verify feat/$ARGUMENTS` (create from `main` and push: `git -C "$WF_TASK_REPO_PATH" push -u origin feat/$ARGUMENTS` if first task in this repo)
4. Pull latest feature branch: `git -C "$WF_TASK_REPO_PATH" checkout feat/$ARGUMENTS && git -C "$WF_TASK_REPO_PATH" pull`
5. Check if task branch already exists: `git -C "$WF_TASK_REPO_PATH" rev-parse --verify feat/$ARGUMENTS/{task-id}-{task-name}`
   - If it exists, ask the user: "Task branch `feat/$ARGUMENTS/{task-id}-{task-name}` already exists (likely from a previous aborted attempt). Delete it and start fresh, or continue on the existing branch?"
   - If starting fresh: delete the branch (`git branch -D feat/$ARGUMENTS/{task-id}-{task-name}`) and create a new one
   - If continuing: checkout the existing branch and proceed
6. Create task branch from the integration branch: `feat/$ARGUMENTS/{task-id}-{task-name}`
6a. **Snapshot spec config** — write a normalized JSON snapshot of the effective fields to `.monitor-context-snapshot`:
   ```bash
   bash -c 'source ~/.claude/scripts/config-loader.sh && wf_load_config --spec $ARGUMENTS && wf_write_snapshot .monitor-context-snapshot'
   ```
   This snapshot is compared by `/ship` to detect mid-task `config.yml` drift. Normalized JSON (sorted keys, sorted gate list) ensures whitespace-only edits do not trigger false drift.
7. Read the task's `ground_rules` files (per `knowledge-base-rules.md`)
8. Read context for the task. **Feature track** (`WF_SPEC_TRACK=feature`, default): read `specs/$ARGUMENTS/spec.md` and `specs/$ARGUMENTS/design.md`. **Technical track** (`WF_SPEC_TRACK=technical`): spec.md/design.md do not exist — read `docs/adr/` + repo-root `CONTEXT.md` (the recorded rationale) and the task file's `technical_acceptance` instead. (`WF_SPEC_TRACK` is exported by the Step 0/6 `wf_load_config --spec` call.)
**Implementation is test-driven.** Follow the `tdd` skill at `~/.claude/skills/tdd/SKILL.md` — it is the governing method for steps 9–11. Code is written to make a failing test pass, not before it. The horizontal-slice anti-pattern (all tests, then all code) is prohibited; slices are vertical (one test → one impl → repeat).

9. **Pre-loop setup — settle the behavior backlog (no code yet):**
   - If `specs/$ARGUMENTS/test-strategy.md` exists, spawn the `Test Strategist` agent (`engineering-test-strategist`) using the Agent tool. The agent receives:
     - The test-strategy.md content
     - The current task file (with test_cases)
     - List of existing test files from completed tasks (find test files in the task branches already merged to `feat/$ARGUMENTS`)

     Instruct the agent with this directive: "Review this task's test cases against the test strategy and existing test coverage from completed tasks. For each test case, determine: keep, skip (already covered), or modify. Add any missing integration seam tests assigned to this task. List shared fixtures available from completed tasks. Return the result as an **ordered behavior backlog** (priority order, one behavior per entry). Use the Implementation Refinement Output format defined in your agent definition."

     Apply the agent's output to produce the ordered backlog: drop `skip` items, apply `modify`, add identified integration tests, note reusable shared fixtures.

     If the agent errors or times out, or if test-strategy.md does not exist, use the task file's `test_cases` as-is in listed order and note: *"Test Strategist refinement unavailable — using task file test_cases as the behavior backlog."* (On the **technical track** test-strategy.md never exists by design — this is the expected path, not a failure; do not emit the unavailable note.)
   - **Technical track — seed the backlog with acceptance criteria.** If the task file has a non-empty `technical_acceptance` list, **prepend** each entry to the behavior backlog, tagged as an acceptance criterion. Ordering rule: a `technical_acceptance` entry that asserts *behavior is unchanged* (characterization — typical of refactor tasks) comes **first**; its test is written and confirmed GREEN against current code **before** any change, then must stay GREEN throughout (the RED for such an item is a *new* required assertion the change introduces, e.g. an added trace span — not the characterization itself). Non-characterization acceptance items follow, then the task's `test_cases`.
   - **Planning gate (HITL only).** Read the task file's `interaction` frontmatter field:
     - `interaction: hitl` → use `AskUserQuestion` to confirm the public interface shape and the behavior priority order before the loop. Apply the user's adjustments to the backlog.
     - `interaction: afk` (or absent — defaults to afk) → the pre-approval is `spec.md` BDD scenarios + the refined backlog on the **feature track**, or `technical_acceptance` + `docs/adr/` + the refined backlog on the **technical track**. Do not prompt. Proceed directly to the loop.

10. **Red-green-refactor loop — iterate the backlog one behavior at a time** (vertical slices):

    For each behavior in the ordered backlog, in order:
    - **RED**: Write exactly ONE test for this behavior (Given/When/Then structure from testing knowledge-base rules; public interface only — never implementation internals). Run it. Confirm it **fails** for the expected reason. Emit:
      `~/.claude/scripts/monitor.sh log_event $ARGUMENTS tdd_red <task-id> '{"behavior":"<short label>"}'`
    - **GREEN**: Write the **minimal** code to make that test pass — no speculative features, no anticipating later backlog items. Run the test. Confirm it **passes** (and previously-green tests stay green). Emit:
      `~/.claude/scripts/monitor.sh log_event $ARGUMENTS tdd_green <task-id> '{"behavior":"<short label>"}'`
    - Follow architectural decisions from design.md (feature track) or `docs/adr/` (technical track), language patterns from knowledge-base/languages/, and security rules from both knowledge bases while writing GREEN code.
    - **On error or unexpected test failure during GREEN** → spawn the `Ultrathink Debugger` agent (`ultrathink-debugger`) with the error output, relevant source files, and task context. The agent must return its findings in the structured format defined in the agent's "Implementation Fix Output" section. Present the agent's diagnosis and proposed fix to the user. On accept: apply the fix and continue the loop. On reject or if the agent cannot resolve the issue: report the failure with the agent's diagnosis and pause for guidance.
    - **Never refactor while RED.** Get to GREEN first. Move to the next backlog behavior.

11. **Refactor — after the whole backlog is GREEN:**
   - Extract duplication, deepen modules (small interface / deep implementation), apply SOLID where natural, consider what new code revealed about existing code.
   - Run the full test suite after each refactor step; revert any step that breaks a test.
   - Tests are behavior-level and must survive this refactor unchanged — if a test breaks on a pure internal rename, it was testing implementation; fix the test to assert behavior.
12. Add implementation notes to the task file explaining decisions made (interface choices, backlog deviations, refactors applied)

## Post-Implementation Quality Check
After all code and tests are written (before setting status to `implemented`), spawn the implement-phase agents from `WF_SPEC_AGENTS_IMPLEMENT` for a pre-validation sanity check. If `WF_SPEC_AGENTS_IMPLEMENT` is empty, skip this step. If it contains `code-quality-pragmatist` or any advisory agent, spawn it using the Agent tool. The spawned agent(s) receive:
- All changed files (`git -C "$WF_TASK_REPO_PATH" diff --name-only --diff-filter=ACMR feat/$ARGUMENTS...HEAD`)
- The task file (scope, ground rules)
- The project's `CLAUDE.md`

Instruct the agent to use its YAML validation-gate output format (not the standalone prose format) so findings have structured severity levels. Mark all findings with `source: llm`.

If the agent returns findings with **high or critical** severity:
1. Present each issue to the user with the agent's recommendation
2. On accept: apply the fix before marking the task as implemented
3. On reject: note the reasoning and proceed

Low and medium severity findings are logged but do not block — `/validate` will catch them.

If the agent errors or times out, proceed without the quality check and note the failure.

This is a lightweight pre-flight check — `/validate` remains the authoritative validation step.

13. Run `~/.claude/scripts/task-manager.sh set-status <task-file> implemented`

## Open Draft PR (pre-validation human review)

After status set to `implemented`, open a **draft PR** so the user can review the diff on GitHub before validation runs.

1. Stage + commit any uncommitted work: `git -C "$WF_TASK_REPO_PATH" add -A && git -C "$WF_TASK_REPO_PATH" commit -m "type(task-id): {task-title}"` — skip if tree clean and commits already exist.
2. Push task branch: `git -C "$WF_TASK_REPO_PATH" push -u origin feat/$ARGUMENTS/{task-id}-{task-name}`.
3. Create the draft PR (run from `$WF_TASK_REPO_PATH` so `gh` picks the right remote):
   ```
   (cd "$WF_TASK_REPO_PATH" && gh pr create --draft --base feat/$ARGUMENTS \
     --title "type(task-id): {task-title}" \
     --body "<diff summary>

   Pre-validation draft for human review. Comment on the PR, then run \`/pr-review $ARGUMENTS\` to address comments. Run \`/validate $ARGUMENTS\` when ready.")
   ```
4. Save the returned PR URL to the task file frontmatter via `~/.claude/scripts/task-manager.sh set-pr-url <task-file> <url>`. Then persist the task-file change (single-repo: commit in repo root and push; vault mode: commit in vault repo if it's a git repo, else warn — same persistence pattern as `/ship` step 10).
5. Emit monitor event: `~/.claude/scripts/monitor.sh log_event $ARGUMENTS pr_opened_draft <task-id> '{"pr_url":"<url>"}'`.

If PR creation fails (e.g. `gh auth` missing, no remote), report the failure and instruct the user to create the PR manually, then re-run nothing — `/pr-review` will pick up `pr_url` from frontmatter.

IMPORTANT:
- Do NOT start the next task automatically — serial execution, one task in flight at a time.
- Do NOT auto-invoke `/validate` or `/pr-review`. Stop and instruct the user: "Draft PR opened: <url>. Review on GitHub and comment, then run `/pr-review $ARGUMENTS` to address comments. Run `/validate $ARGUMENTS` when comments resolved (or skip `/pr-review` if no comments)."

## Spec-Done Detection

Before stopping, check the feature's `.monitor.jsonl` tail for a `spec_last_task_done` event emitted during a prior `set-status done` call:

```bash
tail -50 specs/$ARGUMENTS/.monitor.jsonl 2>/dev/null \
  | grep -q '"category":"spec_last_task_done"'
```

If present, surface this to the user and instruct: "All tasks for `$ARGUMENTS` are done. Run `/validate-impl $ARGUMENTS` to perform the final spec-completion audit." Do NOT invoke `/validate-impl` automatically.

## Error Recovery
If implementation is aborted mid-task (crash, user cancels), the task is stuck at `in-progress`. Run `/continue-task $ARGUMENTS` to resume from the correct phase, or reset via `~/.claude/scripts/task-manager.sh set-status <task-file> todo` and clean up the partial branch manually. Never hand-edit task YAML frontmatter — it bypasses state-machine validation and the pre-commit hook. If the post-implementation quality check was in progress, any accepted fixes will already be on the branch.
