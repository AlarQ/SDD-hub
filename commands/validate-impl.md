Run the spec-completion audit (FR-15, ADR-008). Reuses the existing **Odium** agent (`agents/odium.md`) unchanged — all spec-specific context flows through the wrapper prompt built here.

Feature name: $ARGUMENTS

> Terminology: see `~/.claude/scripts/workflow-glossary.md` for canonical definitions of **ceiling**, **effective-set**, **spec-union** (reserved for Step 2 here). Do not use bare "union" for ceiling/effective-set.

## Prerequisites

1. Read and follow `$WF_GENERAL_KB/_rules.md`.
2. Verify every task under `specs/$ARGUMENTS/tasks/` has `status: done`. If not, refuse with a list of non-done tasks.
3. Refuse with `--reaudit` guidance if the most-recent of `{spec_audit_done, spec_reaudit_requested}` events in `specs/$ARGUMENTS/.monitor.jsonl` is `spec_audit_done` and the user did not pass `--reaudit`.
4. If the user passed `--reaudit`: append a `spec_reaudit_requested` event (append-only — never truncate or rewrite prior `spec_audit_done` events; the audit trail must remain intact) before proceeding:

   ```bash
   source ~/.claude/scripts/monitor.sh
   log_event "$ARGUMENTS" spec_reaudit_requested "" \
     "$(printf '{"requested_ts":"%s","reason":"%s"}' "$(get_timestamp)" "user --reaudit")"
   ```

## Step 0 — Load Spec Config

```bash
bash -c 'source ~/.claude/scripts/config-loader.sh && wf_load_config --spec '"$ARGUMENTS"' && \
  printf "WF_SPEC_GATES=%s\nWF_VALIDATE_SCOPE=%s\nWF_GATE_POOL=%s\n" \
  "$WF_SPEC_GATES" "$WF_VALIDATE_SCOPE" "${WF_GATE_POOL:-}"'
```

> See `~/.claude/scripts/step0-load-config.md` for canonical invocation and remediation. This step uses: `WF_SPEC_GATES`, `WF_VALIDATE_SCOPE`, `WF_GATE_POOL`, `WF_SPEC_TIER`.

### Tier early-exit

If `WF_SPEC_TIER == small`, skip the entire Odium audit:

```bash
bash ~/.claude/scripts/monitor.sh log_event "$ARGUMENTS" validate_impl_skipped "" \
  '{"reason":"tier_small"}'
```

Print: "Spec tier is `small` — `/validate-impl` skipped. Mark spec `done` directly and run `/ship`." Exit 0.

## Step 1 — Emit `spec_audit_start`

```bash
source ~/.claude/scripts/validate-impl.sh
wf_vi_emit_start "$ARGUMENTS"
```

## Step 2 — Spec-Union Gate Execution (only if `validate_scope ∈ {per-spec, both}`)

If `WF_VALIDATE_SCOPE` is `per-task`: skip this step.

Otherwise execute the **spec-union** (union of every task's effective-set; see CLAUDE.md glossary) against the cumulative diff (first task branch-point → HEAD) via `wf_vi_run_union_gates` (T016):

```bash
spec_dir="$WF_SPEC_STORAGE/$ARGUMENTS"
gate_log="/tmp/spec-audit-gates-$$.log"
gate_json="$(wf_vi_run_union_gates "$ARGUMENTS" "$spec_dir" "$gate_log")"
# JSON shape: {"verdict":"reopen|"","gate_failures":[...],"log_path":"…"}
forced_verdict="$(printf '%s' "$gate_json" | jq -r '.verdict')"
extra_evidence=""
[[ -n "$forced_verdict" || -s "$gate_log" ]] && extra_evidence="$gate_log"
```

Helper semantics (see `scripts/validate-impl.sh`, which delegates ceiling/effective-set/spec-union math to `scripts/gate-ceiling.sh` — same canonical helpers used by `/validate`):
1. Spec-union = `wf_compute_union_set <spec_dir>` from `gate-ceiling.sh`: union of every task's effective-set (each task's language tags ∩ ceiling `WF_SPEC_GATES`), plus gates with `applies_to: [any]`. Sorted, unique.
2. Each gate runs **once** against the cumulative diff range (deterministic order from `sort -u`).
3. **Empty spec-union on a code-bearing spec** → helper returns rc 3 (fail-closed per ADR-003); abort `/validate-impl` before spawning Odium.
4. **Blocking gate non-zero exit** → helper stdout = `reopen`. Captured log is passed to `wf_vi_build_prompt` as `extra_evidence`; Odium is **still** spawned, but its verdict is overridden to `reopen` in Step 4.
5. **Non-blocking gate failure** → recorded in `gate_log` but does not force `reopen`.

### Multi-repo handling (vault mode)

When `WF_REPO_NAMES` is non-empty, Steps 2–3 fan out **per repo** instead of using a single `merge-base main feat/$ARGUMENTS..HEAD` range:

- Spec-union (Step 2) is computed once for the spec, then each gate runs **once per repo** that has at least one task assigned (filter tasks by `repo:` field). Diff range per repo: `git -C "$(wf_repo_path <name>)" diff $(git -C "$(wf_repo_path <name>)" merge-base main feat/$ARGUMENTS)..HEAD`. Gate output is labeled with the repo name in `gate_log`.
- The Odium prompt (Step 3) embeds **per-repo diff sections**, each labeled `### Repo: <name> (<path>)` followed by that repo's diff. Tasks are grouped by repo in the task list. Ground-rule resolution preserves `repo:<name>:` prefixes.
- A gate failure in any repo forces `verdict=reopen` (same as single-repo case). The `extra_evidence` log includes which repo failed.

## Step 3 — Build Odium Wrapper Prompt

```bash
spec_dir="$(bash -c 'source ~/.claude/scripts/config-loader.sh && wf_load_config --spec '"$ARGUMENTS"' && echo "$WF_SPEC_STORAGE/'"$ARGUMENTS"'"')"
prompt_file="$(mktemp)"
wf_vi_build_prompt "$ARGUMENTS" "$spec_dir" "${extra_evidence:-}" > "$prompt_file"
```

The wrapper prompt contains:
- Parsed FR allowlist from `spec.md` (every `### FR-N:` heading).
- `prd.md` IN/OUT scope.
- Task list with paths.
- Report paths under `reports/`.
- Git diff range (`merge-base main feat/$ARGUMENTS..HEAD`).
- Failing-gate output, if step 2 captured any.
- Required output: YAML frontmatter (`feature`, `timestamp`, `scope`, `verdict`) + FR × Status matrix + orphan-code section + over-engineering flags.

## Step 4 — Spawn Odium via Agent Tool

Spawn the Odium agent (`subagent_type: odium`) with the prompt file's content. **Do not edit `agents/odium.md`.** Capture the agent's full Markdown output into a temp file `/tmp/spec-audit-body-$$.md`.

Parse `verdict` from the agent's frontmatter. If step 2 set `forced_verdict=reopen`, override agent verdict to `reopen`.

Reject any FR id in the agent output not in the allowlist (fail closed; print unknown ids and stop).

## Step 5 — Persist Report

```bash
report_path="$(wf_vi_write_report "$ARGUMENTS" "$spec_dir" "$verdict" /tmp/spec-audit-body-$$.md)"
wf_vi_emit_done "$ARGUMENTS" "$verdict" "$report_path"
```

## Step 6 — Verdict Routing

- `verdict: complete` → `wf_vi_set_spec_shipped "$spec_dir"` then `wf_vi_emit_complete "$ARGUMENTS"`.
- `verdict: reopen` → `wf_vi_emit_reopen "$ARGUMENTS"`. Hand the report path to `/review-findings $ARGUMENTS`. Each `missing` / `partial` FR row in the report becomes one review unit; **Accept** invokes `task-manager.sh create-followup "$ARGUMENTS" <FR-id> "<description>"`, which fail-closes on unknown FR ids and inherits ground_rules from `spec.md`. After the follow-up tasks reach `done`, the T015 detector re-fires `spec_last_task_done` (because the most-recent guard event is `spec_reaudit_requested`, not `spec_audit_done`) and `/validate-impl` runs again — cycle converges when verdict = `complete`.

## Notes

- This command is idempotent: it does not advance task state. Re-running on a clean spec is a no-op except for new monitor events.
- T016 owns the spec-union gate executor helper referenced in Step 2; until then, `validate_scope=per-spec/both` callers should expect a placeholder log.
- Odium's identity stays generic (ADR-008) — wrapper prompt is the only specialization surface.
