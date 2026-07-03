---
name: promote-tier
description: /promote-tier — Re-run /propose at a higher tier
disable-model-invocation: true
args:
  - name: feature
    description: Feature name (used as $ARGUMENTS in body)
    required: true
---
# /promote-tier — Re-run /propose at a higher tier

Triggered when `/implement` step 0 detects a tier-ceiling breach and the user picks **abort**. Promotes the spec to the next tier (`small → medium`, `medium → large`) and re-runs the propose pipeline for **remaining (non-`done`) scope only** — implemented tasks stay implemented.

**Argument:** `$ARGUMENTS` is `<feature>`.

## Step 0 — Load config + verify breach

```bash
source ~/.claude/scripts/config-loader.sh
wf_load_config --spec "$ARGUMENTS" || exit $?
```

Run `bash ~/.claude/scripts/tier-check.sh "$ARGUMENTS"`. Exit code 0 → no breach detected; refuse to promote without justification (use `AskUserQuestion` to confirm forced promotion).

## Step 1 — Pick target tier

```
small  → medium
medium → large
large  → REFUSE (no higher tier; redesign feature instead)
```

## Step 2 — Snapshot done tasks

Read `specs/$ARGUMENTS/tasks/*.md` frontmatter. Bucket:
- `status: done` or `implemented` → **preserved** (skip re-decomposition)
- everything else → **scope to re-propose**

Write `specs/$ARGUMENTS/.promote-snapshot.json` with `{preserved: [...], reproposed: [...], from_tier, to_tier, ts}`.

## Step 3 — Update config.yml

Before editing, render the planned diff:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Tier Promotion — <feature>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  tier:         <from>  →  <to>
  tier_ceiling: <current>  →  (dropped)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Then **MUST** invoke `AskUserQuestion` (per `~/.claude/scripts/ask-user-protocol.md`):
- **question:** `Approve tier promotion <from> → <to> and config.yml edit?`
- **options:** `Approve and overwrite` — write the change | `Cancel promotion` — abort, leave file unchanged.

**Fail-closed:** if `AskUserQuestion` cannot be invoked or returns no selection, treat as cancel — do NOT write.

On `Approve`: edit `specs/$ARGUMENTS/config.yml`:
- `tier:` → new tier
- Drop `tier_ceiling:` if present (let `.workflow.yml` defaults apply)

Then emit:
```bash
$HOME/.claude/scripts/monitor.sh log_event "$ARGUMENTS" "config_approved" "" \
  "$(printf '{"config_path":"%s","mode":"promote-tier"}' "specs/$ARGUMENTS/config.yml")"
```

On `Cancel` (or missing selection): print `Promotion cancelled. config.yml unchanged.` and exit non-zero so the `/implement` abort path knows.

## Step 4 — Re-run /propose deltas

Invoke the relevant chunks of `/propose` (do NOT run the whole command — that would re-decompose preserved tasks). Specifically:

- **small → medium**: write `spec.md` (was skipped at small). Re-decompose only the unfinished scope into tasks. Skip `design.md`, `test-strategy.md`.
- **medium → large**: write `design.md` (spawn `Software Architect`) and `test-strategy.md` (spawn `Test Strategist`). Re-decompose unfinished scope.

Preserved tasks: leave files untouched.

## Step 5 — Emit event + next step

```bash
bash ~/.claude/scripts/monitor.sh log_event "$ARGUMENTS" tier_promoted "" \
  "$(printf '{"from":"%s","to":"%s","preserved":%d,"reproposed":%d}' \
    "$from" "$to" "$pres_n" "$rep_n")"
```

Print: `Promoted $ARGUMENTS: $from → $to. Run \`/implement $ARGUMENTS\` next.`
