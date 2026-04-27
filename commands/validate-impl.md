Run the spec-completion audit (FR-15, ADR-008). Reuses the existing **Karen** agent (`agents/karen.md`) unchanged — all spec-specific context flows through the wrapper prompt built here.

Feature name: $ARGUMENTS

## Prerequisites

1. Read and follow `~/.claude/knowledge-base-rules.md`.
2. Verify every task under `specs/$ARGUMENTS/tasks/` has `status: done`. If not, refuse with a list of non-done tasks.
3. Refuse with `--reaudit` guidance if a `spec_audit_done` event already exists in `specs/$ARGUMENTS/.monitor.jsonl` and the user did not pass `--reaudit`.

## Step 0 — Load Spec Config

```bash
bash -c 'source ~/.claude/scripts/config-loader.sh && wf_load_config --spec '"$ARGUMENTS"' && \
  printf "WF_SPEC_GATES=%s\nWF_VALIDATE_SCOPE=%s\nWF_GATE_POOL=%s\n" \
  "$WF_SPEC_GATES" "$WF_VALIDATE_SCOPE" "${WF_GATE_POOL:-}"'
```

Non-zero exit:
- exit 4 → "Missing spec config for `$ARGUMENTS`. Expected: `specs/$ARGUMENTS/config.yml` — create it via `/explore $ARGUMENTS`."
- any other → halt and print loader error.

Record `WF_SPEC_GATES`, `WF_VALIDATE_SCOPE`, `WF_GATE_POOL`.

## Step 1 — Emit `spec_audit_start`

```bash
source ~/.claude/scripts/validate-impl.sh
wf_vi_emit_start "$ARGUMENTS"
```

## Step 2 — Union Gate Execution (only if `validate_scope ∈ {per-spec, both}`)

If `WF_VALIDATE_SCOPE` is `per-task`: skip this step.

Otherwise execute the union of spec-eligible gates against the cumulative diff (first task branch-point → HEAD):

1. Compute language tags by unioning every task's `ground_rules` language tags (T016 helper once available).
2. Effective union = `WF_SPEC_GATES` ∩ gates whose `applies_to` matches any of those tags or `any`.
3. Run each gate's `command` from `gates.yml`. Capture stdout/stderr to `/tmp/spec-audit-gates-$$.log`.
4. **Blocking gate failure** → set `forced_verdict=reopen` and pass the captured log to the wrapper prompt as `extra_evidence`. Karen is **still** spawned.
5. **Non-blocking gate failure** → record in audit body but do not force `reopen`.

## Step 3 — Build Karen Wrapper Prompt

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

## Step 4 — Spawn Karen via Agent Tool

Spawn the Karen agent (`subagent_type: karen`) with the prompt file's content. **Do not edit `agents/karen.md`.** Capture the agent's full Markdown output into a temp file `/tmp/spec-audit-body-$$.md`.

Parse `verdict` from the agent's frontmatter. If step 2 set `forced_verdict=reopen`, override agent verdict to `reopen`.

Reject any FR id in the agent output not in the allowlist (fail closed; print unknown ids and stop).

## Step 5 — Persist Report

```bash
report_path="$(wf_vi_write_report "$ARGUMENTS" "$spec_dir" "$verdict" /tmp/spec-audit-body-$$.md)"
wf_vi_emit_done "$ARGUMENTS" "$verdict" "$report_path"
```

## Step 6 — Verdict Routing

- `verdict: complete` → `wf_vi_set_spec_shipped "$spec_dir"` then `wf_vi_emit_complete "$ARGUMENTS"`.
- `verdict: reopen` → `wf_vi_emit_reopen "$ARGUMENTS"`. Hand the report path to `/review-findings $ARGUMENTS` for accept/reject of partial/missing FRs (T017 owns the auto-task creation).

## Notes

- This command is idempotent: it does not advance task state. Re-running on a clean spec is a no-op except for new monitor events.
- T016 owns the union gate executor helper referenced in Step 2; until then, `validate_scope=per-spec/both` callers should expect a placeholder log.
- Karen's identity stays generic (ADR-008) — wrapper prompt is the only specialization surface.
