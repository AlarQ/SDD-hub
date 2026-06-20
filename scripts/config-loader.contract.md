# config-loader.sh contract

Single source of truth for `wf_load_config` exported env vars and exit codes. Each workflow command sources `~/.claude/scripts/config-loader.sh` and calls `wf_load_config [--spec <feature>]`. Commands MUST link here instead of inlining partial lists.

## Usage

```bash
source ~/.claude/scripts/config-loader.sh
wf_load_config                       # repo-level only (.workflow.yml, inline gate_pool)
wf_load_config --spec <feature>      # also loads <spec_storage>/<feature>/config.yml
wf_load_config --project <name>      # vault: resolve {project} in spec_storage
wf_load_config --require-spec        # vault: fail (exit 4) if no --spec given
```

**Flags:**
- `--spec <feature>` — also load the per-spec `config.yml`.
- `--project <name>` — supply the project segment for a `spec_storage`
  containing the `{project}` token before any per-spec `config.yml` exists
  (first `/explore`). For `--spec` runs without `--project`, the loader
  recovers the segment from the unique existing spec dir; ambiguity → exit 4.
- `--require-spec` — gate/KB-touching commands pass this. Under
  `spec_storage_mode: vault` with no `--spec`, there is no ambient gate pool;
  loader fails closed (exit 4) rather than silently skipping gates.

Idempotent: re-sourcing is a no-op unless `WF_RELOAD=1`.

## Exported environment variables

| Variable | Type | Set when | Meaning |
|---|---|---|---|
| `WF_CONFIG_LOADED` | `1` | always on success | Guards re-sourcing. |
| `WF_REPO_ROOT` | abs path | always | Dir containing `.workflow.yml` (walk-up from CWD). In vault mode this is the vault dir itself (not a code repo). |
| `WF_CONFIG_FILE` | abs path | always | `$WF_REPO_ROOT/.workflow.yml`. |
| `WF_SPEC_STORAGE` | abs path | always | Resolved `spec_storage` dir (default `specs/`). A `{project}` token is substituted with the resolved project segment (vault mode). |
| `WF_GATE_POOL` | abs path or empty | always | Path to the `.workflow.yml` whose inline `.gate_pool[]` array is the gate pool (`= $WF_CONFIG_FILE`) in **repo mode**. **Empty in vault mode** — no single pool; gates resolve per-task from the bound repo's `.workflow.yml` (see `WF_TASK_GATE_POOL` in `multi-repo-resolution.md`). Non-empty in vault mode **only** under the self-hosting exception (a `repos[]` entry resolves to the vault root), where it points at the vault `.workflow.yml`. |
| `WF_SPEC_PROJECT` | name | only with resolved `{project}` | The project segment substituted into `spec_storage`. Consistency-checked against per-spec `config.yml project:` (mismatch → exit 4). |
| `WF_AGENT_POOL` | abs path | always | Resolved `agent_pool` dir (default `~/.claude/agents`). |
| `WF_GENERAL_KB` | abs path | always | Resolved `general_kb_path` dir — host of the general (cross-repo) knowledge base. **Required**: no default, missing/empty key → exit 2. Path may live outside `WF_REPO_ROOT` (e.g. inside a master-brain Obsidian vault). `general:` ground-rule prefix resolves under this dir. |
| `WF_VALIDATE_SCOPE` | enum | always | `per-task` \| `per-spec` \| `both`. Per-spec override wins. |
| `WF_SPEC_CONFIG_FILE` | abs path | `--spec` only | `$WF_SPEC_STORAGE/<feature>/config.yml`. |
| `WF_SPEC_GATES` | newline-sep IDs | `--spec` only | Spec ceiling: gate IDs from `config.yml gates:`. May be empty. |
| `WF_SPEC_HAS_CONFIG` | `1` | `--spec` only | Marker that per-spec config loaded. |
| `WF_SPEC_AGENTS_<PHASE>` | space-sep IDs | `--spec` only | One per phase present in `config.yml agents:`. `<PHASE>` ∈ `EXPLORE`, `PROPOSE`, `IMPLEMENT`, `VALIDATE`, `PR_REVIEW`. Absent if phase not configured. |
| `WF_SPEC_TIER` | enum | `--spec` only | `small` \| `medium` \| `large`. Required in `config.yml`; absence → exit 4. Drives flow shape. |
| `WF_SPEC_TRACK` | enum | `--spec` only | `feature` (default) \| `technical`. Optional in `config.yml`; absence → `feature`. `technical` = `/propose` skips spec.md/design.md/test-strategy.md at every tier (tasks/ only), rationale from docs/adr/+CONTEXT.md, /grill mandatory for medium/large. Invalid value → exit 4. |
| `WF_BRANCH_STRATEGY` | enum | `--spec` only | `per-task` (default) \| `single-branch`. Optional in `config.yml`; absence → `per-task`. `per-task` = per-task sub-branch + per-task draft PR (current behavior). `single-branch` = one `feat/$FEATURE` branch off main, commits accumulate, no per-task PR, one spec PR opened/readied at the final task's inline ship (base `main`). Invalid value → exit 4. Included in the config snapshot — a mid-spec flip is caught by the shared ship procedure's drift check. |
| `WF_COVERAGE_AUDIT` | enum | `--spec` only | `true` (default) \| `false`. Optional in `config.yml`; absence → `true`. Drives `/validate` **Phase 3** (per-task Odium coverage audit of the task's own acceptance criteria). `false` = escape hatch to skip the audit for this spec. Invalid value → exit 4. Audit is also skipped (independent of this flag) on `small` tier and under `validate_scope: per-spec`. |
| `WF_TIER_TASK_CEILING` | int or empty | `--spec` only | Task-count ceiling for this tier (per-spec `tier_ceiling.tasks` override → `.workflow.yml tiers.<tier>.tasks`). Empty = unbounded. |
| `WF_TIER_FILE_CEILING` | int or empty | `--spec` only | File-count ceiling for this tier. Empty = unbounded. |
| `WF_TIER_AGENT_SKIP` | space-sep IDs | `--spec` only | Agent gates to skip in `/validate` Phase 2 for this tier. Empty for medium/large by default. |
| `WF_SPEC_STORAGE_MODE` | enum | always | `repo` (default) \| `vault`. `vault` = specs live outside any code repo (e.g. master-brain Obsidian) and bind code repos via per-spec `repos[]`. |
| `WF_REPO_NAMES` | newline-sep names | `--spec` only, when `repos[]` declared | Logical repo names from per-spec `config.yml repos[]`. Parallel to `WF_REPO_PATHS`. Empty when spec declares none. |
| `WF_REPO_PATHS` | newline-sep abs paths | `--spec` only, when `repos[]` declared | Absolute repo paths matching `WF_REPO_NAMES` (same index). Each verified to be a git work tree at load time. |
| `WF_VAULT_ROOT` | abs path | when `spec_storage_mode: vault` | The vault dir (== `WF_REPO_ROOT`), set on normal walk-up discovery of a `.workflow.yml` declaring `spec_storage_mode: vault`. Unset in repo mode. |

**Walk-up discriminator:** a thin per-repo `.workflow.yml` carrying `kind: repo-gate-pool` (written by `/bootstrap repo-gate-init`) is a gate-pool marker, not a real workflow config. The loader skips it and keeps ascending until a real config (no `kind: repo-gate-pool`) or the filesystem root (exit 2).

All variables unset on any failure path (no partial state).

## Exit codes

| Code | Condition | User message | Recovery |
|---|---|---|---|
| 0 | success | — | — |
| 2 | `.workflow.yml` not found walking up from CWD, malformed, or has invalid `spec_storage`/`gate_pool`/`agent_pool`/`general_kb_path`/`validate_scope`/`spec_storage_mode`. `general_kb_path` is **required** — missing/empty value also returns 2. | `ERROR: .workflow.yml ...` / `ERROR: ... general_kb_path is required ...` | Run `/bootstrap` (vault-init in the vault dir, or repo mode in a code repo); or fix the offending value. |
| 3 | inline `gate_pool` has duplicate gate IDs (repo mode); **or** a vault `.workflow.yml` carries `gate_pool` but no `repos[]` entry resolves to the vault root (self-hosting exception not satisfied) | `ERROR: <.workflow.yml>: duplicate gate_pool ids: ...` / `ERROR: <.workflow.yml>: vault .workflow.yml carries gate_pool but no repos[] entry resolves to the vault root ...` | Fix `gate_pool:` in `.workflow.yml`; or add the vault-root `repos[]` self-entry. |
| 4 | per-spec `config.yml` missing/malformed, invalid feature id, unknown gate id, unknown phase, unresolved agent id, missing/invalid `tier`, invalid `track`, invalid `branch_strategy`, invalid `coverage_audit`; **or** (vault) `--require-spec` with no `--spec`; **or** `{project}` token unresolved (no `--project`, ambiguous spec dir); **or** invalid project id; **or** per-spec `config.yml project:` ≠ resolved spec-path project; **or** (vault) spec gate id not found in any bound repo's `.workflow.yml gate_pool` | `ERROR: per-spec config missing: ...` / `vault mode requires <feature> ...` / `spec_storage uses {project} but no project resolved ...` / `project '<a>' != resolved spec path project '<b>'` / `gate ids not found in any bound repo's .workflow.yml gate_pool: ...` | Run `/config <feature>` or `/explore <feature>`; pass `--project`; align `config.yml project:`; fix gate ids in a bound repo's `.workflow.yml gate_pool`. |
| 5 | `yq` timeout (5s) or JSON extraction failure | `ERROR: <file>: yq timeout` | Retry; investigate filesystem/`yq` perf. |
| 6 | `yq` not installed, or unknown loader argument | `ERROR: yq not installed` | `brew install yq`. |
| 7 | per-spec `repos[]` entry has missing/invalid path (missing, `..` escape, non-directory, not a git work tree, **or path is a subdirectory of a different repo's toplevel**); **or** task `ground_rules` references a `repo:<name>:` prefix whose `<name>` is not in `repos[]`; **or** a task `ground_rule` uses bare `project:`/unprefixed path under `spec_storage_mode: vault` **with 2+ bound repos** (single-repo vault resolves bare/unprefixed to the sole repo; only multi-repo rejects — `task-manager.sh resolve_ground_rule_path`) | `ERROR: <spec.yml>: repos[i] (<name>) ...` / `ERROR: <spec.yml>: ground_rules reference unknown repo names ...` / `ERROR: vault mode rejects ground_rule ...` | Fix `path:` in `specs/<f>/config.yml`; fix the offending task `ground_rules` entry / add the missing repo binding; or convert bare `project:` rules to `repo:<name>:`. Same exit code is also returned by `task-manager.sh` (`resolve_ground_rule_path`) for symmetry. |

Loader emits `WARN:` for non-fatal conditions (e.g. uncommitted `.workflow.yml` modifications in repo mode) without failing.

## Vault mode

`spec_storage_mode: vault` (in the vault's own `.workflow.yml`, found by normal walk-up):

1. The vault `.workflow.yml` is a **thin pointer** — it owns workflow settings + `general_kb_path` only. It declares no `gate_pool` (single KB; no `knowledge-base/` anywhere), **except** the self-hosting exception (#8 below).
2. Loader sets `WF_VAULT_ROOT = WF_REPO_ROOT = <vault dir>`, leaves `WF_GATE_POOL` **empty** (set to the vault `.workflow.yml` only under the self-hosting exception).
3. `spec_storage` may contain `{project}` — substituted from `--project` (pre-config.yml) or, for `--spec` runs, the unique existing spec dir. Result exported as `WF_SPEC_PROJECT`.
4. With `--spec`, per-spec `config.yml repos[]` is **required** (exit 4 if empty); each path validated as a git work tree (exit 7). `WF_REPO_NAMES`/`WF_REPO_PATHS` exported.
5. Spec `gates:` ids are validated against the **union** of every bound repo's inline `.workflow.yml gate_pool` ids (fail-closed, exit 4 on unknown id) — there is no single pool.
6. Gates resolve **per task** from the bound repo: `multi-repo-resolution.md` derives `WF_TASK_REPO_PATH` and `WF_TASK_GATE_POOL` (`= <repo>/.workflow.yml`). `role: primary` only selects default git/PR context — it is **not** a config source.
7. Repo mode (`spec_storage_mode: repo` or absent) is unaffected; `WF_VAULT_ROOT`/`WF_SPEC_PROJECT` stay unset, `WF_GATE_POOL` = `$WF_CONFIG_FILE` (inline `.gate_pool[]`).
8. **Self-hosting exception:** a vault `.workflow.yml` MAY carry an inline `gate_pool` iff a `repos[]` entry resolves to the vault root dir itself (this repo's dogfood case). When satisfied, `WF_GATE_POOL` = the vault `.workflow.yml`; otherwise a vault `gate_pool` is rejected (exit 3).

## CLI mode

`config-loader.sh export [--spec <feature>]` prints `KEY='val'` lines for hooks that cannot `source`. Same exit codes apply.

## Helpers

- `wf_write_snapshot <outfile>` — JSON snapshot of `WF_SPEC_GATES` + all `WF_SPEC_AGENTS_*` + `WF_BRANCH_STRATEGY`. Used by `/implement` Step 0.
- `wf_check_snapshot_drift <snapfile>` — compares current env to snapshot; `SNAPSHOT_OK` (rc 0) or `SNAPSHOT_DRIFT` (rc 1). Silent rc 0 if snapfile absent.
- `wf_repo_path <name>` — print absolute path of bound repo by logical name. Returns rc 1 if `name` is unknown or no repos bound. Requires loader called with `--spec`.
- `wf_for_each_repo <fn>` — invoke `<fn> NAME PATH` for each entry in `WF_REPO_NAMES`/`WF_REPO_PATHS`. Stops on first non-zero rc.

## Environment knobs

- `WF_LEGACY_SPECS_FALLBACK=1` — when `.workflow.yml` is missing or `yq` is unavailable, `monitor.sh::get_spec_storage` falls back to `<repo_root>/specs`. Off (`0`) by default — fail-closed per ADR-005. Intended only for transitional repos that have not been bootstrapped yet.
