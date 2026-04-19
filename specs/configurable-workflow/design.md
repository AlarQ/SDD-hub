---
name: configurable-workflow
status: proposed
---

# Design — Configurable Workflow

This document combines the Software Architect's trade-off analysis and ADRs with the Backend Architect's data contracts and module boundaries. Both agents read `spec.md`, `prd.md`, and the applicable architecture rules from the dual KB.

## Architecture Overview

Three new YAML files (`.workflow.yml`, `knowledge-base/gates.yml`, `specs/<feature>/config.yml`), one new sourced shell loader (`scripts/config-loader.sh`), a path-resolution refactor across existing scripts, and new Rust parsers + a pipeline widget in `workflow-tui/`. Phase structure stays hardcoded — only gate/agent *selection* becomes pluggable.

Loader is a leaf module: parse + validate + export. Workflow scripts source it (or invoke its CLI mode for hooks). Loader sources nothing from workflow scripts. Same parse logic mirrored in Rust (`workflow-tui/src/parse/`) so the TUI and shell agree on what's eligible.

## Trade-off Analysis

### Decision 1 — Three-file split vs single config

| | Single `.workflow.yml` (embedded registry + per-spec map) | Three-file split *(chosen)* |
|---|---|---|
| Gain | One parse, one watcher, one schema, easy bootstrap | Orthogonal lifecycles; spec dirs stay self-contained and vault-portable; per-layer caching; done specs frozen |
| Lose | Couples stable repo config to per-spec churn; spec edits force repo-root diffs; breaks vault use case | Three schemas to version; cross-file referential integrity needed |

**Why:** Lifecycles and writers differ (stable / KB / ephemeral). Collapsing them couples unrelated change rates and breaks the vault storage use case where spec dirs move outside the repo. ADR-001.

### Decision 2 — `gates.yml` canonical vs language-file frontmatter

| | Frontmatter canonical | `gates.yml` canonical *(chosen)* |
|---|---|---|
| Gain | No new file; gates colocated with language guidance | O(1) ID resolution; cross-cutting gates have a home (`applies_to: [any]`); spec-config references unambiguous |
| Lose | No home for cross-cutting gates; N-file scan to answer "what gates apply"; spec config IDs need scan to resolve | Drift risk between gates.yml and language prose; contributors editing `rust.md` may miss gates.yml |

**Why:** Cross-cutting gates have no sensible owner under the frontmatter model, and spec-config ID references need one authoritative resolution point. Mitigated by generating initial gates.yml from current `validation_tools` frontmatter in the same commit. ADR-002.

### Decision 3 — Ceiling semantics vs spec-authoritative

| | Spec config authoritative | Ceiling — eligible ∩ ground_rules *(chosen)* |
|---|---|---|
| Gain | One source of truth; simple mental model | Preserves task ground_rules contract; doc-only tasks naturally skip code gates; least privilege at task boundary |
| Lose | Doc-only tasks can't scope down without config edit; loses task-local exception path | Two-layer semantics; silent empty intersection risks false-green; debugging "why didn't X run" requires checking two places |

**Failure modes (mitigated):**
- Empty intersection on a code task → fail closed, log `gate_skip` with reason `empty intersection`, block transition to `done`. Doc-only tasks declare empty-OK explicitly.
- Task adds a `ground_rule` that references a gate outside the spec ceiling → `gate_skip` event with reason `not in spec ceiling`.
- User edits `ground_rules` expecting gate to run, spec config silently drops it → `/spec-status` surfaces effective gate set per task.

ADR-003.

### Decision 4 — LLM inference at spec birth vs runtime `when:` DSL

| | Runtime `when:` DSL | Birth-time inference *(chosen)* |
|---|---|---|
| Gain | Dynamic, expressive, no stale-config problem | Static, diffable, PR-reviewable; determinism frozen after one LLM call; no parser/eval/injection surface |
| Lose | DSL = grammar + parser + evaluator + test matrix + injection surface; non-determinism leaks into runtime | Goes stale if scope drifts (re-run via `/config`); LLM nondeterminism at birth (user approves) |

**Why:** User explicitly rejected DSL as over-engineered. Static config is debuggable ("what did we run?" = read a file). Re-inference is user-initiated, never a runtime surprise. ADR-004.

### Decision 5 — Walk-up vs env var vs CLI flag for path resolution

| | `WORKFLOW_ROOT` env var | `--workflow-root` CLI flag | Walk-up to `.workflow.yml` *(chosen)* |
|---|---|---|---|
| Gain | Zero filesystem probing; trivial test override | Explicit | Works from any cwd including git-hook subdirs; matches git/direnv mental model; single unambiguous marker |
| Lose | Every entry point must export it; forgotten = silent wrong dir; doesn't survive `git commit` from random subdir | Slash commands and git hooks can't thread flags | FS probe per invocation (cheap, bounded); symlinks need realpath defense; new "marker not found" error path |

ADR-005.

### Decision 6 — Sourced shell vs sub-shell loader

| | Sub-shell `config-loader.sh get <key>` | Sourced shell *(chosen)* |
|---|---|---|
| Gain | Loader is a black box; per-call isolation; no namespace pollution | Single yq parse per invocation (PRD requirement); helper functions reusable; no `eval` footgun |
| Lose | Re-parses yq every call (defeats caching) | `WF_*` namespace pollution; sourcing order matters; circular-source risk |

**Why:** Single-parse requirement forces in-process caching. Sourcing is the only shell mechanism that keeps parsed state across function calls. Enforce one-way dependency: workflow scripts source loader; loader sources nothing back. ADR-006.

## Architecture Decision Records

### ADR-001 — Split config into three files by lifecycle

- **Status:** Accepted
- **Context:** Configuration spans three axes with different writers and change rates: repo-stable storage/pool pointers, KB-curated gate registry, per-spec ephemeral selections.
- **Decision:** Three files — `.workflow.yml` (repo root, stable), `knowledge-base/gates.yml` (KB-curated), `specs/<feature>/config.yml` (per-spec, LLM-inferred).
- **Consequences:**
  - Positive: orthogonal diffs; spec dirs self-contained and vault-portable; per-layer caching; done specs frozen.
  - Negative: three schemas to version; referential integrity (`spec.gates → gates.yml ids`) needs explicit validation; bootstrap writes two files.
- **Alternatives:** Single `.workflow.yml` with embedded registry and per-spec map (rejected — couples lifecycles, breaks vault use case).

### ADR-002 — `gates.yml` canonical; language-file frontmatter display-only

- **Status:** Accepted
- **Context:** Current `validation_tools` frontmatter in `knowledge-base/languages/*.md` is the execution source of truth but has no home for cross-cutting gates and forces N-file scans for ID resolution.
- **Decision:** `knowledge-base/gates.yml` becomes the single registry of executable gates, keyed by `id`, tagged via `applies_to`. Language-file frontmatter is downgraded to documentation.
- **Consequences:**
  - Positive: O(1) ID resolution; cross-cutting gates have a natural home (`applies_to: [any]`); spec config references unambiguous.
  - Negative: drift risk between gates.yml and language prose; contributors editing `rust.md` may miss gates.yml.
- **Alternatives:** Frontmatter canonical with synthetic merge (no owner for cross-cutting gates); inline gate definitions in spec config (no reuse, no audit).

### ADR-003 — Ceiling semantics at `/validate`

- **Status:** Accepted
- **Context:** Two reasonable authorities exist: spec config (feature-wide) and task `ground_rules` (task-local). Picking one deletes information.
- **Decision:** Spec config is a *ceiling* of eligible gates. Task `ground_rules` is authoritative within that ceiling. `/validate` runs the intersection.
- **Consequences:**
  - Positive: preserves task ground_rules contract; doc-only tasks naturally skip code gates; least privilege at task boundary.
  - Negative: two-layer semantics; silent empty intersection risks false-green — must fail-closed when empty for code tasks; debugging "why didn't X run" requires checking both layers. Mitigated via `/spec-status` and `gate_skip` events.
- **Alternatives:** Spec config authoritative (erases task-local scoping); ground_rules authoritative alone (no spec-wide veto mechanism).

### ADR-004 — LLM inference at spec birth, no runtime DSL

- **Status:** Accepted
- **Context:** Per-spec gate/agent selection needs to adapt to the spec's actual shape.
- **Decision:** A `config-inferencer` agent runs once at `/explore` step 0, produces a draft `config.yml`, user approves/edits. No `when:` DSL. Re-inference via `/config`.
- **Consequences:**
  - Positive: static, diffable, PR-reviewable; determinism frozen after one LLM call; no parser/eval/injection surface; inference cost paid once.
  - Negative: goes stale if scope drifts — user must remember to `/config`; LLM nondeterminism at birth (mitigated by approval); schema-only tests, no golden fixtures.
- **Alternatives:** Runtime `when:` DSL (over-engineered, injection surface, user explicitly refused); hand-curated template per language (doesn't handle multi-language repos or spec-specific scope).

### ADR-005 — Walk-up `.workflow.yml` for path resolution

- **Status:** Accepted
- **Context:** Scripts and TUI currently hardcode `specs/`. Making storage configurable requires cwd-independent root discovery.
- **Decision:** All scripts and the TUI scanner walk parent directories until they find `.workflow.yml`, git-style. `realpath` normalizes before the walk.
- **Consequences:**
  - Positive: works from any cwd including git-hook invocation in subdirs; matches established mental model (git, node, direnv); single unambiguous marker.
  - Negative: filesystem probe per invocation (bounded, cheap); symlinked worktrees need realpath defense; new "marker not found" fail-closed error path.
- **Alternatives:** `WORKFLOW_ROOT` env var (entry points forget to export); `--workflow-root` CLI flag (slash commands and git hooks can't thread it).

### ADR-006 — Config loader is sourced, not sub-shelled

- **Status:** Accepted
- **Context:** PRD requires single-yq-parse-per-invocation caching. Sub-shell invocation re-parses on every call.
- **Decision:** `scripts/config-loader.sh` is sourced by callers. Runs `timeout 5 yq` once, exports `WF_*` env vars and helper functions. Sourcing direction is strictly one-way: workflow scripts source the loader; the loader sources nothing from them.
- **Consequences:**
  - Positive: one parse per script run; helper functions reusable; no `eval` footgun.
  - Negative: `WF_*` namespace pollution; order-of-sourcing matters; circular-source risk if discipline breaks.
- **Alternatives:** Sub-shell `config-loader.sh get <key>` (defeats caching); in-memory daemon (over-scoped for shell).

### ADR-007 — Gate cadence configurable, spec-completion audit mandatory

- **Status:** Accepted
- **Context:** FR-7 picks *which* gates run; it does not pick *when*. Current hardcoded cadence (per-task) dominates overhead on small features (3–5 tasks) where gates largely no-op per task. Skipping gates entirely would lose correctness; keeping per-task mandatory blocks the small-feature UX.
- **Decision:** Introduce `validate_scope ∈ {per-task, per-spec, both}` in `.workflow.yml` (repo default) with optional override in `specs/<feature>/config.yml`. Irrespective of scope, run a mandatory spec-completion audit once all tasks in the spec transition to `done` (FR-15/16). The audit closes the late-catch gap that `per-spec` otherwise opens.
- **Consequences:**
  - Positive: small features can ship without per-task gate overhead; large/high-stakes features keep `per-task` or `both`; spec-level audit gives end-to-end traceability from FR to code regardless of scope.
  - Negative: two cadence knobs to reason about; `per-spec` delays gate failure signal until spec end (mitigated by mandatory audit + FR matrix); enum drift risk if future modes added (mitigated by strict allowlist at loader).
- **Alternatives:** (a) per-task hardcoded (status quo — rejected, small-feature pain unaddressed); (b) skip gates entirely for short specs (rejected — correctness regression, no FR verification); (c) dynamic per-task heuristic (rejected — non-deterministic, brittle).

### ADR-008 — Reuse Karen agent for spec-completion audit

- **Status:** Accepted
- **Context:** Spec-level audit needs an agent that specializes in claimed-vs-actual gap analysis across a feature's full artifact set. Options: (a) reuse existing Karen agent, (b) enhance Karen with spec-specific affordances, (c) fork a purpose-built `spec-completion-auditor`.
- **Decision:** Reuse Karen unchanged. Supply spec-specific context (spec.md FR list, prd.md scope, task list, report paths, git diff range) via a wrapper prompt at the call-site in `commands/validate-impl.md`. Karen's existing ethos — "distinguish claimed vs actual completion, identify half-implemented features, produce realistic gap analysis" — is already the right shape; explicit spec/PRD parsing lives in the wrapper, not the agent definition.
- **Consequences:**
  - Positive: zero agent-definition churn; Karen's identity stays generic and useful elsewhere; wrapper prompt is the only specialization surface and is easy to iterate; matches existing pattern of `/validate` Phase 2 spawning generic agents with phase-specific context.
  - Negative: wrapper-prompt drift (mitigated by a single wrapper template versioned under `commands/validate-impl.md`); Karen output format not strictly schema-constrained at the agent level (mitigated by FR-id allowlist + Markdown section headers enforced in the wrapper).
- **Alternatives:** (b) enhance Karen with spec-awareness (rejected — couples Karen to this workflow, bloats agent definition); (c) fork `spec-completion-auditor` (rejected — duplicates Karen's ethos, two agents to maintain, no functional gain).

## Backend Design

### Schemas

#### `.workflow.yml` (repo root)

| Field | Type | Req | Default | Validation | On invalid |
|---|---|---|---|---|---|
| `spec_storage` | string (path) | no | `specs/` | `realpath` resolves under `$HOME` or repo root; no symlink ancestors; exists; is dir; no `..` segments | exit 2 |
| `gate_pool` | string (path) | no | `knowledge-base/gates.yml` | resolves inside repo root or `~/.claude/`; readable file | exit 2 |
| `agent_pool` | string (path) | no | `~/.claude/agents` | resolves inside repo root or `~/.claude/`; is dir | exit 2 |
| `validate_scope` | enum | no | `per-task` | one of `per-task`,`per-spec`,`both` (strict); see ADR-007 | exit 2 |

Unknown top-level keys → warning, ignored. File absent → all defaults, loader returns 0.

#### `knowledge-base/gates.yml`

Top-level: `gates:` (list, ≥0 entries).

| Field | Type | Req | Default | Validation |
|---|---|---|---|---|
| `id` | string | yes | — | `^[a-zA-Z0-9_-]{1,64}$`, unique within file |
| `command` | string | yes | — | ≤256 chars, non-empty; static scan rejects unquoted shell metacharacters outside quoted args |
| `applies_to` | list<string> | yes | — | each ∈ {`any`,`rust`,`typescript`,`javascript`,`python`,`go`,`shell`,`markdown`}; non-empty |
| `category` | enum | yes | — | one of `lint`,`test`,`security`,`format`,`build`,`docs` |
| `blocking` | bool | no | `true` | strict bool |

Duplicate `id`, unknown `applies_to`, or unknown `category` → fail closed, exit 3.

#### `specs/<feature>/config.yml`

| Field | Type | Req | Default | Validation |
|---|---|---|---|---|
| `tags` | list<string> | no | `[]` | each `^[a-zA-Z0-9_-]{1,32}$` |
| `gates` | list<string> | no | `[]` (legacy) | each `^[a-zA-Z0-9_-]{1,64}$`; each exists in `gates.yml` |
| `agents` | map<phase,list<string>> | no | `{}` | keys ∈ {`explore`,`propose`,`implement`,`validate`,`pr-review`}; values match **Agent ID grammar** below; each resolves to an existing file under `agent_pool` |
| `validate_scope` | enum | no | inherits from `.workflow.yml` (else `per-task`) | one of `per-task`,`per-spec`,`both` (strict); see ADR-007. Spec-level value overrides repo-level |

File absent = legacy fallback (no error). Malformed or unknown ID = fail closed, exit 4.

##### Agent ID grammar and resolution

Agent IDs are **fully qualified**: `<category>/<name>` or bare `<name>` for root-level agents. No implicit prefix stripping, no stem-matching, no subdir walking.

- **Regex:** `^[a-z0-9_-]+(/[a-z0-9_-]+)?$` (lowercase; at most one `/`; no leading/trailing `/`; no `..`).
- **Resolution:**
  - `<category>/<name>` → `<agent_pool>/<category>/<category>-<name>.md`
  - bare `<name>` (no slash) → `<agent_pool>/<name>.md`
- **Rationale:** filenames in `agents/<category>/` already carry a `<category>-` role prefix (e.g. `engineering/engineering-security-engineer.md`). The `<category>/<name>` form is human-readable and resolves to one unambiguous file without magic.
- **Canonical examples:**
  - `design/ux-researcher` → `agents/design/design-ux-researcher.md`
  - `engineering/security-engineer` → `agents/engineering/engineering-security-engineer.md`
  - `engineering/software-architect` → `agents/engineering/engineering-software-architect.md`
  - `engineering/code-reviewer` → `agents/engineering/engineering-code-reviewer.md`
  - `engineering/config-inferencer` → `agents/engineering/engineering-config-inferencer.md` (new, added in T008)
  - `code-quality-pragmatist` → `agents/code-quality-pragmatist.md` (root-level)
- **Validation:** loader resolves each ID at parse time; missing file → fail closed, exit 4; ambiguous-by-construction is impossible (one ID → exactly one path).

#### Task frontmatter additions

This spec adds **one** advisory field to task frontmatter — no state-machine impact, no change to existing fields. Per ADR-003 and prd.md §OUT exception.

| Field | Type | Req | Default | Validation | Scope |
|---|---|---|---|---|---|
| `empty_intersection_ok` | bool | no | `false` | strict bool (JSON `true`/`false`; not `"true"` string) | Per-task advisory. Consumed by `/validate` ceiling-intersection check only. Does **not** participate in state transitions. |

Semantics: when `/validate` computes the ceiling intersection (spec-eligible gates ∩ task ground_rules gates) and the result is empty, the task normally fails closed. If the task frontmatter declares `empty_intersection_ok: true`, `/validate` passes with zero gates executed and emits a `gate_skip` monitor event carrying reason `empty_intersection_ok`. Code-bearing tasks that set this flag are still free to fail other gates; the flag only governs the empty-intersection edge.

Validator: `task-manager.sh validate` rejects non-bool values (e.g., string `"yes"`, integer `1`) with exit code 2. Unknown frontmatter fields continue to warn-and-ignore per existing task-manager behavior.

### `scripts/config-loader.sh` API

**Invocation:** `source scripts/config-loader.sh` then call `wf_load_config [--spec <feature>]`. CLI mode: `config-loader.sh export` prints `KEY=VAL` lines for hooks to `eval`.

**Args:** `--spec <id>` (load spec config too); `--no-defaults` (fail if `.workflow.yml` missing).

**Exports** (idempotent; guarded by `WF_CONFIG_LOADED=1`):

| Var | Type | Example |
|---|---|---|
| `WF_CONFIG_LOADED` | `0`/`1` | `1` |
| `WF_REPO_ROOT` | abs path | `/Users/x/proj` |
| `WF_SPEC_STORAGE` | abs path | `/Users/x/proj/specs` |
| `WF_GATE_POOL` | abs path | `/Users/x/proj/knowledge-base/gates.yml` |
| `WF_AGENT_POOL` | abs path | `/Users/x/.claude/agents` |
| `WF_CONFIG_FILE` | abs path or empty | `/Users/x/proj/.workflow.yml` |
| `WF_SPEC_CONFIG_FILE` | abs path or empty | set only with `--spec` |
| `WF_SPEC_GATES` | newline-separated IDs | `rust-clippy\nsemgrep-security` |
| `WF_SPEC_AGENTS_<PHASE>` | space-separated fully-qualified IDs | `WF_SPEC_AGENTS_VALIDATE="engineering/security-engineer code-quality-pragmatist"` |
| `WF_SPEC_HAS_CONFIG` | `0`/`1` | `0` = legacy fallback |
| `WF_VALIDATE_SCOPE` | enum | `per-task` / `per-spec` / `both` (default `per-task`) — exported by T002 alongside other `WF_*` vars. T013 extends parsing with the enum allowlist check and spec-level override; T002 exports the field with the repo-default value only. |

**Return codes:** `0` ok (incl. missing-with-defaults); `2` invalid path in `.workflow.yml`; `3` `gates.yml` invalid/missing when referenced; `4` spec `config.yml` invalid; `5` `yq` timeout; `6` unexpected (yq missing).

**Caching:** single `timeout 5 yq e -o=json . <file>` per file per process. `WF_CONFIG_LOADED=1` guards re-entry. Subshells inherit via exported env — only the outermost shell parses.

**Error handling:** every `yq`/`jq` call wrapped with `timeout 5`. Non-zero → emit `ERROR: <file>: <reason>` to stderr, unset partial `WF_*` vars, return non-zero. Loader never writes; never executes values from YAML.

### Caller integration

- **`monitor.sh`** — replaces `find_project_root` (currently scans for `specs/` dir) with a walk-up for `.workflow.yml`. Reads `$WF_SPEC_STORAGE` if set; falls back to hardcoded `specs/` until E2E green (dogfood safety). Keeps `validate_id` helper at `monitor.sh:64-70` as canonical when sourced standalone — T001 tightens its regex to `^[a-zA-Z0-9_-]{1,64}$` (adds length cap); delegates to `config-paths.sh` version when loader is loaded.
- **`task-manager.sh`** — same env-var read pattern. Uses `$WF_SPEC_STORAGE` to locate task files. Legacy fallback.
  - **New subcommand (added in T017):** `task-manager.sh create-followup <feature> <fr-id> <description>`. First subcommand that *creates* task files; extends the canonical CLI set documented in CLAUDE.md (`validate`, `set-status`, `unblock`, `next`, `check-unvalidated`, `status`) to seven verbs.
    - **Inputs:** `<feature>` — spec id (must exist under `$WF_SPEC_STORAGE`); `<fr-id>` — must match one of the `### FR-N:` headings in `spec.md` (FR-id allowlist, per FR-17 security); `<description>` — free text, ≤256 chars, escaped when written.
    - **Outputs:** writes one new task file at `$WF_SPEC_STORAGE/<feature>/tasks/<NNN>-<slug>.md` with `status: todo`, `blocked_by: []`, `ground_rules` inherited verbatim from `spec.md §Applicable Ground Rules`. Prints the created filename on stdout; no JSONL event (the caller — `/validate-impl` — emits the audit-level monitor event).
    - **Idempotency:** re-running with the same `<feature>, <fr-id>` returns exit 0 and prints the existing filename without creating a duplicate (lookup by `FR-<id>` token in task `name`). Different `<description>` on a re-run is ignored; the original file is authoritative.
    - **State transition:** introduces a new *create* transition `∅ → todo` (no prior state). The transition is author-time only — it does not participate in the existing `blocked → todo → in-progress → implemented → review → done` machine for existing tasks.
    - **Docs:** `docs/workflow-diagram.md` MUST be updated in the same PR (T017 estimated file) to show the audit → `/review-findings` → `create-followup` → new-task edge and the reopen loop.
- **`pre-commit-hook.sh`** — calls loader in CLI mode (hooks have unpredictable cwd). `eval "$(scripts/config-loader.sh export)"` once at hook start. Walks up from `$(git rev-parse --show-toplevel || pwd)`.

### Service boundaries — shell

```
scripts/
  config-paths.sh           # leaf: find_workflow_root, realpath_safe, validate_id
  config-loader.sh          # depends on config-paths.sh; parses + validates + exports
  monitor.sh                # reads WF_* env; keeps standalone validate_id for back-compat
  task-manager.sh           # reads WF_* env
  pre-commit-hook.sh        # CLI eval of config-loader.sh
```

**Dependency direction (strict, one-way):**

```
config-paths.sh ──▶ config-loader.sh ──▶ monitor.sh / task-manager.sh / pre-commit-hook.sh
                    (no back-edges; CI grep enforces)
```

`config-loader.sh` MUST NOT `source` any workflow script. Logging from the loader goes to plain stderr, never via `monitor.sh`.

### Service boundaries — Rust (`workflow-tui/`)

```
workflow-tui/src/
  model/
    workflow_config.rs     # NEW: WorkflowConfig { spec_storage, gate_pool, agent_pool }
    spec_config.rs         # NEW: SpecConfig { tags, gates, agents: HashMap<Phase, Vec<String>> }
    gate.rs                # NEW: Gate { id, command, applies_to, category, blocking }
    spec.rs                # MODIFIED: gains config: Option<SpecConfig>
  parse/
    workflow_config.rs     # NEW: ONLY locator/parser of .workflow.yml; walk-up discovery
    spec_config.rs         # NEW: per-spec parser; tolerates absent file (Ok(None))
    gates.rs               # NEW: gates.yml parser
    scanner.rs             # MODIFIED: uses WorkflowConfig.spec_storage instead of "specs/"
    frontmatter.rs         # UNCHANGED
  ui/
    pipeline.rs            # NEW: per-task gate/agent pipeline widget; sole renderer of intersection
    spec_list.rs           # MODIFIED: reads spec_storage from WorkflowConfig
  watcher.rs               # MODIFIED: also watches .workflow.yml (debounce ≥100ms)
  app.rs                   # MODIFIED: holds WorkflowConfig at top of state tree
```

**Ownership rules:**
- `parse/workflow_config.rs` is the *only* module that locates and parses `.workflow.yml`. All others receive `&WorkflowConfig`.
- `parse/gates.rs` owns `gates.yml` exclusively. `model/gate.rs` is pure data — no IO.
- `parse/spec_config.rs` owns per-spec config. Tolerates missing file (legacy specs).
- `ui/pipeline.rs` is the sole renderer of the intersection computation. Prevents divergent intersection logic between shell and Rust.

**Dependency direction (inward):**

```
ui/*  ──▶  model/*  ◀──  parse/*
                          │
                          └──▶  std::fs, serde_yml
```

UI never calls `parse` directly. `app.rs` orchestrates load → hands immutable model refs to UI. Watcher triggers re-parse → new model → UI re-renders. Matches the existing Elm-like architecture.

### Boundary validation points

Per `general:architecture/general.md` and `general:security/general.md`:

1. `config-paths.sh::validate_id` — every gate/agent ID before any shell use.
2. `config-paths.sh::find_workflow_root` — `realpath` + symlink ancestor rejection.
3. `parse/workflow_config.rs` — same checks in Rust via `std::fs::canonicalize`.
4. `parse/spec_config.rs` — reject referenced IDs not in gates.yml or agent pool; fail closed with the missing IDs listed.

## Data Flow

### Flow A — repo config edit

```
user edits .workflow.yml
   │
   ▼
/validate (or any script) sources config-loader.sh
   │
   ▼
find_workflow_root: walk up from realpath($PWD) for .workflow.yml
   │
   ▼
timeout 5 yq -> JSON -> validate fields (realpath, regex, existence)
   │
   ▼ (fail → exit non-zero, fail closed)
   │
export WF_SPEC_STORAGE / WF_GATE_POOL / WF_AGENT_POOL / WF_CONFIG_LOADED=1
   │
   ▼
monitor.sh reads $WF_SPEC_STORAGE → writes <storage>/<feature>/.monitor.jsonl
task-manager.sh reads $WF_SPEC_STORAGE → locates task file
TUI watcher notices .workflow.yml mtime change → re-parses → rebuilds scanner root
```

### Flow B — spec config lifecycle

```
/explore <feature> step 0
   │
   ▼
spawn config-inferencer agent
   (reads Cargo.toml/package.json/go.mod, gates.yml ids, agent pool dir, PRD)
   │
   ▼
agent emits draft YAML → render summary on screen
   │
   ▼
user one-key approve OR /config override
   │
   ▼
write $WF_SPEC_STORAGE/<feature>/config.yml
   │
   ▼
monitor.sh log_event config_inferred + config_approved
   │
   ... later ...
   ▼
/validate <task>
   │
   ├─ source config-loader.sh --spec <feature>
   │  → WF_SPEC_GATES, WF_SPEC_HAS_CONFIG
   ├─ read task ground_rules → derive applicable languages/categories
   ├─ load gates.yml → filter by applies_to ∩ ground_rules (eligible set)
   └─ intersect with WF_SPEC_GATES (ceiling) → execute
      skipped → log gate_skip event
```

### Flow C — spec-completion audit at last-task done

```
task-manager.sh set-status <last-task> done
   │
   ▼
all-done detector: count tasks where status != done
   │
   ▼ (== 0 and no prior spec_audit_done event)
   │
emit spec_last_task_done event
   │
   ▼
/implement auto-chain observes event → invokes /validate-impl <feature>
   │
   ├─ source config-loader.sh --spec <feature>
   │  → WF_VALIDATE_SCOPE, WF_SPEC_GATES
   ├─ if scope in {per-spec, both}:
   │    union(spec-eligible gates) ∩ gates.yml applies_to
   │    execute once over cumulative diff (branch-point → HEAD)
   ├─ spawn Karen agent with wrapper prompt:
   │    spec.md FR list + prd.md scope + tasks status + reports/ + diff range
   │  emit spec_audit_start
   ├─ Karen produces FR × status matrix + orphan-code list + over-eng flags
   │  write specs/<feature>/reports/spec-audit-<ISO8601>.md
   │  emit spec_audit_done
   │
   ▼
verdict branch:
   ├─ complete → emit spec_complete, set spec frontmatter status=shipped
   └─ reopen   → /review-findings accept/reject on missing/partial items
                  accepted → task-manager.sh create follow-up todo task
                  rejected → optional project-KB rule (feedback loop)
                  spec stays in-progress until new tasks reach done
                  (cycle may re-trigger Flow C)
```

## Risk Flags

| Severity | Risk | Mitigation |
|---|---|---|
| **HIGH** | Dogfood breakage during path-resolution rollout. Half-migrated walk-up implementation strands in-flight specs mid-task; monitor events stop landing; pre-commit blocks commits. | Keep `specs/` fallback behind a feature flag until all four call sites (monitor, task-manager, pre-commit, TUI) pass E2E against a non-default `spec_storage`. Land path-resolution migration in a single PR. Run TUI against a throwaway repo before cutover. The TUI call site is validated by **T011 E2E step (d)**: scanner discovers the spec at `/tmp/vault`. |
| **MEDIUM** | gates.yml vs language-file drift after frontmatter becomes display-only. | Generate initial gates.yml from current `validation_tools` frontmatter in the same commit that marks frontmatter display-only. `/validate` precheck diffs documented commands against gates.yml entries and warns on mismatch. |
| **MEDIUM** | config-inferencer nondeterminism — LLM-produced config.yml varies run to run; golden-fixture tests would be brittle. | Schema-shape tests only (keys present, values in allowed sets, all referenced IDs resolve). One-key approval makes user the determinism layer. Log exact inputs to a monitor event for replay. |
| **LOW** | config-loader.sh circular sourcing — if loader ever sources monitor.sh you get an unbootable shell. | Enforce dependency direction in code review and CI grep that fails if `config-loader.sh` contains `source` of any workflow script. Loader logs via plain stderr. |
| **LOW** | pre-commit hook subdir cwd — git commit from subdir runs hook with cwd = subdir. | `find_workflow_root` walks up unconditionally from `realpath($PWD)`. Test via `tests/test-path-resolution.sh` invoked from a nested tmp dir. Single code path with TUI/loader. |
| **LOW** | Empty gate intersection at `/validate` — false-green ship. | Fail closed when intersection is empty AND task category is code-bearing. Loud `gate_skip` event with reason `empty intersection`. Block transition to `done`. Doc-only tasks declare empty-OK explicitly. |
| **LOW** | Referential integrity across the three config files — spec config references IDs in `gates.yml` and `~/.claude/agents/`; either side can drift. | `config-loader.sh` validates all referenced IDs at parse time; fails closed listing missing IDs. `/config` re-resolves against current pools. |
| **MEDIUM** | `per-spec` mode delays gate failure feedback until spec end; a bad change caught only after N tasks are already committed. | Mandatory Karen audit + FR × status matrix catches behavioural gaps at end; `both` mode available when user wants per-task safety net plus end-of-spec audit; report verdict `reopen` spawns follow-up tasks rather than silently merging. |
| **LOW** | Karen wrapper-prompt drift — spec-audit quality depends on one prompt template not the agent definition. | Template versioned in `commands/validate-impl.md`; schema-shape test on audit report verifies FR-matrix presence + status enum + orphan-code section; FR-id allowlist rejects hallucinated IDs. |
| **LOW** | All-done detector races — concurrent `set-status done` calls could double-fire `spec_last_task_done`. | Detector checks prior `spec_audit_done` event before emitting; `/validate-impl` is idempotent within a single done-sweep; serial execution rule (CLAUDE.md) already forbids concurrent task completion. |

## Scaling / Integration Notes

- **yq fork multiplication:** each task run touches ~6 scripts. Without caching, that's 6× yq + path validation. `WF_CONFIG_LOADED=1` guard + env inheritance means only the outermost shell parses; subshells inherit free. CLI-mode callers (pre-commit) `eval` once at hook start.
- **TUI watcher reload cost:** `.workflow.yml` changes are rare. Debounce file events ≥100 ms in `watcher.rs` to coalesce editor save bursts. Parse errors surface as non-fatal `ParseWarning` — TUI keeps last-good config.
- **Parse-bomb DoS:** `timeout 5 yq` on every parse, fail closed. Billion-laughs caps at 5 s wall clock.
- **Cross-project vault collision:** `monitor.sh` uses *only* `$WF_SPEC_STORAGE` when set — no global `~/specs` fallback.

## Affected Files

**New (shell):** `scripts/config-loader.sh`, `scripts/config-paths.sh`, `knowledge-base/gates.yml`, `templates/workflow.yml.template`, `templates/spec-config.yml.template`

**New (Rust):** `workflow-tui/src/model/workflow_config.rs`, `workflow-tui/src/model/spec_config.rs`, `workflow-tui/src/model/gate.rs`, `workflow-tui/src/parse/workflow_config.rs`, `workflow-tui/src/parse/spec_config.rs`, `workflow-tui/src/parse/gates.rs`, `workflow-tui/src/ui/pipeline.rs`

**New (commands/agents):** `commands/config.md`, `commands/validate-impl.md`, `agents/engineering/engineering-config-inferencer.md`

**Unchanged agents (reused):** `agents/karen.md` — spawned from `/validate-impl` with wrapper prompt (ADR-008)

**Modified (shell):** `scripts/monitor.sh`, `scripts/task-manager.sh`, `scripts/pre-commit-hook.sh`, `setup.sh`

**Modified (commands):** `commands/explore.md`, `commands/propose.md`, `commands/implement.md`, `commands/validate.md`, `commands/pr-review.md`, `commands/review-findings.md`, `commands/bootstrap.md`

**Modified (Rust):** `workflow-tui/src/parse/scanner.rs`, `workflow-tui/src/model/spec.rs`, `workflow-tui/src/ui/spec_list.rs`, `workflow-tui/src/watcher.rs`, `workflow-tui/src/app.rs`

**Modified (docs):** `CLAUDE.md`, `docs/workflow-diagram.md`, `onboarding.md`

**Untouched:** `hooks/*`, task state machine.

**Lightly modified:** `commands/ship.md` — adds one pre-flight drift check (re-read `config.yml`, normalize to JSON, diff against the snapshot `/implement` persisted at task start; refuse on mismatch). The commit/PR pipeline itself is unchanged. This work is carried by **T004** (whose `estimated_files` includes `commands/ship.md`), co-located with the `/implement` snapshot logic since they share the normalization contract.

## Ground Rules Applied

- `general:architecture/general.md` — small modules (config-loader split into `config-paths.sh` + `config-loader.sh`), explicit interfaces (env var contract), boundary validation (loader + Rust parsers), dependency direction (one-way sourcing).
- `general:architecture/code-analysis.md` — systematic impact analysis surfaced dogfood breakage as HIGH risk.
- `general:security/general.md` — input validation at boundary (ID allowlist, path realpath), fail closed (every error path), least privilege (loader writes nothing).
- `general:languages/shell.md` — `set -euo pipefail`, quoted expansions, 150-line cap, shellcheck.
- `general:languages/rust.md` — module boundaries, `Result<T,E>`, no `unwrap` in production parsers.
- `general:testing/principles.md` — pure parser functions, schema-shape tests only for inferencer, Given/When/Then in BDD scenarios.
- No project-KB rules apply: the dev-workflow repo has no project-KB layer; every rule above maps into the General KB at `~/.claude/knowledge-base/`.
