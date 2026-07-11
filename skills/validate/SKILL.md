---
description: Run validation gates on implemented code for a feature.
disable-model-invocation: false
args:
  - name: feature
    description: feature name
    required: true
---
Run validation gates on implemented code for a feature.

Feature name: $ARGUMENTS

> Terminology: see `~/.claude/scripts/workflow-glossary.md` for canonical definitions of **ceiling**, **effective-set**, **spec-union**. Do not use bare "union" for ceiling/effective-set.

## Prerequisites
1. Read and follow `$WF_GENERAL_KB/_rules.md` for knowledge base prerequisites and resolution rules
2. Read tasks from `specs/$ARGUMENTS/tasks/` — find tasks with `status: implemented`
   - If no tasks have `status: implemented`, report and stop
   - If more than one task has `status: implemented`, report an error: "Multiple tasks are at `implemented` status — only one task should be in flight at a time. Check task state integrity."
   - Validate exactly one task
3. **Draft-PR comment soft check** (non-blocking): if the task has a `pr_url` in frontmatter, list comments on the PR (`gh api repos/<owner/repo>/pulls/<num>/comments` + `…/issues/<num>/comments`) and count those not authored by the current `gh api user` whose body does not start with `[claude]`. If > 0, print a one-line warning: "PR has N comments. Consider running `/pr-review $ARGUMENTS` before `/validate`." Proceed regardless — this is informational only.

## Step 0 — Load Spec Config

Before running any gate or spawning any agent, run (substituting the actual feature name for `$ARGUMENTS`):

> See `~/.claude/scripts/step0-load-config.md` for canonical invocation and remediation. This phase uses: `WF_SPEC_GATES`, `WF_SPEC_AGENTS_VALIDATE`, `WF_GATE_POOL`, `WF_SPEC_TIER`, `WF_SPEC_TRACK`, `WF_BRANCH_STRATEGY`, `WF_COVERAGE_AUDIT` (the last four drive the Phase 3 coverage-audit gating below).

```bash
bash -c 'source ~/.claude/scripts/config-loader.sh && wf_load_config --spec $ARGUMENTS --require-spec && printf "WF_SPEC_GATES=%s\nWF_SPEC_AGENTS_VALIDATE=%s\nWF_GATE_POOL=%s\nWF_SPEC_TIER=%s\nWF_SPEC_TRACK=%s\nWF_BRANCH_STRATEGY=%s\nWF_COVERAGE_AUDIT=%s\n" "$WF_SPEC_GATES" "${WF_SPEC_AGENTS_VALIDATE:-}" "${WF_GATE_POOL:-}" "${WF_SPEC_TIER:-}" "${WF_SPEC_TRACK:-feature}" "${WF_BRANCH_STRATEGY:-per-task}" "${WF_COVERAGE_AUDIT:-true}"'
```

### Multi-repo task resolution

Before Phase 1, resolve task repo per `~/.claude/scripts/multi-repo-resolution.md` → sets `WF_TASK_REPO_PATH` and, in vault mode, `WF_TASK_GATE_POOL` (the bound repo's `.workflow.yml`; `WF_GATE_POOL` is empty in vault mode — `gate-ceiling.sh` uses `WF_TASK_GATE_POOL` when set, querying its inline `.gate_pool[]`). Every gate command in Phase 1 runs as `(cd "$WF_TASK_REPO_PATH" && <gate command>)`. Phase 2 advisory agents receive `WF_TASK_REPO_PATH` and a scoped diff (`git -C "$WF_TASK_REPO_PATH" diff feat/$ARGUMENTS...HEAD`) instead of repo-root diff.

### `applies_to_repos` filter

For each gate in the effective set, check its `applies_to_repos` field in the gate pool (`.workflow.yml .gate_pool[]`). If present and the task's `repo:` is not in the list, skip the gate and emit:
```bash
$HOME/.claude/scripts/monitor.sh log_event "$ARGUMENTS" gate_skip "<task-id>" \
  "$(printf '{"gate":"%s","reason":"applies_to_repos","repo":"%s"}' "<id>" "$task_repo")"
```
Default (no `applies_to_repos` field) = applies to all repos. This filter applies after the ceiling intersection.

## Step 0.5 — Validation Set Preview (non-blocking info)

Before any gate runs and before any agent is spawned, resolve the effective set from config and render it as an audit-trail banner, then fall through to Phase 1 with **no prompt**. The set is fully determined by config the user already approved (`config.yml` `gates:`/`agents:`/`coverage_audit:`/`tier`/`track`/`validate_scope` + each task's `ground_rules`); there are no runtime escape hatches. Want agents off? Edit `config.yml` and re-run. Ctrl-C covers true emergencies.

1. Compute the per-task effective set once for preview:
   ```bash
   source ~/.claude/scripts/gate-ceiling.sh
   effective="$(wf_compute_effective_set "<task-file>")"
   ```
   Capture also: ceiling-skipped gates (in `WF_GATE_POOL`, language-applicable, but not in `WF_SPEC_GATES`), `applies_to`-skipped gates, `applies_to_repos`-skipped gates.

2. Compute the post-tier-skip advisory agent list. Start from `WF_SPEC_AGENTS_VALIDATE`, drop any agent listed in `WF_TIER_AGENT_SKIP`, capture skipped agents with reason `tier_skip=<WF_SPEC_TIER>`. **This is what runs** — the tier filter that previously sat in Phase 2 lives here (so Phase 2's filter is a no-op).

2a. Compute the **Phase 3 coverage-audit** status for the preview (full gating lives in Phase 3 below) via the same decision predicate Phase 3 uses — `eval "$(bash ~/.claude/scripts/decide.sh coverage-skip)"`: `VERDICT=skip` → preview shows `skipped reason: <REASON>` (`tier_small` | `config_off` | `scope=per-spec`); `VERDICT=run` → `enabled`. The priority chain is not re-derived here.

3. Render the preview as plain status output, then proceed straight to Phase 1:
   ```
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
     Validate — <feature> / <task-id>
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
     Deterministic gates (effective set):
       - <gate-id>  [<category>]
       …
     Skipped deterministic gates:
       - <gate-id>  reason: <not-in-ceiling|applies_to|applies_to_repos>
       …
     Advisory agents (post-tier-skip):
       - <agent-id>
       …
     Skipped advisory agents:
       - <agent-id>  reason: tier_skip=<tier>
     Coverage audit (Phase 3):
       <enabled | skipped reason: <tier_small|config_off|scope=per-spec>>
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ```

4. Proceed to Phase 1 with the resolved sets. No `AskUserQuestion`, no abort affordance — config is the single source of truth.

## Phase 1: Gate Ceiling Intersection (hard gates)

For each task with `status: implemented`:
1. Source the canonical helper and compute the per-task effective set (same source of truth as `/validate-impl`):

   ```bash
   source ~/.claude/scripts/gate-ceiling.sh
   effective="$(wf_compute_effective_set "<task-file>")"; rc=$?
   ```

   Semantics: extracts language tags from the task's `ground_rules` (paths matching `languages/<lang>.md`), reads the gate pool, and returns `WF_SPEC_GATES` (ceiling) ∩ {gates whose `applies_to` matches a task tag or contains `any`} — sorted, unique. Gate pool source: `WF_TASK_GATE_POOL` when set (vault mode — the per-task bound repo's `.workflow.yml`, resolved in "Multi-repo task resolution" above), else `WF_GATE_POOL` (repo mode). Both point at a `.workflow.yml`; gate lookups query its inline `.gate_pool[]`. `gate-ceiling.sh` applies this precedence internally; in vault mode `WF_GATE_POOL` is empty and must not be relied on here.
2. On rc 3 (empty effective set on code-bearing task without `empty_intersection_ok: true`) record the critical finding from step 5 below before continuing. On rc 90 abort with "yq required".
3. **Effective set** is the value printed by the helper.

### Scope short-circuit (T016)

After computing the effective set above and before step 4 below, branch on `WF_VALIDATE_SCOPE`:
- `per-task` (default) or `both`: continue with the rest of Phase 1 unchanged.
- `per-spec`: for every gate id `<g>` in the effective set, emit `gate_skip` with `reason=scope=per-spec`:
  ```bash
  $HOME/.claude/scripts/monitor.sh log_event "$ARGUMENTS" gate_skip "<task-id>" \
    "$(printf '{"gate":"%s","reason":"scope=per-spec","scope":"per-spec"}' "<g>")"
  ```
  Then write a single zero-findings report `specs/$ARGUMENTS/reports/<task-id>-scope-skip.yaml` with `status: pass`, skip Phase 2 entirely, and proceed to the zero-findings status update path. The **spec-union** runs later via `/validate-impl` (Step 2).

  Empty-intersection fail-closed (ADR-003) still applies: if the effective set is empty AND `empty_intersection_ok` is not `true`, treat as the existing `error` finding before this short-circuit takes effect.
4. For each language-applicable gate whose ID is **not** in `WF_SPEC_GATES`: emit a `gate_skip` monitor event:
   ```bash
   $HOME/.claude/scripts/monitor.sh log_event "$ARGUMENTS" "gate_skip" "" \
     "$(printf '{"gate":"%s","reason":"not in spec ceiling"}' "<id>")"
   ```
5. If the effective set is empty:
   - Read task frontmatter `empty_intersection_ok` field (default `false`).
   - If `empty_intersection_ok: true`: emit `gate_skip` event with `reason: empty_intersection_ok`, record 0 gates executed, treat as pass — skip to Phase 2.
   - If `false` (default): record a `critical` error finding (`"Empty effective gate set on code-bearing task — ceiling ∩ ground_rules yielded no gates. Verify spec config.yml gates and task ground_rules."`), set gate status to `error`, block transition to `done`.
6. Build a self-contained **job spec** from the effective set via the canonical helper — do **not** hand-loop the gates and accumulate JSON in prose (that re-derives a pure data transform every run and is a classic LM error site). `wf_build_gate_job_spec` pulls each surviving gate's `command`, `cwd`, and `category` from the active gate pool (`WF_TASK_GATE_POOL` when set in vault mode, else `WF_GATE_POOL` — the same precedence `gate-ceiling.sh` uses) and emits the `[{gate_id, command, cwd?, category}]` JSON array directly (compact, input-order, `cwd` omitted when the gate declares none; command strings escaped as data):
   ```bash
   source ~/.claude/scripts/gate-ceiling.sh
   pool="${WF_TASK_GATE_POOL:-$WF_GATE_POOL}"
   job_spec="$(wf_build_gate_job_spec "$effective" "$pool")"   # rc 90 if yq missing
   ```
7. **Delegate execution to the `gate-runner` subagent** so raw gate output never enters the main session. Spawn **one** agent (`subagent_type: gate-runner`) for the whole effective set, passing only the mechanical job spec:
   - `task_id` = the implemented task's id.
   - `WF_TASK_REPO_PATH` = the path resolved in "Multi-repo task resolution" above.
   - `report_dir` = `specs/$ARGUMENTS/reports/` (absolute).
   - `report_schema_path` = `~/.claude/scripts/report-schema.md`.
   - `gates` = `$job_spec`, the `[{gate_id, command, cwd?, category}]` JSON built in step 6.

   The subagent runs each gate (`(cd "$WF_TASK_REPO_PATH[/cwd]" && <command>)`), converts output to the report schema, **writes** `reports/<task-id>-<gate>.yaml` itself (`source: tool`), and returns **only** a compact per-gate verdict (`pass | findings(N) | error` + report path + totals). It performs no analysis, no fixes, no retries, and reads no KB/config/design files.

   Do **not** ingest the raw gate output. On return, main reads the on-disk `reports/<task-id>-*.yaml` exactly as Gate Aggregation and Status Update below already do — including a missing or `status: error` report, which the existing "any gate error → re-run `/validate`" path re-spawns the whole set for (the subagent is stateless and never retries internally).

## Phase 2: Agent-Powered Analysis (advisory)

Spawn agents **in parallel** to analyze code against knowledge-base rules. Agent list comes from `WF_SPEC_AGENTS_VALIDATE` (space-separated IDs loaded in Step 0). If `WF_SPEC_AGENTS_VALIDATE` is empty, skip Phase 2 entirely (no advisory agents for this spec).

**Tier-based skip:** Already applied in Step 0.5 — the agent list at this point is the post-tier-skip resolved set. Tier-skip `gate_skip` events were emitted there. If the resolved list is empty (all agents were tier-filtered, or `WF_SPEC_AGENTS_VALIDATE` was empty), skip Phase 2 entirely.

Each spawned agent receives:
- The task file path and changed files (from `estimated_files` or git diff)
- All `ground_rules` files referenced in the task (per `knowledge-base-rules.md`)
- The project's `CLAUDE.md` and relevant rule files from the general KB (`$WF_GENERAL_KB`)

Resolve each agent ID per the Agent ID grammar in `design.md §Backend Design §Agent ID grammar`:
- `<category>/<name>` → `<agent_pool>/<category>/<category>-<name>.md`
- bare `<name>` → `<agent_pool>/<name>.md`

Unknown agent ID → stop immediately with error "Unknown agent ID '<id>' in specs/$ARGUMENTS/config.yml agents.validate — not found in agent pool."

### Independent Verification Rule
Each agent gate operates independently. No agent should trust or defer to another agent's results. Redundant findings are acceptable — missed findings are not.

### Agent Output Contract
Each agent must return findings in the report schema (below). When constructing the prompt for each agent, instruct it to output findings as a YAML list matching the report schema. Mark all agent findings with `source: llm`.

#### Grade → severity mapping (graded KB rules)
KB topic files grade each rule with a leading keyword (`MUST` / `SHOULD` / `MAY`) per `$WF_GENERAL_KB/_authoring.md`. When an agent reports a finding for a violated graded rule, it MUST set the finding `severity` from the violated rule's grade:

| Violated rule grade | Finding `severity` | Disposition |
|---|---|---|
| `MUST`   | `high`   | blocking — routes the task to `review` |
| `SHOULD` | `medium` | advisory |
| `MAY`    | `low`    | note / informational |

Instruct each advisory agent in its prompt: *"Each KB rule opens with a grade keyword. A violated `MUST` is a `high` (blocking) finding; a violated `SHOULD` is `medium` (advisory); a violated `MAY` is `low` (note). Carry the grade into the finding severity; do not invent severities."* Deterministic pass/fail stays in the Phase 1 linters/gates — this mapping governs only the advisory (`source: llm`) findings.

### Collecting Results
After all agents complete, merge their findings into per-gate YAML reports. If an agent errors or times out, record a single `error` finding for that gate (do not block other gates).

## Phase 3: Per-Task Coverage Audit (advisory)

Reuses the generic **Odium** agent (`agents/odium.md`, **do not edit**) to verify the implemented diff covers **this task's own** acceptance criteria — `## Acceptance` Given/When/Then rows + `## Implements` FR refs on the feature track, or `technical_acceptance:` frontmatter on the technical track. It is **advisory**: any gap becomes a `source: llm` finding in `reports/<task-id>-coverage.yaml` and flows through the existing Gate Aggregation → `review` → `/review-and-ship` pipeline. No new hard-block path; no new status.

Source the helpers (same module `/validate-impl` uses):

```bash
source ~/.claude/scripts/validate-impl.sh
spec_dir="$WF_SPEC_STORAGE/$ARGUMENTS"
```

1. **Skip** (emit `gate_skip` and proceed straight to Gate Aggregation) when the decision predicate says so. The first-matching-reason priority chain (`tier_small` → `config_off` → `scope=per-spec`) lives once in `~/.claude/scripts/decide.sh` — do not re-derive it here:

   ```bash
   eval "$(bash ~/.claude/scripts/decide.sh coverage-skip)"   # sets VERDICT, REASON
   if [[ "$VERDICT" == "skip" ]]; then
     $HOME/.claude/scripts/monitor.sh log_event "$ARGUMENTS" gate_skip "<task-id>" \
       "$(printf '{"gate":"coverage","reason":"%s"}' "$REASON")"
     # proceed straight to Gate Aggregation
   fi
   ```

   (The `scope=per-spec` skip normally never reaches Phase 3 — the Phase-1 per-spec short-circuit already wrote the single pass report and skipped Phase 2; the predicate's guard is defensive.)

2. Compute the task-scoped diff range and build the wrapper prompt:
   ```bash
   diff_range="$(wf_vi_task_diff_range "$ARGUMENTS" "<task-file>")" || { echo "coverage audit: cannot resolve diff range"; }
   prompt="$(wf_vi_build_task_prompt "$ARGUMENTS" "<task-file>" "$spec_dir" "$diff_range")"
   ```
   On `wf_vi_task_diff_range` non-zero (rc 5 — no range resolvable), treat as a Phase-3 error: write a single `status: error` finding to `reports/<task-id>-coverage.yaml` (see step 6) and stop the phase. Never audit a guessed range.

3. Emit start, then spawn Odium:
   ```bash
   wf_vi_emit_coverage_start "$ARGUMENTS" "<task-id>"
   ```
   Spawn the agent with `subagent_type: odium`, passing `$prompt` as its instructions and `WF_TASK_REPO_PATH` as the working directory (Odium runs `git diff <diff_range>` itself). Capture its full Markdown body. Do **not** edit `agents/odium.md` — the per-task framing lives entirely in the wrapper prompt.

4. Parse the returned `verdict` from the agent's YAML frontmatter (`complete` | `reopen`). Reject any FR id appearing in the body that is **not** in the prompt's FR-reference allowlist (fail closed, mirroring `/validate-impl` Step 4) — a hallucinated FR ref downgrades the verdict to `reopen` and is noted. Write the agent's Acceptance × Coverage matrix to a temp file `<matrix_file>` (the table rows from its output).

5. Persist the report and emit done:
   ```bash
   report="$(wf_vi_write_task_coverage_report "$ARGUMENTS" "$spec_dir" "<task-id>" "<complete|reopen>" "<matrix_file>")"
   wf_vi_emit_coverage_done "$ARGUMENTS" "<task-id>" "<complete|reopen>" "$report"
   ```
   `complete` → `status: pass`, `findings: []`. `reopen` → one `source: llm` finding per `missing` (severity `high`) / `partial` (severity `medium`) matrix row.

6. **Odium error/timeout** (or rc-5 diff range from step 2) → write a single `status: error` finding to `reports/<task-id>-coverage.yaml` (matches Phase 2 error handling). The existing Gate Aggregation "any gate error → re-run" rule governs.

The coverage report is just another `reports/<task-id>-*.yaml` — Gate Aggregation and Status Update below treat it identically to every other gate report. No special-casing.

## Output
One YAML report per gate to `specs/$ARGUMENTS/reports/{task-id}-{gate}.yaml`. Schema: `~/.claude/scripts/report-schema.md` (canonical).

## Gate Aggregation (Triple-Gate Rule)
Before determining the final status, verify ALL gates produced a report:
- If any gate has `status: error` (agent timed out or crashed), that gate must be re-run before proceeding. Do not allow shipping with an incomplete gate.
- If any gate has `status: findings` with unresolved items, the task goes to `review`.
- Only when ALL gates report `status: pass` (zero findings each) is the task eligible for `done`.

## Status Update
- If any gate has `status: error`: report which gate(s) failed and instruct: "Re-run `/validate $ARGUMENTS` to retry the failed gate(s)."
- If any findings exist across any gate: run `~/.claude/scripts/task-manager.sh set-status <task-file> review`, then stop and instruct the user: "Findings present. Run `/review-and-ship $ARGUMENTS` next." (it addresses findings and ships the task inline)
- If zero findings across all gates and all gates have `status: pass`:
  1. Run `~/.claude/scripts/task-manager.sh set-status <task-file> done`
  2. Run `~/.claude/scripts/task-manager.sh unblock specs/$ARGUMENTS/tasks/`
  3. Do NOT delete reports here — reports are retained (local audit trail); nothing deletes them. `/learn-from-reports` mines passing reports for borderline LLM advisories in place.
  4. **Ship the task inline.** Run the shared `~/.claude/scripts/ship-procedure.md` against `<task-file>` / `<task-id>` / `<task-title>` (config loaded in Step 0; `WF_TASK_REPO_PATH` resolved in "Multi-repo task resolution"). It commits, pushes, and marks the PR ready (drift check, branch strategy, single-branch last-task spec PR all owned by the procedure).
  5. Stop and instruct the user: "All gates pass and task shipped (PR ready). Run `/learn-from-reports $ARGUMENTS <task-id>` next." (pass the task-id resolved above so mining is scoped to this task)

Report schema: see `~/.claude/scripts/report-schema.md`. All findings written here use `review_status: pending`; tool gates set `source: tool`, advisory agents set `source: llm`.

Gate selection: determined by ceiling intersection (Phase 1 above) using `gates.yml` and `WF_SPEC_GATES`. Advisory agents: determined by `WF_SPEC_AGENTS_VALIDATE` from `config.yml`.
