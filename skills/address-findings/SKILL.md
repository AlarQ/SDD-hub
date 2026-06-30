---
name: address-findings
description: Walk one work unit (1+ related findings) from a violations/audit report (e.g. files under `reports/` like `dry-violations-*.md`, `docs-*.md`) through plan → implement → multi-agent review → ship. Use whenever the user says "address findings", "next finding", "process the report", "/address-findings", or hands over a report path containing H2 finding sections with severity/files/fix structure. Handles exactly one unit per invocation (the scheduler bundles duplicate/coupled findings into one unit), marks each member `— RESOLVED (YYYY-MM-DD)` in the source report (or deletes the report when those were the last open ones), and ships via `/quick-ship`. Trigger even when the user only names a report file and asks to "work through it" or "knock out the next item".
---

# Address Findings

Single-purpose orchestration skill: take a markdown report of findings/violations, pick the next un-done **work unit** (one finding, or a scheduler-bundled cluster of duplicate/coupled findings), fully address every member, and stop.

## Inputs

- **Report path** — required, passed as arg or named in the user's message. Absolute or repo-relative path to a markdown file.
- If no path supplied → ask user for it. Don't guess.
- **`--finding <report>:<slug>`** — optional and **repeatable**. Each occurrence names one member of the unit to address: the open H2 whose kebab-case slug matches `<slug>` (lowercase, non-alnum → `-`, trimmed) in the report at `<report>` (absolute or repo-relative path). A unit may span **two reports**, so the per-member `<report>` prefix is load-bearing — don't assume all members live in the report-path arg. Used by `scripts/address-reports.sh` to assign one work unit (1+ findings) to a worker. If **any** named member is missing or already RESOLVED, abort with an explicit error (do NOT fall back, do NOT partially address). When no `--finding` is given, behavior is unchanged: pick the first open H2 top-to-bottom as a single-member unit.
- **`--finding <slug>` (bare, no `<report>:` prefix)** — back-compat form. Resolves against the single report-path arg. Same repeatable semantics as the prefixed form above.

## Report format assumptions

Each finding is an H2 (`## ...`) block. Body typically contains:
- `**Severity**: ...`
- `**Files**: ...` (paths, optionally with `:line` suffix)
- `**Fix**: ...` or `**Pattern**: ...` describing intent

**Done marker**: heading ending with `— RESOLVED (YYYY-MM-DD)` (em-dash + ISO date, matches existing convention in `reports/dry-violations-*.md`). Also treat `**Status**: done` line in body as done, and legacy ` - DONE` suffix from older reports. Anything else = open.

## Workflow

Execute these steps in order. Do not skip. Do not auto-advance past step 8.

**Auto-mode trigger**: this skill runs in auto mode when EITHER (a) env var `ADDRESS_FINDINGS_AUTO=1` is set, OR (b) the invocation includes the `--auto` arg (e.g. `/address-findings <report> --finding <slug> --auto`). Either signal alone is sufficient. Detect early — before step 2 — and apply auto-mode rules below for the rest of the run.

(Step 2's plan-approval gate is bypassed in auto mode. All other steps run identically except step 6 — see step 6 for the auto-mode rule.)

### ⛔ Auto-mode hard rules (auto mode active)

When in auto mode (env var `ADDRESS_FINDINGS_AUTO=1` OR `--auto` arg), the following are **forbidden**. Treat as compiler errors — if you find yourself about to do any of these, STOP and skip the operation:

1. **Do NOT read, write, edit, or `git add` the report file** beyond step 1's slug lookup. Specifically: no `Edit`, no `Write`, no shell `sed`/`awk` on the report path. The scheduler (`scripts/address-reports.sh`) is the sole writer of RESOLVED markers and runs in a separate process — any worker write races with sibling workers and corrupts shared state.
2. **Do NOT re-invoke `/address-findings` for any other unit.** This skill processes exactly **one work unit (1+ findings) per invocation** — you address every member named by `--finding`, then stop. Do not reach for findings outside the named set. Step 8 is "stop"; obey it. The scheduler will start the next worker.
3. **Do NOT interpret marks on other H2 headings as completion of your own finding.** Your finding is fixed when your code change is shipped (PR open) — not when you see somebody else's heading marked.

Violating any of these will be caught by review; more importantly, it produces silently inconsistent reports.

### 1. Locate the work unit's members

Read the report(s). Scan H2 headings top-to-bottom.

- If invoked with one or more `--finding <report>:<slug>` args: for **each** member, open its `<report>`, compute the kebab-case slug of each open H2 (lowercase, non-alnum → `-`, trimmed), and pick the one matching `<slug>`. Resolve **every** named member. If **any** member fails to resolve (not found, or already RESOLVED), abort the whole unit — do NOT fall back, and do NOT address the members that did resolve (no partial work units). On abort, first give the operator full context on the bad unit: quote the H2 headings of all members that DID successfully resolve (with each one's report basename), then name the offending `--finding <report>:<slug>` (and whether it was missing or already RESOLVED), e.g. `ABORT: --finding <report>:<slug> not found among open H2 findings (resolved members: "<heading>" in <basename>, ...)`. Abort the whole unit after stating this — no partial fix.
- Otherwise: the first heading that is NOT done = a single-member unit. If none, tell user "All findings DONE in `<report>`" and stop.

State the unit you picked — quote **every** member heading (and its report basename when the unit spans reports) — before continuing.

### 2. Plan

Extract **every member's** body. Produce a short plan covering the whole unit:
- Files to touch (only those named across the unit's members, unless the fix obviously requires a sibling file — call that out explicitly). For a duplicate/coupled unit the members overlap by construction; plan the single coordinated edit that resolves all of them.
- Concrete change per file (1–2 lines each).
- Verification command (e.g. `make check`, `cargo test -p <crate>`).

**Classify each member — this decides how step 3 runs.** A unit may mix buckets (one member behavior-changing, another structure-only); classify per member. A fix falls into one of two buckets, and the difference is whether a test can express what the fix changes:

- **Behavior-changing** — corrects a bug, changes output/logic/validation, adds or removes a code path a caller can observe. A test can name the wrong behavior and assert the right one. Examples: off-by-one, wrong operator, missing null guard, incorrect status code, a regex that over-matches.
- **Structure-only** — pure refactor, dead-code or duplicate-impl deletion, rename, move, comment/doc edit, config or formatting change. No observable behavior delta exists for a *new* test to pin; the existing suite is what proves you changed nothing.

State the bucket per member in the plan (one word each: `behavior-changing` or `structure-only`) and, for each behavior-changing member, name the test that will express its fix. When genuinely unsure, treat it as behavior-changing — a redundant test costs little; a silent behavior change costs a lot. This classification is a judgement call about *this* finding, not a label on the finding's category — a "DRY" finding that collapses two impls into one can be either, depending on whether the impls actually behaved identically.

Present via `ExitPlanMode`. If user rejects → exit, no changes. If the plan concludes the finding warrants **no code change** (the suggested fix is wrong/harmful/not worth it), do not silently stop — that path is **step 5b (won't-fix)**, and it still requires the step-4 review to confirm before exiting.

**Headless/auto mode**: if auto mode is active (env var `ADDRESS_FINDINGS_AUTO=1` OR `--auto` arg, scheduler-driven, e.g. `scripts/address-reports.sh`), skip `ExitPlanMode` entirely — print the plan to stdout and proceed directly to step 3. No human is present to approve.

**Scope discipline**: do not introduce new abstractions, helper modules, or refactors beyond what the unit requires. The budget is the **union of the members' stated scope** — nothing more. Repo `CLAUDE.md` and global code-quality rules forbid scope creep. A unit whose members say "delete two impls" means delete two impls — nothing else.

### 3. Implement

Implement **all members of the unit in this one worktree** — one coordinated change set, one eventual PR. For a duplicate unit that is a single edit that satisfies every member; for a coupled unit it is the set of edits to the shared code; for a multi-member independent unit (rare — the scheduler usually splits those) address each in turn. How you implement each member depends on its bucket from step 2. The point of splitting buckets is that a test is only worth writing when it can fail for the right reason — that's what makes it evidence rather than decoration.

**Behavior-changing → test-first (red → green → refactor).**

1. **Red.** Write the smallest test that asserts the *correct* behavior, then run it and watch it fail. Confirm it fails because of the bug the finding describes — not a typo, missing import, or wrong fixture. A test that fails for the wrong reason proves nothing; a test that passes before you've touched the code isn't exercising the bug. This red step is the whole point: it shows the test actually reaches the defect.
2. **Green.** Apply the fix from the plan. Re-run — the new test passes and nothing previously green broke.
3. **Refactor.** Optional. Tidy the change if it helps, re-running the suite to stay green. Stay inside the finding's scope (see scope discipline in step 2) — don't fold in unrelated cleanup.

If the finding *is* about a missing or broken test (the code is fine, the test is wrong), there's no red step to stage — fix the test, run it, confirm it now passes for the right reason, and you're done.

**Structure-only → lean on the existing suite.** No new test — a fresh assertion over a pure refactor either restates what existing tests already cover or, worse, locks in current behavior as if it were a spec. Apply the edits, then run the existing tests plus the verification command; their staying green is the proof you preserved behavior. One exception: if the code you're restructuring has *no* test coverage and the change is non-trivial, add a characterization test capturing current behavior *before* you touch the code, so the refactor has a safety net. Note that gap to the user.

**Verification command** (run after green / after refactor, both buckets).

Resolve the command in this order:

1. **Target repo's `.workflow.yml gate_pool`** (preferred when present). Pick the blocking gate(s) whose `category` is `code-quality` or `testing` and whose `applies_to` matches the detected language of the changed files (e.g. `applies_to: [rust]` for a `.rs` change, `[ts]`/`[typescript]` for a `.ts` change). Run those gate `command`s. This keeps verification identical to what `/validate` would run.
2. **Language fallback** when there is no `.workflow.yml` (or no matching gate). Detect the stack from repo markers at the changed file's nearest package root:
   - **Rust** (`Cargo.toml`): `make check` if a `Makefile` defines it, else `cargo check --workspace`. For an affected crate also `cargo test -p <crate>`.
   - **TypeScript/JS** (`package.json` / `tsconfig.json`): `tsc --noEmit` (prefer the repo's `npx tsc --noEmit` / `pnpm exec tsc --noEmit`). Run `npm test` / `pnpm test` **only if** a `test` script is defined in `package.json` (opt-in — don't invoke an undefined or interactive test runner).
   - **Other stacks**: the verification command named in the plan.

**Auto-mode (`ADDRESS_FINDINGS_AUTO=1` OR `--auto` arg): never block on a prompt.** There is no human to ask, so the resolution above is exhaustive — `.workflow.yml` gate, then the Rust/TS fallback, then the plan's command. If none of these resolve to a runnable command, do NOT prompt; stop with an explicit error (`ABORT: no verification command could be resolved for <stack>`) so the worker fails loudly and the scheduler keeps the worktree for inspection.

If verification fails → stop. Surface error. Do not proceed to review/ship. Fix or abort.

### 4. Review (parallel)

Spawn three agents in a **single message, three Agent tool calls** so they run concurrently:

- `subagent_type: "Code Reviewer"`
- `subagent_type: "Software Architect"`
- `subagent_type: "odium"`

Each gets the same self-contained brief:

```
Reviewing the fix for a work unit (1+ related findings) from <report path(s)>.

## Findings in this unit (verbatim)
<paste EVERY member's H2 heading and full body; for a duplicate/coupled unit
note the relationship — these were judged to share code>

## Files changed
- <path>: <one-line summary of change>
- ...

## Diff
<paste the combined `git diff` for the whole unit, or if >300 lines, paste the command and a summary>

## Your job
Under 200 words. Focus only on this diff:
1. Does it actually fix every finding in the unit?
2. Any correctness, security, or architecture concern specific to these changes?
3. Any scope creep (changes unrelated to the unit's findings)?
4. For each member that changes behavior, is there a test that would fail without the code change (i.e. one that genuinely exercises the fix, not a trivial pass)? For pure refactor/deletion members, is existing coverage enough to trust it? Flag a missing or toothless test; don't demand a test for a finding where none is meaningful.

Do not suggest broader refactors. Do not propose work outside the unit's stated scope.
```

### 5. Address review feedback

Consolidate the three reports. Surface to user as a short list:
- Issue → which reviewer raised it → proposed fix.

Apply only the items the user agrees with (or, in auto mode, the clearly-correct correctness/security items; punt taste calls to user). Re-run verification.

### 5b. Won't-fix (no code change warranted) — terminal

A finding can legitimately resolve to **no code change**: on inspection the report's suggested fix is wrong, harmful, or not worth it, **and** the step-4 review is **unanimous** (all three reviewers) that the current code is correct as-is — e.g. "idiomatic, no viable abstraction", "the duplication is cosmetic, not behavioral, and an abstraction would fight the type system". This is a real disposition, **not** an escape hatch. It requires the three-reviewer consensus from step 4 — if you reach this conclusion earlier (at step 2 plan time), you must still run step 4's review to confirm before taking this exit. A finding you merely find tedious is **not** won't-fix; only unanimous "the code is right as written" qualifies.

When the unit is won't-fix:

- **Auto mode (`ADDRESS_FINDINGS_AUTO=1` OR `--auto` arg)**: write a `WONTFIX` sentinel file in the worktree root (current working directory) whose **first line** is a one-sentence rationale citing the reviewer consensus, then **STOP**. Do NOT call `/quick-ship`; do NOT read, edit, or `git add` the report. The scheduler (`scripts/address-reports.sh`) consumes `WONTFIX`, marks every member H2 `— RESOLVED (YYYY-MM-DD, wontfix)`, and drops the worktree — same bookkeeping ownership as the PR path (see Auto-mode hard rules). Write it with a literal command, not prose:

  ```
  printf '%s\n' 'Idiomatic Axum — each handler carries distinct command/repo/response types; no viable abstraction (3-reviewer consensus).' > WONTFIX
  ```

  This is the only sanctioned no-PR success exit in auto mode. Without the `WONTFIX` sentinel, a worker that ships no PR is treated as **FAILED** and its worktree kept for inspection — so a genuine won't-fix MUST write the file, and a worker that just gave up MUST NOT.

- **Interactive mode**: surface the won't-fix rationale to the user via `AskUserQuestion` and let them choose (a) **accept won't-fix** → mark every member H2 `— RESOLVED (YYYY-MM-DD, wontfix)` using step 6's interactive mechanics (commit the report change), skip step 7 (no PR); or (b) **implement anyway** → return to step 3. Never write a `WONTFIX` file in interactive mode — that sentinel is scheduler-only.

### 6. Mark RESOLVED + commit report

**Auto mode (`ADDRESS_FINDINGS_AUTO=1` OR `--auto` arg)**: SKIP THIS STEP ENTIRELY — including the last-finding check and any archival. Do not open, mark, `git mv`, or `git add` the report; do not "preview the diff that would result". Proceed directly to step 7. The scheduler (`scripts/address-reports.sh`) owns all report bookkeeping — it serializes the `— RESOLVED` marker writes across parallel workers; a worker doing it races and corrupts the shared report. The scheduler marks RESOLVED in place and never deletes; sweeping fully-resolved reports into `reports/done/` is the pipeline wrapper's job (`improve-architecture-pipeline.sh`, after stage 2). See Auto-mode hard rules above.

**Interactive mode**: mark **every member of this unit** RESOLVED, then decide whether they were the **last open ones** in the report(s). After all of the unit's targets are resolved, scan every other H2 heading (in each touched report): if none remain open (all carry a done marker — `— RESOLVED`, `**Status**: done`, or legacy ` - DONE`), this was the last finding in that report. Otherwise, open findings remain.

- **Open findings remain** → edit the report file(s): append `— RESOLVED (YYYY-MM-DD)` (em-dash + today's ISO date) to **each** member H2 heading. Preserve everything else.

  ```
  git add <report path(s)>
  git commit -m "docs(findings): mark <N> finding(s) RESOLVED"
  ```

- **This was the last open finding** → archive the whole report into `reports/done/` instead of leaving it in the live `reports/` dir. A report with every finding resolved is spent — keeping it in `reports/` is just stale clutter the next scheduler/invocation has to scan and skip — but the work product is worth preserving, so move it rather than delete it. Don't bother writing the RESOLVED marker first; the archive supersedes it. If `reports/done/<basename>` already exists (the same code unit resurfaced in a later cycle), splice a UTC stamp before `.md` (`<basename-without-ext>.YYYYMMDDTHHMMSSZ.md`) so the earlier archive is not clobbered.

  ```
  mkdir -p reports/done
  git mv <report path> reports/done/<basename>   # stamp the basename if the target exists
  git commit -m "docs(findings): archive <basename> (all findings resolved)"
  ```

  If the report lives outside version control (untracked), fall back to a plain filesystem `mv` into `reports/done/` and note it to the user.

Commit the report change (mark or archive) **on its own**, before shipping the fix. Rationale: report bookkeeping is independent of the code fix. A separate commit ensures the bookkeeping lands even if the ship step is interrupted, and keeps the fix commit focused on code.

### 7. Ship fix

Invoke `/quick-ship` skill via the Skill tool to commit + push + open **one** PR for the whole unit's change set. The commit/PR body should **enumerate every finding addressed** (one line per member heading); for a duplicate/coupled unit, note that they were resolved together because they share code. The report bookkeeping commit from step 6 (RESOLVED markers, or the report archive into `reports/done/` when these were the last findings) is included automatically since it's already on the branch.

### 8. Stop

Do not look for the next finding. Do not call `/address-findings` again. Do not invoke the Skill tool. Tell user finding is shipped and they can re-invoke for the next one. In auto mode, the worker process terminates here — the scheduler picks up via the success sentinel and starts the next one.

## Edge cases

| Case | Action |
|------|--------|
| Report path missing/unreadable | Error out, ask user for correct path |
| No open findings (at step 1) | Report "all RESOLVED", stop. (A spent report should already be archived into `reports/done/` by step 6 of the prior run; if one lingers in `reports/`, point it out.) |
| Target was the last open finding | Interactive: `git mv` the report into `reports/done/` instead of marking it (step 6). Auto: scheduler owns bookkeeping — worker does nothing. |
| Verification fails after implementation | Stop, surface error, do not review/ship |
| Plan/review concludes no code change warranted (unanimous) | Step 5b won't-fix. Auto: write `WONTFIX` sentinel (rationale line 1), stop — scheduler marks RESOLVED (wontfix). Interactive: ask user via `AskUserQuestion`. |
| User rejects plan in step 2 | Exit cleanly, no file changes |
| Finding body lacks `**Files**` | Ask user to clarify scope before planning |
| Reviewer flags genuine bug | Fix before shipping; re-run verification |
| `make check` not available | Resolve via the step-3 order: `.workflow.yml` gate → Rust (`cargo check --workspace`) / TS (`tsc --noEmit`) fallback → plan's command. Interactive: ask only if all fail. Auto: never ask — `ABORT` if none resolve. |

## Notes

- One **work unit** per invocation is intentional — keeps review units small and ships incrementally. A unit is usually a single finding; the scheduler bundles **duplicate/coupled** findings into one unit because they share code and are best reviewed together (reviewing them apart would mean reviewing the same diff twice, or worse, two conflicting half-fixes).
- The `— RESOLVED (YYYY-MM-DD)` suffix convention is load-bearing: future invocations and the `scripts/address-reports.sh` scheduler rely on it to skip completed work. Do not use a different marker. (Legacy ` - DONE` from older reports is recognised as done for back-compat, but new work always writes RESOLVED.)
- A report is archived into `reports/done/` once its **last** open finding is resolved (interactive mode, step 6). The whole point of the live `reports/` dir is to track outstanding work — an all-RESOLVED file is finished business, and keeping it there just makes every later scan re-read a file with nothing left to do. Archival (not deletion) is the natural terminal state: the spent report leaves the scan path but its audit trail survives. Only the final finding triggers it; earlier ones get the RESOLVED marker so siblings stay visible.
- Reviewer parallelism matters for latency. Always single-message three-tool-call.
