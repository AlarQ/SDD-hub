# PRD — Configurable Workflow

## Problem

Dev-workflow today is hardcoded. Validation gates live in `commands/validate.md` + `knowledge-base/languages/*.md` frontmatter. Agent spawns are baked into command markdown. Specs always live under `specs/` in the repo root. Four pains hit solo use across projects:

1. **Wrong gates fire** — Rust repo runs TS-specific checks; doc-only specs run full security gate.
2. **Spec sprawl** — `specs/` pollutes repo root; no option for central vault.
3. **Agent mismatch** — default agents fire on specs where they add zero value.
4. **Rigidity** — experimenting with new gates/agents requires editing command markdown.

## Goal

Externalize "which gates/agents run" and "where specs live" into config. LLM curates per-spec at birth via a dedicated `config-inferencer` agent; user approves. Phase structure and ship mechanics stay fixed — only advisor/gate *selection* becomes pluggable inside the existing skeleton.

## User Perspective

- **Who benefits:** Ernest (solo), using the workflow across multiple personal projects of mixed languages.
- **Pain driver:** rigidity is the umbrella; wrong gates, spec sprawl, agent mismatch are symptoms of the same root.
- **Shortest path framing:** rejected. All four pains live in one spec so config layers don't fight each other. Task ordering within the spec handles incremental delivery.

## Scope

**IN**

- `.workflow.yml` at repo root: `spec_storage` path, gate pool reference, agent pool reference
- `knowledge-base/gates.yml`: explicit deterministic-gate registry with `applies_to` tags (language-specific or `[any]` for cross-cutting)
- `specs/<feature>/config.yml` per-spec: chosen gates + agents-per-phase, LLM-proposed at `/explore` time, user-approved
- `config-inferencer` agent: reads repo signals (`Cargo.toml`, `package.json`, `go.mod`, etc.), gates.yml, `agents/` directory, spec description; emits draft `config.yml`
- `/explore` step 0: spawn inferencer, render summary, one-key approve / `/config` override, write draft
- All phase commands (`/propose`, `/implement`, `/validate`, `/pr-review`, `/review-findings`) read agent lists from spec config with legacy fallback
- `/validate` applies **ceiling semantics**: executes intersection of spec-eligible gates ∩ task `ground_rules`
- Path resolution refactor: walk up for `.workflow.yml` instead of `specs/` across `monitor.sh`, `task-manager.sh`, `pre-commit-hook.sh`, TUI scanner
- Monitor event categories: `config_inferred`, `config_approved`, `agent_spawn`, `gate_skip`
- TUI: `workflow_config.rs`, `spec_config.rs`, pipeline widget, watcher for `.workflow.yml`
- `/config` command to edit/regenerate spec config post-creation
- `/bootstrap` generates `.workflow.yml` for new repos
- Security: `realpath` + symlink rejection + absolute-or-`$HOME` requirement on `spec_storage`; `[a-zA-Z0-9_-]+` ID allowlist in every script that reads gate/agent IDs; `timeout 5 yq` on every parse; fail-closed on errors
- Config loader caches yq reads (single parse per script invocation, exports env vars)
- `validate_scope ∈ {per-task, per-spec, both}` — gate cadence control at repo default (`.workflow.yml`) with per-spec override; small features can skip per-task `/validate` and rely on the spec-completion audit
- `/validate-spec` command — runs once when all spec tasks reach `done`; reuses existing **Karen** agent (`agents/karen.md`) via wrapper prompt; produces FR × status audit matrix and routes partial/missing findings through `/review-findings`
- `task-manager.sh set-status done` — emits `spec_last_task_done` event when last task transitions; `/implement` auto-chain invokes `/validate-spec` in response

**OUT**

- Phase reordering, custom phases, custom ship/commit flows, custom hooks per repo
- Task state machine changes; task frontmatter schema changes that touch existing fields (`id`, `name`, `status`, `blocked_by`, `ground_rules`, etc.). **Exception:** additive, advisory fields that do not gate state transitions are allowed (e.g., `empty_intersection_ok: bool` per ADR-003).
- Runtime conditional `when:` DSL (LLM curates once at spec birth instead)
- Vault sync strategy (user handles via iCloud/git/Dropbox)
- Trust-on-first-use prompt for unknown `.workflow.yml`
- `.workflow.local.yml` override pattern (single file)
- Migration of existing done specs (they stay as-is, scanner tolerates missing `config.yml`)
- End-to-end scripted Claude session tests
- LLM inference golden-fixture tests (brittle)

## Key Decisions (Locked)

- **Config shape:** auto-infer + visible summary + one-key override at `/explore` start. Not a step-0 wizard.
- **Pipeline tier B:** selection configurable, phase *structure* hardcoded.
- **Two registries, two lists:** `gates.yml` for deterministic shell gates, `agents/*.md` for LLM advisors. Spec config carries separate `gates:` and `agents:` sections.
- **gates.yml canonical for execution.** `validation_tools` frontmatter in language files becomes display-only.
- **Gate language binding via `applies_to` tags.** Cross-cutting gates tag `[any]`.
- **Gate selection = ceiling.** Spec config lists *eligible* gates. Task `ground_rules` stays authoritative. `/validate` runs the intersection.
- **Storage configurable** via `.workflow.yml`, default `specs/` in repo.
- **Monitor path resolution + new event categories** both v1.
- **Done specs untouched.** No migration.
- **Gate cadence configurable, spec audit mandatory.** `validate_scope` lets users opt into per-task, per-spec, or both. Irrespective of cadence, a Karen-backed `/validate-spec` audit runs at last-task-done. ADR-007 / ADR-008.
- **Karen reused for spec audit** — no new agent; wrapper prompt at call-site carries spec.md / prd.md / task list / diff range. ADR-008.

## Config Schemas

**`.workflow.yml`** (repo root)
```yaml
spec_storage: specs/
gate_pool: knowledge-base/gates.yml
agent_pool: ~/.claude/agents
validate_scope: per-task       # per-task | per-spec | both
```

**`knowledge-base/gates.yml`**
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

**`specs/<feature>/config.yml`**
```yaml
tags: [api, auth]
validate_scope: per-spec       # optional override; inherits from .workflow.yml if absent
gates:
  - rust-clippy
  - rust-test
  - semgrep-security
agents:
  explore:    [design/ux-researcher, engineering/security-engineer]
  propose:    [engineering/software-architect]
  implement:  [code-quality-pragmatist]
  validate:   [engineering/security-engineer, code-quality-pragmatist]
  pr-review:  [engineering/code-reviewer]
```

## Affected Areas

- `scripts/monitor.sh`, `scripts/task-manager.sh`, `scripts/pre-commit-hook.sh`, new `scripts/config-loader.sh`
- `commands/explore.md`, `commands/propose.md`, `commands/implement.md`, `commands/validate.md`, `commands/pr-review.md`, `commands/review-findings.md`, `commands/bootstrap.md`, new `commands/config.md`, new `commands/validate-spec.md`
- `agents/engineering/engineering-config-inferencer.md` (new; ID `engineering/config-inferencer`)
- `knowledge-base/gates.yml` (new)
- `workflow-tui/src/parse/scanner.rs`, new `workflow_config.rs`, new `spec_config.rs`, `model/spec.rs`, new `ui/pipeline.rs`, `watcher.rs`
- `templates/workflow.yml.template` (new), `templates/spec-config.yml.template` (new), `setup.sh`
- `CLAUDE.md`, `docs/workflow-diagram.md`, `onboarding.md`

**Not touched:** `hooks/*`, task state machine.

**Lightly touched:** `commands/ship.md` gains one pre-flight check — re-reads `specs/<feature>/config.yml`, compares against the snapshot `/implement` wrote at task start, refuses to proceed on drift (per Security Scenario "Tampered spec config detected at ship"). Commit/PR flow itself is unchanged — the drift check is an added gate, not a rewrite.

## Testing Expectations

- `tests/test-config-loader.sh` — valid parse, missing file defaults, path traversal rejected, symlink rejected, malformed YAML fails closed, yq timeout, ID allowlist
- `tests/test-path-resolution.sh` — `spec_storage` to temp dir, confirm files land in configured location
- `tests/test-config-inferencer.sh` — schema shape check only (LLM nondeterministic; no golden fixtures)
- `cargo test` in `workflow-tui/`
- Backward compat: scanner handles missing `config.yml` on done specs

## Security Model

1. Shell injection via IDs — `validate_id` allowlist in all scripts reading gate/agent IDs. T001 tightens the existing helper at `monitor.sh:64-70` to the stricter regex `^[a-zA-Z0-9_-]{1,64}$` (current helper lacks the length cap); all scripts then reuse the updated version.
2. Path traversal via `spec_storage` — `realpath` + symlink ancestor rejection + absolute-or-`$HOME`. Fail closed.
3. Cross-project info disclosure in vault — scope strictly to configured path, no global fallback.
4. yq parse-bomb DoS — `timeout 5` wrapper, fail closed.

Trust-on-first-use and `.local` override explicitly OUT per user decision.

## Performance

Only hot spot: `yq` fork cost multiplied by config layer. Mitigation = `config-loader.sh` single parse per script invocation, exports env vars, other functions read from env.

## Risks

- **HIGH — dogfood breakage during path-resolution rollout.** dev-workflow's own `specs/` dir could break mid-work. Mitigation: keep `specs/` fallback until E2E green, then remove.
- **MEDIUM — gates.yml / language-file drift** if generated far apart. Mitigation: generate gates.yml from current `validation_tools` frontmatter in the same commit.
- **MEDIUM — config-inferencer nondeterminism** — test schema shape only.
- **LOW — circular source deps.** `config-loader.sh` must not source `monitor.sh`.
- **LOW — pre-commit hook subdir cwd.** Walk-up must handle arbitrary `git commit` cwd.

## Applicable Ground Rules

**General KB**
- `general:security/general.md` — boundary validation (path + ID)
- `general:architecture/general.md` — small modules, explicit interfaces
- `general:testing/principles.md` — unit over integration, no brittle fixtures
- `general:languages/shell.md` — `set -euo pipefail`, quoted expansions
- `general:languages/rust.md` — TUI parser additions

The `knowledge-base/` directory at this repo's root serves dual purpose: it is the General KB source (installed globally to `~/.claude/knowledge-base/` by `setup.sh`) and this repo's own project KB. Rules cited by this spec map to their installed General KB paths at `~/.claude/knowledge-base/`. Language files that exist only in the General KB (e.g. `typescript.md`, `nextjs.md`, `scala.md`) are not present in this repo and must be referenced by their full installed path.

## Agent Insights (Explore Phase)

**UX Researcher (advisory)**
- Step-0 wizard is friction with rubber-stamp risk → adopted auto-infer + visible summary instead.
- Agent selection per-spec is the real win; pains #1/#4 are symptoms of the same root → unified the mechanism.
- Multi-machine: repo config syncs via git, vault does not — user owns sync (accepted).
- Open-source leak via committed `.workflow.yml` — flagged; user opted out (solo).
- Plug-and-play framing risks over-engineering — resisted DSL. No `when:` expressions. Curate at spec birth.

**Security Engineer (advisory)**
- Tampering via YAML → shell: ID allowlist in all scripts, not only monitor.sh.
- EoP via path traversal: `realpath`, reject symlink ancestors, require absolute or `$HOME`.
- Info disclosure in vault: no global default fallback.
- DoS via yq parse bombs: `timeout` wrapper, fail closed.
- Trust-on-first-use: flagged; user opted out.

**Plan Agent (Phase 2 validation)**
- Gate semantics fork surfaced → ceiling chosen (spec eligible, task authoritative, intersect at `/validate`).
- gates.yml vs language-file canonicality resolved → gates.yml canonical; frontmatter display-only; `applies_to` tag model handles language-specific + cross-cutting split.
- Task decomposition (12 atomic tasks) + dependency ordering (T1+T2+T3 → T4 → T5; T7 → T8 → T9; T11 parallelizable).
- Dogfood breakage risk flagged (HIGH) → keep `specs/` path-resolution fallback until final cleanup.
- Alternative shapes considered and rejected: piggyback gates on frontmatter (awkward for cross-cutting gates), inline inferencer prompt (loses reuse by `/config`).
