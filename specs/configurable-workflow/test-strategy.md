---
name: configurable-workflow
type: test-strategy
---

# Test Strategy — Configurable Workflow

## Overview

Layer tests by trust boundary: T001/T002 own shell loader invariants (paths, IDs, exits), T005 mirrors them in Rust, T003 owns cwd-walk-up integration for shell callers, T007 owns the single intersection computation in Rust with shell/Rust parity, T004 owns phase-command ceiling semantics, T011 owns end-to-end dogfood against a non-default `spec_storage`.

## Fixture Ownership

`tests/fixtures/config/` is shared across T001 (creates), T002 (extends), T005 (consumes read-only from Rust), T013 (extends with `validate_scope` variants), and others that reuse fixtures.

**Single-owner rule for fixture *schema*:** T001 owns the shape of every fixture file it creates. Any task that needs to **change an existing fixture's shape** (rename a key, add a required field, remove a field, alter a value's semantics) MUST edit T001's test suite in the same PR so its assertions stay coherent.

**Additive rule:** Any task MAY **add new fixture files** to `tests/fixtures/config/` without touching T001. New fixtures are owned by the task that introduces them (T002 → loader-specific fixtures; T013 → scope variants; etc.). Each task's §Shared fixtures (creates) bullet is its authoritative fixture inventory.

**Conflict resolution:** if two tasks in flight both propose shape changes to the same T001-owned fixture, the later task rebases onto the earlier; no fixture file has two concurrent owners.

## Task Test Responsibilities

### T001 — scaffold-config-paths-and-gates-registry
- **Theme:** primitive safety — walk-up, realpath defense, ID allowlist, gates.yml schema
- **Owns:**
  - `find_workflow_root` walk-up from nested subdir + missing-marker failure
  - `realpath_safe` `../../` and symlink-ancestor rejection
  - `validate_id` accept/reject (hyphen, shell metachars, 65-char length)
  - `gates.yml` well-formedness, unique IDs, required field presence
  - CI grep guard: `config-paths.sh` sources no workflow script
- **Must NOT test:** WF_* env exports (T002), spec-config referential integrity (T002), caller cwd (T003)
- **Integration seams:** none
- **Shared fixtures (creates):** `tests/fixtures/config/workflow-valid.yml`, `gates-valid.yml`, `gates-duplicate-id.yml`, `symlink-ancestor/` tree, `nested/deep/cwd/` for walk-up

### T002 — config-loader-shell
- **Theme:** loader contract — WF_* exports, exit codes, single-parse caching
- **Owns:**
  - WF_SPEC_STORAGE export from valid `.workflow.yml`
  - Missing file → exit 0 with defaults
  - `gates.yml` malformed → exit 3; unknown spec gate → exit 4; path traversal → exit 2
  - yq billion-laughs → exit 5 within 5 s
  - Idempotency guard (`WF_CONFIG_LOADED=1`)
  - CLI `export` mode emits evaluable `KEY=VAL`
  - `--spec` populates `WF_SPEC_GATES` / `WF_SPEC_AGENTS_<PHASE>` / `WF_SPEC_HAS_CONFIG`
  - Uncommitted `gates.yml` stderr warning (non-blocking)
  - CI grep guard: no `source` of workflow scripts from loader
- **Must NOT test:** primitive helpers (T001), caller semantics (T003)
- **Integration seams:** loader ↔ `config-paths.sh` (one-way dep assertion)
- **Shared fixtures (creates):** `workflow-vault.yml` (spec_storage=/tmp/vault), `spec-config-valid.yml`, `spec-config-unknown-gate.yml`, `billion-laughs.yml`

### T003 — refactor-shell-callers-to-loader
- **Theme:** caller cwd independence + `$WF_SPEC_STORAGE` honored, no global fallback leaks
- **Owns:**
  - `monitor.sh` from nested cwd writes under `$WF_SPEC_STORAGE/<feature>/.monitor.jsonl`
  - Four new event categories accepted; unknown rejected
  - `$HOME → ~` redaction in event output
  - `task-manager.sh validate` from deep subdir
  - `pre-commit-hook.sh` from subdir (via `git rev-parse --show-toplevel`)
  - Vault case: `/tmp/vault` routing, never `./specs`
  - Legacy `.workflow.yml`-absent fallback still works
  - Negative test: "no global `~/specs` fallback" when `WF_SPEC_STORAGE` set
- **Must NOT test:** loader internals (T002), phase-command ceiling (T004)
- **Integration seams:**
  - Shell caller ↔ loader WF_* contract end-to-end
  - Pre-commit CLI `eval` mode
- **Shared fixtures (creates):** `tests/fixtures/nested-subdir-repo/` (real git init for hook cwd reproduction)

> T003 also owns adding `config_inferred`, `config_approved`, `agent_spawn`, `gate_skip` to the `monitor.sh` closed allowlist. T014 adds `spec_audit_start`, `spec_audit_done`. T015 adds `spec_complete`, `spec_reopened`, `spec_last_task_done`. T017 adds `spec_reaudit_requested`. Each task's test cases must include a grep check that the new categories appear in the allowlist.

### T004 — phase-commands-read-spec-config
- **Theme:** ceiling semantics — intersection, fail-closed empty, drift detection
- **Owns:**
  - `/validate` intersection (spec ceiling ∩ ground_rules eligible)
  - `gate_skip` emission for ground_rules gate outside ceiling
  - Empty intersection on code task blocks `done` transition
  - Missing `config.yml` legacy fallback (full ground_rules set, silent)
  - `/implement` snapshot + `/ship` mid-task drift detection (normalized JSON compare: whitespace edit → no drift; gate removed/added → drift)
  - Unknown agent ID in spec config → phase command exits non-zero
  - Doc-only empty-OK task passes with zero gates
- **Must NOT test:** loader exit codes (T002), TUI pipeline rendering (T007)
- **Integration seams:**
  - Phase command ↔ loader `--spec` ↔ `gates.yml` filter
  - `/implement` snapshot ↔ `/ship` drift comparison
- **Shared fixtures (creates):** `tests/fixtures/config/task-rust-ground-rules.md`, `task-doc-only-empty-ok.md`

### T005 — tui-config-parsers-and-models
- **Theme:** Rust parser parity with shell loader
- **Owns:**
  - `parse::workflow_config::load` walk-up from nested cwd
  - Rust realpath defense against `../../etc`
  - `parse::spec_config::parse` returns `Ok(None)` for missing file
  - `gates.rs` duplicate IDs / unknown `applies_to` / unknown `category` rejection
  - `spec_config` rejects unknown gate/agent IDs
  - No-panic guarantee on malformed YAML (`Result::Err` only)
- **Must NOT test:** scanner integration (T006), intersection rendering (T007)
- **Integration seams:** Rust parser ↔ shared YAML fixtures (parity: same fixture, same verdict as shell)
- **Shared fixtures:** REUSES `tests/fixtures/config/*` from T001/T002 — MUST NOT duplicate. Rust reads via `CARGO_MANIFEST_DIR/../tests/fixtures/config/`.

### T006 — tui-scanner-spec-list-watcher-integration
- **Theme:** scanner honors `spec_storage` + watcher debounce + graceful legacy handling
- **Owns:**
  - Scanner reads non-default `spec_storage`
  - Legacy spec renders with "no config" indicator
  - `.workflow.yml` edit → single reload within debounce window
  - Parse error → last-good config retained + `ParseWarning` surfaced
  - `Spec.config = None` when `config.yml` absent
  - `app.rs` holds `WorkflowConfig` at top; UI gets immutable refs
- **Must NOT test:** parser-level schema (T005), pipeline widget rendering (T007)
- **Integration seams:** watcher ↔ parse ↔ app state rebuild
- **Shared fixtures:** REUSES T001/T002 fixtures; adds `workflow-tui/tests/fixtures/legacy-spec/`

### T007 — tui-pipeline-widget
- **Theme:** single source of truth for intersection rendering + shell/Rust parity
- **Owns:**
  - Pipeline widget renders ceiling gates for Rust task
  - Ceiling-skipped vs executed visual distinction
  - Empty intersection on code task → fail-closed indicator
  - Doc-only empty-OK → OK state
  - **Parity test:** intersection result equals shell loader's on same fixture (both sides emit sorted JSON `{executed, skipped}` for byte-equal compare)
  - Architectural test: no other UI module computes effective gates
- **Must NOT test:** watcher/scanner plumbing (T006), actual gate execution (T004)
- **Integration seams:** SHELL ↔ RUST intersection parity (owns this seam — final context holder)
- **Shared fixtures:** REUSES T001/T002 + T004 task fixtures; parity fixture bytes identical across shell and Rust.

### T008 — config-inferencer-agent
- **Theme:** schema-shape validity + secret-read prohibition + fallback
- **Owns:**
  - Emitted `config.yml` parses against T002/T005 validators
  - All emitted gate IDs resolve in `gates.yml`
  - All emitted agent IDs resolve under `agent_pool`
  - Prompt-contract test: forbids reading `.env*`, `*.pem`, `id_*`, `.git/config`
  - Timeout → manual-entry prompt OR default template
  - **Negative-shape assertion:** given Cargo.toml-only signals, output MUST include ≥1 gate with `applies_to` containing `rust` and MUST NOT include python/js-only gates (catches gross mis-inference without pinning exact output)
  - Schema-shape only — NO golden fixtures
- **Must NOT test:** `/explore` wiring (T009), `/config` regeneration (T010)
- **Integration seams:** none
- **Shared fixtures:** `tests/fixtures/inferencer/signal-files/{Cargo.toml,package.json}`; reuses T001 `gates-valid.yml`

### T009 — explore-step-0-wiring
- **Theme:** step 0 orchestration — spawn → summary → approval → events
- **Owns:**
  - `config-inferencer` spawned before normal explore flow
  - Summary fits one screen
  - Single-key approval writes `specs/<feature>/config.yml`
  - Both `config_inferred` + `config_approved` monitor events emitted
  - Timeout → manual-entry fallback
  - Route to `/config` override path before approval
- **Must NOT test:** inferencer output validity (T008), `/config` internals (T010)
- **Integration seams:** `/explore` ↔ inferencer ↔ `monitor.sh` event emission
- **Shared fixtures:** none

### T010 — config-command
- **Theme:** post-creation edit/regenerate lifecycle with re-resolution
- **Owns:**
  - `/config <feature>` edit flow
  - `--regenerate` re-runs inferencer and shows diff
  - Approval overwrites; rejection leaves untouched
  - Re-resolution rejects stale gate IDs
  - Re-resolution rejects stale agent IDs
  - Docs discourage direct YAML edit
- **Must NOT test:** initial `/explore` writing (T009), inferencer output (T008)
- **Integration seams:** none
- **Shared fixtures:** none

### T011 — bootstrap-and-cleanup
- **Theme:** dogfood E2E against non-default `spec_storage` + fallback removal cleanup
- **Owns:**
  - `/bootstrap` writes `.workflow.yml` with defaults in fresh repo
  - `setup.sh --force` installs all new artifacts globally
  - **E2E against `/tmp/vault`** — must explicitly exercise:
    (a) `/bootstrap` writes `.workflow.yml` in throwaway repo with `spec_storage=/tmp/vault`
    (b) `/explore` step 0 produces `config.yml` under `/tmp/vault`
    (c) monitor events land under `/tmp/vault` (not `./specs`)
    (d) TUI scanner discovers the spec
    (e) `/validate` runs a non-empty intersection
    (f) `/ship` snapshot comparison succeeds
  - Grep guard: no `specs/` hardcoded fallback remains
  - All `knowledge-base/languages/*.md` mark `validation_tools` display-only
  - Existing tests still green after fallback removal
- **Must NOT test:** individual loader units (T002), individual caller cwd tests (T003)
- **Integration seams:** FULL STACK — `.workflow.yml` → loader → callers → phase commands → TUI
- **Shared fixtures (creates):** `tests/fixtures/e2e/vault-repo/` scratch workspace

### T012 — docs-update
- **Theme:** doc consistency and diagram coverage
- **Owns:**
  - `CLAUDE.md` section exists + names three-file split, ceiling, loader
  - Mermaid updates for `/explore` step 0 and `/validate` intersection
  - `onboarding.md` walkthrough from bootstrap to approval
  - Cross-references between the three docs
- **Must NOT test:** anything runtime
- **Integration seams:** none
- **Shared fixtures:** none

### T013 — validate-scope-field-loader
- **Theme:** loader enum contract for `WF_VALIDATE_SCOPE`
- **Owns:**
  - Absent field → default `per-task` exported
  - Valid enum values (`per-task`, `per-spec`, `both`) each round-trip through loader
  - Unknown enum value (e.g. `disabled`) → exit 2, no partial exports
  - Spec-config override wins over repo-config default
  - Template files document the field with commented default
- **Must NOT test:** cadence semantics at `/validate` (T016), trigger detector (T015), audit command (T014)
- **Integration seams:** loader ↔ `config-paths.sh` (enum helper reuse)
- **Shared fixtures (creates):** `tests/fixtures/config/workflow-scope-per-task.yml`, `workflow-scope-per-spec.yml`, `workflow-scope-invalid.yml`, `spec-config-scope-override.yml`

### T014 — validate-impl-command-and-karen-wrapper
- **Theme:** audit command orchestration + Karen wrapper contract (no agent edits)
- **Owns:**
  - `/validate-impl` loads scope via config-loader `--spec`
  - FR id parsing from spec.md `### FR-N:` headings
  - Karen wrapper prompt includes FR list + PRD scope + task list + report paths + git diff range
  - Report frontmatter written with `{feature, timestamp, scope, verdict}`
  - `spec_audit_start` / `spec_audit_done` event order
  - `verdict=complete` → spec.md `status: shipped` + `spec_complete`
  - `verdict=reopen` → `spec_reopened` emitted, spec status unchanged
  - Karen invocation uses existing `agents/karen.md` (no diff to agent file)
- **Must NOT test:** trigger detection (T015), scope-dependent gate execution (T016), review-findings integration (T017)
- **Integration seams:** `/validate-impl` ↔ config-loader (`--spec`) ↔ Karen (via Agent tool) ↔ monitor events
- **Shared fixtures (creates):** `tests/fixtures/spec-audit/sample-spec/` (3 FRs, 2 tasks, stubbed Karen output for deterministic test)

### T015 — last-task-done-trigger
- **Theme:** all-done detector + auto-chain invocation
- **Owns:**
  - `set-status done` on the last non-done task emits `spec_last_task_done`
  - Detector ignores transitions when any task still non-done
  - Detector is idempotent via prior `spec_audit_done` event guard
  - `/implement` auto-chain observes the event and invokes `/validate-impl`
  - Standalone CLI `task-manager.sh set-status done` emits the event but does NOT auto-invoke (parity with existing monitor behaviour)
  - Serial-execution assumption holds: tail-grep guard is sufficient, no file lock needed
- **Must NOT test:** audit command internals (T014), scope semantics (T016), follow-up task creation (T017)
- **Integration seams:** `task-manager.sh set-status done` ↔ `.monitor.jsonl` ↔ `/implement` auto-chain observer
- **Shared fixtures (creates):** `tests/fixtures/last-task-done/` (3 task files + empty `.monitor.jsonl`)

### T016 — per-spec-gate-skip-and-union-execution
- **Theme:** scope semantics — `/validate` skip + `/validate-impl` union
- **Owns:**
  - `/validate` under `per-spec` emits `gate_skip` with `reason=scope=per-spec` and runs no gates
  - `/validate` under `per-task` matches T004 baseline
  - `/validate` under `both` matches T004 baseline AND allows T014 audit to run
  - `/validate-impl` union computation: each gate in `WF_SPEC_GATES` ∩ union of task language rules runs exactly once
  - Union execution against cumulative diff range (branch-point → HEAD)
  - Empty union on code spec fails closed even under `per-spec` (ADR-003 preserved)
  - Doc-only empty-OK tasks pass under all three modes
- **Must NOT test:** scope field parsing (T013), trigger detection (T015), audit command wrapper (T014)
- **Integration seams:** `WF_VALIDATE_SCOPE` ↔ `/validate` branch ↔ `/validate-impl` union helper ↔ `monitor.sh` accept-list
- **Shared fixtures (creates):** `tests/fixtures/scope/rust-spec-per-spec/` (2 tasks disjoint ground_rules), `tests/fixtures/scope/doc-only-per-spec/`

### T017 — spec-audit-report-review-findings-integration
- **Theme:** reopen path — `/review-findings` → follow-up task creation → FR-id allowlist enforcement
- **Owns:**
  - `/review-findings` recognises `spec-audit-*.md` reports
  - Accepted "missing FR" finding → `task-manager.sh create-followup` writes next-sequential task with inherited ground_rules
  - Follow-up task name references the FR id
  - Unknown FR id in report → fail closed, no task created, error names unknown ids + the FR list consulted
  - Rejected finding remains available for `/learn-from-reports` mining
  - `--reaudit` flag clears the `spec_audit_done` idempotency guard so T015 trigger can re-fire
  - Cycle convergence: after follow-up tasks reach done, chain re-runs `/validate-impl` until verdict=complete
- **Must NOT test:** Karen spawn (T014), scope execution (T016), trigger detection (T015)
- **Integration seams:** audit report ↔ `/review-findings` accept/reject ↔ `task-manager.sh create-followup` ↔ spec.md FR allowlist
- **Shared fixtures (creates):** `tests/fixtures/spec-audit/reopen-report-with-missing-fr.md`, `tests/fixtures/spec-audit/reopen-report-unknown-fr.md`

## Spec Coverage Map

Every BDD scenario from `spec.md` → exactly one owning task.

### Core Flow
| Scenario | Owner |
|---|---|
| Explore writes config after approval | T009 |
| Validate applies ceiling semantics | T004 |
| Missing spec config falls back to legacy | T004 |
| Gates registry loads with `applies_to` tags (FR-2) | T001 |
| Config loader exports WF_* env vars on first source (FR-10) | T002 |
| Monitor walks up for `.workflow.yml` | T003 |
| Bootstrap writes starter config | T011 |
| Config command regenerates spec config | T010 |

### Edge Cases & Errors
| Scenario | Owner |
|---|---|
| Unknown gate ID in spec config fails closed | T002 |
| `gates.yml` parse error fails closed | T002 |
| yq timeout on config parse | T002 |
| Legacy scanner tolerates missing `config.yml` | T006 |
| Inferencer failure falls back to manual | T009 (UX); T008 owns timeout → template fallback |

### Validate Scope + Spec Audit
| Scenario | Owner |
|---|---|
| per-spec mode skips per-task validate | T016 |
| last-task-done triggers spec audit | T015 |
| clean audit marks spec shipped | T014 |
| Karen finds missing FR → spec reopens | T017 |
| Reaudit cycle after follow-up tasks land | T017 |
| per-spec mode runs union at /validate-impl | T016 |
| Unknown FR id in Karen audit output rejected | T017 (allowlist); T014 reports event |
| validate_scope enum enforced | T013 |

### Security
| Scenario | Owner |
|---|---|
| Shell injection via gate ID rejected | T001 (`validate_id` primitive) |
| Path traversal via `spec_storage` rejected | T002 (loader-level check) |
| Symlink ancestor in `spec_storage` rejected | T001 (`realpath_safe` primitive) |
| yq parse bomb DoS mitigated | T002 |
| Tampered spec config detected at ship | T004 |
| Cross-project vault leak prevented | T003 |
| Monitor events redact absolute paths | T003 |
| Unknown gate/agent ID spoofing rejected | T004 (phase-command layer); T002 covers loader layer separately |
| `gates.yml` tracked-state warning | T002 |

No unowned scenarios. The deliberate split (loader-level rejection in T001/T002; phase-command-level rejection in T004) is required — both enforce at different trust boundaries.

## Integration Test Plan

| Seam | Owner | Rationale |
|---|---|---|
| `config-paths.sh` primitives ↔ `config-loader.sh` composition | T002 | Loader is the composer; proves primitives integrate under one WF_* contract |
| Loader WF_* contract ↔ shell callers (monitor/task-manager/pre-commit) | T003 | Callers are consumers with full knowledge of both sides and cwd/hook context |
| Loader `--spec` output ↔ phase command intersection ↔ ground_rules | T004 | `/validate` is the intersection authority |
| `/implement` snapshot ↔ `/ship` drift comparison | T004 | Both ends of snapshot live in phase-command layer |
| Shared YAML fixture ↔ shell verdict ↔ Rust verdict (parser parity) | T005 | Rust is newcomer against established shell contract |
| Intersection parity: shell loader vs TUI pipeline widget | T007 | Widget is sole Rust renderer of intersection; sorted JSON byte-compare against shell fixture |
| Watcher ↔ parse ↔ app state rebuild | T006 | Scanner integration owns the reload path |
| `/explore` step 0 ↔ inferencer agent ↔ monitor event emission | T009 | `/explore` orchestrates all three |
| Full-stack dogfood: `.workflow.yml` → loader → callers → commands → TUI | T011 | Cleanup task is final gate; E2E against `/tmp/vault` is defining deliverable |
| `WF_VALIDATE_SCOPE` ↔ `/validate` skip branch ↔ `/validate-impl` union | T016 | `/validate-impl` is the sole union-execution authority; `/validate` is the sole skip-branch authority |
| `task-manager.sh set-status done` ↔ `.monitor.jsonl` event ↔ `/implement` chain invocation | T015 | Detector + auto-chain form a single feedback edge; splitting their tests hides race/idempotency bugs |
| `/validate-impl` ↔ Karen (Agent tool) ↔ audit report schema | T014 | Wrapper prompt + report frontmatter form the agent contract; stub Karen for determinism |
| audit report ↔ `/review-findings` ↔ `task-manager.sh create-followup` ↔ FR-id allowlist | T017 | Reopen flow spans four components; allowlist is the critical security boundary — must be tested end-to-end not just unit |

## Risk Flags

| Severity | Risk | Mitigation |
|---|---|---|
| **HIGH** | Dogfood breakage during T003 path-resolution refactor. Half-migrated call sites strand in-flight specs and block commits. | T003 runs full test matrix against BOTH default repo AND `/tmp/vault` repo in same CI job. T003→T011 form unbreakable chain — do not mark T003 done until T011 vault E2E is green on throwaway repo. Keep hardcoded `specs/` fallback behind feature flag until T011 removes it. |
| **HIGH** | Shared-fixture drift between T001/T002 (shell) and T005/T007 (Rust). If each side maintains copies, parity assertion in T007 becomes meaningless. | Canonicalize under `tests/fixtures/config/` at repo root (NOT under `workflow-tui/tests/`). Rust reads via `CARGO_MANIFEST_DIR/../tests/fixtures/config/`. T001 creates; T002/T005/T007 consume same bytes. CI check fails if `workflow-tui/tests/fixtures/config/` duplicates shared set. |
| **MEDIUM** | LLM nondeterminism in T008 — schema-shape tests pass on semantically wrong configs (e.g., python gates for Rust repo). | Negative-shape assertions: given Cargo.toml-only, output MUST include ≥1 Rust gate and MUST NOT include python/js-only gates. Log inferencer inputs + outputs to monitor events for offline review. |
| **MEDIUM** | T011 E2E vault test ambiguity — "goes green end-to-end" undefined. Risk of shallow smoke test. | T011 E2E must explicitly exercise steps (a)–(f) listed in its task owns section above. Assert each step produces its expected artifact. |
| **MEDIUM** | T004 "tampered spec config" test — snapshot format instability causes false positives on yq canonicalization. | Snapshot compares normalized JSON of effective fields (`gates[]`, `agents` map), not raw YAML text. Cover: whitespace-only → no drift; gate removed/added → drift; agent reordering → drift if order-significant (document choice). |
| **LOW** | T003 pre-commit hook subdir test must reproduce git's hook invocation context (cwd = subdir, GIT_DIR set). Naive `cd subdir && run` misses git env. | Real git init fixture under `tests/fixtures/nested-subdir-repo/`; invoke via `git -C subdir commit --dry-run` or call hook directly with `PWD=subdir` AND `GIT_DIR` set. Do not rely on bare cd. |
| **LOW** | T007 parity test brittleness — shell and Rust may produce intersection results in different orders. | Canonicalize to sorted list before comparison on both sides. Parity fixture emits JSON `{"executed":[sorted],"skipped":[sorted]}`. Shell loader gets tiny test-only helper to emit same shape. |
| **MEDIUM** | T014 Karen-stub drift — tests use a stubbed Karen for determinism; stub could lag real Karen's output format. | Stub output and real-Karen prompt live in the same `commands/validate-impl.md` file; schema-shape test validates both stub output AND any real-Karen output against the frontmatter + FR-matrix section contract. CI periodically replays the stubbed prompt against real Karen and diffs shape only. |
| **MEDIUM** | T017 follow-up task creation could create duplicate tasks if the same `spec-audit-*.md` report is processed twice. | `task-manager.sh create-followup` writes a `source_report` field into the task frontmatter; creation is a no-op when an existing task already references that report+FR pair. |
| **LOW** | T015 all-done detector false-negative on concurrent completion — two near-simultaneous `set-status done` calls could both think another task is still pending. | Serial execution rule (CLAUDE.md) forbids concurrent task completion; detector verifies by re-reading all task statuses after the transition rather than trusting prior state. |
| **LOW** | T016 union computation silently drops a gate when spec_storage sits on a case-insensitive filesystem (macOS default) — gate id collisions across case. | `validate_id` regex already rejects non-ASCII; add unit test ensuring duplicate-id detection in `gates.yml` is case-sensitive (reject exact-match duplicates; document that case-differing ids are valid). |
