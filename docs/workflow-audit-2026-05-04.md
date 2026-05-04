# Workflow Audit — 2026-05-04

Scope: `commands/`, `scripts/`, `agents/`, `hooks/`, `templates/`, `CLAUDE.md`,
`knowledge-base-rules.md`. Focus: duplications, inconsistencies, complexity,
transparency gaps.

Findings grouped by severity. Each entry has **Summary**, **Example**, **Solution**.

---

## Critical

### C1 — Monitor hook unwired in default install ✅ DONE

**Summary.** `hooks/monitor-tool-calls.sh` exists and is functional, but
`templates/settings.json` only registers `block-git-hook-bypass` (PreToolUse) and
`block-dismissive-language` + the findings-persistence prompt (Stop). No
`PostToolUse` hook → tool-call events never logged. Spec audit trails
(`specs/<feature>/.monitor.jsonl`) stay empty unless user wires manually.

**Example.** `templates/settings.json` registers two hooks; `monitor-tool-calls.sh`
referenced nowhere in the template. New projects bootstrapped via `setup.sh` get
no event logging. `/validate-impl` references monitor events for context but they
will be empty.

**Solution.** Add `PostToolUse` block to `templates/settings.json` invoking
`monitor-tool-calls.sh`. Or document explicitly in `CLAUDE.md` that monitor is
opt-in and provide the snippet. Recommended: wire by default — observability
should not require manual setup.

---

## High

### H1 — Report schema fragmented across commands ✅ DONE

**Summary.** Report YAML shape (frontmatter, finding fields, enums) is restated
in three commands with subtly different field lists. No canonical schema doc.
Drift risk: a change in one command silently desyncs the others; agents writing
reports may emit incompatible shapes.

**Example.**
- `commands/validate.md:115` lists fields inline: `{id, severity, category, title,
  description, file, lines, code_snippet, fix_proposal, review_status, source}`
- `commands/validate-spec.md:43-51` shows a different inline shape with
  `severity: critical|high|medium|low|info` enum.
- `commands/review-findings.md:20` enforces frontmatter `verdict ∈ {complete,
  reopen}` — only documented here.
- `review_status` enum (`pending|accepted|rejected|noted`) never listed in one
  place; reader must scan all 3 files to learn the values.

**Solution.** Extract `docs/report-schema.md` with one canonical YAML example +
explicit enum lists for `severity`, `review_status`, `verdict`, `source`,
`status`. All commands link there with a one-line reference; delete inline
restatements.

---

### H2 — Glossary triplicated despite M1 lock ✅ DONE

**Summary.** Audit M1 (commit `13ebbaf`) locked the canonical definitions of
`ceiling`, `effective-set`, `spec-union`. But the definitions live in three
files and have already drifted in wording.

**Example.**
- `CLAUDE.md:89-91` — definitions, plus the "do not use bare 'union'" rule.
- `commands/validate.md:6-9` — restated with slightly different phrasing.
- `commands/validate-impl.md:6-9` — restated again, plus an extra "Reserved for
  Step 2" qualifier on spec-union.

Three sources of truth = drift on next edit.

**Solution.** Move canonical definitions to `docs/glossary.md` (or keep in
CLAUDE.md as the single source). Replace inline blocks in `validate.md` and
`validate-impl.md` with `> See docs/glossary.md (or CLAUDE.md §Configurable
Workflow) for ceiling / effective-set / spec-union.`

---

### H3 — Security Engineer agent: two contracts under one ID

**Summary.** `commands/explore.md` and `commands/propose.md` both invoke the
same agent (`engineering-security-engineer`) with materially different prompts
and expected output shapes. The agent file cannot satisfy both contracts cleanly
— output ambiguity is structural.

**Example.**
- `explore.md:104-111` — lightweight threat-surface checklist during
  requirements clarification.
- `propose.md:29-42` — full STRIDE threat model with mitigations during design.

Same `subagent_type`, different deliverables. If the agent definition leans one
way, the other phase gets a mismatched report.

**Solution.** Either:
1. Split into two agent IDs (`security-threat-surface`, `security-stride`), each
   with a phase-specific prompt; or
2. Keep one ID but document phase-conditional behavior explicitly in the agent
   markdown and have callers pass a `phase: explore|propose` argument.

Option 1 is clearer; option 2 is fewer files.

---

### H4 — Agent model selection inconsistent

**Summary.** Only `review-findings.md:39` explicitly pins `model: "sonnet"` for
fix sub-agents. Every other spawn (Karen, Software Architect, Code Reviewer,
Ultrathink Debugger, Spec Reviewer, Code Quality Pragmatist) inherits the
session default. Silent model drift = silent quality drift; no ADR records why
sonnet is mandated for fixes but unspecified elsewhere.

**Example.** Search `commands/*.md` for `model:` — only review-findings sets it.
Karen invocations in `validate-impl.md` and Software Architect in `propose.md`
omit the field entirely.

**Solution.** Add `agents/_models.md` (or a section in `CLAUDE.md`) mapping
phase → model with rationale. Update every `Agent` invocation site to set the
field explicitly. Pre-commit guard: grep for `Agent\(` blocks lacking `model:`.

---

## Medium

### M1 — KB prerequisite check duplicated, never validated

**Summary.** "Read and follow `~/.claude/knowledge-base-rules.md`" appears as
step 1 in 11+ commands. No script verifies that the general or project KB
actually exists. Partial `setup.sh` failure or missing `/bootstrap` produces
late, confusing errors mid-workflow.

**Example.** `commands/{explore,propose,implement,validate,validate-impl,ship,
spec-status,learn-from-reports,validate-spec,...}.md` all open with the same
line. None checks `[ -f ~/.claude/knowledge-base-rules.md ]` or that
`knowledge-base/_index.md` exists in the project.

**Solution.** Add `scripts/validate-kbs.sh` that asserts both KBs and emits a
clear error pointing to `/bootstrap`. Source it from `config-loader.sh`
(already invoked by every config-dependent command). Cache result via env var
so it runs once per command.

---

### M2 — Review-findings grouping algorithm too complex for LLM execution

**Summary.** `commands/review-findings.md:25-31` specifies (a) sort by file +
line, (b) Pass-1 line-proximity merge with **transitive closure** at ≤5 lines,
(c) Pass-2 same-file same-category merge, (d) per-file mutex for parallel fix
sub-agents. This is a deterministic algorithm executed by an LLM via prose. No
test, no script, no reproducibility. User cannot verify it ran correctly.

**Example.** `review-findings.md:27-29` — three nested merge rules with
transitive closure described in English. Compare with `scripts/task-manager.sh`
which encodes simpler logic in actual shell with explicit state.

**Solution.** Extract `scripts/group-findings.sh` that reads all reports, emits
groups as JSON. Command consumes the script output. Or: simplify spec to
"one group per file, sequential fix application" and drop transitive closure +
parallel mutex. The complexity buys little — most tasks have <10 findings.

---

### M3 — Snapshot drift check only in `/ship`

**Summary.** `commands/ship.md` step 0 runs `wf_check_snapshot_drift` against
`.monitor-context-snapshot` written by `/implement`. `/validate` and
`/validate-impl` do not. Config can change between implement and validate,
silently invalidating gate selection.

**Example.** Sequence: `/implement` writes snapshot → user edits
`specs/X/config.yml` adding a gate → `/validate` runs against new ceiling
without warning → `/ship` finally catches drift, but only after fix work is
done.

**Solution.** Add `wf_check_snapshot_drift` to step 0 of `/validate` and
`/validate-impl`. Same exit code semantics — abort with clear message.

---

### M4 — Archived reports accumulate forever

**Summary.** `review-findings.md` archives reports via
`mv specs/X/reports specs/X/reports.archived-$(date +%s)` to preserve mining
input across re-validation cycles. Deletion is owned by `/learn-from-reports`.
But `/learn-from-reports` only deletes the active `reports/` dir — it doesn't
clean `reports.archived-*`. They pile up in every spec.

**Example.** A spec that goes through three re-validation rounds ends with
three `reports.archived-<ts>/` directories shipped into git.

**Solution.** Extend `/learn-from-reports` to also remove `reports.archived-*`
after mining (they were already mined in their original `reports/` location, or
should be mined-then-deleted as part of this command). Or add a `.gitignore`
entry and a TTL cleanup.

---

## Low

### L1 — `templates/CLAUDE.md` drift risk

**Summary.** Heavy overlap with root `CLAUDE.md`. Nothing marks the template as
derived; next edit to root will likely miss the template, and bootstrapped
projects ship stale instructions.

**Example.** Compare the "Configurable Workflow" sections — both files contain
near-identical prose, but the template has no `<!-- synced from CLAUDE.md -->`
marker.

**Solution.** Add a header comment to `templates/CLAUDE.md` declaring it
derived. Add a `setup.sh` step that diffs sync-marked sections and warns on
drift. Or auto-generate the template from CLAUDE.md.

---

### L2 — `status` zsh-reserved-name hazard not enforced

**Summary.** `commands/implement.md:15` warns that `status` is read-only in
zsh; future scripts may forget. No automated guard.

**Example.** Any new `scripts/*.sh` could write `status=foo` and silently break
when sourced under zsh.

**Solution.** Add a check in `scripts/pre-commit-hook.sh` (or a separate lint):
`grep -nE '^[[:space:]]*status=' scripts/*.sh && exit 1`.

---

### L3 — Stop-hook prompt embedded inline (~1500 chars)

**Summary.** `templates/settings.json` Stop hook contains a long inline `prompt`
string with two checks. Hard to diff, lint, or version meaningfully.

**Example.** `templates/settings.json` lines ~22-25 — single JSON string with
escaped newlines, ~1500 chars covering findings-persistence + auto-handoff
checks.

**Solution.** Extract to `hooks/stop-prompt-checks.md`; settings.json points at
the file path or a shell wrapper that reads it. Easier review, normal markdown
diffs.

---

### L4 — Conventional commit type inferred by LLM judgment

**Summary.** `commands/ship.md:5` says commit type "(feat, fix, refactor, docs,
chore, test, style)" is "determined from the task context." Pure LLM judgment,
no explicit signal.

**Example.** `ship.md` step 5 gives no rule mapping task fields to a commit
type; two runs may produce different types for the same task.

**Solution.** Derive from task frontmatter — add `commit_type:` field to task
schema, or map from existing `category:` field (e.g. `feature → feat`,
`bugfix → fix`). Fail closed if missing.

---

## Quick wins (≤1 h each)

1. Wire monitor hook in `templates/settings.json` (C1).
2. Extract `docs/report-schema.md`, link from 3 commands (H1).
3. Replace duplicated glossary blocks with link to CLAUDE.md (H2).
4. Add snapshot drift check to `/validate` step 0 (M3).
5. Extend `/learn-from-reports` to delete `reports.archived-*` (M4).

## Root cause

Commands evolved independently; recent audits (L4, M1, H2, H3 in commits 752fdf4
… 283a06a) fixed isolated issues but no enforcement keeps cross-command
contracts in sync. Two structural fixes would prevent recurrence:

- **Shared doc fragments** — `docs/report-schema.md`, `docs/glossary.md`,
  `agents/_models.md` referenced from commands instead of inlined.
- **Meta-lint** — pre-commit script checking: glossary terms only defined in
  one place; `Agent(` calls have explicit `model:`; KB prerequisite check
  centralized; commit-type derivable from task frontmatter.
