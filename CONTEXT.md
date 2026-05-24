# Spec-Driven Development Workflow

The domain language of a file-based, spec-driven development workflow for Claude Code: how planned work is specified, decomposed, gated, validated, and shipped. This glossary covers workflow concepts only — not the Rust TUI's rendering internals.

> Canonical definitions of **ceiling**, **effective-set**, and **spec-union** live in `scripts/workflow-glossary.md` (installed to `~/.claude/scripts/`). This file references them rather than duplicating.

## Language

### Work units

**Feature**:
One unit of planned work — the `specs/<feature>/` workspace holding all its artifacts.
_Avoid_: "spec" (when meaning the directory), ticket, story.

**Spec**:
The `spec.md` artifact alone — functional requirements and scope for one Feature.
_Avoid_: using "spec" for the whole Feature workspace.

**Project**:
A vault-mode grouping of Features under one product (`projects/<project>/specs/...`).
_Avoid_: repo, feature.

**Task**:
The thinnest vertical slice of a Feature that still ships end-to-end demoable behavior (tracer-bullet lens); one Task = one repo.
_Avoid_: subtask, slice (when used loosely).

### Validation

**Gate**:
A deterministic, executable check listed in `.workflow.yml gate_pool` that reports a pass/fail `status`; tool-sourced (`source: tool`).
_Avoid_: "agent gate", calling an LLM check a gate.

**Validation agent**:
An LLM agent spawned in `/validate` Phase 2 (security, code-quality, architecture, compliance) producing advisory findings (`source: llm`).
_Avoid_: "agent gate", "Phase-2 gate".

**Finding**:
A single issue raised by a Gate or a Validation agent.
_Avoid_: error, violation (when used loosely).

**Review unit**:
A group of related Findings (same file + nearby lines, or same file + category) decided with one accept/reject in `/review-findings`.
_Avoid_: "finding group" (informal), batch.

**Blocking**:
A Gate property (`blocking: true`) making it mandatory for matching Tasks — skipping is not allowed.
_Avoid_: required, hard gate.

### Knowledge base

**Knowledge base** (single; was "General KB"):
The one rule-set (security, architecture, testing, style, plus learned language/convention rules) living in the master-brain vault; required, resolved via `$WF_GENERAL_KB`. The dual Project KB / General KB layer was collapsed — see ADR-0002.
_Avoid_: global rules, shared KB, "Project KB" (removed term).

**Ground rule**:
A bare `$WF_GENERAL_KB`-relative path in a Task's `ground_rules:` (e.g. `security/general.md`) that resolves to a KB rule file. Legacy `general:`/`project:`/`repo:<name>:` prefixes are stripped + deprecation-warned.
_Avoid_: using it for the rule's content (that is "a KB rule"); the legacy prefix grammar.

**Gate registry**:
The inline `gate_pool:` array in `.workflow.yml` — the sole source of truth for executable Gates; distinct from KB rules.
_Avoid_: gate KB, gate config, standalone `gates.yml`.

### Modes & repo binding

**Repo mode**:
Workflow config and specs live inside the code repo; `.workflow.yml` at repo root carries an inline `gate_pool:` array.
_Avoid_: local mode, single-repo mode.

**Vault mode**:
Going-forward path — specs live in the master-brain vault; the vault `.workflow.yml` is a thin pointer (no `gate_pool`, except the self-hosting exception); gates resolve per-Task from each Bound repo's thin `.workflow.yml` (`kind: repo-gate-pool`).
_Avoid_: multi-repo mode (multi-repo is a consequence, not the name).

**Bound repo**:
A code repo declared in a Feature's `config.yml repos[]` (name → path → role).
_Avoid_: linked repo, target repo.

**Primary repo**:
The Bound repo with `role: primary`; selects the default git/PR context only.
_Avoid_: treating it as a config or KB authority.

### Sizing & execution

**Tier**:
A Feature size class (`small | medium | large`) that right-sizes flow ceremony; inferred at `/explore` step 0 and approved by the user.
_Avoid_: size, complexity level.

**Tier breach**:
A Tier's task or file ceiling exceeded (`tier-check.sh` exit 9) — user must acknowledge or `/promote-tier`.
_Avoid_: overflow, violation.

**Tracer-bullet slice**:
The decomposition lens — a Task is the thinnest slice that still ships end-to-end demoable behavior.
_Avoid_: MVP, increment.

**HITL** / **AFK**:
A Task's `interaction` field. **HITL** = needs a human-in-the-loop decision; **AFK** = autonomously implementable and mergeable (preferred default).
_Avoid_: manual/auto, interactive/batch.

**Branch strategy**:
A Feature's per-spec `branch_strategy` axis (`per-task | single-branch`),
orthogonal to Tier/Track; inferred at `/explore` step 0, user-approved, absent → `per-task`. **per-task** = `feat/<feature>` integration branch + a per-Task sub-branch and one draft PR per Task (today's default). **single-branch** = one `feat/<feature>` branch off `main`, commits accumulate, no per-Task PR — one spec PR opened at the final `/ship` (base `main`).
_Avoid_: "branch mode", "PR strategy", conflating with Tier.

**task_base_sha**:
The `git rev-parse HEAD` recorded into a Task's frontmatter at Task start under `single-branch` (via `task-manager.sh set-base-sha`); anchors start-vs-mid detection and the quality diff range (`${task_base_sha}..HEAD`).
_Avoid_: "base commit", "start sha" (when used loosely).

### Audits

**Task validation**:
Per-Task post-implementation run (`/validate`) executing the effective-set of Gates plus Phase-2 Validation agents; Findings patch code.
_Avoid_: "validate" bare.

**Spec-completion audit**:
The terminal claimed-vs-actual audit (`/validate-impl`, Odium agent) once all Tasks reach `done`; verdict **complete** ships the Feature, **reopen** spawns follow-up Tasks.
_Avoid_: final validation, impl validation.

## Relationships

- A **Project** contains one or more **Features**
- A **Feature** contains exactly one **Spec** (`spec.md`) and one or more **Tasks**
- A **Task** is bound to exactly one repo
- A **Gate** or **Validation agent** produces zero or more **Findings**
- **Findings** are grouped into **Review units** for accept/reject
- A **Task** moves through the state machine: `blocked → todo → in-progress → implemented → review → done` (canonical source: `scripts/task-manager.sh`)
- A **Feature** has exactly one **Tier**, one **Track**, and one **Branch strategy**; each **Task** carries one **interaction** mode (HITL or AFK)
- **Task validation** runs per Task; **Spec-completion audit** runs once after the last Task is `done`

## Flagged ambiguities

- "spec" was used for both the `specs/<feature>/` workspace and the `spec.md` artifact — resolved: **Feature** is the workspace, **Spec** is the artifact.
- "project" vs "feature" vs "repo" — resolved: **Project** is the vault grouping, **Feature** is the work unit, repo is the code location a Task targets.
- "agent gate" / "Phase-2 agent gates" — resolved: a **Gate** is deterministic only; LLM checks are **Validation agents**. The two are never merged under "gate".
- "primary repo" implying config/KB authority — resolved: **Primary repo** is git/PR default context **only**. There is no primary repo for config; gates and KB resolve per-Task from each Bound repo.
- "ground rule" vs "KB rule" — resolved: a **Ground rule** is a bare `$WF_GENERAL_KB`-relative pointer in task frontmatter; the content it resolves to is "a KB rule".
- "Project KB" vs "General KB" / prefix grammar / vault `exit 7` ambiguity — **resolved by ADR-0002**: the dual KB collapsed to one **Knowledge base** (`$WF_GENERAL_KB`); `gates.yml` folded into inline `.workflow.yml gate_pool:`; `ground_rules` are bare paths (legacy prefixes stripped + deprecation-warned); the feedback loop writes to the general KB; `/promote-rules` deleted.
- "review" — overloaded across the `review` Task state, `/review-findings` (triage Findings), and `/pr-review` (handle PR comments). Resolved: keep distinct; "review" bare = the Task state.
- "validate" — shared root across `/validate` and `/validate-impl`. Resolved: **Task validation** (per-Task), **Spec-completion audit** (terminal). Never "validate" bare in docs.

## Example dialogue

> **Dev:** "Once all Tasks are `done`, Task validation has already run per Task — why another audit?"
> **Maintainer:** "Task validation checks each slice in isolation. The Spec-completion audit (Odium) checks claimed-vs-actual for the whole Feature. `reopen` spawns follow-up Tasks; `complete` ships it."
> **Dev:** "If a Gate is `blocking: true` but it's a `small` Tier?"
> **Maintainer:** "Blocking still holds for matching Tasks. Tier trims ceremony — Phase-2 Validation agents — not Blocking Gates."
