# Architecture Review — 2026-06-03

Deepening review (Ousterhout deep-vs-shallow lens) of the live bash/markdown
spec-driven workflow. Vocabulary: domain terms per `CONTEXT.md`; architecture
terms (module, interface, seam, depth, locality, leverage, deletion test) per
the `improve-codebase-architecture` skill's `LANGUAGE.md`.

## Status context

Repo is **LIVE but slated for deprecation** (successor: Rust `flowctl` in parent
`future-proof-oss/`, ADR-0006). Candidates 1–6 are worth doing while live; they
**also double as the salvage checklist** for the Rust rewrite — the same friction
will reappear in `flowctl` if not named now. Candidate 7 (deletion) is zero-risk
and should happen regardless.

Scouts: 4 parallel `Explore` agents over bash scripts, Rust crates, command/agent
markdown, and docs/tests.

---

## 1. Config resolution — one deep module, not a god script + 3 clones

**Files:** `scripts/config-loader.sh` (779 lines), `scripts/config-paths.sh`,
plus repo-root resolution re-implemented in `scripts/task-manager.sh:32-44`,
`scripts/monitor.sh:49-56`.

**Problem:** `wf_load_config()` alone is **579 lines with 21 error-return paths**;
the `wf__unset_partials` cleanup ritual is repeated ~45× (lines 144,150,168,186,…,644).
One function holds 9 unrelated jobs: path-safety validation (45-108), yaml/json
parse (34-81), walk-up root resolution + repo-gate-pool marker handling (141-174),
multi-part extraction (183-305), gate-pool validation w/ monitor side-effects
(307-341), per-spec config (343-652), snapshot/drift via embedded Python (696-738),
CLI export mode (741-778). **Repo-root resolution exists in 3 divergent copies:**
`config-paths.sh:110-123` (specs-dir walk fallback), `task-manager.sh:32-44`
(git-root fallback), `monitor.sh:49-56` (neither). They silently disagree on the
`repo-gate-pool` marker that only config-loader handles.

**Solution:** One **config resolution** module, small interface
(`load --spec X` → exported env). Path-safety, root-resolution, snapshot become
private behind it. Every other script calls the one resolver instead of rolling
its own root-walk.

**Benefits (locality + leverage):** Root-resolution logic, gate-marker semantics,
and error vocabulary live in ONE place. Deletion test: removing the 3 clones
*concentrates* complexity, doesn't move it. The 579-line function splits into
testable pieces — the interface becomes the test surface. Leverage: every command
re-derives config today; they'd get it from one deep call.

**Severity:** High. **Salvage:** Yes — split into composable Rust modules
(spec-resolve, repo-resolve, tier-resolve) in `flowctl`.

---

## 2. Task state machine — deep Task module, not 3 pure-dispatch shards

**Files:** `scripts/task-manager.sh`, `scripts/task-status.sh`,
`scripts/task-unblock.sh`.

**Problem:** `task-status.sh` (~195 lines) and `task-unblock.sh` (~84 lines) are
**pure dispatch with no exported helpers** — they import `read_frontmatter`,
`update_frontmatter`, `emit_transition_event`, `die` from task-manager. This is a
seam that isn't real: hidden coupling that breaks silently if a signature drifts
(`task-unblock.sh` calls `emit_transition_event` defined in `task-manager.sh:60-86`).
`blocked_by` dependency-graph logic is duplicated across status + unblock, and
**one has cycle detection while the other has an unguarded infinite loop**
(per `docs/architecture-review-2026-05-18.md`).

**Solution:** Collapse into one **Task** module owning the state machine
(`blocked → todo → in-progress → implemented → review → done`, canonical in
task-manager) and the dependency graph behind a small interface. No three-file
split that buys nothing.

**Benefits:** The cycle-detection bug vanishes (one graph impl). Atomic
frontmatter mutation (`update_frontmatter`, task-manager.sh:222-250) lives once.
Locality: a state-machine change touches one file. Deletion test: merging
concentrates.

**Severity:** Medium-High. **Salvage:** Yes — shared Rust graph module.

---

## 3. Leaf I/O module — kill 3 yq wrappers + escape-source coupling

**Files:** `config-paths.sh` (`wf_with_timeout`, line 129), `config-loader.sh`
(`wf__timeout`, 14-15), `task-manager.sh` (`_wf_yq`, 170-172);
`escape_json_string` defined in `monitor.sh:43` but consumed by
`task-manager.sh:73-81` and `validate-impl.sh` (152,173,181,187,198,374);
`validate_id` defined in `config-paths.sh:146`, called 11× across scripts.

**Problem:** Three competing yq-timeout shims. `gate-ceiling.sh:59,71` and
`tier-check.sh:34` call **bare yq — can hang forever** on malformed YAML, and
they sit on the hot path (`/validate`, `/validate-impl`). `escape_json_string`
living in monitor.sh means any caller breaks silently if source order is wrong;
YAML escaping (`_wf_vi_yaml_dq` in validate-impl) is a separate, incompatible
impl.

**Solution:** One leaf **io** module — timeout-wrapped yq, json + yaml escaping,
`validate_id` — sourced by everyone. No upward dependencies (leaf).

**Benefits:** Hang risk removed everywhere. One escape impl, no source-order
landmine. Pure leaf = trivially testable. Small interface, high reuse = deep.

**Severity:** Medium (High for the bare-yq hang). **Salvage:** Folded into the
Rust core's typed YAML layer.

---

## 4. Rust: collapse scanner clones, delete speculative seams

**Files:** `workflow-core/src/parse/scanner/{tasks,reports,monitor}.rs`,
`parse/{task_parser,report_parser,frontmatter}.rs`, `watch.rs`,
`workflow-tui/`, `workflow-web/`.

**Problem:** Three scanner modules (~45 LOC each) are mechanically identical —
dir-walk + ext-filter + size-cap + symlink check + `ParseWarning` construction —
differing only in extension and parse fn. A symlink/size-cap bug needs three
fixes. The parsers (`parse_task`, `parse_report`) are **serde_yml wrappers adding
zero leverage** (interface ≈ implementation; 1–8 LOC of real code). `watch.rs` is
a **speculative seam: zero implementors, and the `WatchSource` trait CLAUDE.md
claims doesn't actually exist** — only a `WatchEvent` enum used nowhere in
production. `workflow-tui/` is an orphan — no `src/`, not in `Cargo.toml` workspace
members, only stale `target/` artifacts. `workflow-web/` is a ~10-LOC placeholder
that contradicts flowctl's stated "no end-user UI surface" direction.

**Solution:** Generic `scan_dir<T: Parse>` (extension + parser injected) over the
three clones. Delete `watch.rs` until a real 2nd implementor exists (one adapter =
hypothetical seam). Delete `workflow-tui/`. Decide web-vs-flowctl — likely delete
`workflow-web/`.

**Benefits:** Security assumptions (symlink, size cap) concentrate in one scanner.
Deletion test strongly positive: 3 clones + 2 dead crates collapse. Removes the
"where is the watcher impl?" confusion for future readers.

**Severity:** Medium (High for web/flowctl strategic conflict). **Salvage:**
The scan abstraction is worth carrying; the web crate is not.

---

## 5. Command prose — DRY via shared phase-contract

**Files:** all `commands/*.md`.

**Problem:** KB-prerequisite prose is copy-pasted in **13 commands**
(bootstrap:10, config:8, continue-task:6, explore:4, implement:6,
learn-from-reports:10, propose:6, review-findings:6, ship:6, spec-status:6,
validate-impl:9, validate:8, capture-rule:19). Step-0 config-loader invocation is
duplicated in **6** commands. Multi-repo resolution is applied at **inconsistent
hook points across 5 commands** (validate:25, validate-impl:71, implement:45,
ship:36, review-findings: 3× at 18/27/53) — no standard "when." Monitor-event
emission is ad-hoc per command (emit before vs after approval varies). Adding one
env var = editing 6 files.

**Solution:** Pull the repeated blocks into single referenced contracts; fix
multi-repo resolution to one standard step position. (This is exactly the parent's
`.flow` phase-contract DRY anchor, D48 — proves the direction.)

**Benefits:** Single source of truth; drift dies. Each command shrinks to its
genuinely-unique logic.

**Severity:** Medium (High for multi-repo scatter — gate logic varies by phase,
masking bugs). **Salvage:** Yes — the phase-contract is already the parent's model.

---

## 6. Config-axis explosion (simplification, not deepening)

**Axes:** `tier × track × branch_strategy × validate_scope × coverage_audit ×
interaction × implementer`. Each command grows 2–3 conditional branches
(`/implement` has ~5 major branches). Combinations are untested and some are
redundant (`coverage_audit:false` is already implied by `small` tier or
`per-spec` scope; `single-branch` lacks the tier-breach continue/abort gate that
`per-task` has — possible asymmetry bug).

**Solution:** Cull knobs (drop `coverage_audit` as a standalone escape hatch;
fold `validate_scope` into a runtime toggle) OR write a formal combination test
matrix. This is a knob-reduction, not a seam fix.

**Severity:** High for maintainability. **Salvage:** Decide the axis set *before*
the Rust rewrite — don't port the combinatorial prose.

---

## 7. Pure deletion (do regardless of the above)

- `agents-unused/` — 16 files, **zero references** from any command. Dead weight.
- `workflow-tui/` — orphan crate, no `src/`.
- Stale root design docs, all implemented/superseded:
  `configurable-PR-creation.md` (→ ADR-0003), `project_kb_removal.md` (→ ADR-0002),
  `opencode-migration.md` (OpenCode not a stated target), `audit-findings.md`
  (15/21 DONE, historical), `todo.md` (3 contextless lines).
- `CLAUDE.md` is doing glossary + decision-log + ADR-index + command-reference at
  once (30KB) — the parent split these into an mdBook; this repo did not. Thin it
  while live; don't maintain parity with the parent book.

**Effort:** ~40min. **Risk:** zero. **Value:** removes ~1.3K lines of historical
noise and the "which agents actually exist?" ambiguity.

---

## Open issues these intersect (from prior audits)

From `docs/workflow-audit-2026-05-04.md`, still open and overlapping the above:
review-findings grouping logic unimplemented; parallel-agent file mutex
unimplemented; monitor hook (`monitor-tool-calls.sh`) never wired into
`templates/settings.json` / `setup.sh`; snapshot drift invisible within one shell.
Missing dedicated tests: `tier-check.sh`, `task-status.sh`, `task-unblock.sh`.

---

## Priority

| # | Candidate | Type | Severity | Deletion test | Salvage to Rust |
|---|-----------|------|----------|---------------|-----------------|
| 7 | Delete cruft | Hygiene | — | n/a | n/a |
| 1 | Config resolution | God script + clones | High | Concentrates | Yes |
| 2 | Task module | Shallow shard + bug | Med-High | Concentrates | Yes |
| 3 | Leaf I/O module | Duplication + hang | Med (High hang) | Concentrates | Yes |
| 4 | Rust scanners | Clones + dead seams | Med (High web) | Concentrates | Partial |
| 5 | Command prose | Duplication | Med (High multi-repo) | Concentrates | Yes |
| 6 | Axis explosion | Over-engineering | High maint. | Simplify | Decide first |

Recommended order: **7** (free) → **1** (highest leverage) → **2** → **3** → **5** → **4** → **6**.
