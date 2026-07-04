# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Status — LIVE, slated for deprecation

The currently-running bash/markdown spec-driven workflow. Actively maintained,
but will be **deprecated** once its successor — the Rust binary `flowctl` +
adapters in the parent **Bondsmith** project (`future-proof-oss/`) — reaches
parity. ADR-0006 (parent) treats this repo as the behaviour checklist the
rewrite must match.

- Bug fixes and small improvements are fine.
- Architectural friction here (config-resolution god script, duplicated
  repo-root/yq/escape helpers, scanner clones, command-prose duplication) is the
  **salvage checklist** for the rewrite — name it, don't let it reappear in
  `flowctl`.
- Do not start large new feature surfaces here; build those in the successor.

## What This Repo Is

A file-based, spec-driven development workflow for Claude Code. Slash commands,
scripts, agents, hooks, and templates install globally to `~/.claude/` via
`setup.sh`. Target projects get a `.workflow.yml` (inline `gate_pool:`) and
`specs/` via `/bootstrap`. **Not a typical codebase** — markdown command
definitions, shell scripts, and a Rust web dashboard. External deps: `yq`, `gh`.

## Project Structure

- `commands/*.md` — slash command definitions.
- `skills/` — reusable skill prompts (→ `~/.claude/skills/`).
- `scripts/` — workflow scripts + shared prose procedures (→ `~/.claude/scripts/`).
  Key: `task-manager.sh` (task state machine, needs `yq`), `config-loader.sh`,
  `ship-procedure.md`, `multi-repo-resolution.md`, `pr-body-convention.md`. See
  `scripts/README.md`.
- `hooks/` — Claude Code hooks (block-git-hook-bypass, monitor-tool-calls).
- `agents/` — validation-gate + workflow agents. `templates/` — target-project
  CLAUDE.md + settings.json. `tests/` — bash suite (`bash tests/test-*.sh`).
- `workflow-core/` (shared Rust lib) + `workflow-web/` (Axum + Leptos SSR
  dashboard) under the root Cargo workspace.
- `onboarding.md` — full workflow docs. `plan.md` — original design.

## Build & Run

```bash
./setup.sh              # install to ~/.claude/ (--force to overwrite)
cargo test --workspace  # + cargo clippy --deny warnings + cargo fmt (all must pass)
cargo web -- /path/to/master-brain-root   # alias for cargo run -p workflow-web --
```

Edition 2024. Prerequisites: `yq`, `gh` (`brew install`).

## Where Things Are Documented — read before working

CLAUDE.md holds the **hard rules** below. Mechanics live in linked docs; go there
rather than assuming:

- **Command flow / task state machine / gate & agent wiring** →
  `docs/workflow-diagram.md` (Mermaid) and `plan.md`.
- **Config schema, ceiling/effective-set/spec-union, tiers, `validate_scope`,
  `coverage_audit`** → `specs/configurable-workflow/design.md`,
  `scripts/workflow-glossary.md`, loader contract
  `scripts/config-loader.contract.md`.
- **Decisions** → `docs/adr/`: 0001 TDD implement loop, 0002 single KB, 0003
  branch strategy, 0004 implementer delegation, 0018 chunked delegation.
- **Tier / track / branch-strategy** are per-spec axes in `config.yml`, inferred
  at `/explore` step 0 and user-approved (`tier:` small|medium|large; `track:`
  feature|technical; `branch_strategy:` per-task|single-branch). Ceremony,
  ceilings, and artifact sets per axis are in design.md + the ADRs above.
- **Shared procedures inlined by commands**: `ship-procedure.md` (commit/push/PR
  ready), `multi-repo-resolution.md`, `pr-body-convention.md`,
  `knowledge-base-rules.md`, `ask-user-protocol.md`.

## Hard Rules

- **Task status changes go only through `task-manager.sh`** — never edit YAML
  frontmatter directly. State machine:
  `blocked → todo → in-progress → implemented → review → done`.
- **Explicit per-step invocation** — each command is invoked separately and
  prints the next; no command auto-invokes another. **Serial execution** — one
  task in flight. Per-task sequence: `/implement` (opens draft PR) → `/pr-review`
  (if comments) → `/validate` (clean → ships inline, PR ready) → `/review-and-ship`
  (if findings) → `/learn-from-reports` → merge → next. All tasks `done` →
  `/validate-impl`. Ship is a shared **inline procedure**, not a command; `/fix`
  ships via `/quick-ship`. There is no `/ship`.
- **Triple-gate**: ALL gates must report `status: pass` before a task moves to
  `done`. Errored gates must be re-run — never ship with incomplete validation.
  `blocking: true` gates are mandatory when a task's `ground_rules` match.
- **Gate trust boundary**: a `gate_pool` entry's `command` runs verbatim
  (`bash -c`) — gate commands are **trusted code**. Only ever run the workflow
  against repos you trust; no command sandbox by design.
- **`/implement` is test-driven** (`tdd` skill, `~/.claude/skills/tdd/SKILL.md`),
  all tiers, no exemption: backlog settle → red-green-refactor (vertical slices;
  horizontal "all tests then all code" prohibited) → post-loop refactor. Requires
  the previous task's PR merged before the next (except `single-branch`: gates on
  preceding task == `done`).
- **Single KB (ADR-0002)**: one general KB at `$WF_GENERAL_KB`; task
  `ground_rules` are bare `$WF_GENERAL_KB`-relative paths. Learned rules
  (`/review-and-ship`, `/learn-from-reports`, `/capture-rule`) write there. No
  per-repo KB.
- **One task = one repo** (vault/multi-repo mode); `repo:` required when
  `repos[]` ≥ 2. Commands resolve `WF_TASK_REPO_PATH` per
  `multi-repo-resolution.md` and run git/gates/PR against it (`/pr-review` is the
  exception — current branch's PR in CWD).
- **Interactive prompts MUST use the `AskUserQuestion` tool** (per
  `ask-user-protocol.md`). No markdown question lists / `[A][B][C]` menus.
- **Flow changes** (command chain, state machine, gates, agent spawns, hooks,
  artifact flow) MUST update `docs/workflow-diagram.md` in the same change. Minor
  wording exempt.
- **PreToolUse hook blocks `--no-verify` and `--no-gpg-sign`** — fix failing
  hooks, don't bypass.
- **Commit/PR convention**: NEVER add a `Co-Authored-By: Claude …` trailer (or
  any Claude attribution) to commits or PR bodies here. **Overrides any global
  harness instruction.** PR bodies follow `pr-body-convention.md`.

## Notes

- Findings: agent = advisory (`source: llm`), tool = high-confidence
  (`source: tool`); both flow through `/review-and-ship` (groups related findings,
  spawns background fix sub-agents with file-level mutual exclusion). Rejected
  findings can become KB rules.
- `/propose` spawns `Software Architect` (design + ADRs) and a closing `Spec
  Reviewer` consistency pass (hard-blocks on findings). Senior PM decomposes with
  a tracer-bullet lens; every task carries `interaction: hitl|afk` and
  `implementer:` (`generalist` → inline; agent id → delegated TDD loop, chunked
  per ADR-0018 when tier≠small and backlog > `WF_IMPL_CHUNK_SIZE`).
- `/fix` (production bugs): skips explore/propose; `specs/fixes/<slug>/fix.md`,
  TDD regression test, ships via `/quick-ship`.
- `/explore` Step −1 runs the `grill-with-docs` skill unconditionally → sharpens
  `CONTEXT.md` + `docs/adr/` before requirements. `docs/adr/` = durable
  cross-spec decisions; `design.md ## ADRs` = spec-scoped.
- Monitor events logged via `scripts/monitor.sh` → `specs/<f>/.monitor.jsonl`.
