# Plan: Headless Pi Runtime for `improve-architecture-pipeline.sh`

Status: **PLAN** (no code changed). Target script:
`scripts/improve-architecture-pipeline.sh` (+ required coordinated changes in its
stage-2 delegate `scripts/address-reports.sh`).

Parent context (Bondsmith `future-proof-oss/CLAUDE.md`): two divergent runtime
targets — **Claude Code** (mandatory, native parallel subagents) and **Pi**
(personal runtime, no built-in subagents, inline dispatch). This plan makes the
architecture pipeline runnable on **both**, defaulting to Claude (zero behaviour
change) and adding an opt-in Pi headless path.

Pi version in scope: **0.80.7** (`/opt/homebrew/bin/pi`). Pi docs:
`/opt/homebrew/lib/node_modules/@earendil-works/pi-coding-agent/docs/`.

---

## 1. Goal & scope

**Goal.** Let `improve-architecture-pipeline.sh` run end-to-end against either
runtime:

- Stage 1 (find) — headless scan that writes `reports/*.md`.
- Gate — runtime-neutral (pure bash tally; unchanged).
- Stage 2 (address) — hand off to `address-reports.sh`, whose triage judge and
  per-finding workers must also run headless on the chosen runtime.

**Non-goals.** Rewriting the report format, the gate, the worktree scheduler
spine, or the triage clustering logic — all stay runtime-neutral. We only swap
the **LLM-driver invocation** (scan, judge, worker) and the **usage-extraction
parser** per runtime.

**Why the scheduler is in scope.** The pipeline owns Stage 1 directly but
delegates Stage 2 to `address-reports.sh`, which itself shells out to `claude`
in two places (triage judge + worker spawn). A Pi pipeline that stops at the
handoff is useless, so the scheduler's two Claude call-sites must gain a Pi
branch too. The pipeline is the **entry point that selects the runtime** and
propagates it to the scheduler via env.

---

## 2. Current Claude coupling (the call sites to branch)

| # | File | Function | Current Claude invocation |
|---|------|----------|---------------------------|
| 1 | `improve-architecture-pipeline.sh` | `run_scan` | `claude -p "$STAGE1_PROMPT" --model "$ARCH_FIND_MODEL" --permission-mode bypassPermissions --output-format stream-json --verbose` |
| 2 | `address-reports.sh` | `run_triage_judge` | `printf '%s' "$payload" \| claude -p "$TRIAGE_PROMPT" --model … --permission-mode bypassPermissions --output-format json` → unwrap `.result` |
| 3 | `address-reports.sh` | `run_worker` | `ADDRESS_FINDINGS_AUTO=1 claude -p "/address-findings … --auto" --model … --permission-mode bypassPermissions --output-format stream-json --verbose` (in a git worktree) |
| — | both | `extract_usage` (pipeline) + `extract_pr_num` (scheduler) | parse Claude `stream-json` `{"type":"result",…}` line; grep `github.com/.../pull/<N>` |

Claude `stream-json` result line parsed today:
`{"type":"result","usage":{"input_tokens","output_tokens","cache_read_input_tokens","cache_creation_input_tokens"},"total_cost_usd":…}`.

---

## 3. Obligatory skills (Pi availability & compatibility) — answers the second ask

The pipeline has **three transitive skill dependencies**. None is a "Pi-native"
skill; all are Claude-authored skills. Pi can *load* some automatically, but
**none is Pi-compatible as-is** because they assume Claude-only affordances
(parallel subagents, `ExitPlanMode`, `AskUserQuestion`, the `Skill` tool).

| Skill | Used by | Lives at | Pi auto-discovers? | Pi-compatible as-is? | Obligatory? |
|-------|---------|----------|--------------------|----------------------|-------------|
| **`improve-codebase-architecture`** | Stage-1 scan (`STAGE1_PROMPT` says "Run the /improve-codebase-architecture analysis") | `~/.agents/skills/improve-codebase-architecture/` | **Yes** — `~/.agents/skills/` is a Pi global skill location | **Partial** — Step 1 says *"use the Agent tool with `subagent_type=Explore`"*; Pi has no subagents → must explore inline (read/grep/find/ls). Scan-only/headless override already present in `STAGE1_PROMPT`. | Yes (Stage 1) |
| **`address-findings`** | Stage-2 worker (scheduler sends `/address-findings … --auto`) | `~/.claude/skills/address-findings/` | **No** — `~/.claude/skills/` is **not** a Pi default location (only `~/.pi/agent/skills/` and `~/.agents/skills/` are). Must be wired via pi settings `"skills":["~/.claude/skills"]` **or** `--skill ~/.claude/skills/address-findings`. | **No** — Step 4 spawns 3 parallel subagents (`Code Reviewer`, `Software Architect`, `odium`); Step 2 uses `ExitPlanMode`; Step 5b interactive uses `AskUserQuestion`; Step 7 invokes `/quick-ship` *via the Skill tool*. Auto-mode removes ExitPlanMode/AskUserQuestion/report-writes, but Step 4 (3 parallel reviewers) and Step 7 (Skill-tool `/quick-ship`) remain Claude-only. | Yes (Stage 2) |
| **`quick-ship`** | `address-findings` Step 7 (ship the PR) | `~/.claude/skills/quick-ship/` | **No** (same reason); also has `disable-model-invocation: true` → hidden from system prompt, requires `/skill:quick-ship` with `enableSkillCommands:true` to invoke. | **Partial** — it is a git/gh procedure, but it gates sensitive files via `AskUserQuestion` (blocks headless) and assumes the Claude Skill tool. | Yes on the **Claude** path; **replaced by inline ship** on the Pi path (see §7) |

**Non-skill Claude affordances the pipeline also leans on** (not "skills in Pi",
but obligatory to replace for the Pi path):

- Reviewer subagent types `Code Reviewer` / `Software Architect` / `odium`
  (`address-findings` Step 4) — Claude subagents; **Pi has no subagents**. (Pi has
  a `code-review` skill in `~/.agents/skills/`, auto-discovered — a *different*
  artifact, not a drop-in for the 3-agent parallel review.) → Pi path uses
  **inline review** (see §7).
- `ExitPlanMode`, `AskUserQuestion`, the `Skill` tool — Claude-only. Avoided on
  the Pi path via prompt overrides + `--exclude-tools ask_question`.

**Conclusion for the user's question.** No skill is *defined in Pi* that the
scripts obligatorily require. The obligatory skills are the three Claude skills
above. Pi auto-loads only `improve-codebase-architecture`; the other two must be
**wired in** (`--skill` / settings) **and** all three must be **adapted** for
Pi's no-subagent model. The adaptation is done via **Pi-specific prompt
overrides** (Stage 1 + worker), **not** by editing the shared skills — so the
Claude path is untouched.

**Optional Pi-native leverage** (not obligatory, future enhancement):
- Pi auto-discovers `code-review` and `tdd` from `~/.agents/skills/`. The inline
  review step (§7) could drive the `code-review` skill; the test-first implement
  step could lean on `tdd`. Out of scope for the MVP.

---

## 4. Design: runtime selector & env contract

New env var **`WF_RUNTIME`** (`claude` | `pi`), default **`claude`**
(preserves today's behaviour exactly). Add `--runtime <claude|pi>` flag to the
pipeline. The pipeline **exports** `WF_RUNTIME` so the scheduler subprocess
inherits it (no scheduler flag needed; scheduler reads `$WF_RUNTIME`).

Per-runtime model env (all optional; fall back to the runtime's configured
default):

| Role | Claude env (existing) | Pi env (new) | Pi default if unset |
|------|----------------------|--------------|---------------------|
| Stage-1 scan | `ARCH_FIND_MODEL` | `PI_SCAN_MODEL` | pi default model (omit `--model`) |
| Triage judge | `CLAUDE_MODEL` | `PI_JUDGE_MODEL` | pi default model |
| Stage-2 worker | `CLAUDE_MODEL` | `PI_WORKER_MODEL` | pi default model |

`MAX_PARALLEL`, `MAX_FINDINGS`, `NO_COLOR`, `--limit/--resume/--rescan/--cleanup`
are runtime-neutral — unchanged.

Pi settings currently: `defaultProvider=openrouter`, `defaultModel=z-ai/glm-5.2`.
The plan does **not** change global pi settings; all wiring is per-invocation
flags (deterministic, no host mutation).

### Claude → Pi flag parity

| Concern | Claude | Pi |
|---------|--------|-----|
| Headless run | `claude -p "PROMPT"` | `pi -p "PROMPT"` |
| Model | `--model claude-opus-4-8` | `--model anthropic/claude-opus-…` (or omit → pi default) |
| "Bypass permissions" | `--permission-mode bypassPermissions` | **No equivalent** — Pi runs tools by default (no per-call prompts; by design). Add `--approve` to trust project resources; add `--exclude-tools ask_question` to prevent any prompt tool from blocking headless runs. |
| Streaming events | `--output-format stream-json --verbose` | `--mode json` (events stream by default; `--verbose` is startup-logging only, not needed) |
| Single-shot JSON answer (judge) | `--output-format json` → unwrap `.result` | `pi -p` **text mode** → stdout is the answer directly (no `.result` unwrap) |
| Piped stdin → prompt | `claude -p` reads stdin | `pi -p` also reads piped stdin and merges into the initial prompt (confirmed in `docs/usage.md`) |
| Skill slash command | `/address-findings` | `/skill:address-findings` (needs `enableSkillCommands:true`) **or** `--skill <path>` + plain prompt (recommended — see §7) |
| Context files | always loaded | `-nc`/`--no-context-files` to skip `AGENTS.md`/`CLAUDE.md` (use for the judge; keep for workers) |
| Session persistence | (claude manages) | `--no-session` for ephemeral judge/scan; workers may use `--session-dir` if a log is wanted (the scheduler already redirects stdout→session log, so `--no-session` is fine) |

---

## 5. Stage-1 changes (`improve-architecture-pipeline.sh`)

### 5.1 `validate_env`

Add a `WF_RUNTIME` validation block. When `WF_RUNTIME=pi`:

- `command -v pi >/dev/null 2>&1 || die "pi CLI not found in PATH"` (keep the
  `claude` check only on the Claude branch).
- Keep `git`, `gh` checks (both runtimes need them — `gh` for PRs).
- Keep scheduler discovery unchanged.

```bash
case "$WF_RUNTIME" in
  claude) command -v claude >/dev/null 2>&1 || die "claude CLI not found in PATH" ;;
  pi)     command -v pi     >/dev/null 2>&1 || die "pi CLI not found in PATH" ;;
  *)      die "WF_RUNTIME must be claude or pi (got: $WF_RUNTIME)" ;;
esac
export WF_RUNTIME
```

### 5.2 `run_scan` — Pi branch

Branch on `$WF_RUNTIME`. The Claude branch is unchanged. The Pi branch:

```bash
run_scan_pi() {
  ensure_reports_gitignored
  # … same --rescan / existing-reports skip logic as run_scan …

  local -a pi_flags=( -p --mode json --approve --exclude-tools ask_question )
  # Load the arch skill so its vocabulary (LANGUAGE.md, deletion test) is in
  # context; the prompt overrides its subagent step for Pi.
  pi_flags+=( --skill "$HOME/.agents/skills/improve-codebase-architecture" )
  [[ -n "${PI_SCAN_MODEL:-}" ]] && pi_flags+=( --model "$PI_SCAN_MODEL" )

  log "SCAN start runtime=pi repo=$REPO_ROOT"
  local rc=0
  ( cd "$REPO_ROOT" && pi "${pi_flags[@]}" "$STAGE1_PROMPT_PI" ) >>"$LOG" 2>&1 || rc=$?
  [[ $rc -eq 0 ]] || die "stage 1 scan failed (pi rc=$rc; see $LOG)"
  # … same report tally + USAGE line as run_scan, but via extract_usage_pi "$LOG" …
}
```

Key points:
- `--approve` trusts the (cloned) target repo's project resources; `--exclude-tools ask_question`
  guarantees no prompt blocks the headless run. Tools run by default (Pi has no
  permission popups) — this is the `bypassPermissions` parity.
- `--mode json` so `extract_usage` can parse usage (see §8). The scan's stdout
  (json events) is appended to `$LOG`, same as Claude's `stream-json`.
- `--skill …/improve-codebase-architecture` puts the skill description in context;
  the **prompt** is the source of truth and overrides the skill's subagent step.

### 5.3 `STAGE1_PROMPT_PI`

Adapt the existing `STAGE1_PROMPT` for Pi's no-subagent model. Differences from
the Claude `STAGE1_PROMPT`:

- Do **not** say "Run the /improve-codebase-architecture analysis" (Pi skill
  commands are `/skill:…` and we load the skill via `--skill` anyway). Instead:
  "Follow the `improve-codebase-architecture` skill's vocabulary and method
  (Module/Interface/Depth/Seam/Adapter, deletion test — see its LANGUAGE.md)."
- Replace Step 1's *"use the Agent tool with subagent_type=Explore"* with
  **inline exploration**: "Explore the repo inline using `read`, `grep`, `find`,
  and `ls` (Pi has no subagents). Walk the codebase yourself; note where you
  experience friction."
- Keep the identical **scan-only / headless** overrides (steps 1–2 only; skip
  candidate-presentation and the grilling loop; never `AskUserQuestion`/wait;
  never `ExitPlanMode`).
- Keep the **identical output contract** (reports/`architecture-<unit>.md`,
  header, one H2 per finding, `**Severity**`/`**Files**`/`**Problem**`/`**Fix**`,
  concrete `file:line`, unique slugs, no frontmatter, no source edits, final
  one-line summary). This contract is what the gate + scheduler parse — it must
  not drift between runtimes.

---

## 6. Stage-2 handoff + required `address-reports.sh` changes

The pipeline's `run_address` already just shells out to the scheduler with
flags + report list — **no change needed** there beyond exporting `WF_RUNTIME`
(done in `validate_env`). The scheduler reads `$WF_RUNTIME` and branches at its
two Claude call-sites.

### 6.1 `run_triage_judge` — Pi branch

The judge is a pure-LLM classifier (no tools, no files, no skills). Use **Pi
text mode** — stdout is the answer, no `.result` unwrap:

```bash
run_triage_judge() {
  local payload="$1" verdict inner rc
  [[ -n "${TRIAGE_VERDICT_FILE:-}" ]] && { cat "$TRIAGE_VERDICT_FILE"; return 0; }
  set +e
  if [[ "${WF_RUNTIME:-claude}" == "pi" ]]; then
    local -a jf=( -p --no-tools --no-skills --no-extensions --no-context-files --exclude-tools ask_question )
    [[ -n "${PI_JUDGE_MODEL:-}" ]] && jf+=( --model "$PI_JUDGE_MODEL" )
    verdict="$(printf '%s' "$payload" | pi "${jf[@]}" "$TRIAGE_PROMPT" 2>>"$LOG")"
  else
    verdict="$(printf '%s' "$payload" | "${TIMEOUT_PREFIX[@]+"${TIMEOUT_PREFIX[@]}"}" \
      claude -p "$TRIAGE_PROMPT" --model "${CLAUDE_MODEL:-claude-sonnet-4-6}" \
      --permission-mode bypassPermissions --output-format json 2>>"$LOG")"
  fi
  rc=$?
  set -e
  (( rc == 124 )) && die "ABORT triage judge timed out …"
  (( rc == 0 ))   || die "ABORT triage judge call failed (rc=$rc) …"
  if [[ "${WF_RUNTIME:-claude}" == "pi" ]]; then
    inner="$verdict"                       # text mode = the answer itself
  else
    inner="$(jq -r '.result // empty' <<<"$verdict" 2>/dev/null || true)"
    [[ -n "$inner" ]] || inner="$verdict"
  fi
  printf '%s' "$inner" | sed -E '/^[[:space:]]*```/d'
}
```

Notes:
- `--no-tools --no-skills --no-extensions --no-context-files` makes the judge
  fast, deterministic, and free of repo/skill bias. `--exclude-tools ask_question`
  is belt-and-suspenders (already `--no-tools`).
- **No `--mode json`** for the judge — text mode gives the bare answer, which is
  exactly what the `{"units":[…]}` parser wants. (`--mode json` would force us
  to reassemble text from `message_update` deltas — unnecessary.)
- The `TRIAGE_PROMPT` text is runtime-neutral; no change.

### 6.2 `run_worker` — Pi branch

The Claude worker sends `/address-findings … --auto` and relies on the skill's
subagent review + Skill-tool `/quick-ship`. **Pi cannot do either.** So the Pi
worker uses a **Pi-adapted worker prompt** (`WORKER_PROMPT_PI`) that re-specifies
the `address-findings` flow for Pi's inline model, and loads the skill via
`--skill` only as vocabulary reference.

```bash
run_worker() {
  # … unchanged: idx/slug/heading/lineno, report_abs, worktree add, fargs …
  set +e
  if [[ "${WF_RUNTIME:-claude}" == "pi" ]]; then
    local -a wf=( -p --mode json --approve --exclude-tools ask_question )
    wf+=( --skill "$HOME/.claude/skills/address-findings" )   # vocabulary only
    [[ -n "${PI_WORKER_MODEL:-}" ]] && wf+=( --model "$PI_WORKER_MODEL" )
    ( cd "$wt" && ADDRESS_FINDINGS_AUTO=1 pi "${wf[@]}" "$WORKER_PROMPT_PI" ) >>"$session_log" 2>&1
  else
    ( cd "$wt" && ADDRESS_FINDINGS_AUTO=1 claude -p "/address-findings $report_abs ${fargs[*]} --auto" \
        --model "${CLAUDE_MODEL:-claude-sonnet-4-6}" \
        --permission-mode bypassPermissions \
        --output-format stream-json --verbose ) >>"$session_log" 2>&1
  fi
  rc=$?
  set -e
  # … unchanged: FAILED / WONTFIX sentinel / extract_pr_num …
}
```

`extract_pr_num` (grep `github.com/.../pull/<N>`) is **runtime-agnostic** — it
greps the session log text, so it works for Pi as long as the PR URL lands in the
log (it does: the inline-ship step runs `gh pr create`, whose output is captured
in `--mode json` `tool_execution_end` events). **No change.**

---

## 7. `WORKER_PROMPT_PI` — the key adaptation

A new constant in `address-reports.sh`, parallel to `STAGE1_PROMPT`. It is the
Pi-flavoured restatement of `address-findings` for headless, no-subagent
execution. It must keep the **same observable contract** the scheduler depends on
(one PR per unit via `extract_pr_num`, `WONTFIX` sentinel on won't-fix, never
touch the report file, stop after one unit) while replacing the Claude-only
affordances:

| `address-findings` step | Claude behaviour | Pi adaptation in `WORKER_PROMPT_PI` |
|--------------------------|-------------------|--------------------------------------|
| 1. Locate unit members | read report, match `--finding` slugs | **Same** (inline `read`/`grep`). |
| 2. Plan + `ExitPlanMode` | auto-mode already prints plan, skips ExitPlanMode | **Same** — print plan to stdout, proceed. (Pi has no ExitPlanMode regardless.) |
| 3. Implement (test-first for behavior-changing; lean on suite for structure-only) | red/green/refactor | **Same** (inline `bash`/`edit`/`write`; lean on Pi `tdd` skill optionally). Verification resolution order (`.workflow.yml` gate → Rust/TS fallback → plan) unchanged. |
| 4. Review — 3 parallel subagents (`Code Reviewer`/`Software Architect`/`odium`) | single message, 3 Agent calls | **Inline self-review**: one consolidated critique of `git diff` against the unit's findings (correctness/security/scope/test-toothiness), under ~200 words. (Pi has no subagents — per Bondsmith "inline dispatch".) A richer multi-pi-process review is a **future enhancement**, out of MVP scope. |
| 5. Address feedback | apply agreed items | **Same** (apply clearly-correct correctness/security items in auto mode). |
| 5b. Won't-fix | write `$wt/WONTFIX` (auto) | **Same** — `printf '%s\n' '<rationale>' > WONTFIX` (literal command, not prose). The scheduler already consumes it. |
| 6. Mark RESOLVED + commit report | auto-mode skips entirely (scheduler owns it) | **Same** — do **not** touch the report file; the scheduler writes RESOLVED markers. |
| 7. Ship via `/quick-ship` (Skill tool) | invoke `/quick-ship` | **Inline ship** (do NOT invoke a skill): stage, commit (conventional, no Co-Authored-By), `git push -u origin <branch>`, `gh pr create --base <default> --title … --body <pr-body-convention.md>`, print the PR URL. This avoids both the `Skill`-tool gap and `quick-ship`'s `AskUserQuestion` sensitive-file gate (which would block headless). |
| 8. Stop | terminate | **Same.** |

The prompt must restate the **auto-mode hard rules** verbatim (never edit the
report; one unit per invocation; don't re-invoke). These are load-bearing for
scheduler/worker concurrency safety and are runtime-independent.

Why inline ship (not `/skill:quick-ship`): `quick-ship` has
`disable-model-invocation: true` (won't auto-load), requires
`enableSkillCommands:true` to invoke as `/skill:quick-ship`, and gates sensitive
files via `AskUserQuestion` — three headless blockers. Inlining the git/gh steps
(already documented in `scripts/ship-procedure.md` and `pr-body-convention.md`)
sidesteps all three and keeps the Pi path self-contained. The Claude path keeps
using `/quick-ship` unchanged.

---

## 8. Usage / cost extraction parity (empirically confirmed)

The pipeline's `extract_usage` and `report_usage`, and the scheduler's per-worker
accounting, parse session logs. Today they grep Claude's
`{"type":"result","usage":{…},"total_cost_usd":…}`. Confirmed Pi `--mode json`
emits the usage on every `turn_end` (and `agent_end`) event:

```json
{"type":"turn_end","message":{"role":"assistant",…,
  "usage":{"input":370,"output":14,"cacheRead":0,"cacheWrite":0,
           "reasoning":12,"totalTokens":384,
           "cost":{"input":…,"output":…,"cacheRead":0,"cacheWrite":0,
                   "total":0.000382536}},"stopReason":"stop",…},"toolResults":[]}
```

Differences from Claude:
- Field names: `input`/`output`/`cacheRead`/`cacheWrite` (not `_tokens` suffixes).
- Cost is nested at `.usage.cost.total` (not top-level `total_cost_usd`).
- Pi emits **per-turn** usage (one `turn_end` per assistant turn). Claude's last
  `result` line is the **cumulative** session total. → Pi parity = **sum all
  `turn_end` usages** in the log.

### Recommended: auto-detecting `extract_usage` (single function, both runtimes)

Avoid threading `WF_RUNTIME` through every reader. Make `extract_usage` detect
the log format:

```bash
extract_usage() {
  local logf="$1"
  if [[ -s "$logf" ]] && grep -q '"type":"turn_end"' "$logf" 2>/dev/null; then
    extract_usage_pi "$logf"      # Pi: sum turn_end.message.usage
  else
    extract_usage_claude "$logf"  # existing logic (last result line)
  fi
}
```

```bash
extract_usage_pi() {
  local logf="$1" out='0 0 0 0 0'
  [[ -s "$logf" ]] && command -v jq >/dev/null 2>&1 || { printf '%s\n' "$out"; return; }
  out="$(grep '"type":"turn_end"' "$logf" | jq -r '
    .message.usage // empty
    | [ .input, .output, (.cacheRead//0), (.cacheWrite//0), (.cost.total//0) ]
    | @tsv' 2>/dev/null \
    | awk -F'\t' '{i+=$1;o+=$2;cr+=$3;cc+=$4;c+=$5} END{printf "%d %d %d %d %.4f",i,o,cr,cc,c}' \
    || true)"
  [[ -n "$out" ]] || out='0 0 0 0 0'
  printf '%s\n' "$out"
}
```

(Field order matches the existing 5-field contract: `in out cache_read
cache_creation cost`.) The existing Claude branch becomes `extract_usage_claude`
unchanged. This keeps `report_usage` (pipeline) and any scheduler usage logging
runtime-agnostic. **No `--verbose` flag** for Pi — `--mode json` already streams
all events.

---

## 9. Pi skill wiring (one-time, host-side)

Two options; **recommend (A)** for determinism (no host mutation, no global
toggle dependency):

- **(A) Per-invocation `--skill`** (used in §5.2/§6.2): the scheduler/pipeline
  pass `--skill ~/.agents/skills/improve-codebase-architecture` (scan) and
  `--skill ~/.claude/skills/address-findings` (worker) explicitly. No pi settings
  edit. Does **not** require `enableSkillCommands` because we use a plain prompt,
  not `/skill:…`.
- **(B) Global settings** (alternative): add to `~/.pi/agent/settings.json`:
  ```json
  { "skills": ["~/.claude/skills"], "enableSkillCommands": true }
  ```
  Makes `address-findings`/`quick-ship` auto-discoverable and `/skill:…`
  invocable. Mutates host config; still need `WORKER_PROMPT_PI` (skills aren't
  Pi-compatible). Not recommended for the pipeline, but fine if the user wants
  `/skill:address-findings` available interactively.

Either way: `improve-codebase-architecture` is already auto-discovered (it lives
in `~/.agents/skills/`), so §5.2's explicit `--skill` for it is belt-and-suspenders.

---

## 10. Validation / testing plan

Dev-workflow-repo hard rule: `bash tests/test-*.sh` for shell suites +
`shellcheck` for scripts. There is no existing test for this pipeline; add:

1. **`shellcheck`** both edited scripts clean (existing convention).
2. **`bash -n`** syntax check on both.
3. **New `tests/test-improve-architecture-pipeline.sh`** (bash, no network):
   - `WF_RUNTIME=claude` path unchanged: assert `run_scan` still emits the Claude
     invocation (use a `claude` stub on `PATH` that records args + prints a canned
     `stream-json` result line + a fake report file; assert `extract_usage`
     returns the Claude fields).
   - `WF_RUNTIME=pi` path: assert `run_scan` emits `pi -p --mode json --approve
     --exclude-tools ask_question --skill …`; use a `pi` stub that prints a canned
     `--mode json` `turn_end` line + writes a fake report; assert
     `extract_usage_pi` sums correctly and `extract_usage` auto-detects Pi vs
     Claude logs.
   - Scheduler: stub `pi`/`claude`, feed a 2-finding `reports/architecture-foo.md`,
     assert the judge receives the clusters payload on stdin and the worker is
     invoked in a worktree with `--skill …/address-findings` (Pi) /
     `/address-findings … --auto` (Claude). Assert `extract_pr_num` finds the PR
     URL from a canned tool-execution log line.
4. **`WF_RUNTIME` default**: assert unset → `claude` (no regression).
5. **End-to-end smoke (manual, opt-in, costs tokens)**: run
   `WF_RUNTIME=pi PI_SCAN_MODEL=<cheap-model> ./improve-architecture-pipeline.sh
   --rescan <small-repo>` against a throwaway repo; verify `reports/*.md` written,
   gate tally correct, then `--yes` and verify one PR opens (or `WONTFIX`
   sentinel + `reports/done/` archive). Mirror with `WF_RUNTIME=claude` and
   diff the report shapes (must match the §5.3 contract).

---

## 11. Decisions to confirm (open questions)

1. **Pi default model.** Use pi's configured default (`z-ai/glm-5.2` on
   openrouter) when `PI_*_MODEL` unset, or hard-fail until set? **Recommend:**
   use pi default (matches pi ergonomics); document that a strong model is
   expected for Stage 1 (it does deep analysis).
2. **Inline review vs. skip review (Pi worker Step 4).** MVP = inline
   self-review. Acceptable? (Alternative: skip review entirely and rely on
   verification + the gate; or spawn 3 sequential `pi -p` review sub-processes
   mimicking the 3 reviewers — more faithful but ~3× cost and complexity.)
3. **Inline ship (Pi Step 7) vs. `/skill:quick-ship`.** Recommend inline (§7).
   Confirm we may bypass the shared `quick-ship` skill on the Pi path only.
4. **`--approve` vs `--no-approve` for Pi workers.** `--approve` trusts the
   worktree's project resources (mirrors `bypassPermissions`). If a target repo's
   `.pi/`/`.agents/skills/` is untrusted, `--no-approve` is safer (skips them;
   global + `--skill` skills still load). **Recommend `--approve`** (the
   pipeline already trusts the repo per the gate-trust-boundary rule), with
   `--no-approve` noted as the locked-down option.
5. **Scope of this change in a soon-deprecated repo.** The dev-workflow-repo
   `CLAUDE.md` says "do not start large new feature surfaces here; build those in
   the successor." This is a medium feature in the deprecated repo. Confirm we
   proceed here (vs. porting the pipeline to the Bondsmith successor first).
   User explicitly requested it → proceeding, but flagged.

---

## 12. Out of scope

- Porting the pipeline to the Bondsmith `flowctl` successor.
- Changing the report format, gate, triage clustering, or worktree scheduler.
- Multi-pi-process parallel review (future enhancement).
- A Pi-native `address-findings`/`quick-ship` skill variant (the plan adapts via
  prompts instead, leaving the shared skills Claude-faithful).
- Windows/Termux path adjustments (Pi supports them; not needed for this host).

---

## 13. File change summary (when implemented)

| File | Change |
|------|--------|
| `scripts/improve-architecture-pipeline.sh` | `--runtime` flag + `WF_RUNTIME` env; `validate_env` runtime branch; `run_scan` Pi branch; new `STAGE1_PROMPT_PI`; `extract_usage` auto-detect + `extract_usage_pi`; `usage()`/env doc updates. |
| `scripts/address-reports.sh` | `run_triage_judge` Pi branch (text mode, no `.result`); `run_worker` Pi branch + `--skill`; new `WORKER_PROMPT_PI`; `extract_usage` parity if it has its own. No change to clustering/gate/spine. |
| `tests/test-improve-architecture-pipeline.sh` | New: stub `claude`/`pi`, assert both runtime invocations + usage parsing + judge/worker wiring + `extract_pr_num`. |
| (host, optional) `~/.pi/agent/settings.json` | Only if option (B) chosen; (A) needs no host change. |
