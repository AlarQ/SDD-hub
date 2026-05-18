# Architecture Review — 2026-05-18

Deepening opportunities surfaced by `/improve-codebase-architecture`. Scope: `scripts/` bash modules + `workflow-tui/` Rust. No `CONTEXT.md` present. One ADR (`docs/adr/0001-tdd-implement-loop.md`) — none of these candidates touch it.

Vocabulary: **module** = interface + implementation; **deep** = lots of behaviour behind a small interface; **seam** = where behaviour can be altered without editing in place; **deletion test** = if deleting the module concentrates complexity, it earns its keep.

---

## 1. Frontmatter parsing — three implementations, no seam

**Files:** `scripts/task-manager.sh` (yq), `scripts/gate-ceiling.sh` (awk regex, lines 33–44), `scripts/validate-impl.sh` (grep), plus the well-formed `workflow-tui/src/parse/frontmatter.rs`.

**Problem:** One concept — "read task/spec frontmatter" — parsed three different fragile ways in bash. `gate-ceiling.sh`'s awk regex assumes exact YAML spacing and silently returns empty on drift. A schema change requires editing 3 places with no shared contract to catch a miss.

**Solution:** One deep `task-frontmatter.sh` module (yq-backed, mirroring the Rust `extract_frontmatter`). All bash callers route through it.

**Benefit:** Locality — frontmatter schema knowledge in one place. Leverage — small read/write interface hides yq quirks. Testable in isolation (currently needs a full spec tree). Deletion test passes: remove it and fragile parsing reappears across 3 callers.

## 2. `wf_load_config` — 485-LOC monolith function

**File:** `scripts/config-loader.sh` (lines ~66–550).

**Problem:** One function does path resolution, vault/repo branching, tier resolution, the multi-repo loop, and ~20 interdependent env-var exports. Cannot test "does my spec.yml parse?" without running all of it. An early error kills later code, so callers cannot tell what failed. Shallow wrappers (`tier-check.sh`) just front it.

**Solution:** Split behind the stable env-var contract into deep sub-modules: spec-resolve, repo-resolve, tier-resolve. `wf_load_config` becomes a thin composer.

**Benefit:** The interface is the test surface — each piece independently testable. Locality of error states. Leverage unchanged for callers (same exported env-var contract).

## 3. task-manager ↔ monitor — coupled through file format

**Files:** `scripts/task-manager.sh` (`emit_transition_event`, `maybe_emit_spec_last_task_done`, lines ~60–123), `scripts/monitor.sh`, `scripts/config-loader.sh` (emits `gate_pool_dirty`, lines ~300–320).

**Problem:** The task state machine reads `.monitor.jsonl` raw, greps event categories, and hardcodes the schema. `config-loader` — nominally a pure loader — has monitor side effects. A monitor schema change breaks task-manager silently. There is no `set-status` without side effects.

**Solution:** Introduce a real seam — task-manager and config-loader emit a structured event to one sink module; the sink owns the monitor file format. Loader stays pure.

**Benefit:** Two adapters (real sink + null/test sink) = testable state transitions without a monitor file. Locality — event-schema knowledge leaves task-manager.

## 4. Task dependency logic — duplicated, one half unguarded

**Files:** `scripts/task-unblock.sh` vs `scripts/task-status.sh`.

**Problem:** Both implement `blocked_by` resolution independently. `task-status.sh` has Kahn cycle detection; `task-unblock.sh` has none → a cycle is a silent infinite loop. A schema change requires editing both.

**Solution:** Shared deep dependency-graph module (build graph, detect cycles, query unblocks). Both callers consume it.

**Benefit:** Locality — one dependency model; the cycle bug is fixed once. Leverage — graph behind a small interface. Deletion test passes (complexity concentrates).

## 5. Rust model carries a UI concern

**Files:** `workflow-tui/src/model/task.rs` (`TaskStatus::color`, `Interaction::color`, lines ~18–27, 54–59), consumed by `workflow-tui/src/ui/spec_list.rs`.

**Problem:** The model imports ratatui `Color` — the data layer knows about rendering. Colour scheme is split across `task.rs` and `ui/styles.rs`.

**Solution:** Move colour mapping into `ui/` next to `styles.rs`. Model becomes ratatui-agnostic.

**Benefit:** Clean seam between data and render. Single colour source. Smaller change than 1–4.

## 6. Health diagnostics buried in UI render

**File:** `workflow-tui/src/ui/progress.rs` (lines ~124–148).

**Problem:** Deadlock detection and status categorization live inside the render function — untestable and unreusable. `dep_graph.rs` recomputes the reverse-dependency map separately.

**Solution:** Extract `model/health.rs` — `diagnose_spec(&Spec) -> Vec<HealthIssue>`. UI renders the result only.

**Benefit:** The interface is the test surface — diagnostics gain unit tests. Reusable by `dep_graph` and `progress`.

---

## Priority

| # | Candidate | Type | Leverage |
|---|-----------|------|----------|
| 1 | Frontmatter parsing seam | Shallow→deep, fragile parsing | High |
| 2 | `wf_load_config` split | Untestable monolith | High |
| 3 | task-manager ↔ monitor seam | Tight coupling, silent failure | High |
| 4 | Dependency-graph module | Duplication, unguarded cycle bug | Med-High |
| 5 | Model colour → UI | Separation-of-concerns | Low |
| 6 | `model/health.rs` extract | Business logic in UI | Low-Med |

Strongest leverage: **#1**, **#2** (bash testability is the worst pain). **#3 / #4** fix silent-failure bugs. **#5 / #6** smaller Rust hygiene.
