---
name: configurable-workflow
status: proposed
---

# Spec — Configurable Workflow

## Summary

Externalize "which gates/agents run" and "where specs live" into YAML config. LLM curates per-spec at birth via a `config-inferencer` agent; user approves. Phase structure and ship mechanics stay hardcoded — only gate/agent *selection* is pluggable inside the existing skeleton. Replaces four symptoms (wrong gates fire, spec sprawl, agent mismatch, rigidity) with one config layer.

See `prd.md` for full problem framing and rationale.

## Terminology

**Ceiling** (a.k.a. **eligible set**) — the spec's eligible-gate set: the union of gate IDs listed in `specs/<feature>/config.yml` `gates:`. Acts as an upper bound; no gate outside this set runs for this spec. "Ceiling" and "eligible set" are strict aliases — the same union from `config.yml gates:`.

**Effective set** — the per-task intersection result: `ceiling ∩ gates-applicable-to-ground_rules`. This is the set actually executed for a given task.

**Terminology discipline:** use **ceiling** in configuration docs and schema references; use **effective set** in audit reports, error messages, and per-task output; never swap the two. Do not introduce new aliases ("gate pool", "ID allowlist", "ceiling intersection") — those are stale wording and must be normalized to the two canonical terms above.

**Per-task execution** — computes the **effective set** (ceiling ∩ gates applicable to the task's `ground_rules`; language + category match). Computed fresh each task.

**Per-spec execution** — for each task, compute (ceiling ∩ task-applicable gates); take the union of those sets across all tasks; execute each gate once against the cumulative diff (branch-point → HEAD). Gates that would have been skipped per-task due to scope=per-spec are not double-counted.

Cross-references: FR-7 (per-task), FR-14 (validate_scope field), FR-15 (/validate-impl union execution).

## Functional Scope

### FR-1: Repo Config (`.workflow.yml`)

Single file at repo root with three fields:

```yaml
spec_storage: specs/              # path where specs live
gate_pool: knowledge-base/gates.yml
agent_pool: ~/.claude/agents
```

File is **required** for any active invocation (phase commands, monitor, task-manager, pre-commit hook). Missing file → loader exit 2 with explicit error naming the repo root and instructing the user to run `/bootstrap`. Per-field defaults apply only **within** a present file — a missing field inside the file resolves to its default (`spec_storage: specs/`, others from install layout). Loader walks up from CWD to find it — does not require running from repo root.

### FR-2: Gate Registry (`knowledge-base/gates.yml`)

Canonical deterministic-gate list:

```yaml
gates:
  - id: rust-clippy
    command: "cargo clippy -- -D warnings"
    applies_to: [rust]
    category: lint
    blocking: true
  - id: semgrep-security
    command: "semgrep --config auto"
    applies_to: [any]
    category: security
    blocking: true
```

`applies_to` tags bind gate to language(s) or `[any]` for cross-cutting. `validation_tools` frontmatter in `knowledge-base/languages/*.md` becomes display-only after this spec ships.

### FR-3: Spec Config (`specs/<feature>/config.yml`)

Per-spec file written during `/explore`. Two sections:

```yaml
tags: [api, auth]
gates:
  - rust-clippy
  - semgrep-security
agents:
  explore:    [design/ux-researcher, engineering/security-engineer]
  propose:    [engineering/software-architect]
  implement:  [code-quality-pragmatist]
  validate:   [engineering/security-engineer, code-quality-pragmatist]
  pr-review:  [engineering/code-reviewer]
```

Agent IDs are **fully qualified** (`<category>/<name>` or bare `<name>` for root-level agents). Resolution rule and full grammar: see `design.md §Backend Design §Schemas §Agent ID grammar and resolution`.

`config.yml` is **required** for any spec created after this feature ships. Missing file on active processing paths (`/propose`, `/implement`, `/validate`, `/pr-review`, `/review-findings`, `/validate-impl`, `/ship`) → fail closed with explicit error naming the spec and expected path. No hardcoded-default fallback.

### FR-4: Config Inferencer Agent

New agent at `agents/engineering/engineering-config-inferencer.md` (ID: `engineering/config-inferencer`). Inputs: repo signal files (`Cargo.toml`, `package.json`, `go.mod`, `requirements.txt`, etc.), `gates.yml`, `agents/` directory listing, spec description/PRD. Output: draft `config.yml` matching the schema above.

### FR-5: `/explore` Step 0

Before normal explore flow:
1. Spawn `config-inferencer` with spec description.
2. Render one-screen summary: chosen gates + agents-per-phase + reasoning.
3. Accept single-key approval OR invoke `/config` for manual override.
4. Write `specs/<feature>/config.yml`.
5. Emit `config_inferred` and `config_approved` monitor events.

### FR-6: Phase Commands Read Spec Config

`/propose`, `/implement`, `/validate`, `/pr-review` read agent list from `config.yml` (the `agents` map keys are ∈ {`explore`, `propose`, `implement`, `validate`, `pr-review`} — see design.md §Backend Design §specs/<feature>/config.yml). Missing file → fail closed (loader exit 4, see FR-10). No hardcoded-default fallback. Note: `/review-findings` is **not** a consumer of the `agents` map; it is wired through other FRs (e.g. spec-audit report handling, T017) and does not spawn phase agents.

### FR-7: `/validate` Ceiling Semantics

Executes **intersection** of spec-eligible gates (from `config.yml`) ∩ gates applicable to task `ground_rules` (language + category match). Task `ground_rules` remains authoritative for what applies; spec config is a ceiling that restricts eligibility. Skipped gates emit `gate_skip` monitor events.

### FR-8: Path Resolution Refactor

`scripts/monitor.sh`, `scripts/task-manager.sh`, `scripts/pre-commit-hook.sh` walk up from CWD to find `.workflow.yml`, resolve `spec_storage`, then scan from there. Fall back to hardcoded `specs/` until E2E green (dogfood safety).

### FR-9: Monitor Event Categories

`scripts/monitor.sh` accepts new event categories. Existing categories unchanged. Ownership by task:

| Category | Added by |
|---|---|
| `config_inferred` | T003 |
| `config_approved` | T003 |
| `agent_spawn` | T003 |
| `gate_skip` | T003 |
| `spec_audit_start` | T014 |
| `spec_audit_done` | T014 |
| `spec_complete` | T015 |
| `spec_reopened` | T015 |
| `spec_last_task_done` | T015 |
| `spec_reaudit_requested` | T017 |

Each task that adds categories must also extend `monitor.sh`'s closed allowlist in the same PR.

### FR-10: Config Loader Script

New `scripts/config-loader.sh`:
- Walks up for `.workflow.yml`
- Single `timeout 5 yq` parse per invocation
- Exports `WF_SPEC_STORAGE`, `WF_GATE_POOL`, `WF_AGENT_POOL` env vars
- Fails closed on parse error, timeout, or missing file (with defaults where safe)
- Must NOT source `monitor.sh` (circular dep risk)

### FR-11: `/config` Command

New `commands/config.md`. Edits or regenerates `specs/<feature>/config.yml` post-creation. Re-runs inferencer on demand.

### FR-12: `/bootstrap` Generates `.workflow.yml`

`/bootstrap` writes starter `.workflow.yml` at repo root (alongside project KB). Must work on **existing** repos, not only fresh ones — existing repos are the primary target.

**Behavior:**

- Fresh repo (no `.workflow.yml`): write starter file from `templates/workflow.yml.template` with defaults. Exit 0.
- Existing `.workflow.yml` present: **no-op + print current config, exit 0**. No modification without an explicit flag.
- `/bootstrap --force`: show diff against template defaults, ask single-key confirmation, then overwrite. Refuses when target path is a symlink (security — writer never follows symlinks into untrusted locations).
- `/bootstrap --repair`: regenerate only missing fields, preserve existing values. Never overwrites a present field.

Writer touches only `.workflow.yml`. Other repo files untouched. Idempotent: second run on a repo with `.workflow.yml` is a no-op — the file is not opened for write and `mtime` is unchanged (observable property, not a byte-equality claim).

### FR-13: TUI Additions — **DEFERRED**

Postponed pending TUI-vs-web-UI decision. See `DEFERRED.md`. FR number reserved so downstream cross-references (if any) remain stable; no TUI work ships in this spec.

### FR-14: `validate_scope` Config Field

Adds gate **cadence** control on top of FR-7 gate *selection*. Small features (≤5 tasks) can skip per-task validation entirely and rely on the spec-level audit.

`.workflow.yml` (repo default):

```yaml
validate_scope: per-task       # per-task | per-spec | both
```

`specs/<feature>/config.yml` (optional override):

```yaml
validate_scope: per-spec
```

Semantics:

| Mode | `/validate` per task | `/validate-impl` at last-task `done` |
|---|---|---|
| `per-task` (default) | runs | runs |
| `per-spec` | skipped in `/implement` auto-chain (emit `gate_skip` with `reason=scope=per-spec`) | runs, executes **union** of spec-eligible gates |
| `both` | runs | runs |

Validation: enum allowlist. Unknown value → fail closed (loader exit 2). Missing field → `per-task`. Loader exports `WF_VALIDATE_SCOPE`.

### FR-15: `/validate-impl` Command + Karen Wrapper

New `commands/validate-impl.md`. Runs once when all spec tasks reach `done`. Reuses existing **Karen agent** (`agents/karen.md`) unchanged — wrapper prompt at the call-site supplies spec-specific context.

Steps:

1. `source config-loader.sh --spec <feature>` → loads ceiling, scope, agents.
2. If `validate_scope ∈ {per-spec, both}`: execute **union** of spec-eligible gates (FR-2 `applies_to` filter ∩ FR-3 spec ceiling) against the spec's cumulative diff (first task branch-point → HEAD). **Gate-failure path:** if any blocking gate in the union exits non-zero, the audit report verdict is forced to `reopen` AND Karen is still spawned — the wrapper prompt includes the failing-gate output as additional evidence alongside the Karen inputs in step 3. Non-blocking gate failures are recorded but do not force `reopen`.
3. Spawn Karen with a wrapper prompt containing:
   - Parsed FR list from `specs/<feature>/spec.md` (every `### FR-N:` heading).
   - `specs/<feature>/prd.md` IN/OUT scope.
   - Task list with final statuses.
   - Report paths under `specs/<feature>/reports/`.
   - Git diff range (branch-point → HEAD).
   - Explicit instruction: produce an FR × status matrix (`implemented | partial | missing`), list orphan code not traceable to any FR, flag over-engineering.
4. Write Karen's report to `specs/<feature>/reports/spec-audit-<ISO8601>.md`.
5. Emit `spec_audit_start` before, `spec_audit_done` after.
6. Partial/missing findings route through `/review-findings` accept/reject. Accepted items spawn new `todo` tasks in the spec; rejected items can become project-KB rules.
7. Clean audit → emit `spec_complete`, set spec frontmatter `status: shipped` in `specs/<feature>/spec.md`.

### FR-16: Last-Task-Done Trigger

`scripts/task-manager.sh set-status <task> done` — after the transition succeeds, run an all-done detector. If every task file under the spec's tasks dir has `status: done` AND no prior `spec_audit_done` event exists in `.monitor.jsonl`, emit `spec_last_task_done` event. `/implement`'s auto-chain listens for this event and auto-invokes `/validate-impl`. Standalone CLI users get the event but not the auto-chain (same pattern as existing event-emission).

### FR-17: Spec Audit Report + `/review-findings` Integration

- Report location: `specs/<feature>/reports/spec-audit-<ISO8601>.md`. Schema: YAML frontmatter (`feature`, `timestamp`, `scope`, `verdict ∈ {complete, reopen}`), markdown body with FR matrix + orphan-code list + over-engineering flags.
- `/review-findings` accepts a `spec-audit-*.md` report the same way it accepts per-task reports (`source: llm`). Accepted "missing FR" findings auto-create follow-up tasks via `task-manager.sh`; the task name references the FR ID and description. Rejected findings may become project-KB rules via the normal feedback loop.
- Unknown FR references in Karen's output (e.g. `FR-99` when spec only declares FR-1..17) → fail closed; no task auto-created; error lists the unknown IDs.

## BDD Scenarios

### Core Flow

**Scenario: Explore writes config after approval**
```
Given a new spec "payments-api" with a PRD describing a Rust backend
When the user runs /explore payments-api
Then the config-inferencer agent runs first
And a summary of proposed gates and per-phase agents is displayed
When the user presses the approval key
Then specs/payments-api/config.yml is written with inferencer output
And a config_inferred monitor event is emitted
And a config_approved monitor event is emitted
```

**Scenario: Validate applies ceiling semantics** *(T004 — per-task cadence only; scope branching layered in T016)*
```
Given a task with ground_rules [general:security/general.md, general:languages/rust.md]
And a spec config.yml with gates [rust-clippy, semgrep-security]
And a gates.yml entry rust-test applies_to [rust]
And validate_scope is per-task (default; pre-T013)
When /validate runs for this task
Then rust-clippy runs (in spec ∩ ground_rules language)
And semgrep-security runs (any applies to all)
And rust-test does NOT run (not in spec ceiling)
And a gate_skip event is emitted for rust-test
```

**Scenario: Missing spec config blocks active processing**
```
Given a spec with no config.yml file
When /validate (or any active phase command) runs for one of its tasks
Then the command exits non-zero with exit code 4
And the error names the spec and the expected config.yml path
And no gate executes and no agent spawns
```

**Scenario: Gates registry loads with `applies_to` tags** *(FR-2; owned by T001)*
```
Given gates.yml at knowledge-base/gates.yml containing
  - id: rust-clippy, applies_to: [rust], category: lint, blocking: true
  - id: semgrep-security, applies_to: [any], category: security, blocking: true
When config-loader.sh parses gates.yml
Then each gate's applies_to list is preserved verbatim
And duplicate id or unknown applies_to value causes fail-closed exit 3
And gates with applies_to [any] match every language bucket
```

**Scenario: Config loader exports WF_* env vars on first source** *(FR-10; owned by T002)*
```
Given .workflow.yml at repo root with spec_storage=specs/ and a spec "payments-api" with config.yml
When a caller sources scripts/config-loader.sh and calls `wf_load_config --spec payments-api`
Then WF_CONFIG_LOADED=1 is exported
And WF_REPO_ROOT, WF_SPEC_STORAGE, WF_GATE_POOL, WF_AGENT_POOL are exported as absolute paths
And WF_SPEC_GATES contains newline-separated gate IDs from the spec config
And WF_SPEC_AGENTS_<PHASE> is exported per phase in the spec config
When the same process sources the loader again in a subshell
Then yq is NOT re-invoked (single-parse guard via WF_CONFIG_LOADED)
And exported vars are inherited unchanged
```

**Scenario: Monitor walks up for .workflow.yml**
```
Given .workflow.yml at repo root with spec_storage=/tmp/vault
And current working directory is a nested subdirectory
When monitor.sh logs an event
Then the event is written under /tmp/vault/<feature>/.monitor.jsonl
```

**Scenario: Bootstrap writes starter config on fresh repo**
```
Given a fresh repo with no .workflow.yml
When /bootstrap runs
Then .workflow.yml is created at repo root
And it contains spec_storage, gate_pool, agent_pool defaults
```

**Scenario: Missing .workflow.yml blocks active commands** *(FR-1; owned by T002)*
```
Given an existing repo with no .workflow.yml at root
When any active workflow command (/validate, /implement, monitor.sh, task-manager.sh, pre-commit-hook.sh) runs
Then config-loader exits 2
And the error message names the resolved repo root and instructs the user to run /bootstrap
And no gate executes, no agent spawns, no monitor event is written
```

**Scenario: Bootstrap on existing repo adds only .workflow.yml** *(FR-12; owned by T011)*
```
Given an existing repo with prior files but no .workflow.yml
When /bootstrap runs
Then .workflow.yml is created at repo root with template defaults
And no other file in the repo is modified, created, or deleted
And exit code is 0
```

**Scenario: Bootstrap is idempotent when .workflow.yml already exists** *(FR-12; owned by T011)*
```
Given a repo with an existing .workflow.yml
When /bootstrap runs without --force
Then the file is not modified (byte-identical)
And the current config is printed to stdout
And exit code is 0
When /bootstrap --force runs
Then a diff against template defaults is shown
And on single-key confirmation the file is overwritten
And when the target path is a symlink, /bootstrap --force refuses with a non-zero exit
```

**Scenario: Config command regenerates spec config**
```
Given an existing spec with config.yml
When the user runs /config <feature> --regenerate
Then the config-inferencer agent re-runs
And the user is shown a diff against the existing config
And on approval the file is overwritten
```

**Scenario: Config command opens existing config for edit** *(FR-11; owned by T010)*
```
Given an existing spec with config.yml
When the user runs /config <feature>
Then config.yml opens for edit in the user's editor
And no inferencer run occurs
And the file is saved with any user changes on exit
```

### Edge Cases & Errors

**Scenario: Unknown gate ID in spec config fails closed**
```
Given specs/foo/config.yml lists a gate id "nonexistent-gate"
When /validate runs
Then the command exits non-zero
And the error names the unknown ID and the registry consulted
```

**Scenario: gates.yml parse error fails closed**
```
Given knowledge-base/gates.yml contains malformed YAML
When /validate runs
Then config-loader returns non-zero
And no gates execute
And the error is reported to the user
```

**Scenario: yq timeout on config parse**
```
Given a pathologically nested YAML file
When config-loader.sh parses it
Then yq is killed after 5 seconds
And the loader fails closed
And no downstream command proceeds
```

**Scenario: Inferencer failure falls back to manual**
```
Given the config-inferencer agent times out
When /explore reaches step 0
Then the user is shown a manual-entry prompt
And a default template is written if the user skips manual entry
```

### Validate Scope + Spec Audit

**Scenario: per-spec mode skips per-task validate**
```
Given a spec with validate_scope=per-spec in config.yml
And three tasks in the spec, each ready to run /validate
When /implement auto-chain reaches the /validate step for any task
Then /validate emits a gate_skip event with reason "scope=per-spec"
And the auto-chain proceeds directly to /review-findings with zero findings
And no gate command is executed for that task
```

**Scenario: last-task-done triggers spec audit**
```
Given a spec with three tasks, two already in status done and one in status implemented
When task-manager.sh set-status <last-task> done succeeds
Then a spec_last_task_done event is emitted on the spec's .monitor.jsonl
And /implement auto-chain invokes /validate-impl <feature>
And Karen is spawned with a wrapper prompt containing spec.md FR list, prd.md scope, task list, and git diff range
```

**Scenario: union gate failure forces reopen with Karen evidence**
```
Given a spec with validate_scope ∈ {per-spec, both}
And the union of spec-eligible gates includes at least one blocking gate
When /validate-impl executes union gate execution
And at least one blocking gate exits non-zero
Then the audit report verdict is "reopen"
And Karen is still spawned with the failing gate output embedded in the wrapper prompt as additional evidence
And spec_audit_done is emitted after Karen completes
And spec.md frontmatter status is NOT updated to shipped
```

**Scenario: clean audit marks spec shipped**
```
Given every FR in spec.md has corresponding implemented code traceable via Karen's matrix
When /validate-impl completes
Then the report verdict field is "complete"
And a spec_complete monitor event is emitted
And spec.md frontmatter status is updated to "shipped"
```

**Scenario: Karen finds missing FR → spec reopens**
```
Given an FR in spec.md has no corresponding implementation
When /validate-impl runs
Then the audit report lists that FR with status "missing"
And /review-findings presents the missing FR as an accept/reject finding
When the user accepts the finding
Then a new follow-up task is created in tasks/ with status todo referencing the FR id
And the spec's aggregate status remains in-progress until the new task reaches done
```

**Scenario: Reaudit cycle after follow-up tasks land** *(FR-17; owned by T017)*
```
Given a spec with a prior spec_audit_done event in .monitor.jsonl from a previous audit
And one or more follow-up tasks created by create-followup have reached status done
When the user runs /validate-impl --reaudit
Then a spec_reaudit_requested sentinel event is appended to .monitor.jsonl
And no prior event is mutated, rewritten, or deleted (append-only discipline)
And the T015 detector sees spec_reaudit_requested as the newest of {spec_audit_done, spec_reaudit_requested}
And the detector fires spec_last_task_done → /validate-impl once more
When the new audit completes
Then a fresh spec_audit_done is appended
And the guard is re-closed until the next explicit --reaudit
```

**Scenario: per-spec mode runs union at /validate-impl**
```
Given a spec config.yml with gates [rust-clippy, semgrep-security]
And validate_scope=per-spec
And two tasks with disjoint ground_rules (one rust, one shell)
When /validate-impl executes
Then rust-clippy runs once across the cumulative diff
And semgrep-security runs once across the cumulative diff
And the gate execution count equals the size of the union, not the task count times the union
```

## Security Scenarios

_From Security Engineer STRIDE analysis. All scenarios fail closed._

**Scenario: Shell injection via gate ID rejected (Elevation of Privilege — Critical)**
```
Given a spec config.yml with gate id "; rm -rf ~"
When /validate reads the config
Then the ID allowlist check fails (regex ^[a-zA-Z0-9_-]{1,64}$)
And the command exits non-zero before any shell execution
And no command from gates.yml is executed
```

**Scenario: Path traversal via spec_storage rejected (Information Disclosure — High)**
```
Given a .workflow.yml with spec_storage "../../etc"
When config-loader resolves the path
Then realpath normalization detects escape from $HOME / repo root
And the loader fails closed
And no file is read from the target path
```

**Scenario: Symlink ancestor in spec_storage rejected (Information Disclosure — High)**
```
Given spec_storage points to a directory whose parent is a symlink to /etc
When config-loader validates the path
Then the symlink ancestor check rejects the path
And the loader fails closed
```

**Scenario: yq parse bomb DoS mitigated (DoS — Medium)**
```
Given a .workflow.yml with deeply nested YAML (billion-laughs style)
When config-loader parses it
Then timeout 5 yq kills the process at 5 seconds
And the loader returns non-zero
And no downstream script proceeds
```

**Scenario: Tampered spec config detected at ship (Tampering — High)**
```
Given /implement snapshots config.yml into task state at start
And the config.yml is edited mid-task to remove a blocking gate
When /ship runs the final validation
Then the snapshot comparison detects the drift
And ship refuses to proceed until config is re-approved or restored
```

**Scenario: Cross-project vault leak prevented (Information Disclosure — High)**
```
Given spec_storage points to a shared vault directory used by two projects
When monitor.sh logs a spec event from project A
Then the event is scoped strictly to the configured path (no global fallback)
And no file handles from project B are opened
```

**Scenario: Monitor events redact absolute paths (Information Disclosure — Medium)**
```
Given a monitor event referencing a path under $HOME
When the event is written to JSONL
Then the path is rendered with $HOME replaced by ~
And the raw YAML body is never embedded in the event
```
*(Test ownership: T003 — both legs covered by monitor.sh test cases: `$HOME → ~` prefix rendering + rejection/truncation of YAML-body payloads.)*


**Scenario: Unknown gate/agent ID spoofing rejected (Spoofing — Medium)**
```
Given spec config.yml references an agent id not present in agent_pool
When the phase command loads the agent list
Then the command rejects the unknown ID with an explicit error
And does not silently fall back to defaults
```

**Scenario: gates.yml tracked-state warning (Tampering — High)**
```
Given knowledge-base/gates.yml has uncommitted modifications
When config-loader reads gates.yml
Then a loud warning is displayed to the user
And the loader still executes (trust boundary is filesystem, not block)
```

**Scenario: Unknown FR id in Karen audit output rejected (Spoofing — High)**
```
Given spec.md declares FR-1 through FR-17
And Karen's audit report references "FR-99 missing"
When /review-findings processes the audit report
Then the unknown FR id is rejected before any task auto-creation
And the command exits non-zero naming the unknown id(s) and the FR list consulted
And no follow-up task is written to tasks/
```

**Scenario: validate_scope enum enforced (Tampering — Medium)**
```
Given .workflow.yml sets validate_scope to "disabled"
When config-loader parses it
Then the enum allowlist check fails (only per-task, per-spec, both accepted)
And the loader returns exit 2
And no downstream command proceeds
```

## Security Requirements

- **Authentication:** N/A — local developer tool, no network surface. Trust boundary = filesystem ACLs.
- **Authorization:** `.workflow.yml` and `gates.yml` edits gated by repo write access. `/bootstrap` writer refuses to write through a symlink at the `.workflow.yml` target path. `specs/<feature>/config.yml` edits flow through `/config` or `/explore` approval; direct YAML edits discouraged (mirrors task-manager pattern).
- **Data handling:** All config files are plaintext YAML, committed to git — must contain zero secrets. Monitor events redact `$HOME` → `~`, log only event type + ID + git SHA, never embed raw YAML bodies. Inferencer must not read `.env*`, `*.pem`, `id_*`, `.git/config`.
- **Input validation:**
  - Gate/agent IDs: `^[a-zA-Z0-9_-]{1,64}$`
  - `spec_storage`: absolute path under `$HOME` (or explicit allowlist), `realpath`-resolved, no symlink ancestors, must exist and be a directory
  - `gate_pool` / `agent_pool`: resolves inside repo root or `~/.claude/`, no `..`
  - `gates.yml` schema: `id` (ID regex), `command` (string ≤ 256 chars), `applies_to` (list of enum), `category` (enum), `blocking` (bool)
  - YAML parsing: `timeout 5 yq` wrapper, fail closed on non-zero exit
  - `validate_scope`: enum {`per-task`, `per-spec`, `both`}; unknown → fail closed
  - FR ids in audit report: must match `^FR-[0-9]{1,3}$` AND exist in `spec.md` `### FR-N:` heading list; unknown → fail closed, no task auto-create

## Applicable Ground Rules

All applicable rules live in the **General KB** (installed globally at `~/.claude/knowledge-base/`). No project-KB layer exists for the dev-workflow repo itself.

**Resolution rule:** The `general:` prefix always resolves against `~/.claude/knowledge-base/` (the installed global KB), never against this repo's own `knowledge-base/`. The repo's `knowledge-base/` directory is the *source* that `setup.sh` installs globally; it is not a fallback resolution root. Tasks and runners must read `general:` rules from `~/.claude/knowledge-base/`. Any task editing those files must reference their full installed path, not a repo-relative path.

- `general:security/general.md` — input validation, path traversal, secret handling, least privilege
- `general:architecture/general.md` — small modules, explicit interfaces, boundary validation
- `general:architecture/code-analysis.md` — systematic impact analysis
- `general:testing/principles.md` — pure functions, Given/When/Then, unit over integration
- `general:code-review/general.md` — review discipline for shell + Rust diffs
- `general:documentation/general.md` — docs/CLAUDE.md/onboarding update discipline
- `general:languages/shell.md` — shellcheck, bash -n, 150-line module cap

## Out of Scope

Per PRD:
- Phase reordering, custom phases, custom ship/commit flows, custom hooks per repo
- Task state machine or frontmatter schema changes
- Runtime conditional `when:` DSL
- Vault sync strategy (user handles via iCloud/git/Dropbox)
- Trust-on-first-use prompt for unknown `.workflow.yml`
- `.workflow.local.yml` override
- Migration of existing done specs
- E2E scripted Claude session tests
- LLM inference golden fixtures
