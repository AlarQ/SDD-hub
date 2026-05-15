Edit or regenerate the spec config for a feature.

Feature name: $ARGUMENTS (strip any `--regenerate` flag before treating as the feature name)

> **Direct YAML edits to `specs/<feature>/config.yml` are discouraged.** Route all config changes through this command — it validates IDs against the current registries before writing, the same reason task frontmatter changes go through `task-manager.sh` rather than direct edits.

## Prerequisites
1. Read and follow `$WF_GENERAL_KB/_rules.md` for knowledge base prerequisites and resolution rules
2. Parse `$ARGUMENTS`: split on whitespace. The last token is `--regenerate` if present (set `MODE=regenerate`), otherwise `MODE=edit`. The remaining tokens are the feature name. If no feature name remains after stripping the flag, stop: "Usage: `/config <feature>` or `/config <feature> --regenerate`."
3. Source the config loader with the parsed feature name. `--spec`/`--require-spec` are required: in vault mode this substitutes the `{project}` token in `WF_SPEC_STORAGE` (from the spec's `config.yml project:`) — without it the path would still contain the literal `{project}` and the step-4 existence check would resolve wrong. Substitute the parsed feature name for `<feature>` (the `--regenerate`-stripped token from step 2):
   ```bash
   bash -c 'source ~/.claude/scripts/config-loader.sh && wf_load_config --spec <feature> --require-spec && printf "WF_SPEC_STORAGE=%s\nWF_GATE_POOL=%s\nWF_AGENT_POOL=%s\n" "$WF_SPEC_STORAGE" "${WF_GATE_POOL:-}" "$WF_AGENT_POOL"'
   ```
   On non-zero exit: stop — print the loader error and halt. (Note: `WF_GATE_POOL` is empty in vault mode — gate IDs validate against the per-repo union below, not this var.)
4. Verify `$WF_SPEC_STORAGE/<feature>/config.yml` exists. If not: stop — "No config.yml found for '<feature>'. Run `/explore <feature>` to create one."

## ID Re-resolution (runs in both modes before any write)

After reading or receiving a config.yml, validate all referenced IDs against current registries. This step fails closed — never write a config that references unknown IDs.

**Gate ID validation:**
```bash
bash -c '
  source ~/.claude/scripts/config-loader.sh
  wf_load_config --spec <feature> --require-spec
  if [[ "$WF_SPEC_STORAGE_MODE" == "vault" ]]; then
    # No single pool: union the bound repos knowledge-base/gates.yml ids.
    while IFS= read -r p; do
      [[ -f "$p/knowledge-base/gates.yml" ]] && yq ".gates[].id" "$p/knowledge-base/gates.yml" 2>/dev/null
    done <<< "$WF_REPO_PATHS"
  else
    yq ".gates[].id" "$WF_GATE_POOL" 2>/dev/null
  fi
'
```
For each gate ID listed in the config's `gates:` array, check it appears in the (unioned) gate pool output. Collect all missing IDs.

**Agent ID validation:**
For each phase in the config's `agents:` map, for each agent ID listed:
- Resolve the ID using the grammar in `design.md §Backend Design §Schemas §Agent ID grammar and resolution`
- Check the resolved path exists under `$WF_AGENT_POOL`
- Collect all missing IDs

If any gate or agent IDs are missing, stop without writing:
```
ID re-resolution failed. The following IDs no longer exist in their registries:

  Gates (checked against $WF_GATE_POOL):
    - <missing-gate-id>

  Agents (checked against $WF_AGENT_POOL):
    - <missing-agent-id>

Edit the config to remove or replace these IDs, then re-run `/config <feature>`.
```

## Mode: Edit (`/config <feature>`)

1. Read `$WF_SPEC_STORAGE/<feature>/config.yml` and print its current contents in a fenced YAML block:
   ```
   Current config.yml for <feature>:
   ─────────────────────────────────
   <yaml content>
   ─────────────────────────────────
   Paste your edited YAML below, or press Enter to keep it unchanged.
   ```
2. Wait for user input:
   - **Non-empty input:** treat as the edited YAML. Run ID re-resolution on the new content. On failure: print the missing-ID error and stop (file unchanged). On pass: overwrite `$WF_SPEC_STORAGE/<feature>/config.yml` with the new content. Emit `config_approved` event (see Event Emission). Report: "config.yml updated."
   - **Empty input (Enter):** do nothing. Report: "config.yml unchanged."

## Mode: Regenerate (`/config <feature> --regenerate`)

1. Spawn the `Config Inferencer` agent (`engineering-config-inferencer`) using the Agent tool. Pass:
   - The feature name
   - Current `$WF_SPEC_STORAGE/<feature>/config.yml` contents (so the agent can use it as a baseline)
   - Any PRD available at `$WF_SPEC_STORAGE/<feature>/prd.md` (read if it exists; omit if not)
   - Gate registry contents: in repo mode, the full contents of `$WF_GATE_POOL` (if it exists). In vault mode (`WF_SPEC_STORAGE_MODE=vault`, `WF_GATE_POOL` empty), the concatenated contents of each bound repo's `knowledge-base/gates.yml` (iterate `$WF_REPO_PATHS`, label each block by repo name) — never pass an empty pool, the inferencer needs the gate list to choose a ceiling.
   - Listing of all agent files under `$WF_AGENT_POOL`
   - The project's `CLAUDE.md`

   Instruct: "Infer a draft `config.yml` for this spec using the current config as a baseline. Use the Output Contract defined in your agent definition. Return REASONING block and YAML block."

   **On timeout or agent error:** stop — "Config Inferencer unavailable. Try again or use `/config <feature>` to edit manually."

2. Compute a diff between the current config.yml and the agent's proposed YAML:
   ```bash
   diff <(cat "$WF_SPEC_STORAGE/<feature>/config.yml") <(echo "<agent-yaml>")
   ```
   If there is no diff, stop — "Inferencer produced no changes. config.yml is already up to date."

3. Present the approval summary:
   ```
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
     Config Regeneration — <feature>
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
     <REASONING block from agent — trimmed to ≤ 10 lines>

     Diff (current → proposed):
   <diff output>
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ```
   Then invoke `AskUserQuestion` (per `~/.claude/scripts/ask-user-protocol.md`) — "Approve regenerated config?" options: `Approve and overwrite`, `Reject and keep current`.

4. **Approve:** run ID re-resolution on the proposed YAML. On failure: print the missing-ID error and stop (file unchanged). On pass: overwrite `$WF_SPEC_STORAGE/<feature>/config.yml`. Emit `config_approved` event. Report: "config.yml overwritten with regenerated config."

5. **Reject:** do nothing. Report: "config.yml unchanged."

## Event Emission

After any successful write:
```bash
$HOME/.claude/scripts/monitor.sh log_event "<feature>" "config_approved" "" \
  "$(printf '{"config_path":"%s","mode":"%s"}' "$WF_SPEC_STORAGE/<feature>/config.yml" "<edit|regenerate>")"
```
If monitor.sh is not found or exits non-zero, log a warning and continue — event emission is best-effort and must not block.
