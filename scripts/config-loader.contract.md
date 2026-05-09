# config-loader.sh contract

Single source of truth for `wf_load_config` exported env vars and exit codes. Each workflow command sources `~/.claude/scripts/config-loader.sh` and calls `wf_load_config [--spec <feature>]`. Commands MUST link here instead of inlining partial lists.

## Usage

```bash
source ~/.claude/scripts/config-loader.sh
wf_load_config                  # repo-level only (.workflow.yml + gates.yml)
wf_load_config --spec <feature> # also loads specs/<feature>/config.yml
```

Idempotent: re-sourcing is a no-op unless `WF_RELOAD=1`.

## Exported environment variables

| Variable | Type | Set when | Meaning |
|---|---|---|---|
| `WF_CONFIG_LOADED` | `1` | always on success | Guards re-sourcing. |
| `WF_REPO_ROOT` | abs path | always | Dir containing `.workflow.yml` (walk-up from CWD). |
| `WF_CONFIG_FILE` | abs path | always | `$WF_REPO_ROOT/.workflow.yml`. |
| `WF_SPEC_STORAGE` | abs path | always | Resolved `spec_storage` dir (default `specs/`). |
| `WF_GATE_POOL` | abs path | always | Resolved `gate_pool` file (default `knowledge-base/gates.yml`). |
| `WF_AGENT_POOL` | abs path | always | Resolved `agent_pool` dir (default `~/.claude/agents`). |
| `WF_VALIDATE_SCOPE` | enum | always | `per-task` \| `per-spec` \| `both`. Per-spec override wins. |
| `WF_SPEC_CONFIG_FILE` | abs path | `--spec` only | `$WF_SPEC_STORAGE/<feature>/config.yml`. |
| `WF_SPEC_GATES` | newline-sep IDs | `--spec` only | Spec ceiling: gate IDs from `config.yml gates:`. May be empty. |
| `WF_SPEC_HAS_CONFIG` | `1` | `--spec` only | Marker that per-spec config loaded. |
| `WF_SPEC_AGENTS_<PHASE>` | space-sep IDs | `--spec` only | One per phase present in `config.yml agents:`. `<PHASE>` ∈ `EXPLORE`, `PROPOSE`, `IMPLEMENT`, `VALIDATE`, `PR_REVIEW`. Absent if phase not configured. |
| `WF_SPEC_TIER` | enum | `--spec` only | `small` \| `medium` \| `large`. Required in `config.yml`; absence → exit 4. Drives flow shape. |
| `WF_TIER_TASK_CEILING` | int or empty | `--spec` only | Task-count ceiling for this tier (per-spec `tier_ceiling.tasks` override → `.workflow.yml tiers.<tier>.tasks`). Empty = unbounded. |
| `WF_TIER_FILE_CEILING` | int or empty | `--spec` only | File-count ceiling for this tier. Empty = unbounded. |
| `WF_TIER_AGENT_SKIP` | space-sep IDs | `--spec` only | Agent gates to skip in `/validate` Phase 2 for this tier. Empty for medium/large by default. |
| `WF_SPEC_STORAGE_MODE` | enum | always | `repo` (default) \| `vault`. `vault` = specs live outside any code repo (e.g. master-brain Obsidian) and bind code repos via per-spec `repos[]`. |
| `WF_REPO_NAMES` | newline-sep names | `--spec` only, when `repos[]` declared | Logical repo names from per-spec `config.yml repos[]`. Parallel to `WF_REPO_PATHS`. Empty when spec declares none. |
| `WF_REPO_PATHS` | newline-sep abs paths | `--spec` only, when `repos[]` declared | Absolute repo paths matching `WF_REPO_NAMES` (same index). Each verified to be a git work tree at load time. |
| `WF_VAULT_ROOT` | abs path | only when invoked from a vault dir with no `.workflow.yml` | CWD that held `specs/<feature>/config.yml`. Set when loader fell back to vault discovery — `WF_REPO_ROOT` then points at the chosen `repos[]` entry (role=`primary`, else first). Absent in normal repo-CWD invocations. |

All variables unset on any failure path (no partial state).

## Exit codes

| Code | Condition | User message | Recovery |
|---|---|---|---|
| 0 | success | — | — |
| 2 | `.workflow.yml` missing (and no vault fallback applies — i.e. no `--spec` passed, or no `$PWD/specs/<feature>/config.yml` to anchor on), malformed, or has invalid `spec_storage`/`gate_pool`/`agent_pool`/`validate_scope` | `ERROR: .workflow.yml ...` | Run `/bootstrap`; or fix path/scope value; or invoke from a dir that holds `specs/<feature>/config.yml` (vault mode). |
| 3 | `gates.yml` malformed or has duplicate gate IDs | `ERROR: <pool>: malformed` / `duplicate gate ids: ...` | Fix `knowledge-base/gates.yml`. |
| 4 | per-spec `config.yml` missing/malformed, invalid feature id, unknown gate id, unknown phase, unresolved agent id, or missing/invalid `tier` | `ERROR: per-spec config missing: ...` / `tier required (small\|medium\|large)` etc. | Run `/config <feature>` or `/explore <feature>`; fix gate/agent/tier in `specs/<f>/config.yml`. |
| 5 | `yq` timeout (5s) or JSON extraction failure | `ERROR: <file>: yq timeout` | Retry; investigate filesystem/`yq` perf. |
| 6 | `yq` not installed, or unknown loader argument | `ERROR: yq not installed` | `brew install yq`. |
| 7 | per-spec `repos[]` entry has missing/invalid path (missing, `..` escape, non-directory, not a git work tree, **or path is a subdirectory of a different repo's toplevel**); **or** task `ground_rules` references a `repo:<name>:` prefix whose `<name>` is not in `repos[]`; **or** a task `ground_rule` uses bare `project:`/unprefixed path under `spec_storage_mode: vault` (rejected by `task-manager.sh resolve_ground_rule_path`) | `ERROR: <spec.yml>: repos[i] (<name>) ...` / `ERROR: <spec.yml>: ground_rules reference unknown repo names ...` / `ERROR: vault mode rejects ground_rule ...` | Fix `path:` in `specs/<f>/config.yml`; fix the offending task `ground_rules` entry / add the missing repo binding; or convert bare `project:` rules to `repo:<name>:`. Same exit code is also returned by `task-manager.sh` (`resolve_ground_rule_path`) for symmetry. |

Loader emits `WARN:` for non-fatal conditions (e.g. uncommitted `gates.yml` modifications, or chosen-repo `spec_storage` lying outside `WF_VAULT_ROOT` under vault-CWD invocation) without failing.

## Vault-CWD invocation

When `wf_load_config --spec <feature>` runs in a directory with no `.workflow.yml` but with `specs/<feature>/config.yml`:

1. Loader probes `$PWD/specs/<feature>/config.yml` via `find_vault_spec_config`.
2. Reads `repos[]` from that file. Picks the entry with `role: primary` if any, else `repos[0]`.
3. Sets `WF_VAULT_ROOT=$PWD`, treats the chosen repo as `WF_REPO_ROOT`, and continues with that repo's `.workflow.yml`.
4. Exit codes during fallback: 2 (no `--spec`, or no vault config), 4 (vault config malformed / empty `repos[]`), 5 (yq timeout), 6 (yq missing), 7 (chosen repo path missing/unresolvable/no `.workflow.yml`).
5. Repo-CWD invocations (walk-up succeeds) are unaffected; `WF_VAULT_ROOT` stays unset.

## CLI mode

`config-loader.sh export [--spec <feature>]` prints `KEY='val'` lines for hooks that cannot `source`. Same exit codes apply.

## Helpers

- `wf_write_snapshot <outfile>` — JSON snapshot of `WF_SPEC_GATES` + all `WF_SPEC_AGENTS_*`. Used by `/implement` Step 0.
- `wf_check_snapshot_drift <snapfile>` — compares current env to snapshot; `SNAPSHOT_OK` (rc 0) or `SNAPSHOT_DRIFT` (rc 1). Silent rc 0 if snapfile absent.
- `wf_repo_path <name>` — print absolute path of bound repo by logical name. Returns rc 1 if `name` is unknown or no repos bound. Requires loader called with `--spec`.
- `wf_for_each_repo <fn>` — invoke `<fn> NAME PATH` for each entry in `WF_REPO_NAMES`/`WF_REPO_PATHS`. Stops on first non-zero rc.

## Environment knobs

- `WF_LEGACY_SPECS_FALLBACK=1` — when `.workflow.yml` is missing or `yq` is unavailable, `monitor.sh::get_spec_storage` falls back to `<repo_root>/specs`. Off (`0`) by default — fail-closed per ADR-005. Intended only for transitional repos that have not been bootstrapped yet.
