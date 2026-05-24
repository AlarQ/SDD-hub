# Plan: Port dev-workflow to OpenCode (dual-target)

## Context

Repo today is Claude Code-only spec-driven workflow installed to `~/.claude/`: 18 commands, 20 agents, 3 hooks, shared bash scripts, dual KB. Goal — produce a co-equal OpenCode target so the same workflow (`/explore → /propose → /implement → /validate → /review-findings → /learn-from-reports → /ship → /validate-impl`) runs natively under OpenCode at `~/.config/opencode/`. Both targets supported long-term, single source of truth, full command chain working in v1.

Supersedes earlier draft (had errors: plugin API shape, permission-key list, file counts, AGENTS.md auto-load assumption, dispatch-prose rewrite cost).

## Locked decisions

- **Both targets forever.** Claude install path stays first-class.
- **Templated single .md** — one source file per command/agent with placeholders (`{{AGENT_DISPATCH:name}}`, `{{WORKFLOW_HOME}}`, `{{PATH:scripts/...}}`); `setup.sh` renders per target at install.
- **TS-native plugin rewrite** — no bash bridge.
- **Agent descriptions: postpone rewrite.** Use existing Claude descriptions as-is in v1. Revisit only if smoke testing shows OpenCode auto-delegation misfires.
- **Knowledge-base → OpenCode skills** required v1 (`~/.config/opencode/skills/<name>/SKILL.md`).
- **Drop dismissive-language hook in OpenCode** — `Stop`-equivalent block-on-output not available.
- **Rust dashboard** out of migration scope — the `workflow-core` + `workflow-web` workspace is runtime-agnostic.
- **Drop custom tools** (`tools/*.ts`) from v1.
- **Project instructions** auto-loaded from `~/.config/opencode/AGENTS.md` (no `instructions:` array — auto-discovery handles it).
- **Parallel subagent spawn**: assumed supported (General subagent docs imply); runtime-verified during smoke test. If sequential-only — accept perf hit, do not block v1.

## Verified facts (from official docs)

| Aspect | Verified value |
|---|---|
| Command path | `~/.config/opencode/commands/*.md` (global) or `.opencode/commands/` (project) |
| Command syntax | `$ARGUMENTS`, `$1..$N`, `` !`bash` ``, `@file` |
| Command frontmatter | `description`, `agent`, `model`, `subtask` |
| Agent path | `~/.config/opencode/agents/*.md` |
| Agent frontmatter | `description`, `mode: primary\|subagent\|all`, `model`, `temperature`, `permission`, `color`, `hidden`, `top_p`, `steps` |
| Permission keys | `read, edit, glob, grep, list, bash, task, external_directory, todowrite, webfetch, websearch, lsp, skill, question, doom_loop` |
| Agent dispatch | `@mention`, auto-delegation (description-driven), or Task tool |
| Plugin path | `~/.config/opencode/plugins/*.ts` (or `.opencode/plugins/`) |
| Plugin shape | `Plugin = async ({project, client, $, directory, worktree}) => ({ "tool.execute.before": async (input, output) => {...} })` |
| Plugin deny | `throw new Error(...)` inside before-hook |
| Events | `tool.execute.before/after`, `session.idle/updated/compacted`, `message.updated/removed`, `file.edited`, `permission.asked/replied` |
| Config | `opencode.json` or `opencode.jsonc`; top-level keys include `permission`, `mcp`, `agent`, `command`, `plugin`, `instructions`, `tools` |
| Custom tools | `tools/<name>.ts` exporting `tool({...})` from `@opencode-ai/plugin` |
| Skills | `skills/<name>/SKILL.md` with frontmatter `name`, `description`, `license`, `compatibility` |

## Scope numbers (verified against repo)

- 18 command files; 16 reference `~/.claude/...` paths
- 20 agent files; 3 reference `~/.claude/...`
- 7 commands explicitly dispatch agents (Task / subagent_type prose)
- 3 hooks → 2 plugins (drop dismissive)
- 3 KB markdown files → 3 SKILL.md

## Architecture

### Source-of-truth layout (this repo)

```
commands/*.md             single source, contain placeholders
agents/*.md               single source, contain placeholders
hooks/*.sh                Claude target only
plugins/*.ts              OpenCode target only (NEW — 2 files)
templates/
  CLAUDE.md               Claude target
  AGENTS.md               OpenCode target (NEW)
  settings.json           Claude hook wiring
  opencode.jsonc          OpenCode plugins/permissions/instructions wiring (NEW)
scripts/                  shared bash, target-agnostic, sourced by both
knowledge-base/           shared markdown, also rendered as skills for OpenCode
setup.sh                  --target=claude|opencode (default claude)
scripts/render.sh         NEW — placeholder substitution engine
```

### Placeholder grammar (renderer-driven)

| Placeholder | Claude render | OpenCode render |
|---|---|---|
| `{{WORKFLOW_HOME}}` | `~/.claude` | `~/.config/opencode` |
| `{{PATH:scripts/foo.sh}}` | `~/.claude/scripts/foo.sh` | `~/.config/opencode/scripts/foo.sh` |
| `{{AGENT_DISPATCH:name "prompt"}}` | `Use the Task tool with subagent_type="name" and prompt: "prompt"` | `@name prompt` |
| `{{AGENT_DISPATCH_PARALLEL:[name1,name2,...] "prompt"}}` | parallel Task tool calls | parallel `@name1`, `@name2` mentions in same turn |
| `{{FRONTMATTER_AGENT}}` | Claude shape (current) | OpenCode shape (mode, permission block, hidden, color) |

`scripts/render.sh` reads target from env, runs sed/awk substitution. Idempotent. Lives in repo, not installed.

### Per-target install layout

Claude (unchanged):
```
~/.claude/{commands,agents,hooks,scripts,templates}/...
```

OpenCode (new):
```
~/.config/opencode/
├── commands/         rendered .md
├── agents/           rendered .md (OpenCode frontmatter)
├── plugins/          block-git-hook-bypass.ts, monitor-tool-calls.ts
├── scripts/          symlink or copy of repo scripts/
├── skills/           rendered from knowledge-base/
└── opencode.jsonc    rendered from templates/
```

## Work breakdown

### 1. Renderer + setup.sh dual-target

- New `scripts/render.sh` — single-pass placeholder substitution; takes `--target` and infile, writes outfile. Pure bash + sed.
- Modify `setup.sh`: add `--target=claude|opencode` (default claude). For each command/agent run renderer before placement. For OpenCode target, also render `templates/opencode.jsonc` and copy plugins/.
- Idempotent — re-run does not double-write.
- Smoke: `./setup.sh --target=opencode --dry-run` lists actions.

### 2. Migrate commands to placeholder syntax

For each `commands/*.md`:
- Replace literal `~/.claude/scripts/` → `{{PATH:scripts/...}}` (16 files).
- Replace agent dispatch prose → `{{AGENT_DISPATCH:...}}` / `{{AGENT_DISPATCH_PARALLEL:...}}` (6 files: explore, propose, validate, implement, review-findings, pr-review).

Critical: dispatch placeholders must capture the **prompt body** verbatim — keep multi-line prompts intact.

### 3. Migrate agents to placeholder syntax

For each `agents/*.md`:
- Frontmatter rewrite: build-time step reads existing `tools:` whitelist and emits OpenCode `permission:` block (allow/ask/deny per key). Map: read/edit/glob/grep/list/bash/task/webfetch/websearch/lsp/skill/todowrite. Keys not in current whitelist default to `deny` for OpenCode safety.
- **`tools:` shorthand mapping**: `tools: true` → `permission: {"*": "allow"}`; `tools: false` → `permission: {"*": "deny"}`; per-key boolean → matching permission key. Renderer documents this table.
- Add `mode: subagent` (default) or `mode: primary` (none currently — orchestration done by commands, not primary agents).
- **Descriptions kept verbatim from Claude source.** Postponed rewrite (see Locked decisions).
- Agents needing project KB get `read: {"knowledge-base/**": "allow"}` (project KB lives outside agents' default read scope).
- Replace `~/.claude` refs (3 files).

### 4. Plugins (TS-native, OpenCode only)

`plugins/block-git-hook-bypass.ts`:
- Listens `tool.execute.before`.
- If `input.tool === "bash"` and `output.args.command` matches `/\b--no-verify\b|\b--no-gpg-sign\b/`: `throw new Error("Hook bypass blocked: fix the failing hook instead.")`.
- ~30 LOC.

`plugins/monitor-tool-calls.ts`:
- Listens `tool.execute.after`.
- Resolves spec from cwd (`specs/<feature>/.monitor.jsonl`), appends JSONL event with tool name, args summary, ts.
- Plugin context provides `directory`; uses Bun `fs` directly (not shell-out).
- ~70 LOC.

Smoke tests: `bun test plugins/` with synthetic event payloads.

### 5. Knowledge-base as OpenCode skills

For each `knowledge-base/*.md` (3 files):
- Render to `~/.config/opencode/skills/<slug>/SKILL.md` with frontmatter `name`, `description`, `license`, `compatibility` (optional `metadata` map).
- Skill body = original KB markdown.
- Project KB (`<project>/knowledge-base/`) — not migrated to skills (project-local; agents read directly via Read tool, granted via `read: {"knowledge-base/**": "allow"}`).
- Agents needing KB get `permission: { skill: "allow" }` in OpenCode frontmatter.
- **Skill activation**: agents discover skills via the `<available_skills>` block injected into the `skill` tool description (name + description only). Agent loads full SKILL.md by calling `skill({name: "<slug>"})`. **No `@skill` syntax exists.** Strong skill descriptions (1–1024 chars, action-oriented) are the activation lever.
- Command bodies that require KB context use prose: "Load the `<slug>` skill before proceeding." — not `@skill`.

### 6. Templates

- `templates/AGENTS.md` (NEW): project-instruction file. Same content as `templates/CLAUDE.md` but parametrized via placeholders. Installed to `~/.config/opencode/AGENTS.md` and auto-loaded by OpenCode (no `instructions:` array needed).
- `templates/opencode.jsonc` (NEW): wires plugins (`plugin: ["./plugins/block-git-hook-bypass.ts", ...]`), default permission block, MCP servers (copied from existing `settings.json` MCP). `.jsonc` extension confirmed supported (treated interchangeably with `.json`).
- `templates/settings.json` unchanged (Claude target).

### 7. Path/env

- All command/agent bodies use `{{PATH:...}}` and `{{WORKFLOW_HOME}}` after migration. No env var needed at runtime — paths baked at install.
- `scripts/*.sh` themselves use `$(dirname "${BASH_SOURCE[0]}")`-relative paths where possible; otherwise read `WORKFLOW_HOME` env (set by command bodies). Audit `scripts/config-loader.sh`, `scripts/config-paths.sh`.

### 8. Docs

- New `docs/opencode-mapping.md` — Claude→OpenCode reference for contributors (frontmatter shapes, dispatch syntax, plugin events).
- Update `onboarding.md` with OpenCode install + run section.
- `CLAUDE.md` (this repo): brief note on dual-target + renderer.

## Critical files to modify

- `setup.sh` — add target flag + renderer invocation
- `scripts/render.sh` — NEW
- `commands/*.md` — placeholder migration (18 files)
- `agents/*.md` — placeholder migration + description rewrite (20 files)
- `templates/AGENTS.md` — NEW
- `templates/opencode.jsonc` — NEW
- `plugins/block-git-hook-bypass.ts` — NEW
- `plugins/monitor-tool-calls.ts` — NEW
- `docs/opencode-mapping.md` — NEW
- `scripts/config-loader.sh`, `scripts/config-paths.sh` — audit for hardcoded `~/.claude`
- `onboarding.md`, `CLAUDE.md` — doc updates

## Reuse (do NOT replace)

- `scripts/task-manager.sh`, `scripts/config-loader.sh`, `scripts/monitor.sh`, `scripts/gate-ceiling.sh`, `scripts/config-paths.sh`, `scripts/pre-commit-hook.sh` — already portable
- `knowledge-base/*.md` — body content reused as SKILL.md body
- `templates/CLAUDE.md` — template engine for `AGENTS.md` derivation
- `templates/settings.json` MCP block — copy into `opencode.jsonc` `mcp:`
- Existing `hooks/block-git-hook-bypass.sh` regex/logic — port verbatim into TS plugin
- Existing `hooks/monitor-tool-calls.sh` event shape — preserve JSONL schema

## Verification

1. **Renderer unit**: `scripts/render.sh` round-trips a sample command for both targets — diff against golden fixtures.
2. **Render self-check** (CI gate): post-render grep over `~/.config/opencode/` install tree — fail if any `~/.claude` literal or unrendered `{{...}}` placeholder remains.
3. **Tool-shape probe** (precedes plugin work): minimal logging plugin captures real `output.args` shape per tool (`read`, `edit`, `bash`, `grep`, `glob`, `write`) into `docs/opencode-tool-shapes.md`. Bash shape (`output.args.command`) already confirmed via docs; probe verifies the rest before `monitor-tool-calls.ts` is written.
4. **Plugin smoke**: `bun test plugins/` — synthetic `tool.execute.before` with `git commit --no-verify` throws; `tool.execute.after` writes valid JSONL.
5. **Setup dry-run**: `./setup.sh --target=opencode --dry-run` lists every install action; no writes.
6. **Setup real**: `./setup.sh --target=opencode` installs idempotently; second run is a no-op.
7. **Claude regression**: `./setup.sh --force` followed by full chain on existing test feature — no regression.
8. **OpenCode discovery**: in OpenCode session, `/workflow-summary` runs (proves command loading + `$ARGUMENTS`).
9. **OpenCode dispatch**: `/explore <feature>` triggers `config-inferencer` subagent, writes `specs/<feature>/config.yml`.
10. **OpenCode hook**: `git commit --no-verify` via Bash tool inside session — plugin denies with thrown error.
11. **OpenCode parallel**: `/validate` on a small feature — confirm 4 specialist agents run concurrently (assumed working per locked decisions); if serial, file follow-up.
12. **OpenCode skill activation**: agent in a command that says "Load the `security` skill" actually invokes `skill({name:"security"})` — verify via monitor JSONL.
13. **Full chain (OpenCode)**: throwaway repo, run `/explore → /propose → /implement → /validate → /review-findings → /learn-from-reports → /ship → /validate-impl`. User-driven (per locked decision).
14. **Full chain (Claude)**: same throwaway repo or parallel — confirm dual-target setup didn't break Claude path.

## Architectural revision: hybrid agent-primary shape (2026-05-04)

Original plan ports 18 fat Claude command bodies 1:1 as OpenCode commands. Validation against OpenCode docs + user's existing `~/.config/opencode/agent/core/opencoder.md` shows this under-uses OpenCode idiom.

### OpenCode idiom (per docs)

- **Commands** = thin prompt-template shortcuts. Delegate via `agent:` and `subtask: true` frontmatter. Not orchestrators.
- **Primary agents** = stateful executors with scoped permissions, child sessions, Tab-switch UX, task-tool dispatch. Own multi-step workflows.
- **Subagents** = `@mention`-able / Task-invoked specialists.
- **AGENTS.md** = cross-cutting rules auto-loaded per session.

User's existing `opencoder` proves the pattern: one primary agent, 6-stage workflow, dispatches `ContextScout`/`TaskManager`/`CoderAgent`/`BatchExecutor`/`TestEngineer` via task tool. Spec-driven workflow needs the same shape — different state machine.

### Revised target shape (OpenCode side)

1. **New primary agent `SpecDriver`** (`agents/spec-driver.md`, OpenCode-only — no Claude twin). Owns spec-driven state: `specs/<feature>/`, `task-manager.sh`, gate ceiling, monitor JSONL, phase chain (`explore → propose → implement → validate → review-findings → learn-from-reports → ship → validate-impl`). Cross-phase state (config.yml handle, current task id, monitor file) lives in agent, not command bodies.
2. **Workflow slash commands shrink to ~10 lines** — `/explore`, `/propose`, `/implement`, `/validate`, `/review-findings`, `/learn-from-reports`, `/ship`, `/validate-impl`, `/pr-review`. Frontmatter: `agent: SpecDriver`, `subtask: true`. Body: phase hint + `$ARGUMENTS`.
3. **20 existing subagents port as-is** — already `mode: subagent` shape (Odium, config-inferencer, software-architect, code-reviewer, ultrathink-debugger, etc.). SpecDriver invokes via task tool. Parallel dispatch (validate Phase 2) happens inside SpecDriver, not from command body.
4. **AGENTS.md richer than CLAUDE.md** — centralizes content currently inlined across command bodies: KB prefix convention, gate-skip semantics, triple-gate rule, hook bypass policy, task state machine.
5. **Utility commands stay plain** (no agent wrapper): `/spec-status`, `/workflow-summary`, `/config`, `/bootstrap`, `/quick-ship`, `/continue-task`, `/research`. Pure utilities, no orchestration.

### Plan deltas

- **Placeholder grammar must support per-target body fork.** Claude target = full orchestration body (current plan). OpenCode target = thin agent-delegating stub. Add `{{TARGET_BODY:claude=...,opencode=...}}` block placeholder, or split source into `commands/<name>.claude.md` + `commands/<name>.opencode.md` for the 10 workflow commands. Utility commands remain single-source.
- **New artifact** — `agents/spec-driver.md` (OpenCode-only). Not rendered for Claude target.
- **Risk #1 dissolves** — `{{AGENT_DISPATCH_PARALLEL}}` parallel-from-command-body concern goes away; parallel dispatch lives inside SpecDriver agent body where state and permissions are scoped correctly.
- **Verification step added** — prototype SpecDriver on throwaway feature covering `/explore → /propose` only before expanding. Confirm subagent dispatch + monitor events work cleanly. If OpenCode's auto-delegation or child-session model fights the design, fall back to original 1:1 command port.

### Tradeoffs (why hybrid, not pure-agent or pure-command)

| Option | Pro | Con |
|---|---|---|
| 1:1 command port (original) | Smallest delta from Claude target; templated single-source clean | Fights OpenCode idiom; 200-line command bodies; wastes primary-agent UX, child sessions, scoped permissions |
| Pure agent restructure | Maximally idiomatic | Big rewrite; templated single-source breaks (Claude has no primary-agent equivalent); behavioral drift risk |
| **Hybrid (chosen)** | Idiomatic OpenCode side; thin commands still ~1:1 with Claude commands so `setup.sh` stays sane; reuses validated `opencoder` pattern; subagents port 1:1 | Requires SpecDriver authoring (new OpenCode-only artifact); placeholder grammar must fork command bodies by target |

## Risks

- **Dispatch prose capture**: `{{AGENT_DISPATCH_PARALLEL:...}}` placeholder must preserve multi-line prompts. Mitigation: renderer uses heredoc-style delimited blocks, not single-line sed.
- **Parallelism**: if OpenCode lacks parallel subagent spawn, `/validate` and `/review-findings` slow significantly. Detected during step 9; perf-hit fallback already accepted.
- **Description rewrite quality**: bad descriptions break OpenCode auto-delegation silently. Mitigation: each rewritten description gets a one-line "should trigger when:" comment for review.
- **Skill discoverability**: agents must call `skill({name})` to load full content; only name+description visible at session start. Mitigation: invest in tight skill descriptions (1–1024 chars, action-oriented); command bodies that need KB context include prose instruction "Load the `<name>` skill before proceeding."
- **Plugin path resolution**: `tool.execute.after` plugin needs cwd-relative spec resolution. Mitigation: use plugin context `directory` field (verified in docs).

---

## Discussion notes — 2026-05-19 (not decisions; open threads)

A grilling session reframed *why* this migration exists and surfaced open
questions. Nothing below is locked — these are conversation updates for the next
person (or future self) picking this up.

### Motivation (reframed)

Two distinct problems, not one:

1. **Leave Claude Code** — for the stated reasons: Anthropic-model token
   consumption/cost, and the heavy built-in workflow system prompts injected
   every session.
2. **Regain control of the workflow itself** — commands grew by accretion
   ("adding here and there"); several are now overloaded/huge; quality is
   unverified. This is *loss of control*, not size for its own sake.

Implication still under consideration: the problems may want **sequencing** —
de-bloat / regain control *first*, then port the smaller understood thing —
rather than this plan's current 1:1 dual-target port of the workflow as-is.
Open: this plan ports the bloat 1:1; that tension is unresolved.

### "In control" — working definition (discussed, not ratified)

Candidate ranking that felt right in conversation, for later validation:
**B > A > C** where —
- **B = predictable flow**: can draw the exact path a feature will take before
  running it.
- **A = comprehension**: can read any command/agent in one sitting and predict
  what it does/spawns.
- **C = trustworthy output**: ships correct work without full re-review.

### Fork space — identified, unresolved

Root of unpredictable flow: multiplicative axes decided at `/explore` step 0 —
`Tier{small,medium,large}` × `Track{feature,technical}` ×
`Branch{per-task,single-branch}` × `Mode{repo,vault}` ≈ **24 paths** (before
HITL/AFK and the audit reopen-cycle). Open question deferred by the user: which
forks survive (freeze to one path / collapse to ~2 axes / keep all + add a
dry-run resolver). Specifically flagged for later: is the `technical` track and
`single-branch` actually used, or speculative accretion?

### Runtime research (informational — does not change this plan's target)

Compared terminal agents on: custom commands, parallel subagents, per-tool-call
hooks, skills, multi-model/OpenRouter, observability, footprint.

- **"Pi Terminus" is not a product.** It is **Pi** (badlogic) — minimal TS
  agent, author rejects parallel subagents by design — likely conflated with
  Terminal Trove (directory site). Serious fork: **omp / oh-my-pi** (can1357,
  Rust single binary, MIT).
- **OpenCode** remains the only researched runtime that *natively* owns
  per-tool-call interception (`tool.execute.before/after`, `permission.ask`) —
  which is simultaneously the observability mechanism (tool call → JSONL) and
  the bypass guardrail. Native commands, parallel subagents, skills, OpenRouter.
- **omp/oh-my-pi**: lighter, MIT single binary, superior per-role model routing
  (direct token-cost lever) and broad programmatic observability — **but no
  first-class block-every-tool-call hook**, single-maintainer bus-factor.
- **Codex CLI**: good subagent concurrency knobs; hook = sandbox/approval policy
  only, no JSONL event log, OpenAI-biased multi-model.
- Crush / Goose / Gemini CLI / Aider: each fails ≥1 hard requirement
  (hooks, parallel subagents, or multi-provider).

Open trade-off (not resolved): **lightweight single binary vs hook fidelity**.
omp's per-role model routing directly attacks the token-cost pain that is
reason #1 for leaving Claude Code; OpenCode wins on native hook-based
observability + guardrail. If observability is reframed to come from the
runtime's own structured run log instead of a self-written JSONL hook, the
hook requirement weakens and the lightest tool could win. Unresolved.

