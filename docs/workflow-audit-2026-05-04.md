# Workflow Audit — 2026-05-04

Audit of `dev-workflow` repo: spec-driven Claude Code workflow (commands, scripts, agents, hooks, templates, KB, Rust TUI). Focus areas: duplication, inconsistency, complexity, transparency gaps, general improvements.

Findings grouped by category, prioritized **High / Medium / Low** by impact. Each finding: location, problem, example, fix.

---

## Duplications

### D1 [HIGH] — Step 0 config-loader boilerplate copy-pasted across commands ✅ DONE

**Where:** `commands/implement.md`, `validate.md`, `review-findings.md`, `propose.md`, `validate-impl.md`, `ship.md` (and others).

**Problem:** Each command repeats the same `bash -c 'source ~/.claude/scripts/config-loader.sh && wf_load_config --spec $ARGUMENTS && printf …'` block, plus a hand-curated env-var list and the same "Loader contract … exit-code 4 → run `/explore` or `/config`" prose.

**Example drift:** `validate.md:21` enumerates `WF_GATE_POOL` in its printf; `propose.md:13` omits it. Adding a new exported var (e.g. `WF_AGENT_POOL_SHA`) requires editing every command, and silent omissions are how drift starts.

**Fix:** Extract a single `scripts/step0-load-config.md` snippet (mirror of `knowledge-base-rules.md` / `report-schema.md` pattern) with the canonical invocation + env list. Each command links it: `> See scripts/step0-load-config.md for Step 0`. One source of truth.

---

### D2 [MED] — Snapshot serializer duplicated in config-loader.sh

**Where:** `scripts/config-loader.sh:288-295` (`wf_write_snapshot`) and `:306-313` (`wf_check_snapshot_drift`).

**Problem:** Both inline the same `python3 -c` block to serialize loader state to JSON. Any schema change (new field, ordering) must be made in both places.

**Fix:** Extract `_wf_snapshot_json()` helper that prints the JSON; both callers consume its stdout.

---

### D3 [MED] — Three reimplementations of "timeout with fallback"

**Where:**
- `scripts/config-loader.sh:14-25` — `wf__timeout` (perl fallback)
- `scripts/task-manager.sh:154-158` — `_wf_yq` (plain yq fallback)
- `scripts/monitor.sh:65-67` — inline (empty-string fallback)

**Problem:** Different fallback semantics for the same problem. A yq hang on a malformed file behaves differently in each call site.

**Fix:** Add `wf_with_timeout SECS CMD…` to `scripts/config-paths.sh` (already loaded everywhere) with one canonical fallback policy. Replace the three implementations.

---

### D4 [MED] — Agent-dispatch keyword lists duplicated

**Where:** `commands/propose.md:70-76` and `commands/explore.md:105-106`.

**Problem:** Same backend (`database|API|REST|…`) and UI (`UI|component|CSS|…`) keyword sets in both. Adding `tRPC` or `Tailwind` requires two edits; one will be forgotten.

**Fix:** Extract to `scripts/agent-keyword-rules.md`, link from both commands.

---

### D5 [LOW] — Dead alias layer in validate-impl.sh

**Where:** `scripts/validate-impl.sh:107-110` — `wf_vi_task_languages`, `wf_vi_union_languages`, `wf_vi_compute_union`.

**Problem:** Pure aliases for `wf_gc_*` functions. Callers already use `wf_gc_*` directly elsewhere. Dead back-compat layer.

**Fix:** Delete the aliases, grep-confirm no remaining callers.

---

## Inconsistencies

### I1 [HIGH] — `validate_id` arity mismatch

**Where:** `scripts/monitor-validators.sh:25` calls `validate_id "$category" "category"` (2 args). Canonical `validate_id` in `scripts/config-paths.sh:109-116` takes **1 arg**; the second is silently dropped.

**Problem:** The intended labeled error message (`"category"`) is lost. Worse, `monitor.sh:142,143,160,174,175,194,195` use a parallel 2-arg variant `_wf_mon_validate_labeled_id` reusing the same regex — two validators for one rule.

**Example:** Pass an invalid category "agent spawn" (with space). Error reads "invalid id" instead of "invalid category id 'agent spawn'", making the offending field invisible to the user.

**Fix:** Promote 2-arg signature into the canonical `validate_id` (`label` optional). Migrate all callers, delete the parallel `_wf_mon_validate_labeled_id`.

---

### I2 [HIGH] — `/ship` writes frontmatter directly, violates CLAUDE.md rule

**Where:** `commands/ship.md` step 9 hand-edits task frontmatter to add `pr_url`.

**Problem:** `CLAUDE.md:64` says "All task status changes go through `task-manager.sh` — never edit YAML frontmatter directly." No state-machine entry for `pr_url`, so the rule is being broken silently.

**Example:** A future refactor that splits frontmatter format (e.g. nests metadata) will break `/ship` because it bypasses the parser.

**Fix:** Add `task-manager.sh set-pr-url <task> <url>` that writes via `yq` and validates URL shape. Or weaken the rule text to "status fields" and document `pr_url` as an exception with rationale.

---

### I3 [HIGH] — Snapshot drift invisible inside one shell

**Where:** `commands/implement.md:39` writes snapshot via `wf_write_snapshot`. `commands/ship.md:28` re-loads config and compares.

**Problem:** `wf_load_config` is idempotent (`config-loader.sh:7` early-return on `WF_LOADED=1`). If `/implement` and `/ship` run in the same shell session, `/ship` sees cached env from `/implement` — drift detection always passes, even if `.workflow.yml` was edited between commands.

**Example:** User edits `.workflow.yml` to swap an agent pool while a task is in progress. `/ship` should detect and warn; instead, it silently ships using stale loader state.

**Fix:** In `/ship`'s drift check, force `WF_RELOAD=1` (or `unset WF_LOADED`) before re-invoking `wf_load_config`.

---

### I4 [MED] — CLAUDE.md command list out of sync with `commands/`

**Where:** `CLAUDE.md:13` lists ~14 commands; `commands/` directory has 18.

**Problem:** New commands added without updating the doc list. Readers using CLAUDE.md as the entry-point miss commands.

**Fix:** Either keep the list exhaustive with a contributor checklist note, or replace the inline enumeration with `see commands/ for the full list` + a one-line description per command.

---

### I5 [MED] — Report-extension mismatch silently skips spec audits

**Where:** `scripts/report-schema.md:9` declares per-task gate reports as `<task-id>-<gate>.yaml`, spec-audit reports as `.md`. `commands/learn-from-reports.md:15` reads only `.yaml`.

**Problem:** Spec-audit `.md` reports never feed the mining pass. Patterns inside Odium's spec audit are invisible to `/learn-from-reports`. `/review-findings.md:19` correctly reads both, so behavior is inconsistent across commands.

**Fix:** Teach mining to read both extensions, OR explicitly document "spec audits are mined inline at `/validate-impl` time" with rationale.

---

### I6 [MED] — `WF_SPEC_GATES` shape under-specified

**Where:** `scripts/config-loader.sh:237` exports as newline-separated string. `commands/implement.md:22` formats with single `%s`. `wf_write_snapshot:290` re-splits via `splitlines()`.

**Problem:** Format is undocumented in `config-loader.contract.md`. If a gate id ever contains whitespace (currently blocked by `validate_id` regex but no test asserts this), behavior fractures across consumers.

**Fix:** Add to contract: "newline-separated, no leading/trailing newline, ids match `^[a-z][a-z0-9-]*$`". Add a test that asserts the regex contract.

---

### I7 [LOW] — Loader exit code 2 overloaded

**Where:** `scripts/config-loader.contract.md:38` and many `return 2` paths in `config-loader.sh`.

**Problem:** Exit 2 covers both schema failures (`gate_pool not file`) and recoverable user errors (`spec_storage not dir`). Callers can't distinguish.

**Fix:** Split into 2a (recoverable) / 2b (schema corruption), or use distinct codes 2 and 3.

---

## Complexity

### C1 [HIGH] — `/implement` does too many jobs

**Where:** `commands/implement.md` (~106 lines).

**Problem:** Six distinct responsibilities: (1) Step 0 config, (2) prereq checks (PR merged, in-progress lock, spec-review gate), (3) branch lifecycle (steps 3-6a), (4) Test Strategist refinement (step 10), (5) Ultrathink Debugger spawn on failure, (6) Code Quality Pragmatist post-impl, (7) spec-done detection (94-103). When something errors, the user can't tell which phase failed.

**Example:** "Branch creation failed" — was it the prereq PR-merged check, or the actual `git checkout`? Different remediations.

**Fix:** Extract `scripts/implement-prereqs.sh` and `scripts/implement-postcheck.sh`. Main command becomes a thin orchestrator with explicit phase markers in monitor events (`phase: prereq | branch | code | postcheck`).

---

### C2 [HIGH] — Hand-rolled cycle detection in task-status.sh

**Where:** `scripts/task-status.sh:94-122` (`cmd_status`).

**Problem:** BFS uses comma-separated string as a visited set. Cycle detection compares `q_id == task_ids[$i]` (linear scan), not back-edge tracking. Diamond cycles (A→B, A→C, B→D, C→D, D→A) likely produce false negatives.

**Example:** Construct tasks T1 deps [T2,T3], T2 deps [T4], T3 deps [T4], T4 deps [T1]. Run `cmd_status` — verify whether the cycle is reported.

**Fix:** Replace with a small awk or Python topo-sort that returns SCCs. ~20 LoC, deterministic, testable.

---

### C3 [MED] — Review-findings grouping algorithm undocumented

**Where:** `commands/review-findings.md:27-44`.

**Problem:** Three-pass transitive closure groups findings by file+line proximity AND file+category. Then a file-mutex serializes parallel sub-agent writes. The interaction (group spawn vs mutex wait) is hand-coded with no test fixture and no inline invariant statement.

**Fix:** Add an `## Invariants` section to the command spelling out: "no two sub-agents may hold a write lock on the same file"; "groups are computed over the static finding set before any sub-agent spawns". Future edits will preserve them.

---

### C4 [MED] — `/validate-impl` helper uses two output channels

**Where:** `scripts/validate-impl.sh` `wf_vi_run_union_gates` returns forced-verdict via stdout while writing logs to a path arg.

**Problem:** Caller in `commands/validate-impl.md` Step 4 must read stdout for verdict AND parse the log file for gate detail. Verdict-override rule ("Odium's verdict is final unless a gate failed") requires correlating both.

**Fix:** Return single JSON to stdout: `{"verdict": "...", "gate_failures": [...], "log_path": "..."}`. One channel, one parse.

---

### C5 [LOW] — O(N×M) on every done transition

**Where:** `scripts/task-manager.sh:80-112` (`maybe_emit_spec_last_task_done`).

**Problem:** Re-scans all task files and tail-greps `.monitor.jsonl` on every `set-status done`. Fine at current scale; degrades on specs with many tasks + long monitor history.

**Fix:** Cache last-emit cursor in `.monitor.jsonl.cursor` or skip tail-grep when caller supplies `--no-dedup`.

---

## Transparency Gaps

### T1 [HIGH] — Monitor hook silently swallows everything

**Where:** `hooks/monitor-tool-calls.sh:54` uses `||` chain on JSON extraction; missing `description` and `subagent_type` produce empty `agent_name`. All error paths `exit 0` (intentional, line 12).

**Problem:** When events look wrong in `.monitor.jsonl`, there's no signal explaining what failed. Debugging requires re-running by hand.

**Example:** Agent name appears blank in the event log after a `Task` tool call that succeeded — user has no way to find out why.

**Fix:** Add `WF_MONITOR_DEBUG=1` env that writes to `~/.claude/monitor-debug.log` (sidecar, never blocks the hook). Log raw input + extraction outcome per event.

---

### T2 [HIGH] — `/ship` `clear_context` failure is invisible

**Where:** `commands/ship.md:48` — "Clear monitor context (non-fatal — proceed even if this fails…)".

**Problem:** If clear fails, next unrelated command's tool calls get appended to the prior feature's `.monitor.jsonl`. User notices only when audit data is corrupt weeks later.

**Fix:** Surface failure in command output: `WARN: failed to clear monitor context — next /implement will overwrite, but cross-feature events between now and then will land in stale spec`. Emit a `clear_context_failed` monitor event.

---

### T3 [MED] — Dirty gate-pool warning has no audit trail

**Where:** `scripts/config-loader.sh:202-205` emits `WARN: WF_GATE_POOL has uncommitted modifications` to stderr only.

**Problem:** Spec validated against an uncommitted gate registry is non-reproducible. No monitor event records this — audits can't flag affected reports.

**Fix:** Emit `gate_pool_dirty` monitor event with file SHA. `/learn-from-reports` and `/validate-impl` can refuse or warn based on its presence.

---

### T4 [MED] — `/explore` step 0 template path silent

**Where:** `commands/explore.md:66` — on the empty-input ("M") path, writes the template silently.

**Problem:** No event distinguishes "user accepted inferencer defaults" from "user wrote custom YAML". Provenance lost for KB/agent attribution.

**Fix:** Add `source` field to `config_approved` payload: `agent` | `edited` | `manual` | `template`. Mining can later correlate quality with provenance.

---

### T5 [MED] — Report deletion has no audit trail

**Where:** `commands/learn-from-reports.md:43` — `rm -rf specs/$ARGUMENTS/reports/`.

**Problem:** Despite the explicit invariant "report deletion is owned solely by /learn-from-reports", no event records the deletion. Forensic comparison against `/validate` output is impossible.

**Fix:** Emit `reports_deleted` event with `{count, file_list_sha}` before `rm`.

---

### T6 [LOW] — Validate-impl diff-range silently degrades

**Where:** `scripts/validate-impl.sh:32` `wf_vi_diff_range` falls back to `HEAD~1` if both `merge-base main feat/$X` and `feat/$X^` fail.

**Problem:** Odium audits a meaningless one-commit diff; verdict appears authoritative.

**Fix:** Fail loud: `echo "Cannot determine diff range for $feature; refusing to audit" >&2; return 5`.

---

## General Improvements

### G1 [HIGH] — Stop-hook prompt buried in settings.json string

**Where:** `templates/settings.json` Stop hook embeds ~2KB of behavioral rules as a JSON string literal.

**Problem:** Unmaintainable: no syntax highlighting, no diff readability in PRs, can't be unit-tested or grep'd cleanly. Editing risks JSON-escape mistakes.

**Fix:** Move rule text to `hooks/stop-pipeline-rules.md`. Settings.json hook becomes a 1-liner that pipes the file to the prompt: `cat ~/.claude/hooks/stop-pipeline-rules.md`.

---

### G2 [MED] — `gates.yml` claims languages it doesn't ship

**Where:** `knowledge-base/gates.yml` (39 lines) — only Rust + shell gates. Comments reference `typescript|javascript|python|go|markdown` for `applies_to`.

**Problem:** A project bootstrapping with a TS tag will get an empty effective gate set with no warning, then run "validation" that does nothing.

**Fix:** Either ship starter gates for the documented languages (eslint, ruff, golangci-lint, markdownlint), or add a header comment "this is a starter registry; extend per project — `applies_to` is advisory until you add gates".

---

### G3 [MED] — Stale TODO references implemented work

**Where:** `commands/validate-impl.md:98` says "T016 owns the spec-union gate executor helper… until then, callers should expect a placeholder log."

**Problem:** `wf_vi_run_union_gates` already exists. The TODO misleads readers and might block downstream work.

**Fix:** Delete the paragraph; replace with a one-line link to the helper.

---

### G4 [MED] — Frontmatter parser breaks on body `---`

**Where:** `scripts/task-manager.sh:161-165` `read_frontmatter` extracts via sed between `^---$` lines.

**Problem:** Any horizontal rule (`---`) inside a task body terminates parsing early; remaining real frontmatter never read. Markdown HRs are common in task descriptions.

**Example:** Task with description containing `## Notes\n\n---\n\nrationale: ...` — parser truncates frontmatter at the HR.

**Fix:** Use `yq --front-matter=process` consistently (already used in `wf_vi_set_spec_shipped` — proven pattern in this repo).

---

### G5 [MED] — `cmd_create_followup` parses ground rules fragilely

**Where:** `scripts/task-manager.sh:328-331`.

**Problem:** Awk + grep on backticked tokens in `## Applicable Ground Rules` section. If the heading is renamed or rules aren't backticked, follow-ups silently get zero ground_rules → die at line 332 with "No ground_rules parsed".

**Fix:** Validate the section's presence and shape in `/propose` and `/validate-spec` (fail-closed at spec creation), so `cmd_create_followup` can trust the format.

---

### G6 [LOW] — Undocumented env var

**Where:** `scripts/monitor.sh:82` references `WF_LEGACY_SPECS_FALLBACK` with no documentation anywhere in the repo.

**Fix:** Document in `config-loader.contract.md` (or wherever monitor envs live), or remove if dead.

---

### G7 [LOW] — Unsampled commands need follow-up audit

**Where:** `commands/{quick-ship,bootstrap,config,pr-review,promote-rules,research,spec-status,workflow-summary}.md` — not sampled in this pass.

**Problem:** `quick-ship` and `ship` likely overlap; `bootstrap` and `config` may share inferencer logic; `pr-review` and `review-findings` both group findings.

**Fix:** Run a follow-up audit pass focused on these eight, looking specifically for overlap with the commands already audited.

---

### G8 [LOW] — Prior audit doc deleted in working tree

**Where:** `git status` shows `D docs/workflow-audit-2026-05-04.md` (this file path).

**Problem:** A prior audit was removed; this audit is its replacement. If retained as historical context, restore from git history.

**Fix:** This document overwrites the deleted file. If older audit history matters, add `docs/workflow-audit-archive/` for prior snapshots.

---

## Priority Summary

**Fix first (highest impact / lowest effort):**
1. **D1** — extract shared Step 0 snippet (kills 6× duplication, prevents env-var drift)
2. **I1** — fix `validate_id` arity (silent error-message degradation across hot paths)
3. **C1** — split `/implement` into phases (biggest UX cliff in workflow)
4. **T1** — add `WF_MONITOR_DEBUG` (unblocks all monitor debugging)
5. **G1** — move stop-hook rules out of JSON string (maintainability cliff)

**Defer or batch:** G6, G8, D5, C5, T6 — low blast radius.

**Needs follow-up audit:** G7 (unsampled commands).
