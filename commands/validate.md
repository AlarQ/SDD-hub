Run validation gates on implemented code for a feature.

Feature name: $ARGUMENTS

> Terminology: see `~/.claude/scripts/workflow-glossary.md` for canonical definitions of **ceiling**, **effective-set**, **spec-union**. Do not use bare "union" for ceiling/effective-set.

## Prerequisites
1. Read and follow `$WF_GENERAL_KB/_rules.md` for knowledge base prerequisites and resolution rules
2. Read tasks from `specs/$ARGUMENTS/tasks/` — find tasks with `status: implemented`
   - If no tasks have `status: implemented`, report and stop
   - If more than one task has `status: implemented`, report an error: "Multiple tasks are at `implemented` status — only one task should be in flight at a time. Check task state integrity."
   - Validate exactly one task
3. **Draft-PR comment soft check** (non-blocking): if the task has a `pr_url` in frontmatter, list comments on the PR (`gh api repos/<owner/repo>/pulls/<num>/comments` + `…/issues/<num>/comments`) and count those without a `eyes` reaction by the current `gh api user`. If > 0, print a one-line warning: "PR has N unaddressed comments. Consider running `/pr-review $ARGUMENTS` before `/validate`." Proceed regardless — this is informational only.

## Step 0 — Load Spec Config

Before running any gate or spawning any agent, run (substituting the actual feature name for `$ARGUMENTS`):

> See `~/.claude/scripts/step0-load-config.md` for canonical invocation and remediation. This phase uses: `WF_SPEC_GATES`, `WF_SPEC_AGENTS_VALIDATE`, `WF_GATE_POOL`.

```bash
bash -c 'source ~/.claude/scripts/config-loader.sh && wf_load_config --spec $ARGUMENTS --require-spec && printf "WF_SPEC_GATES=%s\nWF_SPEC_AGENTS_VALIDATE=%s\nWF_GATE_POOL=%s\n" "$WF_SPEC_GATES" "${WF_SPEC_AGENTS_VALIDATE:-}" "${WF_GATE_POOL:-}"'
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

## Step 0.5 — Validation Set Approval (mandatory, fail-closed)

Before any gate runs and before any agent is spawned, preview the resolved set and require explicit user approval.

1. Compute the per-task effective set once for preview:
   ```bash
   source ~/.claude/scripts/gate-ceiling.sh
   effective="$(wf_compute_effective_set "<task-file>")"
   ```
   Capture also: ceiling-skipped gates (in `WF_GATE_POOL`, language-applicable, but not in `WF_SPEC_GATES`), `applies_to`-skipped gates, `applies_to_repos`-skipped gates.

2. Compute the post-tier-skip advisory agent list. Start from `WF_SPEC_AGENTS_VALIDATE`, drop any agent listed in `WF_TIER_AGENT_SKIP`, capture skipped agents with reason `tier_skip=<WF_SPEC_TIER>`. **What the user approves here is what runs** — the tier filter that previously sat in Phase 2 (line 80 below) moves to this step.

3. Render the preview as plain status output:
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
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ```

4. **MUST** invoke `AskUserQuestion` (per `~/.claude/scripts/ask-user-protocol.md`):
   - **question:** "Proceed with this validation set?"
   - **options:**
     - `Run all` — proceed with shown deterministic gates and advisory agents.
     - `Skip advisory agents` — Phase 1 only; treat `WF_SPEC_AGENTS_VALIDATE` as empty for this run; emit `gate_skip` with `reason=user_skipped` per omitted agent.
     - `Edit ceiling` — abort. Print: "Run `/config <feature>` to edit ceiling, then re-run `/validate <feature>`."
     - `Cancel` — abort cleanly; do not change task status.

5. **Fail-closed:** if `AskUserQuestion` cannot be invoked or returns no selection, abort. Do NOT default to `Run all`. Print: `Approval required — validation aborted. Re-run /validate <feature>.`

6. On approval, emit a monitor event:
   ```bash
   $HOME/.claude/scripts/monitor.sh log_event "$ARGUMENTS" "validate_set_approved" "<task-id>" \
     "$(printf '{"gates":%s,"agents":%s,"decision":"%s"}' "<gates-json>" "<agents-json>" "<run_all|skip_agents>")"
   ```

7. On `Run all` or `Skip advisory agents`, proceed to Phase 1 with the approved sets. Phase 2 already-applied tier filter is now a no-op (filtering already done here).

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
6. Run **every** gate in the effective set using its `command` from the gate pool (`.workflow.yml .gate_pool[]`) — skipping is not allowed.
   - If a gate command is missing or fails to install, record it as an error finding.
7. Collect all gate outputs and convert findings into the report schema.

## Phase 2: Agent-Powered Analysis (advisory)

Spawn agents **in parallel** to analyze code against knowledge-base rules. Agent list comes from `WF_SPEC_AGENTS_VALIDATE` (space-separated IDs loaded in Step 0). If `WF_SPEC_AGENTS_VALIDATE` is empty, skip Phase 2 entirely (no advisory agents for this spec).

**Tier-based skip:** Already applied in Step 0.5 — the agent list at this point is the post-tier-skip approved set. Tier-skip `gate_skip` events were emitted there. If the approved list is empty (user picked `Skip advisory agents`, or all agents were tier-filtered, or `WF_SPEC_AGENTS_VALIDATE` was empty), skip Phase 2 entirely.

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

### Collecting Results
After all agents complete, merge their findings into per-gate YAML reports. If an agent errors or times out, record a single `error` finding for that gate (do not block other gates).

## Output
One YAML report per gate to `specs/$ARGUMENTS/reports/{task-id}-{gate}.yaml`. Schema: `~/.claude/scripts/report-schema.md` (canonical).

## Gate Aggregation (Triple-Gate Rule)
Before determining the final status, verify ALL gates produced a report:
- If any gate has `status: error` (agent timed out or crashed), that gate must be re-run before proceeding. Do not allow shipping with an incomplete gate.
- If any gate has `status: findings` with unresolved items, the task goes to `review`.
- Only when ALL gates report `status: pass` (zero findings each) is the task eligible for `done`.

## Status Update
- If any gate has `status: error`: report which gate(s) failed and instruct: "Re-run `/validate $ARGUMENTS` to retry the failed gate(s)."
- If any findings exist across any gate: run `~/.claude/scripts/task-manager.sh set-status <task-file> review`, then stop and instruct the user: "Findings present. Run `/review-findings $ARGUMENTS` next."
- If zero findings across all gates and all gates have `status: pass`:
  1. Run `~/.claude/scripts/task-manager.sh set-status <task-file> done`
  2. Run `~/.claude/scripts/task-manager.sh unblock specs/$ARGUMENTS/tasks/`
  3. Do NOT delete reports here — `/learn-from-reports` mines passing reports for borderline LLM advisories and owns deletion.
  4. Stop and instruct the user: "All gates pass. Run `/learn-from-reports $ARGUMENTS` next."

Report schema: see `~/.claude/scripts/report-schema.md`. All findings written here use `review_status: pending`; tool gates set `source: tool`, advisory agents set `source: llm`.

Gate selection: determined by ceiling intersection (Phase 1 above) using `gates.yml` and `WF_SPEC_GATES`. Advisory agents: determined by `WF_SPEC_AGENTS_VALIDATE` from `config.yml`.
