# Workflow Audit — 2026-05-04

Scope: spec-driven dev workflow at `dev-workflow/`. Reviewed `commands/`, `scripts/`, `agents/`, `hooks/`, `CLAUDE.md`, `knowledge-base-rules.md`, `specs/configurable-workflow/`. Goal: surface duplication, inconsistency, complexity, transparency gaps.

Findings grouped by severity. Each item: **summary**, **example** (file:line), **proposed fix**.

---

## High Severity

### H1. Gate ceiling intersection duplicated across commands ✅ DONE (2026-05-04)

**Summary.** Logic to compute the per-task effective gate set (`WF_SPEC_GATES ∩ gates whose applies_to matches task ground_rules`) is described inline in three commands, with prose drift between them. A bug fix or semantic change requires three coordinated edits.

**Example.**
- `commands/validate.md:32` — "Compute **effective set** = `WF_SPEC_GATES` (ceiling) ∩ language-applicable gates by ID."
- `commands/validate-impl.md:54-55` — `wf_vi_union_languages` + `wf_vi_compute_union`, union semantics over all tasks.
- `commands/implement.md` — references ceiling implicitly via Step 0 export but does not call the helper, leading callers to re-derive.

The helpers `wf_vi_compute_union` / `wf_vi_union_languages` only exist in the validate-impl path; `/validate` reimplements the same intersection in prose for the per-task case.

**Proposed fix.** Extract canonical helper `scripts/gate-ceiling.sh` exposing:
- `wf_compute_effective_set <spec> <task-file>` → newline-separated gate IDs (per-task intersection)
- `wf_compute_union_set <spec>` → newline-separated gate IDs (spec-wide union over all tasks)

Both commands `source` it. Prose in commands shrinks to: "call `wf_compute_effective_set`; on rc 3 (empty + not allowed) record critical finding."

---

### H2. Config-loader contract scattered; exit codes undocumented in one place ✅ DONE (2026-05-04)

**Summary.** Every command sources `config-loader.sh` and calls `wf_load_config`, but the contract (which env vars get exported, which exit codes mean what) lives in code comments inside the loader. Each command re-explains a subset in inline comments, with drift.

**Example.**
- `commands/validate.md:16` — comment lists `WF_SPEC_GATES`, `WF_SPEC_AGENTS_VALIDATE`, `WF_GATE_POOL`.
- `commands/implement.md:22` — only prints `WF_SPEC_AGENTS_IMPLEMENT`, `WF_SPEC_CONFIG_FILE`.
- `commands/ship.md:20` — different subset again.
- `commands/validate-impl.md:21` and `:64` — two separate sourcings inside the same command.

No file enumerates loader exit codes 2/4/5/6 → user-facing message → recovery action.

**Proposed fix.** Add `scripts/config-loader.contract.md`:
- Table of exported env vars (name, type, default, when set).
- Table of exit codes (code, condition, user message, recovery hint).

Each command links to it instead of inlining a partial list. Optionally introduce `wf_print_config_summary` so commands stop hand-rolling `printf` blocks.

---

### H3. Report-deletion ownership ambiguous; risk of mining input loss ✅ DONE (2026-05-04)

**Summary.** `CLAUDE.md` and `learn-from-reports.md:43` declare deletion is centralized in `/learn-from-reports`. But `review-findings.md:62` still contains `rm -rf specs/$ARGUMENTS/reports/` for the "user wants re-validation" branch. If that branch fires, mining never sees the data.

**Example.**
- `commands/review-findings.md:62` — `rm -rf specs/$ARGUMENTS/reports/` before `/learn-from-reports` runs.
- `commands/learn-from-reports.md:43` — claims sole ownership of deletion.
- `CLAUDE.md` — "Report deletion is centralized in this command".

**Proposed fix.** Remove the `rm -rf` from `review-findings.md`. The re-validation branch should:
1. Move reports to `specs/<f>/reports.archived-<timestamp>/` (or call `/learn-from-reports` first).
2. Then `set-status implemented` and re-enter `/validate`.

Add a guard in `learn-from-reports.md` step 6 that warns if reports-dir was already empty on entry (could indicate an earlier rogue deletion).


---

## Medium Severity

### M1. Terminology drift: ceiling / effective set / union ✅ DONE (2026-05-04)

**Summary.** `CLAUDE.md` defines "ceiling" (spec eligible set) and "effective set" (per-task intersection). Commands use "union" for two different concepts: (a) over-all-tasks gate union (`/validate-impl`), (b) ceiling itself in some prose.

**Example.**
- `commands/validate-impl.md:55` — "Union = `WF_SPEC_GATES` (ceiling) ∩ gates whose applies_to ⊇ any tag" — calls an intersection a "union" because it spans tasks.
- `commands/validate.md:43` — "spec-level union runs later via `/validate-impl`".

**Proposed fix.** Coin three terms and lock them:
- **ceiling** — `config.yml gates:` set (spec eligibility).
- **effective-set** — per-task intersection of ceiling + applicable gates.
- **spec-union** — union of effective-sets over every task in the spec.

Sweep all command prose to use only these. Add a glossary block to `CLAUDE.md` and link from each command header.

---

### M2. Spec-audit findings vs gate findings handled asymmetrically

**Summary.** `/review-findings` step 1 ingests both gate reports and synthetic spec-audit findings from `/validate-impl`. Grouping logic assumes findings come from gate reports; spec-audit findings have no report file and a different remediation path (`create-followup` not fix-apply).

**Example.** `commands/review-findings.md:23` — "Spec-audit reports (filename pattern `spec-audit-*.md`)" mentioned but downstream grouping (lines 29-35) doesn't branch on type.

**Proposed fix.** Add explicit Step 0 in `review-findings.md`: "Process spec-audit findings first. Each accepted spec-audit finding spawns `task-manager.sh create-followup`. Skip the fix-application sub-agent path entirely. Then proceed to Step 1 with gate findings only."

---

### M3. `validate_scope=per-spec` defers gate failures until end-of-spec

**Summary.** `validate_scope` is presented as a "cadence" option but the per-spec setting hides gate failures until all tasks are implemented. Users may not realize.

**Example.** `CLAUDE.md` "validate_scope — cadence control: per-task (default), per-spec (skip per-task validate; union runs at /validate-impl)." `/validate.md:43` skips Phase 2 with a zero-findings report.

**Proposed fix.** Add latency warning to the `validate_scope` doc block. Recommend `both` over `per-spec`. Make `/explore` step-0 inferencer warn when proposing `per-spec` for a code-bearing spec.

---

### M4. Background fix sub-agents lack crash recovery

**Summary.** Accepted findings spawn background sub-agents that apply fixes and update report frontmatter (`review_status: accepted`) via `yq`. If sub-agent crashes mid-update, fixes may be partially applied with stale `pending` status. No retry, no re-validation.

**Example.** `commands/review-findings.md` accept-flow (~lines 42-51).

**Proposed fix.**
1. Sub-agent updates `review_status: accepted` *before* applying fixes (intent recording).
2. After fix-apply, write `fix_status: applied|failed` separately.
3. `/review-findings` post-loop scans for `fix_status: failed` or absent; offers resume.
4. Always re-invoke `/validate` after fix application — never proceed straight to mining.

---

### M5. Empty-intersection abort behaviour inconsistent

**Summary.** `/validate` records `critical` finding (`empty_intersection_ok=false`) but `/validate-impl` says only "abort before spawning Karen" with rc 3. No explicit guard shown.

**Example.**
- `commands/validate.md:54` — explicit critical finding + status=error.
- `commands/validate-impl.md:57` — "helper returns rc 3 (fail-closed); abort". No code block showing the rc-3 branch.

**Proposed fix.** Add to `validate-impl.md`:

```bash
if [[ $rc -eq 3 ]]; then
  echo "spec-union empty on code-bearing spec — aborting" >&2
  ~/.claude/scripts/monitor.sh emit "$ARGUMENTS" "validate_impl_abort" '{"reason":"empty_union"}'
  exit 3
fi
```

---

## Low Severity / Complexity

### L1. Post-implementation advisor findings are ephemeral

**Summary.** `/implement` lines ~73-91 spawn Ultrathink Debugger + Code Quality Pragmatist as a pre-validation sanity check. Findings shown inline, not persisted. Re-running `/implement` repeats work; no audit trail.

**Proposed fix.** Persist advisor output to `specs/<f>/reports/<task-id>-<agent>.yaml` with `source: llm`. Let `/review-findings` handle them through the normal accept/reject flow. Removes the bespoke inline review.

---

### L2. Config-snapshot drift only checked at `/ship`

**Summary.** `/implement` writes `.monitor-context-snapshot`; only `/ship` calls `wf_check_snapshot_drift`. Config edits during `/validate` go undetected — gate results may reflect stale config.

**Example.** `commands/implement.md:43` (write), `commands/ship.md:30` (only check site).

**Proposed fix.** Add `wf_check_snapshot_drift` call at `/validate` Step 0 entry. On drift: warn, abort, suggest re-running `/implement` Step 0.

---

### L3. Prefix resolution silent-skip on missing KB files

**Summary.** Unprefixed `ground_rules` default to `project:`. If file missing, commands silently skip. Typos eat rules.

**Example.** `knowledge-base-rules.md:10-24` — default prefix doc, no enforcement.

**Proposed fix.** `/validate` Phase 1 iterates `ground_rules`, resolves each path (general:/project:), fail-closes on unresolvable. Emit error finding listing missing files.

---

### L4. Three-layer config + dead `validation_tools` frontmatter

**Summary.** Config lives across `.workflow.yml` + `gates.yml` + `specs/<f>/config.yml`. Old `validation_tools` frontmatter in language KB files is now "display-only" — dead weight that confuses readers.

**Example.** `CLAUDE.md` "Configurable Workflow" block; language KB files still carrying `validation_tools` frontmatter.

**Proposed fix.** Either delete `validation_tools` from language files and rely solely on `gates.yml`, or add a one-time `scripts/migrate-language-kb.sh` that strips them. Keep the three-file config layering — it has a purpose — but document the data ownership boundary at the top of `CLAUDE.md`.

---

## Top 8 fixes (ordered by ROI)

1. **Extract `scripts/gate-ceiling.sh`** — kills H1, simplifies M5.
2. **Centralize loader contract in `config-loader.contract.md`** — kills H2.
3. **Remove `rm -rf` from `/review-findings`** — kills H3.
4. **Milestone banners on auto-chain** — kills H4.
5. **Persist post-impl advisor findings as reports** — kills L1, simplifies M2/M4.
6. **Split spec-audit review path (Step 0 in `/review-findings`)** — kills M2.
7. **Drop or migrate `validation_tools` frontmatter** — kills L4.
8. **Fail-close on unresolvable `ground_rules`** — kills L3.

---

*Report generated 2026-05-04. Cross-reference: `specs/configurable-workflow/design.md` (ADR-003), `commands/validate.md`, `commands/validate-impl.md`, `commands/review-findings.md`, `commands/learn-from-reports.md`.*
