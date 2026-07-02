# Chunk the delegated `/implement` loop across bounded contexts

Status: accepted

Extends (does **not** supersede) [ADR-0004](0004-delegate-implement-tdd-loop-to-specialist.md).

## Context

ADR-0004 delegates a Task's whole TDD loop to **one** `implementer:` specialist
that owns it in **one** context. That decision keeps main's context flat, but it
silently assumes the specialist can hold the loop in a *single* context. On a
non-trivial Task that one context still accretes the whole lifecycle — design.md
/ ground-rule bodies, a growing diff, a long behavior backlog, and inline
debugging — and grows abruptly. The confirmed root cause is **doc + diff
accumulation** under whole-Task ownership, not debug loops or raw behavior count.
The pain is **peak context per agent** (degraded reasoning / context limits at
high load), not dollar cost.

ADR-0004's core decision ("**one Task = one implementer**") is sound and stays
untouched. Only its hidden assumption — that the implementer owns the loop in a
*single* context — needs amending.

## Decision

The **same** `implementer:` specialist owns the TDD loop across a **sequence of
bounded contexts**. After step 9 settles the ordered behavior backlog, main cuts
that backlog into fixed-size chunks and re-spawns that one specialist per chunk
with fresh context, threading a cumulative `impl_notes` ledger forward.

- **Mechanical backlog chunking, not semantic seam-finding.** Main cuts the
  already-settled *ordered* backlog into runs of **≤ K whole behaviors**. No
  planner, no "find the split point." Chunks cut *between* whole behaviors — a
  test is never split from its code (vertical-slice integrity preserved).
- **K = behavior count, default 3, per-tier default with per-spec override.**
  Exported as `WF_IMPL_CHUNK_SIZE` by `config-loader.sh` (per-spec
  `impl_chunk_size` → `.workflow.yml tiers.<tier>.impl_chunk_size` → hardcoded
  `3`). A deterministic, crude-but-robust proxy for context load.
- **`small` tier never chunks.** The loader forces `WF_IMPL_CHUNK_SIZE = 0`
  (off) for `small` regardless of any override; `0` = one delegated spawn.
  `/implement` also gates on `WF_SPEC_TIER != small` (belt-and-suspenders).
- **Same implementer for all chunks.** Chunking ⊥ agent selection. ADR-0004's
  "one Task = one implementer" holds. Mixed-surface Tasks remain a
  `generalist` / PM-re-slice concern, not a chunk concern.
- **Cumulative `impl_notes` ledger.** Reuse the existing delegated-return schema.
  Main accumulates each chunk's `impl_notes` and passes the running ledger + disk
  state + next backlog slice into the next chunk. Prior behaviors are already
  green on disk in the shared working tree; the ledger tells the next specialist
  what was built and why.
- **Full-suite-green each chunk.** Every chunk runs the **full** suite and keeps
  **all** prior behaviors green — this is what catches a later chunk regressing
  an earlier one.
- **Final chunk owns the closing refactor.** Local refactor within each chunk
  (normal TDD); the **final** chunk (first to reach whole-backlog-green) performs
  the closing whole-diff refactor, reading the whole-task diff (the
  branch-strategy-aware range `/implement` already uses for the post-impl
  quality check — `feat/<f>...HEAD` on `per-task`, `task_base_sha..HEAD` on
  `single-branch`) + the ledger. No separate refactor spawn. Earlier chunks
  refactor locally only.
- **Delegated path only.** `generalist`/inline stays whole-in-main, unchanged. A
  glue Task big enough to need chunking is a PM mis-slice signal, not a chunk
  target.
- **Full re-read each chunk.** Each chunk's specialist reads its
  design/ground-rule **paths** itself (scope + architecture paths re-passed every
  chunk). Accept more total tokens for a flatter peak. No chunk-1 digest in v1.
  Main **never** reads design bodies (ADR-0004 hygiene preserved).
- **Disk is the resume truth.** Persist **nothing** new for crash/resume.
  `/continue-task` re-runs the suite: green tests on disk = done behaviors →
  re-chunk the remainder and continue. The in-session ledger is a best-effort
  bonus.
- **No new telemetry.** Chunking stays invisible to the monitor.
  `tdd_red`/`tdd_green` remain absent on the delegated path (unchanged from
  ADR-0004). The one audit trail is `chunks_spawned: N` — a persisted note-field
  written by main into the task's merged implementation notes (main owns the
  fan-out), **not** a monitor event.

Thin Tasks (backlog ≤ K) produce exactly one chunk = today's ADR-0004 delegated
behavior, unchanged (`chunks_spawned: 1`).

## Considered Options

- **GREEN-only chunking** (main writes the RED test per chunk, specialist makes
  it pass) — a revival of ADR-0004's rejected GREEN-only delegation; rejected for
  the same reason: keeps test-authoring in main, so main context grows with Task
  size again, defeating the purpose. Not revived here.
- **Per-chunk *different* agents** (route each chunk to a best-fit specialist) —
  rejected: breaks ADR-0004's "one Task = one implementer" and requires
  cross-agent seam reasoning the mechanical split deliberately avoids. Mixed
  surfaces stay a `generalist`/PM-re-slice concern. Not revived here.
- **Semantic seam-finding** (a planner picks split points by cohesion) —
  rejected: adds a planning agent and non-determinism for no proven gain over a
  fixed behavior-count budget; the backlog is already ordered.
- **Chunk-1 digest** (chunk 1 summarizes design so later chunks skip the re-read)
  — deferred, not rejected: revisit only if re-read cost shows up in profiling.
  v1 accepts full re-read for simplicity.

## Consequences

- `+` Peak context per agent stays bounded regardless of Task size — the headline
  win over ADR-0004's single-context assumption.
- `+` Thin Tasks and `small` tier are untouched — exact ADR-0004 behavior, so no
  regression for the common case.
- `+` Crash recovery is free: green tests on disk drive re-chunking; nothing new
  to persist.
- `+` `chunks_spawned: N` gives a lightweight audit trail without new monitor
  events.
- `−` More total tokens: full re-read of design/ground-rule paths per chunk (the
  peak-vs-total trade, accepted).
- `−` Extra spawn latency per chunk (serial, one Task in flight).
- `−` `tdd_red`/`tdd_green` telemetry still absent on the delegated path
  (inherited from ADR-0004, not made worse).
- `−` Salvage note: this chunking logic is input for the `flowctl` rewrite —
  record it so it does not silently reappear un-specced there.
