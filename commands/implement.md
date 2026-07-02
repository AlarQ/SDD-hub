Implement the next task for a feature.

Feature name: $ARGUMENTS

## Prerequisites
1. Read and follow `$WF_GENERAL_KB/_rules.md` for knowledge base prerequisites and resolution rules
2. Run `~/.claude/scripts/task-manager.sh next specs/$ARGUMENTS/tasks/` to find the next eligible task
   - If no eligible task found, report which tasks are blocked and by which task IDs
   - If any task has `status: in-progress`, warn: "Task [ID] is stuck at in-progress (likely from a crashed session). Run `/continue-task $ARGUMENTS` to resume or manually reset its status."
3. **Serial gate** — behavior depends on `WF_BRANCH_STRATEGY` (load Step 0 config first if not already loaded; absent → `per-task`):
   - **`per-task`** (default — unchanged): check if any `done` tasks have an unmerged PR:
     - For each task with `status: done` and a `pr_url` in frontmatter, check: `gh pr view <pr_url> --json state --jq .state`
     - If any PR state is `OPEN`, refuse and say: "Task [ID] PR is not yet merged into `feat/$ARGUMENTS`. Merge it before starting the next task."
     - If any `done` task has no `pr_url`, refuse and say: "Task [ID] is done but has no PR — its inline ship step did not finish. Re-run `/validate $ARGUMENTS` or `/review-and-ship $ARGUMENTS` to complete shipping first."
   - **`single-branch`**: there is no per-task PR — the gate is task status, not PR merge. Refuse to start the next task unless the immediately-preceding task (highest-numbered non-`todo`/`blocked` task) has `status: done`. Message: "Task [ID] is [status], not done. Single-branch strategy is serial — finish and ship the previous task first (via `/validate` or `/review-and-ship`)." Do **not** check `pr_url` (none exists until the final task's inline ship opens the spec PR).
   - **Important**: In bash scripts, never use `status` as a variable name — it is read-only in zsh. Use `task_status` instead.

## Step 0 — Load Spec Config

Before running any step, load the spec config (substituting the actual feature name for `$ARGUMENTS`):

```bash
bash -c 'source ~/.claude/scripts/config-loader.sh && wf_load_config --spec $ARGUMENTS && printf "WF_SPEC_AGENTS_IMPLEMENT=%s\nWF_SPEC_CONFIG_FILE=%s\nWF_BRANCH_STRATEGY=%s\nWF_SPEC_TIER=%s\nWF_IMPL_CHUNK_SIZE=%s\n" "${WF_SPEC_AGENTS_IMPLEMENT:-}" "${WF_SPEC_CONFIG_FILE:-}" "${WF_BRANCH_STRATEGY:-per-task}" "${WF_SPEC_TIER:-}" "${WF_IMPL_CHUNK_SIZE:-0}"'
```

> See `~/.claude/scripts/step0-load-config.md` for canonical invocation and remediation. This step uses: `WF_SPEC_AGENTS_IMPLEMENT` (post-impl quality-check agents), `WF_SPEC_CONFIG_FILE` (snapshot source), `WF_SPEC_TIER`, `WF_TIER_TASK_CEILING`, `WF_TIER_FILE_CEILING`, `WF_BRANCH_STRATEGY` (`per-task` default | `single-branch`; absent → `per-task`), `WF_IMPL_CHUNK_SIZE` (chunked delegated-implementation budget K; `0` = chunking off / small tier — see "Delegated implementation").

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
**Steps 5–6 are `per-task`-only.** Under `WF_BRANCH_STRATEGY=single-branch` there is **no per-task sub-branch** — stay on `feat/$ARGUMENTS` (already checked out in step 4), skip steps 5–6, and instead record the task base sha:

```bash
~/.claude/scripts/task-manager.sh set-base-sha <task-file> "$(git -C "$WF_TASK_REPO_PATH" rev-parse HEAD)"
```

`task_base_sha` = HEAD of `feat/$ARGUMENTS` at this task's start. It is the linchpin for single-branch start/mid phase detection (`/continue-task`) and the quality/test diff range below. Then proceed to step 6a.

5. (`per-task`) Check if task branch already exists: `git -C "$WF_TASK_REPO_PATH" rev-parse --verify feat/$ARGUMENTS/{task-id}-{task-name}`
   - If it exists, ask the user: "Task branch `feat/$ARGUMENTS/{task-id}-{task-name}` already exists (likely from a previous aborted attempt). Delete it and start fresh, or continue on the existing branch?"
   - If starting fresh: delete the branch (`git branch -D feat/$ARGUMENTS/{task-id}-{task-name}`) and create a new one
   - If continuing: checkout the existing branch and proceed
6. (`per-task`) Create task branch from the integration branch: `feat/$ARGUMENTS/{task-id}-{task-name}`
6a. **Snapshot spec config** — write a normalized JSON snapshot of the effective fields to `.monitor-context-snapshot`:
   ```bash
   bash -c 'source ~/.claude/scripts/config-loader.sh && wf_load_config --spec $ARGUMENTS && wf_write_snapshot .monitor-context-snapshot'
   ```
   This snapshot is compared by the shared ship procedure (`~/.claude/scripts/ship-procedure.md`, run inline by `/validate` / `/review-and-ship`) to detect mid-task `config.yml` drift. Normalized JSON (sorted keys, sorted gate list) ensures whitespace-only edits do not trigger false drift.
7. Read the task's `ground_rules` files (per `knowledge-base-rules.md`)
8. Read context for the task. **This full-body read happens only on the inline (`generalist`/absent) path** — see "Implementer routing" after step 9. On the delegated path, do **not** read spec.md/design.md/`docs/adr/` bodies into the main session; pass their **paths** to the specialist and let it read them (this is what keeps main context flat). Which artifacts to read is the **track branch** — resolved once by the decision predicate (do not re-derive `WF_SPEC_TRACK == technical` here):

   ```bash
   eval "$(bash ~/.claude/scripts/decide.sh impl-context)"   # sets VERDICT, REASON
   ```

   - `VERDICT=feature` (`REASON=spec.md+design.md`, default track): read `specs/$ARGUMENTS/spec.md` and `specs/$ARGUMENTS/design.md`.
   - `VERDICT=technical` (`REASON=docs/adr/+CONTEXT.md`): spec.md/design.md do not exist — read `docs/adr/` + repo-root `CONTEXT.md` (the recorded rationale) and the task file's `technical_acceptance` instead.

   (`WF_SPEC_TRACK` is exported by the Step 0/6 `wf_load_config --spec` call and consumed by the predicate.)
**Implementation is test-driven.** Follow the `tdd` skill at `~/.claude/skills/tdd/SKILL.md` — it is the governing method for steps 9–11 (and is the method handed to the specialist on the delegated path). Code is written to make a failing test pass, not before it. The horizontal-slice anti-pattern (all tests, then all code) is prohibited; slices are vertical (one test → one impl → repeat).

9. **Pre-loop setup — settle the behavior backlog (no code yet):**
   - If `specs/$ARGUMENTS/test-strategy.md` exists, spawn the `Test Strategist` agent (`engineering-test-strategist`) using the Agent tool. The agent receives:
     - The test-strategy.md content
     - The current task file (with test_cases)
     - List of existing test files from completed tasks on `feat/$ARGUMENTS` (`per-task`: test files in task branches already merged to `feat/$ARGUMENTS`; `single-branch`: test files changed in `feat/$ARGUMENTS` before `${task_base_sha}`)

     Instruct the agent with this directive: "Review this task's test cases against the test strategy and existing test coverage from completed tasks. For each test case, determine: keep, skip (already covered), or modify. Add any missing integration seam tests assigned to this task. List shared fixtures available from completed tasks. Return the result as an **ordered behavior backlog** (priority order, one behavior per entry). Use the Implementation Refinement Output format defined in your agent definition."

     Apply the agent's output to produce the ordered backlog: drop `skip` items, apply `modify`, add identified integration tests, note reusable shared fixtures.

     If the agent errors or times out, or if test-strategy.md does not exist, use the task file's `test_cases` as-is in listed order and note: *"Test Strategist refinement unavailable — using task file test_cases as the behavior backlog."* (On the **technical track** test-strategy.md never exists by design — this is the expected path, not a failure; do not emit the unavailable note.)
   - **Technical track — seed the backlog with acceptance criteria.** If the task file has a non-empty `technical_acceptance` list, **prepend** each entry to the behavior backlog, tagged as an acceptance criterion. Ordering rule: a `technical_acceptance` entry that asserts *behavior is unchanged* (characterization — typical of refactor tasks) comes **first**; its test is written and confirmed GREEN against current code **before** any change, then must stay GREEN throughout (the RED for such an item is a *new* required assertion the change introduces, e.g. an added trace span — not the characterization itself). Non-characterization acceptance items follow, then the task's `test_cases`.
   - **Planning gate (HITL only).** Read the task file's `interaction` frontmatter field:
     - `interaction: hitl` → use `AskUserQuestion` to confirm the public interface shape and the behavior priority order before the loop. Apply the user's adjustments to the backlog.
     - `interaction: afk` (or absent — defaults to afk) → the pre-approval is `spec.md` BDD scenarios + the refined backlog on the **feature track**, or `technical_acceptance` + `docs/adr/` + the refined backlog on the **technical track**. Do not prompt. Proceed directly to the loop.

### Implementer routing (after the backlog is settled)

Read the task file's `implementer:` frontmatter field. It decides who runs the TDD loop:

- **`generalist`, or the field is absent** (legacy specs) → **inline path.** The main session runs steps 10–11 below exactly as today. This requires the step-8 full-body context read — do it now if not already done. The Ultrathink Debugger and `tdd_red`/`tdd_green` monitor events live on this path only.
- **a resolvable agent-pool id** (e.g. `engineering/frontend-developer`, `engineering/backend-architect`) → **delegated path.** Skip steps 10–11 in the main session entirely. Instead spawn that specialist with the contract in "Delegated implementation" below. Do **not** perform the step-8 full-body read; pass paths to the specialist. After the specialist returns `complete`, continue at step 12.

`implementer:` was validated by `task-manager.sh` at `/propose` time (resolvable id or `generalist`; unresolvable → the spec never got here). Resolve the id with the same grammar `/validate` uses: `<category>/<name>` → `<agent_pool>/<category>/<category>-<name>.md`, bare `<name>` → `<agent_pool>/<name>.md`.

### Delegated implementation (delegated path only)

The delegated path runs the **same** `implementer:` specialist across a **sequence of bounded contexts** (ADR-0018). Rather than one spawn owning the task's whole TDD loop in one accreting context, main cuts the settled ordered behavior backlog into fixed-size chunks and re-spawns that one specialist per chunk with fresh context, threading a cumulative `impl_notes` ledger forward. Chunking is orthogonal to agent selection — it never changes *which* implementer runs (ADR-0004's "one Task = one implementer" holds).

**Chunk-decision gate.** Let `K = WF_IMPL_CHUNK_SIZE` (from Step 0; `0` = chunking off, forced for `small` tier). Cut the settled backlog into ordered runs of **≤ K whole behaviors** — **only if** `WF_SPEC_TIER != small` **and** `K > 0` **and** backlog length > `K`. Otherwise there is exactly **one** chunk containing the whole backlog (this is today's pre-ADR-0018 delegated behavior, unchanged). Chunks cut *between* whole behaviors — a test is never split from its code.

**Serial chunk loop.** Maintain a `ledger` (concatenated `impl_notes` from all prior chunks — empty for chunk 1) and a `chunks_spawned` counter. For each chunk in order, spawn the `implementer:` agent **once per chunk** using the Agent tool. The spawn prompt is built here by `/implement` — the agent file stays generic; `/implement` injects the method. Pass exactly:

- **Method**: "Read and strictly follow `~/.claude/skills/tdd/SKILL.md`. Implement red-green-refactor in vertical slices: one failing test → minimal code to pass → repeat. Tests assert the public interface only, never implementation internals. Do **NOT** emit any monitor events."
- **Backlog**: **this chunk's** behavior slice only (not the whole backlog) — inline it (it is compact).
- **Ledger** (prior chunks' work): the accumulated `impl_notes` from all previously-completed chunks (interface choices, backlog deviations, refactors already applied). Empty for chunk 1. "Prior behaviors are already implemented and green on disk in your working tree — build on them, do not re-implement them."
- **Full-suite-green rule**: "Run the **entire** test suite on each slice. Every previously-passing behavior (from earlier slices in this chunk **and** from all prior chunks) must stay green — if a slice regresses an earlier behavior, fix it before moving on."
- **Refactor scope**:
  - **Final chunk only** (the chunk whose completion makes the whole backlog green): "After your slice loop is green, perform the closing whole-diff refactor — read the whole-task diff (`WF_BRANCH_STRATEGY=per-task` → `git -C <WF_TASK_REPO_PATH> diff feat/$ARGUMENTS...HEAD`; `single-branch` → `git -C <WF_TASK_REPO_PATH> diff <task_base_sha>..HEAD`) plus the ledger, then extract duplication / deepen modules across the entire task diff, keeping the full suite green." (`/implement` substitutes the resolved range for the specialist — same range the post-impl quality check uses; `task_base_sha` exists only on `single-branch`.)
  - **Earlier (non-final) chunks**: "Refactor **locally only** — clean up the code you wrote in this chunk; do **not** attempt a whole-task refactor (later chunks are not yet written)."
- **Scope**: the task's `objective`, `acceptance_criteria`, `test_cases`, and `ground_rules` (pass the ground_rules **paths** — the specialist reads them itself). **Re-passed every chunk** (full re-read — accepted cost for flat peak context, ADR-0018 decision 9).
- **Architecture source (paths, not bodies)**: feature track → `specs/$ARGUMENTS/design.md` (+ `specs/$ARGUMENTS/spec.md`); technical track → `docs/adr/` + repo-root `CONTEXT.md` + the task's `technical_acceptance` list. Instruct the specialist to read these itself. **Re-passed every chunk.**
- **Workdir**: `WF_TASK_REPO_PATH`. All edits + test runs happen in that working tree (no worktree isolation — execution is serial, one task in flight). Every chunk's specialist edits the same tree the main session will `git diff`.
- **Error rule**: "Debug failing tests yourself, inline, within your own loop. If you cannot reach green after reasonable attempts, stop and return `status: blocked` with your diagnosis. Do **not** spawn further subagents."
- **Required return** (structured): `status: complete|blocked`, `impl_notes` (interface choices, backlog deviations, refactors applied — for the ledger + task file), `changed_files` (list), `blockers?` (diagnosis when `blocked`).

Handle each chunk's return:
- **`status: complete`** → append the specialist's `impl_notes` to the `ledger`, increment `chunks_spawned`, and continue to the next chunk. After the **last** chunk completes, continue to step 12 with the **merged** ledger as the task's implementation notes.
- **`status: blocked`** on any chunk → **stop the loop**; do **not** mark the task `implemented`. Surface the specialist's `blockers` diagnosis to the user and pause for guidance (same posture as an Ultrathink-Debugger reject on the inline path). The task stays `in-progress` — prior chunks' green tests remain on disk as recoverable progress (`/continue-task` re-runs the suite and re-chunks the remainder).
- If an Agent call itself errors or times out → report the failure and pause; do not silently fall back to inline (the context-hygiene contract assumes the specialist owns the loop).

When all chunks complete, carry the merged `ledger` forward to step 12 (the main session does **not** re-derive it). Main also records `chunks_spawned: N` into the merged implementation notes (a persisted note-field written by main, **not** a monitor event — keeps ADR-0018's "no new telemetry" decision while leaving an audit trail of how many bounded contexts the task used). For a single-chunk task, `chunks_spawned: 1` and the behavior is identical to the pre-ADR-0018 delegated path.

**Steps 10–11 below run on the inline path only.** On the delegated path, jump to step 12 with the merged ledger.

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
12. Add implementation notes to the task file explaining decisions made (interface choices, backlog deviations, refactors applied). **Inline path**: write the notes the main session produced. **Delegated path**: write the specialist's returned `impl_notes` verbatim (lightly formatted) — do not re-analyze the diff to regenerate them. On the delegated path this is the **merged ledger** (all chunks' `impl_notes` concatenated in order); prefix it with a `chunks_spawned: N` line recording how many bounded-context chunks the task consumed (`N == 1` for a single-chunk/unchunked task).

## Post-Implementation Quality Check
After all code and tests are written (before setting status to `implemented`), spawn the implement-phase agents from `WF_SPEC_AGENTS_IMPLEMENT` for a pre-validation sanity check. If `WF_SPEC_AGENTS_IMPLEMENT` is empty, skip this step. If it contains `code-quality-pragmatist` or any advisory agent, spawn it using the Agent tool. The spawned agent(s) receive:
- All changed files for this task. Diff range depends on `WF_BRANCH_STRATEGY`:
  - `per-task`: `git -C "$WF_TASK_REPO_PATH" diff --name-only --diff-filter=ACMR feat/$ARGUMENTS...HEAD`
  - `single-branch`: `git -C "$WF_TASK_REPO_PATH" diff --name-only --diff-filter=ACMR ${task_base_sha}..HEAD`
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

## Open Draft PR (pre-validation human review) — `per-task` only

**`WF_BRANCH_STRATEGY=single-branch`: skip this entire section.** No per-task draft PR, no `gh pr create`, no `pr_url`, no `pr_opened_draft` event. Instead just push the integration branch so work is durable:

```bash
git -C "$WF_TASK_REPO_PATH" push -u origin feat/$ARGUMENTS
```

Then jump to the `single-branch` final instruction below. Review is deferred to the spec-level PR opened at the final task's inline ship (the shared ship procedure run by `/validate` / `/review-and-ship`).

---

**`per-task` (default):** After status set to `implemented`, open a **draft PR** so the user can review the diff on GitHub before validation runs.

1. Stage + commit any uncommitted work: `git -C "$WF_TASK_REPO_PATH" add -A && git -C "$WF_TASK_REPO_PATH" commit -m "type(task-id): {task-title}"` — skip if tree clean and commits already exist.
2. Push task branch: `git -C "$WF_TASK_REPO_PATH" push -u origin feat/$ARGUMENTS/{task-id}-{task-name}`.
3. Create the draft PR (run from `$WF_TASK_REPO_PATH` so `gh` picks the right remote):
   ```
   (cd "$WF_TASK_REPO_PATH" && gh pr create --draft --base feat/$ARGUMENTS \
     --title "type(task-id): {task-title}" \
     --body "<body per ~/.claude/scripts/pr-body-convention.md — ## Why + ## What changed + optional mermaid>

   Pre-validation draft for human review. Comment on the PR, then run \`/pr-review $ARGUMENTS\` to address comments. Run \`/validate $ARGUMENTS\` when ready.")
   ```
4. Save the returned PR URL to the task file frontmatter via `~/.claude/scripts/task-manager.sh set-pr-url <task-file> <url>`. Then persist the task-file change (single-repo: commit in repo root and push; vault mode: commit in vault repo if it's a git repo, else warn — same persistence pattern as the ship procedure step 10).
5. Emit monitor event: `~/.claude/scripts/monitor.sh log_event $ARGUMENTS pr_opened_draft <task-id> '{"pr_url":"<url>"}'`.

If PR creation fails (e.g. `gh auth` missing, no remote), report the failure and instruct the user to create the PR manually — `/pr-review` resolves the PR from the current branch once one exists.

IMPORTANT:
- Do NOT start the next task automatically — serial execution, one task in flight at a time.
- Do NOT auto-invoke `/validate` or `/pr-review`.
- **`per-task`**: Stop and instruct: "Draft PR opened: <url>. Review on GitHub and comment, then run `/pr-review $ARGUMENTS` to address comments. Run `/validate $ARGUMENTS` when comments resolved (or skip `/pr-review` if no comments)."
- **`single-branch`**: Stop and instruct: "Task committed on `feat/$ARGUMENTS` (review deferred — no per-task PR). Run `/validate $ARGUMENTS`." Do NOT mention `/pr-review`.

## Spec-Done Detection

Before stopping, check the feature's `.monitor.jsonl` tail for a `spec_last_task_done` event emitted during a prior `set-status done` call:

```bash
tail -50 specs/$ARGUMENTS/.monitor.jsonl 2>/dev/null \
  | grep -q '"category":"spec_last_task_done"'
```

If present, surface this to the user and instruct: "All tasks for `$ARGUMENTS` are done. Run `/validate-impl $ARGUMENTS` to perform the final spec-completion audit." Do NOT invoke `/validate-impl` automatically.

## Error Recovery
If implementation is aborted mid-task (crash, user cancels), the task is stuck at `in-progress`. Run `/continue-task $ARGUMENTS` to resume from the correct phase, or reset via `~/.claude/scripts/task-manager.sh set-status <task-file> todo` and clean up the partial branch manually. Never hand-edit task YAML frontmatter — it bypasses state-machine validation and the pre-commit hook. If the post-implementation quality check was in progress, any accepted fixes will already be on the branch.
