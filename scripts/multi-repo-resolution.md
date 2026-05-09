# Multi-Repo Task Resolution

Canonical snippet for resolving a task's bound repo path under `spec_storage_mode: vault`. Linked from `/implement`, `/validate`, `/ship`, `/pr-review`, `/fix`, `/quick-ship`.

## Vault-CWD invocation

`wf_load_config --spec <feature>` may also be invoked from a master-brain vault directory that has no `.workflow.yml` of its own but holds `specs/<feature>/config.yml`. The loader then derives `WF_REPO_ROOT` from the spec's `repos[]` (role=`primary` first, else `repos[0]`) and exports `WF_VAULT_ROOT=$PWD`. Multi-repo task resolution below is unchanged — `WF_REPO_NAMES` / `WF_REPO_PATHS` still come from the same `repos[]`. See `config-loader.contract.md` for full semantics.

## When this applies

After `wf_load_config --spec <feature>`:
- If `WF_REPO_NAMES` is empty → single-repo flow, no resolution needed. CWD is the repo.
- If `WF_REPO_NAMES` is non-empty → multi-repo flow. Every task **must** declare a `repo:` field whose value is one of `WF_REPO_NAMES`.

`task-manager.sh validate` already enforces `repo:` membership; commands re-resolve here for git/gate execution.

## Resolution snippet

```bash
# Inputs: $task_file (path to task .md), $ARGUMENTS (feature name)
# Assumes: wf_load_config --spec "$ARGUMENTS" already ran (this shell)

if [[ -n "${WF_REPO_NAMES:-}" ]]; then
  # Parse `repo:` from task frontmatter ONLY — never the markdown body.
  # Extract first `---`-delimited block, then run yq against that text.
  task_repo="$(awk '/^---[[:space:]]*$/{c++; next} c==1' "$task_file" 2>/dev/null \
                | yq -r '.repo // ""' 2>/dev/null)"
  if [[ -z "$task_repo" || "$task_repo" == "null" ]]; then
    echo "ERROR: task $task_file missing required 'repo:' field (multi-repo spec)" >&2
    exit 1
  fi
  WF_TASK_REPO_PATH="$(wf_repo_path "$task_repo")" || {
    echo "ERROR: task repo '$task_repo' not in spec repos[]" >&2
    bash "$HOME/.claude/scripts/monitor.sh" log_event "$ARGUMENTS" repo_missing "" \
      "$(printf '{"repo":"%s","task":"%s"}' "$task_repo" "$task_file")"
    exit 1
  }
  bash "$HOME/.claude/scripts/monitor.sh" log_event "$ARGUMENTS" gate_repo_switch "" \
    "$(printf '{"repo":"%s","path":"%s"}' "$task_repo" "$WF_TASK_REPO_PATH")"
else
  WF_TASK_REPO_PATH="$WF_REPO_ROOT"
fi
export WF_TASK_REPO_PATH
```

## Using `WF_TASK_REPO_PATH`

All git, gate, lint, test, edit, and PR operations for this task run inside `WF_TASK_REPO_PATH`:

- `git -C "$WF_TASK_REPO_PATH" <cmd>` — preferred over `cd` (no shell state mutation).
- Gate commands from `gates.yml`: `(cd "$WF_TASK_REPO_PATH" && <gate command>)`.
- Branch + PR creation: scoped to that repo's remote only.
- Phase-2 advisory agents: pass `WF_TASK_REPO_PATH` + scoped diff (`git -C "$WF_TASK_REPO_PATH" diff …`) instead of repo-root diff.

## Hard rule

One task = one repo. Cross-repo work splits into sibling tasks (one per repo) sharing a spec. `task-manager.sh validate` rejects array-valued `repo:`.

## Gate filtering

If a gate in `gates.yml` declares `applies_to_repos: [<name>, …]`, skip it for tasks whose `repo:` is not in that list. Emit `gate_skip` with `{"reason":"applies_to_repos","gate":"<id>","repo":"<task_repo>"}`. Default (no `applies_to_repos`) = applies to every repo.

## Monitor events

| Event | When | Payload |
|---|---|---|
| `gate_repo_switch` | Before running any gate / git op for the task | `{repo, path}` |
| `repo_missing` | `wf_repo_path` failed (unknown name) | `{repo, task}` |
| `repo_bound` | `/bootstrap` wrote a repo binding | `{repo, path, role}` |

All best-effort; do not block flow on `monitor.sh` failure.
