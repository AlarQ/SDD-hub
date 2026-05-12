# PRD: Agentic Workflow Foundation

## Problem

Current dev-workflow uses slash commands as orchestrators that spawn specialist agents inline. Three pains compound across a session:

1. **Token bloat.** Each command pumps file reads + advisory-agent outputs into the main context window. Multi-command sessions balloon.
2. **Reuse friction.** KB rule loading, gate execution + parsing, findings accept/reject flow, and advisory rendering all repeat across commands. Some logic lives in scripts; some is duplicated in command markdown.
3. **Hard to add new workflow variants.** Tech-debt, refactor, and audit/compliance flows need different gate sets and shapes; today every variant duplicates the command tree.

A fourth driver pushed scope: **two-runtime support**. The same workflow must run in both Claude Code (flat tree: command → agents) and Opencode (deep tree: primary → orchestrators → workers, verified in `~/.config/opencode/agent/core/opencoder.md`). Claude Code's Agent tool effectively caps at 2 levels of delegation; Opencode's `task()` supports arbitrary depth. A single architecture must map cleanly to both.

## Goal

Move the workflow "as close to agentic as possible" by:

- Pairing each command with a **main agent** (1:1 mapping) that owns the phase's heavy thinking and user Q&A in an isolated context window.
- Slimming each command file to a **thin conductor** (~30–60 lines) that handles deterministic preflight + parallel advisory fan-out + main-agent spawn.
- Mirroring the same logical phases in Opencode as a **single primary `workflow-orchestrator`** with a depth-3 subagent tree.
- Sharing all agent prompt bodies, the gate registry, KB, spec layout, task state machine, and monitor events across both flavors.

Foundation only. Defer new workflow variants (refactor/audit/tech-debt), KB fragment retrieval, and Opencode-specific parallelism optimizations to follow-up specs.

## Users

Primary user: the developer (single-operator) running specs through the workflow. Benefits:

- **Shorter main context** → longer sessions before compaction, lower token spend.
- **Faster iteration on new workflow variants** → variants compose existing main agents + alternative gate sets without rewriting command trees.
- **Single mental model across runtimes** → same agent definitions and artifacts whether running in Claude Code or Opencode.

## Shortest path to value

1. Pilot conversion of `/explore` to conductor + `explore-agent` proves the pattern.
2. Roll same shape across the rest of the command set (≈11 commands).
3. Build Opencode `workflow-orchestrator` reusing the same agent bodies.
4. Wire `setup.sh --claude --opencode --all` for dual install.

## Scope

### In scope

- New main agent per command: `explore-agent`, `propose-agent`, `implement-agent`, `validate-agent`, `pr-review-agent`, `review-findings-agent`, `learn-agent`, `impl-audit-agent`, `ship-agent`, `fix-agent`, `spec-reviewer-agent`.
- Conductor rewrites of corresponding command markdown files (slimmed to orchestration only).
- Opencode `workflow-orchestrator` primary agent + phase orchestrator subagents (`explore-orchestrator`, `propose-orchestrator`, `implement-orchestrator`, `validate-orchestrator`, `ship-orchestrator`, `fix-orchestrator`).
- Split agent file layout: `agents/<role>.body.md` + `agents/<role>.claude.yml` + `agents/<role>.opencode.yml`. Setup script merges per target.
- `scripts/spawn-helpers.sh` exposing `wf_spawn_main_agent`, `wf_spawn_advisory_parallel`, `wf_inject_context`.
- `docs/agent-orchestration.md` documenting the conductor contract and KB-injection convention.
- `tests/test-agent-sync.sh` verifying installed agent sets in both targets match expectations and shared bodies hash-match.
- `setup.sh` flags: `--claude`, `--opencode`, `--all` (default).
- Update `docs/workflow-diagram.md` Mermaid diagrams for both flavors.

### Out of scope (deferred follow-up specs)

- New workflow variants (refactor, audit/compliance, tech-debt).
- KB fragment retrieval (QMD search, per-rule chunking) — only formalize the injection contract.
- Per-task dynamic agent selection beyond current spec-level `agents:` + per-task overrides.
- Opencode BatchExecutor-style parallel coder dispatch.

## Key decisions

- **Sub-spawn collision** (agents-can't-spawn-agents in Claude Code) → **conductor pattern**: command does parallel advisory fan-out, then spawns main agent with advisory outputs in initial prompt. Best isolation, keeps specialists reusable.
- **Q&A ownership** → main agent owns conversation via `AskUserQuestion`. Truly isolates conversational context from command shell.
- **Granularity** → 1:1 main agent per command.
- **Migration** → all commands converted in this single spec; no per-command staged rollout.
- **Variant strategy** (future-facing) → hybrid: core conductor commands + variant-specific add-ons later.
- **Agent file sync** → single body file + per-flavor frontmatter file. Setup script merges.
- **Opencode entry shape** → single primary `workflow-orchestrator`; phase orchestrators are subagents.

## Architecture

### Claude flavor — flat conductor (2-level cap)

Slash commands stay user-invoked. Each command is a thin conductor that fans out advisory specialists in parallel, then spawns its paired main agent with the advisories' outputs in its initial prompt. Main agent owns Q&A. No deeper nesting — Claude Code's Agent tool caps practical delegation at 2 levels.

```mermaid
graph TD
    USER([user])
    subgraph Conductor["/explore (conductor .md, ~30-60 lines)"]
        PRE[preflight<br/>config-loader<br/>tier-check]
        FANOUT{parallel fan-out}
        MAIN[explore-agent<br/>owns AskUserQuestion]
        EMIT[emit monitor events<br/>print next-command hint]
    end
    UX[design-ux-researcher]
    SEC[engineering-security-engineer]
    ARCH[engineering-software-architect]

    USER -->|/explore agentic-foundation| PRE
    PRE --> FANOUT
    FANOUT --> UX
    FANOUT --> SEC
    FANOUT --> ARCH
    UX -->|advisory bullets| MAIN
    SEC -->|advisory bullets| MAIN
    ARCH -->|advisory bullets| MAIN
    MAIN <-->|Q&A loop| USER
    MAIN -->|PRD + config.yml| EMIT
    EMIT -->|"/propose <slug>"| USER

    classDef cmd fill:#1f6feb20,stroke:#1f6feb;
    classDef agent fill:#8957e520,stroke:#8957e5;
    class PRE,FANOUT,EMIT cmd;
    class MAIN,UX,SEC,ARCH agent;
```

### Opencode flavor — deep tree (N-level)

Single primary `workflow-orchestrator` replaces all slash commands. Phase orchestrators are subagents that spawn worker specialists via `task()`. Verified in `~/.config/opencode/agent/core/opencoder.md` — OpenCoder → BatchExecutor → CoderAgent is a real 3-level path. Same logical phases as Claude, deeper isolation.

```mermaid
graph TD
    USER([user])
    PRIMARY[workflow-orchestrator<br/>mode: primary]
    EXPO[explore-orchestrator]
    PROPO[propose-orchestrator]
    IMPLO[implement-orchestrator]
    VALO[validate-orchestrator]
    SHIPO[ship-orchestrator]

    UX2[ux-researcher]
    SEC2[security-engineer]
    ARCH2[software-architect]
    SA2[software-architect]
    TS[test-strategist]
    PM[senior-project-manager]
    CODER[coder-agent<br/>parallel batch]
    UD[ultrathink-debugger]
    CQ[code-quality-pragmatist]
    GATES[gate-agents<br/>security / quality / arch / compliance]
    ODIUM2[odium]

    USER --> PRIMARY
    PRIMARY --> EXPO
    PRIMARY --> PROPO
    PRIMARY --> IMPLO
    PRIMARY --> VALO
    PRIMARY --> SHIPO

    EXPO --> UX2
    EXPO --> SEC2
    EXPO --> ARCH2
    PROPO --> SA2
    PROPO --> TS
    PROPO --> PM
    IMPLO --> CODER
    IMPLO --> UD
    IMPLO --> CQ
    VALO --> GATES
    VALO --> ODIUM2

    classDef primary fill:#d29922,stroke:#d29922,color:#000;
    classDef orch fill:#1f6feb20,stroke:#1f6feb;
    classDef worker fill:#8957e520,stroke:#8957e5;
    class PRIMARY primary;
    class EXPO,PROPO,IMPLO,VALO,SHIPO orch;
    class UX2,SEC2,ARCH2,SA2,TS,PM,CODER,UD,CQ,GATES,ODIUM2 worker;
```

### Side-by-side: same logical phases, different runtime shape

```mermaid
graph LR
    subgraph Claude["Claude Code — flat (2-level)"]
        direction TB
        C_USER([user]) -->|"/explore"| C_CMD[explore.md<br/>conductor]
        C_CMD -.parallel.-> C_UX[ux-researcher]
        C_CMD -.parallel.-> C_SEC[security-engineer]
        C_CMD --> C_MAIN[explore-agent]
        C_UX --> C_MAIN
        C_SEC --> C_MAIN
    end

    subgraph Shared["Shared core (single source)"]
        direction TB
        BODY[agents/&lt;role&gt;.body.md<br/>prompt body]
        CYML[agents/&lt;role&gt;.claude.yml<br/>Claude frontmatter]
        OYML[agents/&lt;role&gt;.opencode.yml<br/>Opencode frontmatter]
        GATES_R[gates.yml registry]
        KB[knowledge-base/]
        SPEC[specs/&lt;feature&gt;/]
        TM[task-manager.sh]
        MON[monitor.sh]
        BODY --- CYML
        BODY --- OYML
    end

    subgraph Opencode["Opencode — deep tree (N-level)"]
        direction TB
        O_USER([user]) --> O_PRIM[workflow-orchestrator<br/>primary]
        O_PRIM --> O_EXPO[explore-orchestrator]
        O_EXPO --> O_UX[ux-researcher]
        O_EXPO --> O_SEC[security-engineer]
        O_EXPO --> O_MAIN[explore-agent<br/>reused as worker]
    end

    Claude -.uses.-> Shared
    Opencode -.uses.-> Shared

    classDef sharedNode fill:#3fb95020,stroke:#3fb950;
    classDef claudeNode fill:#1f6feb20,stroke:#1f6feb;
    classDef opencodeNode fill:#d2992220,stroke:#d29922;
    class BODY,CYML,OYML,GATES_R,KB,SPEC,TM,MON sharedNode;
    class C_USER,C_CMD,C_UX,C_SEC,C_MAIN claudeNode;
    class O_USER,O_PRIM,O_EXPO,O_UX,O_SEC,O_MAIN opencodeNode;
```

**Key contrast.** Claude command file owns orchestration (fan-out + spawn order). Opencode lifts that responsibility into the `workflow-orchestrator` primary agent — no `.md` slash command needed because the primary agent itself can spawn subagents via `task()`. Both flavors invoke the same body-file prompts; only frontmatter and entry shape differ.

## Ground rules (applicable)

- `general:style/general.md` — bash/markdown style.
- `general:architecture/general.md` — module boundaries, dependency direction.
- `general:testing/principles.md` — test responsibility per task.
- `project:` (any newly added rules during /review-findings).

## Agent Insights (Explore Phase)

Advisory agents were skipped during this exploration session — discussion-mode covered architectural angles directly with the user. Advisory passes (Software Architect, Security Engineer, UX Researcher) deferred to `/propose` where ADRs and trade-off analyses are formally produced.

## Open questions to resolve in /propose

- Exact tool-grant matrix for each main agent (which agents need Edit, Bash, Agent, AskUserQuestion).
- Concrete prompt-body skeleton template (shared shape so all main agents are consistent).
- Whether `scripts/spawn-helpers.sh` should be sourced or invoked as subshell helpers.
- Test harness shape for verifying conductor→agent contracts (dry-run mode?).
- Backwards-compat strategy for in-flight specs created under current (non-conductor) commands.

## Verification target (high-level)

- All existing bash tests still pass unchanged.
- A full feature run through `/explore → /propose → /implement → /validate → /ship` works end-to-end on both Claude and Opencode flavors.
- Sync test confirms shared agent bodies are byte-identical across installs.
- Monitor JSONL captures phase transitions and agent spawns for both flavors.

## Next command

`/propose agentic-foundation`
