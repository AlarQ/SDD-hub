# Architecture-Improvement Pipeline

Two scripts that turn "this codebase has architectural friction" into a stack of
reviewable PRs — one PR per finding, isolated in its own git worktree.

```
improve-architecture-pipeline.sh   →   address-reports.sh
        (find + gate)                       (address)
```

- **`improve-architecture-pipeline.sh`** — orchestrator. Runs a headless arch
  scan, writes findings as `reports/*.md`, gates for human review, then hands the
  reports to the scheduler.
- **`address-reports.sh`** — parallel scheduler. Takes one or more report files
  and opens one PR per open finding, via a shared worktree worker pool.

Either script runs standalone. The orchestrator is the convenience wrapper that
produces the reports the scheduler consumes; you can also point the scheduler at
hand-written or `audit-finding`-generated reports.

Both are installed to `~/.claude/scripts/` by `setup.sh` and work against any
git repo (Rust + TypeScript are the tested stacks).

---

## Pipeline at a glance

```
$ improve-architecture-pipeline.sh ~/code/myrepo
  Stage 1 (find)   — Opus scans the repo, writes reports/architecture-<unit>.md
  Gate             — prints findings + count, STOPS (review the reports)

$ improve-architecture-pipeline.sh --yes ~/code/myrepo
  Stage 2 (address) — Sonnet workers, one worktree + one PR per finding
```

Two stages, **gated by default**. The gate is a deliberate stop so a human reads
the findings before any code is touched. `--yes` chains straight through.

---

## `improve-architecture-pipeline.sh`

```
Usage: improve-architecture-pipeline.sh [options] [<repo-path>]
```

`<repo-path>` defaults to `.`.

### Options

| Flag | Effect |
|------|--------|
| `--yes` | Chain past the review gate into stage 2 (address). Without it, stop after writing reports. |
| `--limit N` | Address at most `N` findings this run (the PR unit). Rest deferred to a later run. Env: `MAX_FINDINGS`. |
| `--resume` | Self-healing re-run: skip a fresh scan if reports exist, and pass `--resume` to the scheduler (reconcile shipped findings, re-dispatch dead workers — no duplicate PRs). |
| `--rescan` | Force a fresh stage 1 (clears prior `reports/*.md` first). Mutually exclusive with `--resume`. |
| `--cleanup` | Delegate to the scheduler's `--cleanup` (sweep stale worktrees keyed off the existing reports), then exit. |
| `--runtime <claude\|pi>` | LLM runtime for the scan + workers (default: `claude`). Env: `WF_RUNTIME`. `claude` is today's behaviour; `pi` runs the pipeline headless on the `pi` CLI (no subagents, inline dispatch). Exported so the stage-2 scheduler inherits it. |
| `-h`, `--help` | Show help. |

### Environment

| Var | Default | Meaning |
|-----|---------|---------|
| `WF_RUNTIME` | `claude` | `claude` \| `pi` — selects the LLM runtime for stage 1 (scan) and stage 2 (judge + workers). |
| `ARCH_FIND_MODEL` | `claude-opus-4-8` | Claude: model for the stage-1 analysis (one deep pass). |
| `CLAUDE_MODEL` | `claude-sonnet-4-6` | Claude: model for stage-2 judge + workers (passed through to the scheduler). |
| `PI_SCAN_MODEL` | pi default | Pi: model for the stage-1 analysis (omit `--model` → pi configured default). |
| `PI_JUDGE_MODEL` | pi default | Pi: model for the stage-2 triage judge. |
| `PI_WORKER_MODEL` | pi default | Pi: model for stage-2 workers. |
| `MAX_PARALLEL` | `2` | Stage-2 worker pool size. |
| `MAX_FINDINGS` | `0` (no limit) | Default for `--limit`. |
| `NO_COLOR` | — | Disable ANSI. |

### Preflight

Refuses to run unless: target is a git repo, has an `origin` remote, `gh` is
on `PATH`, and the selected runtime's CLI is on `PATH` (`claude` when
`WF_RUNTIME=claude`, `pi` when `WF_RUNTIME=pi`). On the scan path it ensures
`reports/` exists and is gitignored in the target (`reports/` is uncommitted
scratch — the durable outputs are the PRs).

### Stage 1 (find)

Runs `claude -p` with a scan-only prompt override against the
`improve-codebase-architecture` analysis: explore + identify deepening
opportunities, **skip** the interactive candidate-presentation and grilling loop,
and write each opportunity as an `audit-finding`-format H2 into
`reports/architecture-<unit>.md`. Never prompts.

With `WF_RUNTIME=pi`, the scan runs headless on the `pi` CLI (`pi -p --mode json
--approve --exclude-tools ask_question`, the arch skill loaded via `--skill`); the
prompt is adapted for Pi's no-subagent model (explore inline) but the report
contract is identical. Usage is auto-detected per log format (Claude `result`
line vs Pi summed `turn_end` events).

**Scan is skipped by default if reports already exist** (avoids a duplicate
expensive Opus pass on an accidental re-run). `--rescan` forces a fresh scan,
clearing prior reports first.

### Gate

Tallies open findings across the reports and logs the count. Without `--yes` it
prints the report list + the exact next-step command and stops.

### Stage 2 (address)

Invokes `address-reports.sh` with cwd in the target repo, passing the reports
plus `--resume` / `--limit` through. Inherits `WF_RUNTIME` + `CLAUDE_MODEL` (or
the `PI_*_MODEL` vars) + `MAX_PARALLEL`.

### Outputs

| Path | Contents |
|------|----------|
| `<repo>/reports/*.md` | One report per finding (gitignored scratch). |
| `<repo>/reports/.pipeline.log` | Stage-1 + orchestrator events: `SCAN`, `REPORT`, `GATE`, `STAGE2`, `MANIFEST`. |
| `<repo>/reports/.scheduler.log` | Stage-2 scheduler events (see below). |

The final `MANIFEST` block records, per report, how many findings were addressed
vs. remaining, the per-finding PR numbers, and how many worktrees were kept.

---

## `address-reports.sh`

```
Usage: address-reports.sh [-h] [--resume] [--limit N] [--cleanup] <report-path>...
```

Processes all open H2 findings across one or more reports in parallel via git
worktrees. One PR per finding. A single shared pool is gated by `MAX_PARALLEL`.
**The scheduler is the sole writer of the report files** — workers never touch
them (that would race). It marks `— RESOLVED (YYYY-MM-DD, #PR)` on each H2 only
after that finding's PR is open.

### Options

| Flag | Effect |
|------|--------|
| `--resume` | Reconcile a prior interrupted run against GitHub. If a finding's branch already has an OPEN/MERGED PR → mark it RESOLVED and drop it (no duplicate PR). If a worktree was left but no terminal PR → remove worktree + stale local/remote branch and re-dispatch fresh. Without `--resume` the run fails closed on any stale worktree (forces inspection). |
| `--limit N` | Address at most `N` open findings this run (worklist order). Env: `MAX_FINDINGS`. |
| `--cleanup` | Sweep stale `.worktrees/<base>-*` siblings for the given report basenames, then exit. |
| `-h`, `--help` | Show help. |

### Environment

| Var | Default | Meaning |
|-----|---------|---------|
| `WF_RUNTIME` | `claude` | `claude` \| `pi` — selects the LLM runtime for the judge + workers (inherited from the pipeline). |
| `MAX_PARALLEL` | `2` | Worker pool size, shared across all reports. |
| `MAX_FINDINGS` | `0` | Default for `--limit`. |
| `CLAUDE_MODEL` | `claude-sonnet-4-6` | Claude: model passed to `claude --model`. |
| `PI_JUDGE_MODEL` | pi default | Pi: model for the triage judge. |
| `PI_WORKER_MODEL` | pi default | Pi: model for workers. |
| `DRY_RUN=1` | — | Print the planned worklist; spawn no workers, open no PRs. |
| `NO_COLOR=1` | — | Disable ANSI (auto-off when not a TTY). |

### How a finding becomes a PR

1. Scheduler pins `BASE_SHA` = `origin/main`.
2. Per finding, a worker adds a worktree on branch `address/<base>-<slug>` from
   `BASE_SHA` and runs `/address-findings <report> --finding <slug> --auto`.
3. The skill implements the fix (TDD for behavior changes), runs verification
   resolved from `.workflow.yml gate_pool` (Rust → `cargo check`, TS →
   `tsc --noEmit` fallback), runs a 3-agent review, then ships via `/quick-ship`.
4. On success the scheduler marks the H2 RESOLVED and removes the worktree. On
   failure the worktree is kept for inspection.

### Resume model

The report file is the durable work queue. A finding is RESOLVED only after its
PR is open, and the deterministic branch name (`address/<base>-<slug>`) is the
key. `--resume` is idempotent: shipped findings are reconciled, dead ones
re-dispatched, none duplicated. Batching (`--limit`) and resume compose — a later
run with the same `--limit` continues with the next batch because resolved
findings are filtered out.

### Interrupts

Both scripts trap `SIGINT`/`SIGTERM`: they stop in-flight workers (including the
`claude` grandchild), leave worktrees + reports intact (resumable), and print the
exact `--resume` command before exiting.

---

## Worked examples

```bash
# 1. Find only — write reports, stop at the gate for review
improve-architecture-pipeline.sh ~/code/myrepo

# 2. Review reports/, then address the first 2 findings
improve-architecture-pipeline.sh --yes --limit 2 ~/code/myrepo

# 3. Next batch (no re-scan, no duplicate PRs for batch 1)
improve-architecture-pipeline.sh --yes --limit 2 ~/code/myrepo

# 4. A run was Ctrl-C'd — self-heal and continue
improve-architecture-pipeline.sh --resume ~/code/myrepo

# 5. Force a fresh analysis
improve-architecture-pipeline.sh --rescan ~/code/myrepo

# 6. Sweep stale worktrees
improve-architecture-pipeline.sh --cleanup ~/code/myrepo

# Scheduler standalone — dry-run the worklist for a hand-written report
DRY_RUN=1 address-reports.sh reports/architecture-user.md

# Scheduler standalone — 4 workers across two reports
MAX_PARALLEL=4 address-reports.sh reports/arch-user.md reports/arch-ai.md
```

## Report format

Reports are plain markdown, one finding per H2, written by the `audit-finding`
skill (or stage 1). Each H2 carries `**Severity**`, `**Files**`, `**Problem**`,
`**Fix**`. A heading ending in `— RESOLVED (YYYY-MM-DD, #PR)` is closed; anything
else is open. See `skills/audit-finding/references/report-template.md`.

## Related pieces

- `skills/audit-finding/` — captures + propagates a finding across the repo.
- `skills/address-findings/` — fixes one finding (consumed by the scheduler).
- `improve-codebase-architecture` (vendored skill) — the stage-1 analysis.
