# Workflow Diagrams

Visual map of the spec-driven development workflow: slash commands, agent spawns, hooks, scripts, task state machine, and artifact flow. Read these alongside `onboarding.md` for prose context. Diagrams render inline on GitHub and in Mermaid-capable viewers.

**Legend**
- Solid arrow (`-->`) — automatic / auto-chained transition
- Dashed arrow (`-.->`) — human-gated transition (review, merge, decision)
- Subgraph groups: commands, agents, artifacts, hooks

---

## 1. Command Chain

The core auto-chain (`/implement` → `/validate` → `/review-findings` → `/learn-from-reports` → `/ship`) runs without user intervention between steps. Human gates appear only at PR merge, at finding review, and at rule-candidate review. Side commands (`/spec-status`, `/continue-task`, `/pr-review`, etc.) are invokable anytime.

```mermaid
graph LR
    subgraph Setup["One-time setup"]
        BOOT["/bootstrap"]
    end

    subgraph Core["Core spec-driven flow"]
        EXP["/explore"]
        PROP["/propose"]
        IMPL["/implement"]
        VAL["/validate"]
        REV["/review-findings"]
        LEARN["/learn-from-reports"]
        SHIP["/ship"]
    end

    subgraph Side["Side commands"]
        CONT["/continue-task"]
        STAT["/spec-status"]
        PRR["/pr-review"]
        QS["/quick-ship"]
        RES["/research"]
        WS["/workflow-summary"]
    end

    BOOT -.-> EXP
    EXP -.-> PROP
    PROP -.-> IMPL
    IMPL --> VAL
    VAL -->|findings| REV
    VAL -->|zero findings| LEARN
    REV -->|re-validate| VAL
    REV -->|skip| LEARN
    LEARN --> SHIP
    SHIP -.->|PR merged| IMPL

    CONT -.-> IMPL
    CONT -.-> VAL
    CONT -.-> REV
    CONT -.-> LEARN
    CONT -.-> SHIP
    STAT -.-> Core
    PRR -.-> SHIP
```

---

## 2. Task State Machine

Canonical source: `scripts/task-manager.sh:get_allowed_transitions()`. All status changes flow through `task-manager.sh set-status` — never edit task YAML directly.

```mermaid
stateDiagram-v2
    state "in-progress" as in_progress
    [*] --> blocked: deps exist
    [*] --> todo: no deps
    blocked --> todo: deps done (unblock)
    todo --> in_progress: /implement start
    in_progress --> implemented: code written
    implemented --> review: /validate (findings)
    implemented --> done: /validate (zero findings)
    review --> implemented: /review-findings (re-validate)
    review --> done: /review-findings (skip)
    done --> [*]: /ship PR merged
```

---

## 3. Validation Gates

`/validate` fans out five gates in parallel. Four are agent-driven (via `Agent` tool); the `testing` gate is deterministic (language tools only, no agent). All-gates rule: every gate must report `status: pass` before task eligible for `done`. Any finding → task moves to `review`.

```mermaid
graph TD
    V["/validate"] --> G1[security gate]
    V --> G2[code-quality gate]
    V --> G3[architecture gate]
    V --> G4[compliance gate]
    V --> G5[testing gate]

    G1 --> A1[Security Engineer + semgrep]
    G2 --> A2[code-quality-pragmatist + linters]
    G3 --> A3[Software Architect]
    G4 --> A4[claude-md-compliance-checker]
    G5 --> A5[language test/coverage tools]

    A1 --> R1[reports/NNN-security.yaml]
    A2 --> R2[reports/NNN-code-quality.yaml]
    A3 --> R3[reports/NNN-architecture.yaml]
    A4 --> R4[reports/NNN-compliance.yaml]
    A5 --> R5[reports/NNN-testing.yaml]

    R1 --> AGG{All gates pass?}
    R2 --> AGG
    R3 --> AGG
    R4 --> AGG
    R5 --> AGG
    AGG -->|yes| DONE[task: done]
    AGG -->|any findings| REVIEW[task: review]
```

---

## 4. Artifact Flow

Shows which command produces and consumes each artifact. Two knowledge-base layers (general + project) feed every command. Git branches fan out one PR per task into the feature integration branch.

```mermaid
graph TB
    subgraph Inputs
        CONV[conversation]
        PRD[prd.md]
    end

    subgraph Specs["specs/$FEATURE/"]
        SPEC[spec.md]
        DESIGN[design.md]
        TS[test-strategy.md]
        TASKS[tasks/NNN.md]
    end

    subgraph Validation
        REPORTS[reports/NNN-gate.yaml]
    end

    subgraph KB["Knowledge Base"]
        GKB[~/.claude/knowledge-base/ general]
        PKB[knowledge-base/ project]
    end

    subgraph Git
        FEAT[feat/$FEATURE]
        TBR[feat/$FEATURE/NNN-task]
        PR[task PR → feat/$FEATURE]
    end

    subgraph Monitor
        CTX[.monitor-context]
        JSONL[specs/$FEATURE/.monitor.jsonl]
    end

    CONV --> EX["/explore"]
    EX --> PRD
    PRD --> PP["/propose"]
    PP --> SPEC
    PP --> DESIGN
    PP --> TS
    PP --> TASKS

    TASKS --> IM["/implement"]
    GKB -.-> IM
    PKB -.-> IM
    IM --> TBR
    IM --> CTX
    IM --> JSONL

    TBR --> VA["/validate"]
    VA --> REPORTS
    REPORTS --> RF["/review-findings"]
    RF -.->|inline new rules| PKB
    REPORTS --> LFR["/learn-from-reports"]
    LFR -.->|mined new rules| PKB

    TBR --> SH["/ship"]
    SH --> PR
    PR --> FEAT
```

---

## 5. Command → Agent Spawns

One diagram per command. Solid arrow = always spawned. Dashed arrow = conditional (keyword/context-triggered or error-triggered). Agents listed only for commands that spawn them — other commands (`/bootstrap`, `/ship`, `/quick-ship`, `/spec-status`, `/continue-task`, `/research`, `/workflow-summary`) do not spawn agents directly. `/review-findings` spawns background sub-agents to apply accepted fix groups in parallel (not shown as a separate diagram — the agents are generic fix-appliers, not role-specialized).

### 5a. `/explore` — requirements clarification

```mermaid
graph LR
    EX["/explore"] -.->|after perspective Qs| UXR[UX Researcher]
    EX -.->|after security Q| SE[Security Engineer]
    EX -.->|backend kw| BA[Backend Architect]
    EX -.->|ui kw| UXA[UX Architect]
    EX -.->|scope| SA[Software Architect]
    EX -.->|feedback kw| FS[Feedback Synthesizer]
```

### 5b. `/propose` — spec + design + tasks

```mermaid
graph LR
    PR["/propose"] --> SE[Security Engineer]
    PR --> SA[Software Architect]
    PR --> SPM[Senior Project Manager]
    PR --> TSG[Test Strategist]
    PR -.->|backend kw| BA[Backend Architect]
    PR -.->|ui kw| UXA[UX Architect]
    PR -.->|ui kw| UID[UI Designer]
    PR -.->|ai kw| AIE[AI Engineer]
```

### 5c. `/implement` — task execution

```mermaid
graph LR
    IM["/implement"] --> CQP[code-quality-pragmatist]
    IM -.->|if test-strategy.md exists| TSG[Test Strategist]
    IM -.->|on error / test fail| UD[Ultrathink Debugger]
```

### 5d. `/validate` — validation gates (parallel)

```mermaid
graph LR
    VA["/validate"] --> SE[Security Engineer]
    VA --> CQP[code-quality-pragmatist]
    VA --> SA[Software Architect]
    VA --> CMC[claude-md-compliance-checker]
```

### 5e. `/pr-review` — PR comment handling

```mermaid
graph LR
    PRR["/pr-review"] --> CR[Code Reviewer]
```

---

## 6. Hooks

Hooks fire on tool events, orthogonal to commands. Block or monitor every tool call.

```mermaid
graph LR
    TOOL[Bash tool call] --> PRE[PreToolUse]
    STOP_EVT[Claude stop] --> STOPH[Stop]
    POST_EVT[any tool call] -.-> POST[PostToolUse<br/>unwired]

    PRE --> H1[block-git-hook-bypass<br/>blocks --no-verify / --no-gpg-sign]
    STOPH --> H2[block-dismissive-language<br/>blocks bypass / pre-existing phrases]
    STOPH --> H3[findings-persistence + auto-handoff<br/>prompt hook in settings.json]
    POST -.-> H4[monitor-tool-calls<br/>installed but not wired]
```

Notes:
- `scripts/monitor.sh` writes `specs/$FEATURE/.monitor.jsonl` via direct invocation from `/implement`, not a hook.
- `templates/settings.json` wires only `PreToolUse` (Bash) and `Stop`.
- `hooks/monitor-tool-calls.sh` is installed by `setup.sh` as a `PostToolUse` hook but not wired in `templates/settings.json` — pending task tracked in `specs/monitoring-enhancement/prd.md`. When wired, it logs `context_read`, `agent_invocation`, and `tool_call` events to `.monitor.jsonl` automatically.

---

## Key Invariants

- **Serial execution** — one task `in-progress` at a time
- **Auto-chain** — `/implement` drives `/validate` → `/review-findings` → `/ship` without re-prompting
- **All-gates** — all 5 validation gates must pass before `done`
- **Dual KB** — general (`~/.claude/knowledge-base/`) + project (`knowledge-base/`), project overrides general
- **One PR per task** — target is `feat/$FEATURE`, not `main`
- **Ground rules prefix** — `general:...` / `project:...` / unprefixed defaults to project
- **No YAML edits** — all status changes via `task-manager.sh`
- **No bypass** — PreToolUse hook blocks `--no-verify` / `--no-gpg-sign`

## Sources

- `commands/*.md` — command definitions and agent spawns
- `agents/**/*.md` — agent contracts
- `hooks/*.sh` — hook triggers
- `scripts/task-manager.sh` — state machine
- `scripts/monitor.sh` — event logging
- `CLAUDE.md` — design decisions
