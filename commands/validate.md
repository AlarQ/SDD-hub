Run validation gates on implemented code for a feature.

Feature name: $ARGUMENTS

> Terminology: **ceiling**, **effective-set**, **spec-union** — see `CLAUDE.md` "Configurable Workflow → Key terms" glossary. Do not use bare "union" for ceiling/effective-set.

## Prerequisites
1. Read and follow `~/.claude/knowledge-base-rules.md` for knowledge base prerequisites and resolution rules
2. Read tasks from `specs/$ARGUMENTS/tasks/` — find tasks with `status: implemented`
   - If no tasks have `status: implemented`, report and stop
   - If more than one task has `status: implemented`, report an error: "Multiple tasks are at `implemented` status — only one task should be in flight at a time. Check task state integrity."
   - Validate exactly one task

## Step 0 — Load Spec Config

Before running any gate or spawning any agent, run (substituting the actual feature name for `$ARGUMENTS`):

Loader contract (env vars + exit codes): `scripts/config-loader.contract.md`. This phase uses `WF_SPEC_GATES`, `WF_SPEC_AGENTS_VALIDATE`, `WF_GATE_POOL`.

```bash
bash -c 'source ~/.claude/scripts/config-loader.sh && wf_load_config --spec $ARGUMENTS && printf "WF_SPEC_GATES=%s\nWF_SPEC_AGENTS_VALIDATE=%s\nWF_GATE_POOL=%s\n" "$WF_SPEC_GATES" "${WF_SPEC_AGENTS_VALIDATE:-}" "${WF_GATE_POOL:-}"'
```

On non-zero exit, halt and print the loader error. Exit-code 4 specifically means missing/invalid `specs/$ARGUMENTS/config.yml` — recover via `/explore $ARGUMENTS` or `/config $ARGUMENTS`. See contract for full table.

## Phase 1: Gate Ceiling Intersection (hard gates)

For each task with `status: implemented`:
1. Source the canonical helper and compute the per-task effective set (same source of truth as `/validate-impl`):

   ```bash
   source ~/.claude/scripts/gate-ceiling.sh
   effective="$(wf_compute_effective_set "<task-file>")"; rc=$?
   ```

   Semantics: extracts language tags from the task's `ground_rules` (paths matching `languages/<lang>.md`), reads `WF_GATE_POOL` (`gates.yml`), and returns `WF_SPEC_GATES` (ceiling) ∩ {gates whose `applies_to` matches a task tag or contains `any`} — sorted, unique.
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
6. Run **every** gate in the effective set using its `command` from `gates.yml` — skipping is not allowed.
   - If a gate command is missing or fails to install, record it as an error finding.
7. Collect all gate outputs and convert findings into the report schema.

## Phase 2: Agent-Powered Analysis (advisory)

Spawn agents **in parallel** to analyze code against knowledge-base rules. Agent list comes from `WF_SPEC_AGENTS_VALIDATE` (space-separated IDs loaded in Step 0). If `WF_SPEC_AGENTS_VALIDATE` is empty, skip Phase 2 entirely (no advisory agents for this spec).

Each spawned agent receives:
- The task file path and changed files (from `estimated_files` or git diff)
- All `ground_rules` files referenced in the task (per `knowledge-base-rules.md`)
- The project's `CLAUDE.md` and relevant knowledge-base files from both general and project KBs

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
One YAML report per gate to `specs/$ARGUMENTS/reports/{task-id}-{gate}.yaml`

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

Report schema:
- gate: <gate-name>
- task_id: <id>
- status: pass | findings | error
- findings: list of {id, severity (critical|high|medium|low|info), category, title, description, file, lines, code_snippet, fix_proposal, review_status: pending, source: tool|llm}

Gate selection: determined by ceiling intersection (Phase 1 above) using `gates.yml` and `WF_SPEC_GATES`. Advisory agents: determined by `WF_SPEC_AGENTS_VALIDATE` from `config.yml`.
