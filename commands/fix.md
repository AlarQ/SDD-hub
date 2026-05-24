# /fix — Standalone Bug-Fix Flow

Skip `/explore` and `/propose`. Minimal artifact at `specs/fixes/<slug>/fix.md`. Use for production bugs, regressions, hotfixes — anything where spec/design overhead is wasted ceremony.

**Argument:** `$ARGUMENTS` is `<slug>` (kebab-case bug id, e.g. `login-redirect-loop`).

Refuse if `$ARGUMENTS` is empty or invalid (`^[a-z][a-z0-9-]{0,63}$`).

## Step 0 — Load config + monitor context

```bash
source ~/.claude/scripts/config-loader.sh
wf_load_config || exit $?
slug="$ARGUMENTS"
fix_dir="$WF_SPEC_STORAGE/fixes/$slug"
mkdir -p "$fix_dir"
bash ~/.claude/scripts/monitor.sh set_context "fixes/$slug" "fix"
bash ~/.claude/scripts/monitor.sh log_event "fixes/$slug" fix_started "" \
  "$(printf '{"slug":"%s"}' "$slug")"
```

## Step 1 — Capture repro (BDD)

Use `AskUserQuestion` to elicit:
- Symptom (one line)
- Reproduction steps (Given / When / Then-broken)
- Expected vs actual

Write the BDD block into the **Repro** section of `fix.md` (template below).

## Step 2 — Spawn Ultrathink Debugger

Spawn `ultrathink-debugger` agent with the repro block + relevant file paths. Require output:
- Root cause (concrete: function + file + line)
- Affected files (list)
- Proposed fix (paragraph + diff hint)
- Regression test name (must be deterministic, must fail before fix)

Emit `fix_root_cause` event with `{"cause":"<one-line>","files":<count>}`.

## Step 3 — Write fix.md

Render `~/.claude/templates/fix.md.template` into `$fix_dir/fix.md`. Frontmatter required:

```yaml
---
type: fix
slug: <slug>
status: in-progress
regression_test: <test-name>
created: <ISO-8601>
repo: <name>           # required only if WF_SPEC_STORAGE_MODE=vault — must be in default_repos[]
---
```

In vault mode (`WF_SPEC_STORAGE_MODE=vault` from Step 0's `wf_load_config`), refuse if `repo:` is missing. Fixes are spec-less, so `wf_load_config --spec` does not apply — resolve against `default_repos[]` from `.workflow.yml`:

```bash
# Validate name shape *before* feeding into yq to avoid expression injection.
[[ "$repo" =~ ^[a-z0-9][a-z0-9_-]{0,31}$ ]] || { echo "ERROR: repo '$repo' invalid (expected ^[a-z0-9][a-z0-9_-]{0,31}$)" >&2; exit 1; }
# strenv() keeps the value out of the yq expression (no interpolation).
WF_TASK_REPO_PATH="$(repo="$repo" yq -r '.default_repos[] | select(.name == strenv(repo)) | .path' "$WF_CONFIG_FILE" | head -1)"
[[ -z "$WF_TASK_REPO_PATH" || "$WF_TASK_REPO_PATH" == "null" ]] && { echo "ERROR: repo '$repo' not in .workflow.yml default_repos[]" >&2; exit 1; }
WF_TASK_REPO_PATH="${WF_TASK_REPO_PATH/#\~/$HOME}"
toplevel="$(git -C "$WF_TASK_REPO_PATH" rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: $WF_TASK_REPO_PATH is not a git work tree" >&2; exit 1; }
# Strict-equality: reject subdirectories of a different repo (typo guard).
[[ "$(cd "$WF_TASK_REPO_PATH" && pwd -P)" == "$(cd "$toplevel" && pwd -P)" ]] || { echo "ERROR: $WF_TASK_REPO_PATH is inside repo $toplevel, not the toplevel" >&2; exit 1; }
bash "$HOME/.claude/scripts/monitor.sh" log_event "fixes/$slug" gate_repo_switch "" \
  "$(printf '{"repo":"%s","path":"%s"}' "$repo" "$WF_TASK_REPO_PATH")" >/dev/null 2>&1 || true
```

All git ops, regression-test execution, lint, and ship steps below run inside `WF_TASK_REPO_PATH` (use `git -C "$WF_TASK_REPO_PATH" …`). Single-repo mode: `WF_TASK_REPO_PATH="$WF_REPO_ROOT"`.

Sections: `## Repro`, `## Root Cause`, `## Fix Plan`, `## Regression Test`.

## Step 4 — Pre-fix test capture

Run the regression test and **assert it fails**. Capture stderr/stdout into `$fix_dir/pre-fix.log`. If the test passes pre-fix, abort: the test is wrong (does not actually exercise the bug). Loop back to Step 2.

## Step 5 — Implement fix

Apply the fix inline. Single branch `fix/<slug>` off `main`. No separate task files. Run regression test → must pass. Run lint.

## Step 6 — Validate

Run gates from `.workflow.yml gate_pool:` whose `applies_to` matches the touched files' inferred ground rules. Skip Phase-2 agent gates (security, code-quality, architecture, compliance) by default unless the diff touches security-sensitive paths (auth/, crypto/, migrations/) — in that case spawn `Security Engineer` advisory only.

No `/validate-impl`. No `/learn-from-reports` unless a finding is rejected and produces a generalizable rule (then it is written to the general KB).

## Step 7 — Ship

Reuse `/ship` machinery. PR title prefix `fix:`. Body includes Repro + Root Cause + Regression Test name. Set `status: done` in `fix.md`. Emit `fix_shipped`.

## Notes

- `/fix` is single-task — `task-manager.sh` is invoked via the `init-fix <slug>` subcommand only for status tracking; no `blocked_by` graph.
- Tier system does not apply (no `tier:` in `fix.md` frontmatter).
- Refuse to run if any other workflow has an in-flight task (`status: in-progress` or `implemented` in `specs/<other>/tasks/`) — prevents interleaved branches.

Run `/ship` next.
