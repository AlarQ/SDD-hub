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

All variables unset on any failure path (no partial state).

## Exit codes

| Code | Condition | User message | Recovery |
|---|---|---|---|
| 0 | success | — | — |
| 2 | `.workflow.yml` missing, malformed, or has invalid `spec_storage`/`gate_pool`/`agent_pool`/`validate_scope` | `ERROR: .workflow.yml ...` | Run `/bootstrap`; or fix path/scope value. |
| 3 | `gates.yml` malformed or has duplicate gate IDs | `ERROR: <pool>: malformed` / `duplicate gate ids: ...` | Fix `knowledge-base/gates.yml`. |
| 4 | per-spec `config.yml` missing/malformed, invalid feature id, unknown gate id, unknown phase, or unresolved agent id | `ERROR: per-spec config missing: ...` etc. | Run `/config <feature>` or `/explore <feature>`; fix gate/agent ids in `specs/<f>/config.yml`. |
| 5 | `yq` timeout (5s) or JSON extraction failure | `ERROR: <file>: yq timeout` | Retry; investigate filesystem/`yq` perf. |
| 6 | `yq` not installed, or unknown loader argument | `ERROR: yq not installed` | `brew install yq`. |

Loader emits `WARN:` for non-fatal conditions (e.g. uncommitted `gates.yml` modifications) without failing.

## CLI mode

`config-loader.sh export [--spec <feature>]` prints `KEY='val'` lines for hooks that cannot `source`. Same exit codes apply.

## Helpers

- `wf_write_snapshot <outfile>` — JSON snapshot of `WF_SPEC_GATES` + all `WF_SPEC_AGENTS_*`. Used by `/implement` Step 0.
- `wf_check_snapshot_drift <snapfile>` — compares current env to snapshot; `SNAPSHOT_OK` (rc 0) or `SNAPSHOT_DRIFT` (rc 1). Silent rc 0 if snapfile absent.
