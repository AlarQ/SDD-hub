# Findings: `dev-workflow-repo`

**Date**: 2026-06-21
**Scope**: command/skill/script surface — LM prose that is actually deterministic and should move into a shell script.

---

## Summary

**Goal:** find places where a command instructs the LM (Claude) to perform work
that is actually deterministic, so it can be pushed into a shell script.

**Method:** three parallel Explore passes — primary commands
(`explore`/`propose`/`implement`/`validate`/`review-and-ship`/`validate-impl`),
secondary commands + shared procedures
(`pr-review`/`fix`/`quick-ship`/`learn-from-reports`/`continue-task`/`promote-tier`/`bootstrap`/`config`,
`ship-procedure.md`/`multi-repo-resolution.md`/`pr-body-convention.md`/`knowledge-base-rules.md`),
and a capability map of existing `scripts/`.

**Filter applied:** candidates that are *already* scripted (LM just invokes a
helper) were dropped — no win there. What remains is LM told to do mechanical
work that **no script does yet**, so the LM re-derives it every run.

**Architecture frame:** each item is deterministic logic living as **prose**
(shallow; no locality — re-interpreted every invocation, can drift) instead of
behind a **script seam** (deep; the interface becomes the test surface, logic
lives in one place). The deletion test passes hard: delete the prose, the
complexity reappears across every command that re-describes it.

**Salvage note:** every finding below is named in the parent Bondsmith CLAUDE.md
as a `flowctl` Rust-rewrite target. Scripting it here doubles as the behavior
spec for `flowctl`'s deterministic spine. Reject one → record it as an ADR so the
rewrite doesn't re-LM it.

**Recommended order:** (1) `decision predicates` — deepest locality win, unblocks
keyword→agent; (2) `keyword → agent/tier selection` — biggest live
non-determinism. Then gate job-spec, sensitive-file scan, monitor-log probes as
quick mechanical wins.

**Existing scripts to reuse (call, don't re-derive):** `task-manager.sh`
(set-status/unblock/next/create-followup/status — never hand-edit task
frontmatter); `config-loader.sh` (sourced + `export` — never parse `.workflow.yml`
in prose); `gate-ceiling.sh` (`wf_compute_effective_set`/`wf_compute_union_set` —
never parse `ground_rules` by hand); `validate-impl.sh`
(`wf_vi_run_union_gates`/`wf_vi_task_diff_range` — never shell out gate commands
one by one); `monitor.sh log_event` (never format JSONL by hand).

---

## [determinism] Keyword → agent / tier selection — RESOLVED (2026-06-21)

**Severity**: High

**Files**:
- `commands/propose.md` (agent selection — Backend/Security/etc. spawned by grepping fixed keyword sets)
- `commands/explore.md` (step 0f — tier override to `medium` on `auth|security|migration|api|schema|crypto`)

**Problem**:
LM greps the spec/prd for hardcoded keyword lists to decide which agents spawn
and whether to force the tier up. Fixed input set → fixed output, but the LM does
it freehand. A missed or hallucinated keyword = different run, different agents.
Pure non-determinism over a lookup table. Largest live non-determinism on the
surface.

**Fix**:
`wf_select_agents <spec> <prd>` plus folding the tier-keyword override into a
script — greps the keyword tables, exports `WF_SPAWN_BACKEND=1`,
`WF_TIER_FORCED=medium`, etc.; the command just reads the flags. Same spec always
yields the same agent set (testable: feed a fixture spec, assert the flag set).
Keyword tables become data in one place, not prose scattered across two commands;
the **hard rules force ≥medium** policy becomes enforced, not LM-remembered.

---

## [determinism] Skip / decision predicates

**Severity**: High

**Files**:
- `commands/validate.md` (Phase 3)
- `commands/validate-impl.md` (Step 0)
- `commands/implement.md` (step 8/9 track branching)

**Problem**:
LM re-implements priority-ordered flag checks in prose: "skip coverage if
`tier==small` → else `coverage_audit==false` → else `scope==per-spec`". Same
pattern for the tier early-exit and the feature-vs-technical context read. The
loader already exports the vars; only the *decision* is re-derived each run,
across three commands.

**Fix**:
A thin **decision module** — `wf_decide coverage-skip`, `wf_decide impl-context`,
… returning the named verdict + a reason string, one adapter per decision.
Highest locality win — the skip priority lives once. Testable predicates. The
deepest single module: it turns exported state into named decisions. Do this
first; it unblocks the keyword→agent work.

---

## [determinism] Gate job-spec assembly

**Severity**: Medium

**Files**:
- `commands/validate.md` (Phase 1)

**Problem**:
LM loops the effective set, pulls `command`/`cwd`/`category` per gate via
`wf_gc_gate_field`, and accumulates a JSON job spec by hand — a classic LM error
site. A pure data transform sitting between two pieces that already exist
(`gate-ceiling.sh` computes the set; the `gate-runner` agent consumes the spec).

**Fix**:
`wf_build_gate_job_spec <effective> <pool>` → emits the JSON directly. Closes the
gap the inventory flagged ("no standalone gate-spec builder"). The seam already
has two adapters (validate + gate-runner) → a real seam worth deepening.

---

## [determinism] Sensitive-file scan + default-branch resolution

**Severity**: High

**Files**:
- `commands/quick-ship.md`
- `scripts/ship-procedure.md`

**Problem**:
Both re-describe the same git-diff + secret-pattern grep, and the same
`symbolic-ref` default-branch fallback chain. Duplicated prose = two places to
drift; the two ship paths' security checks can silently diverge.

**Fix**:
`wf_scan_sensitive_files` + `wf_default_branch`. Two callers each = a real seam.
The security check becomes identical across both ship paths, one pattern list.

---

## [determinism] Odium verdict parse + FR allowlist guard

**Severity**: High

**Files**:
- `commands/validate-impl.md` (Step 4)

**Problem**:
LM parses the verdict frontmatter, checks every returned FR id against the spec
allowlist, and applies the `forced_verdict` override. The allowlist check is
fail-closed security logic done in prose.

**Fix**:
`wf_validate_odium_verdict <output> <allowlist> <forced>`. Fail-closed
enforcement guaranteed, not LM-dependent. (The LM still does the *audit*; only the
result validation is scripted.)

---

## [determinism] continue-task phase detection

**Severity**: Medium

**Files**:
- `commands/continue-task.md`

**Problem**:
LM maps (task status enum + commits-ahead count + artifact existence) → resume
phase name. A decision table executed freehand.

**Fix**:
`wf_detect_resume_phase <feature>` → prints the phase. Resume becomes
deterministic + testable instead of LM-judged each time.

---

## [determinism] Monitor-log state probes

**Severity**: Low

**Files**:
- `commands/implement.md` (Spec-Done Detection)
- `scripts/ship-procedure.md` (single-branch last-task detection)

**Problem**:
LM is told to `tail -50 .monitor.jsonl | grep '"category":"spec_last_task_done"'`
by hand in multiple spots. Log-shape knowledge leaks into command prose.

**Fix**:
`wf_check_spec_done <feature>` → exit 0/1.

---

## [determinism] Report loading / filtering

**Severity**: Low

**Files**:
- `commands/learn-from-reports.md` (steps 1–2)

**Problem**:
LM resolves the newest-per-task report by recency, flattens findings, and filters
`rule_added`/`auto_accepted`. A file-glob + yq filter. (The *mining* stays LM —
judgment.)

**Fix**:
`wf_load_task_findings <feature> [task-id]` → a clean findings list.

---

## [determinism] Argument-grammar hand-parsing

**Severity**: Low

**Files**:
- `commands/explore.md` (0a)
- `commands/config.md` (step 2)
- `commands/quick-ship.md` (`--repo`)

**Problem**:
Flag grammars are hand-parsed in prose across three commands.

**Fix**:
Small `wf_parse_*` helpers, one per grammar.

---

## [determinism] Template rendering by LM

**Severity**: Low

**Files**:
- `commands/fix.md` (render `fix.md.template` + static frontmatter)
- `commands/bootstrap.md` (`.workflow.yml` from template)

**Problem**:
LM renders static templates with variable substitution by hand.

**Fix**:
`envsubst` over the template files.

---

## [determinism] promote-tier mechanics

**Severity**: Low

**Files**:
- `commands/promote-tier.md`

**Problem**:
Tier-bump lookup (`small→medium→large→refuse`) + done-task bucketing into
preserved/reproposed done by the LM.

**Fix**:
Script the lookup + bucketing.

---

## [determinism] pr-review bot/self comment filter

**Severity**: Low

**Files**:
- `commands/pr-review.md`

**Problem**:
LM skips `user.login == $ME` or body starting `[claude]` by hand. (Comment
*classification* stays LM.)

**Fix**:
`jq` filter on the comment list.

---

## [determinism] ground_rules path resolution duplicated in prose

**Severity**: Low

**Files**:
- `scripts/knowledge-base-rules.md`

**Problem**:
Re-describes the legacy-prefix-stripping that
`task-manager.sh resolve_ground_rule_path` already does — duplicated logic that
can drift from the script.

**Fix**:
Dedup the prose to a pointer at `task-manager.sh resolve_ground_rule_path`.

---
