# Workflow Diagrams

Visual map of the spec-driven development workflow: slash commands, agent spawns, hooks, scripts, task state machine, and artifact flow. Read these alongside `onboarding.md` for prose context. Diagrams render inline on GitHub and in Mermaid-capable viewers.

**Legend**
- Solid arrow (`-->`) — user-invoked next command (printed as a "Run `/foo`" hint at the previous command's exit)
- Dashed arrow (`-.->`) — human-gated transition (review, merge, decision)
- Subgraph groups: commands, agents, artifacts, hooks

---

## 1. Command Chain

Each command runs only when the user invokes it. There is no auto-chaining between slash commands — every command terminates after its own work and prints the next command to run. The per-task sequence is `/implement` → `/validate` → (`/review-findings` if findings) → `/learn-from-reports` → `/ship`. Human gates appear at finding review, rule-candidate review, and PR merge. Side commands (`/spec-status`, `/continue-task`, `/pr-review`, etc.) are invokable anytime.

After `/propose` finishes, the user runs `/validate-spec` — a pre-implementation spec-coherence gate wrapping the `Spec Reviewer` agent. Findings flow through `/review-findings` (also user-invoked) and patch spec/design/tasks (not code). `/implement` is blocked until `specs/<feature>/reports/spec-review.yaml` has `status: pass`.

When the last task in a spec transitions to `done`, `task-manager.sh` emits a `spec_last_task_done` event. `/implement` surfaces this event and instructs the user to run `/validate-impl` (implementation-completion audit via Karen, per ADR-008 of the configurable-workflow spec). Audit verdict `complete` marks the spec shipped; verdict `reopen` routes through `/review-findings`, where each accepted `missing`/`partial` FR finding invokes `task-manager.sh create-followup` to auto-create a `status: todo` follow-up task (FR id validated against `spec.md`, ground_rules inherited from the spec). When the follow-up tasks reach `done`, the T015 detector re-fires `spec_last_task_done` if the user has appended a `spec_reaudit_requested` sentinel via `/validate-impl --reaudit` (event log is append-only — prior `spec_audit_done` is never mutated). Cycle converges when verdict = `complete`.

Under `validate_scope: per-spec` (ADR-007), per-task `/validate` is skipped and the gate union runs once inside `/validate-impl`.

`/explore` step 0 sets `WF_SPEC_TIER` (`small | medium | large`). Tier forks the flow: `small` skips `/validate-spec`, Phase-2 agent gates, and `/validate-impl`; `medium` skips `/validate-spec`; `large` is the unchanged full flow. `/implement` step 0 runs `tier-check.sh`; on breach (exit 9) the user picks `Continue` (proceed) or `Abort` → `/promote-tier` → re-runs `/propose` at the next tier (preserved `done`/`implemented` tasks remain).

```mermaid
graph LR
    subgraph Setup["One-time setup"]
        BOOT["/bootstrap"]
    end

    subgraph Core["Core spec-driven flow"]
        EXP["/explore"]
        TIER{WF_SPEC_TIER}
        PROP["/propose"]
        VSPEC_PRE["/validate-spec"]
        IMPL["/implement"]
        TCHK{tier-check.sh}
        PROMO["/promote-tier"]
        VAL["/validate"]
        REV["/review-findings"]
        LEARN["/learn-from-reports"]
        SHIP["/ship"]
    end

    subgraph Audit["Implementation-completion audit"]
        VIMPL["/validate-impl"]
        KAREN["Karen agent"]
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
    EXP --> TIER
    TIER -->|small / medium / large| PROP
    PROP -->|small: skip| IMPL
    PROP -->|medium / large| VSPEC_PRE
    VSPEC_PRE -->|findings| REV
    VSPEC_PRE -->|pass| IMPL
    IMPL --> TCHK
    TCHK -->|no breach| VAL
    TCHK -.->|breach: Continue| VAL
    TCHK -.->|breach: Abort| PROMO
    PROMO -.-> PROP
    VAL -->|findings| REV
    VAL -->|zero findings| LEARN
    VAL -.->|small: lint+tests only| LEARN
    VAL -.->|scope=per-spec: skip| LEARN
    REV -->|re-validate| VAL
    REV -->|skip| LEARN
    LEARN --> SHIP
    SHIP -.->|PR merged| IMPL
    SHIP -.->|medium/large: last task done| VIMPL
    SHIP -.->|small: skip audit| Core
    VIMPL --> KAREN
    KAREN --> VIMPL
    VIMPL -->|verdict=complete| Core
    VIMPL -.->|verdict=reopen| REV
    REV -.->|accept missing/partial FR<br/>create-followup| IMPL

    CONT -.-> IMPL
    CONT -.-> VAL
    CONT -.-> REV
    CONT -.-> LEARN
    CONT -.-> SHIP
    STAT -.-> Core
    PRR -.-> SHIP
```

### `/fix` — bug-fix flow

Standalone entry. Bypasses `/explore`, `/propose`, `/validate-spec`, `/validate-impl`, and the tier system. Artifact: `specs/fixes/<slug>/fix.md`.

```mermaid
graph LR
    FIX["/fix &lt;slug&gt;"] --> REPRO[BDD repro]
    REPRO --> UD[ultrathink-debugger]
    UD --> FIXMD[write fix.md<br/>Root Cause + Fix Plan + Regression Test]
    FIXMD --> PRE[pre-fix test<br/>must FAIL]
    PRE --> APPLY[apply fix]
    APPLY --> POST[regression test<br/>must PASS]
    POST --> GATES[lint + ground-rule-matched gates<br/>Phase-2 agents skipped unless<br/>auth/crypto/migrations in diff]
    GATES --> SH["/ship (PR title: fix:)"]
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

`/validate` fans out gates in parallel. Four are agent-driven (via `Agent` tool); the `testing` gate is deterministic (language tools only, no agent). All-gates rule: every gate must report `status: pass` before task eligible for `done`. Any finding → task moves to `review`.

**Phase 1** computes the effective gate set as `WF_SPEC_GATES ∩ language-applicable gates from gates.yml` (ceiling intersection). Gates outside the intersection emit a `gate_skip` event and are not run.

**Phase 2** reads the agent list from `WF_SPEC_AGENTS_VALIDATE` (set by config.yml) — not a hardcoded list. Each entry spawns one agent.

```mermaid
graph TD
    V["/validate"] --> CFG0{Step 0: load config.yml}
    CFG0 -->|missing → exit 4| STOP_V[stop]
    CFG0 -->|loaded| CEIL["Phase 1: WF_SPEC_GATES ∩ gates.yml applicable gates"]
    CEIL -->|skipped gates| SKIP[gate_skip event]
    CEIL -->|effective gates| AGT["Phase 2: agents from WF_SPEC_AGENTS_VALIDATE"]

    AGT --> G1[security gate]
    AGT --> G2[code-quality gate]
    AGT --> G3[architecture gate]
    AGT --> G4[compliance gate]
    AGT --> G5[testing gate]

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
        SNAP[.monitor-context-snapshot]
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
    IM -->|step 6a: after branch creation| SNAP

    TBR --> VA["/validate"]
    VA --> REPORTS
    REPORTS --> RF["/review-findings"]
    RF -.->|inline new rules| PKB
    REPORTS --> LFR["/learn-from-reports"]
    LFR -.->|mined new rules| PKB

    TBR --> SH["/ship"]
    SNAP -.->|drift check| SH
    SH --> PR
    PR --> FEAT
```

---

## 5. Command → Agent Spawns

One diagram per command. Solid arrow = always spawned. Dashed arrow = conditional (keyword/context-triggered or error-triggered). Agents listed only for commands that spawn them — other commands (`/bootstrap`, `/ship`, `/quick-ship`, `/spec-status`, `/continue-task`, `/research`, `/workflow-summary`) do not spawn agents directly. `/review-findings` spawns background sub-agents to apply accepted fix groups in parallel (not shown as a separate diagram — the agents are generic fix-appliers, not role-specialized).

### 5a. `/explore` — requirements clarification

Step 0 runs before any perspective questions: the `config-inferencer` agent drafts `config.yml` (gates + agents-per-phase) from repo signal files. User approves (single key) or edits via `/config`. `config.yml` is written before the normal explore flow begins.

```mermaid
graph LR
    EX["/explore"] --> S0{Step 0: config-inferencer}
    S0 --> CI[config-inferencer agent]
    CI --> SUMMARY[one-screen summary\ngates + agents-per-phase]
    SUMMARY -.->|approve| WRITE[write config.yml\nemit config_inferred + config_approved]
    SUMMARY -.->|edit| CFG["/config override"]
    CFG --> WRITE
    WRITE --> PERSP[perspective questions]
    PERSP -.->|after perspective Qs| UXR[UX Researcher]
    PERSP -.->|after security Q| SE[Security Engineer]
    PERSP -.->|backend kw| BA[Backend Architect]
    PERSP -.->|ui kw| UXA[UX Architect]
    PERSP -.->|scope| SA[Software Architect]
    PERSP -.->|feedback kw| FS[Feedback Synthesizer]
    S0 -.->|inferencer timeout| MANUAL[manual entry prompt]
```

### 5b. `/propose` — spec + design + tasks

```mermaid
graph LR
    PR["/propose"] --> CFG0{Step 0: load config.yml}
    CFG0 -->|missing → exit 4| STOP_PR[stop]
    CFG0 -->|loaded| SE[Security Engineer]
    CFG0 -->|loaded| SA[Software Architect]
    CFG0 -->|loaded| SPM[Senior Project Manager]
    CFG0 -->|loaded| TSG[Test Strategist]
    PR -.->|backend kw| BA[Backend Architect]
    PR -.->|ui kw| UXA[UX Architect]
    PR -.->|ui kw| UID[UI Designer]
    PR -.->|ai kw| AIE[AI Engineer]
```

### 5c. `/implement` — task execution

```mermaid
graph LR
    IM["/implement"] --> CFG0{Step 0: load config.yml}
    CFG0 -->|missing → exit 4| STOP_IM[stop]
    CFG0 -->|loaded| CQP[code-quality-pragmatist]
    IM -.->|if test-strategy.md exists| TSG[Test Strategist]
    IM -.->|on error / test fail| UD[Ultrathink Debugger]
    IM -->|step 6a: after branch creation| SNAP[.monitor-context-snapshot]
```

### 5d. `/validate` — validation gates (parallel)

```mermaid
graph LR
    VA["/validate"] --> CFG0{Step 0: load config.yml}
    CFG0 -->|missing → exit 4| STOP_VA[stop]
    CFG0 -->|loaded| CEIL["WF_SPEC_GATES ∩ gates.yml ceiling"]
    CEIL -->|WF_SPEC_AGENTS_VALIDATE| SE[Security Engineer]
    CEIL -->|WF_SPEC_AGENTS_VALIDATE| CQP[code-quality-pragmatist]
    CEIL -->|WF_SPEC_AGENTS_VALIDATE| SA[Software Architect]
    CEIL -->|WF_SPEC_AGENTS_VALIDATE| CMC[claude-md-compliance-checker]
```

### 5e. `/pr-review` — PR comment handling

```mermaid
graph LR
    PRR["/pr-review"] --> CFG0{Step 0: load config.yml}
    CFG0 -->|missing → exit 4| STOP_PRR[stop]
    CFG0 -->|loaded| CR[Code Reviewer]
```

### 5f. `/validate-spec` — pre-implementation spec coherence

```mermaid
graph LR
    VSPEC["/validate-spec"] --> SR[Spec Reviewer]
```

### 5g. `/validate-impl` — implementation-completion audit

```mermaid
graph LR
    VIMPL["/validate-impl"] --> KAREN[Karen]
```

### 5h. `/review-findings` — finding triage

```mermaid
graph LR
    RF["/review-findings"] --> CFG0{Step 0: load config.yml}
    CFG0 -->|missing → exit 4| STOP_RF[stop]
    CFG0 -->|loaded| TRIAGE[group + triage findings]
```

### 5i. `/ship` — commit, push, PR

```mermaid
graph LR
    SH["/ship"] --> CFG0{Step 0: load config.yml}
    CFG0 -->|missing → exit 4| STOP_SH[stop]
    CFG0 -->|loaded| DRIFT{snapshot drift check}
    DRIFT -->|.monitor-context-snapshot vs current config| DRIFT_DEC{drift detected?}
    DRIFT_DEC -->|yes → stop| STOP_DRIFT[stop]
    DRIFT_DEC -->|no| COMMIT[commit / push / PR]
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
- **Per-task sequence** — `/implement` → `/validate` → (`/review-findings` if findings) → `/learn-from-reports` → `/ship`, each invoked explicitly by the user
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
