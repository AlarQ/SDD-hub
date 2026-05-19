# Plan: Remove Project Knowledge Base — collapse to a single general KB

## Context

The workflow ships a **dual knowledge base**: a per-repo *Project KB*
(`knowledge-base/` holding `gates.yml` + `languages/*` + `conventions/*`
rule markdown) and a machine-wide *General KB* (`$WF_GENERAL_KB`). In
practice, project-specific knowledge already lives in `CLAUDE.md`,
`CONTEXT.md`, and `docs/adr/` — the Project KB rule markdown is redundant.
The only non-redundant thing inside `knowledge-base/` is `gates.yml`, which
is *executable config*, not knowledge. The dual layer is also the single
largest source of complexity: the `general:`/`project:`/`repo:<name>:`
prefix grammar, per-task project-KB resolution, and the vault
single/multi-repo ambiguity (`exit 7`) are persistent footguns.

Outcome: one KB (`$WF_GENERAL_KB`). The gate registry folds **inline** into
`.workflow.yml`. `ground_rules` become bare general-KB-relative paths.
The feedback loop writes learned rules to the general KB. `/promote-rules`
is deleted (graduation is now a no-op).

## Locked decisions (user-confirmed via grill)

1. **gates.yml → inline `gate_pool:` array in `.workflow.yml`.** Standalone
   `gates.yml` file and the entire `knowledge-base/` directory are deleted.
2. **Vault: per-repo `.workflow.yml`.** Each bound code repo gets a thin
   `.workflow.yml` (`kind: repo-gate-pool`, only `gate_pool:`). Vault
   `.workflow.yml` stays the thin pointer and remains gateless — **except**
   the self-hosting exception (#7).
3. **Feedback loop → general KB.** Drop the "never modify general KB" wall.
   `/review-findings` + `/learn-from-reports` write to `$WF_GENERAL_KB`.
   `/capture-rule` already general-only — unchanged.
4. **`ground_rules` drop prefixes.** Bare `$WF_GENERAL_KB`-relative paths.
5. **`/promote-rules` deleted** (command, doc refs, tests).
6. **Migration = strip-prefix shim + one-time warn.** `resolve_ground_rule_path`
   strips any `general:`/`project:`/`repo:<name>:`/bare prefix, resolves the
   remainder under `$WF_GENERAL_KB`, emits a once-per-process deprecation
   warning. No spec file rewrites.
7. **Discovery discriminator = `kind: repo-gate-pool` marker.** Loader walk-up
   skips any `.workflow.yml` carrying that marker and keeps ascending.
8. **Self-hosting exception.** A vault `.workflow.yml` MAY carry `gate_pool`
   iff a `repos[]` entry points at the vault dir itself (this repo's case).

Adopted recommendations on minor points: `WF_GATE_POOL` = path to the
`.workflow.yml` file (consumers re-root yq from `.gates[]` to `.gate_pool[]`,
minimal blast radius); one-time warn scope = per-process via a global flag
(no state file); leave dated audit docs (`docs/workflow-audit-*.md`)
untouched, fix only live docs.

## Implementation (ordered)

### 1. ADR ✅ IMPLEMENTED
Create `docs/adr/0002-collapse-to-single-knowledge-base.md`: decision,
options considered (keep dual KB; keep gates.yml file but drop rule md —
both rejected), consequences (loses project-scoped override; old specs work
via shim), cross-ref ADR-002/005/006.

### 2. `scripts/config-loader.sh` ✅ IMPLEMENTED
- Remove `WF_PROJECT_KB` entirely (decls ~21–28; exports ~560–562; CLI
  allowlist ~654–660). No alias.
- `gate_pool` is now an inline array, not a path. Repo mode: `WF_GATE_POOL`
  = path to `$WF_CONFIG_FILE` (the `.workflow.yml`); gate consumers query
  `.gate_pool[]` instead of `gates.yml`'s `.gates[]`. Default `.gate_pool // []`.
  Drop `knowledge-base/gates.yml` default (~227) and the `WF_PROJECT_KB="$root/knowledge-base"` assignment (~225, 233–237).
- gate-pool parse/validate (~283–322): parse `.gate_pool[]` from `$WF_CONFIG_FILE`;
  dup-id + uncommitted-mod git check now target `.workflow.yml`; tighten message.
- Spec gate-id validation: repo (~343–361) reads `$WF_CONFIG_FILE .gate_pool[].id`;
  **vault union (~489–506)** reads each bound repo's `$rp/.workflow.yml .gate_pool[].id`
  (set `rgp="$rp/.workflow.yml"`; missing → `continue`).
- **Walk-up discriminator**: after `find_workflow_root`/parse (~121–136),
  if `.kind == "repo-gate-pool"` continue ascending from parent until a real
  config (has `spec_storage_mode`) or fs root (`exit 2`).
- **Self-hosting exception**: vault mode normally rejects `gate_pool`; allow
  it iff a `repos[]` entry's resolved path == vault root dir.
- Mirror every change in `scripts/config-loader.contract.md` (drop
  `WF_PROJECT_KB` row; rewrite `WF_GATE_POOL` row; vault section steps 5/6;
  exit-3/exit-7 text).

### 3. `scripts/task-manager.sh` — `resolve_ground_rule_path` (~184–256) ✅ IMPLEMENTED
Collapse to one branch + strip-prefix shim:
- Require `WF_GENERAL_KB` (else `return 7`).
- `case` strips `general:` / `project:` / `repo:*:` / `repo:*` prefixes;
  if any prefix matched, call `_wf_ground_rule_deprecation_warn`.
- Return `$WF_GENERAL_KB/$stripped`.
- Add `_wf_ground_rule_deprecation_warn`: global `_WF_GR_PREFIX_WARNED`
  guard, prints once per process to stderr.
- Delete all vault single/multi-repo branching + `repo:<name>:` `wf_repo_path`
  resolution.

### 4. `scripts/multi-repo-resolution.md` ✅ IMPLEMENTED
- `WF_TASK_GATE_POOL="$WF_TASK_REPO_PATH/.workflow.yml"` (was `…/knowledge-base/gates.yml`).
- Error/remediation text → "bound repo missing `.workflow.yml`".
- Rewrite prose: gates read from bound repo `.workflow.yml .gate_pool`; drop
  `WF_PROJECT_KB` mentions.

### 5. `scripts/gate-ceiling.sh` & `scripts/validate-impl.sh` ✅ IMPLEMENTED
Pool precedence `${WF_TASK_GATE_POOL:-${WF_GATE_POOL}}` unchanged. Switch
every `yq … .gates[]` to `.gate_pool[]` (`wf_gc__intersect` + union reader,
~gate-ceiling 89/108, validate-impl ~134).

### 6. `scripts/knowledge-base-rules.md` ✅ IMPLEMENTED
Keep filename (7 commands link it). Rewrite to single-KB model: bare paths
under `$WF_GENERAL_KB`; legacy prefixes stripped + deprecation-warned; remove
two-layer/prefix tables and "never modified by feedback loop" line.

### 7. `commands/bootstrap.md` ✅ IMPLEMENTED
- Modes → two. `vault-init` unchanged (stays gateless unless self-hosting).
- `repo-gate-init` rewritten: writes a thin `$repo/.workflow.yml` with
  `kind: repo-gate-pool` + seeded `gate_pool:` (language prompt). **Delete
  Step B (project-KB files) and Step C (gates.yml).**
- Repo mode (Step A) writes full `.workflow.yml` with inline `gate_pool:`.
- Keep the vault-guard refusal. Drop project-KB prerequisites.

### 8. `commands/review-findings.md` & `commands/learn-from-reports.md` ✅ IMPLEMENTED
- Both: rule write target → `$WF_GENERAL_KB/<category>/<file>.md`, update
  `$WF_GENERAL_KB/_index.md`. Invert "never the general KB" → "write to
  general KB". Drop project-KB resolution refs.
- `commands/capture-rule.md`: remove any `/promote-rules` graduation mention.

### 9. Delete `/promote-rules` ✅ IMPLEMENTED
- Delete `commands/promote-rules.md`.
- Remove refs: `CLAUDE.md` cmd list, `onboarding.md`,
  `commands/workflow-summary.md`, `commands/fix.md`,
  `commands/capture-rule.md`, `opencode-migration.md`. `setup.sh` line ~314
  message → "Run /bootstrap to configure gates". Leave dated audit docs.

### 10. Templates ✅ IMPLEMENTED
- Delete `templates/gates.yml.template`.
- `templates/workflow.yml.template`: inline `gate_pool:` array example +
  documented `kind: repo-gate-pool` per-repo block; rewrite vault comment.
- `templates/spec-config.yml.template`: "Each id must exist in the bound
  repo's `.workflow.yml gate_pool`".

### 11. Docs ✅ IMPLEMENTED
- `CLAUDE.md`: rewrite §"Dual Knowledge Base" → single KB; fix lines ~7,16,17,
  73–80,88–89,164–168,206,220; remove `WF_PROJECT_KB`.
- `CONTEXT.md`: delete term **Project KB**; edit **Ground rule**, **Gate
  registry**, **Repo mode**, **Vault mode**; add resolved-tension note
  pointing at ADR-0002. *(Grill skill normally edits CONTEXT.md inline;
  deferred here because plan mode forbids non-plan edits — execute in this
  step.)*
- `onboarding.md`, `plan.md`: sweep `knowledge-base/`, `gates.yml`,
  `project KB`, `/promote-rules`, prefix convention.

### 12. `docs/workflow-diagram.md` (Mermaid — flow change, mandatory per CLAUDE.md)
- `REPO_MODE`/`REPO_GATE` node labels → inline `gate_pool` / thin
  `.workflow.yml kind: repo-gate-pool`.
- Collapse `GKB`+`PKB` → single `GKB`; repoint `RF`/`LFR`/`IM` edges to `GKB`;
  `WTGP` label → `repo/.workflow.yml gate_pool`. Remove any `/promote-rules`
  node (keep `/promote-tier`). Rewrite Dual-KB / vault bullets.

### 13. Tests
- `tests/test-task-manager.sh` (~273–329): rewrite resolve suite — bare path,
  legacy `general:`/`project:`/`repo:b:` → `$WF_GENERAL_KB/...` + WARN;
  missing `WF_GENERAL_KB` → exit 7; one-time-warn dedup test; delete vault
  ambiguity tests; replace `mkdir knowledge-base` fixture.
- `tests/test-config-loader.sh`: convert all `knowledge-base/gates.yml`
  fixtures → inline `gate_pool` in `.workflow.yml`; remove `WF_PROJECT_KB`
  assertion (~374); malformed/dup-id tests target inline array; add
  walk-up-skips-`kind: repo-gate-pool` test; add self-hosting-exception test.
- Convert `tests/fixtures/config/*`, `tests/fixtures/gates-*` to inline form.
- Sweep `test-config-paths.sh`, `test-scope-semantics.sh`,
  `test-validate-impl.sh`, `test-phase-command-ceiling.sh`,
  `test-inferencer-schema.sh` for `gates.yml`/`knowledge-base`/`WF_PROJECT_KB`.

### 14. Dogfood migration (this repo)
- `.workflow.yml`: keep `spec_storage_mode: vault`; **keep** `gate_pool`
  but convert from path to inline array (self-hosting exception #8 — a
  `repos[]` entry points at this dir). Verify/add that `repos[]` self-entry.
- Migrate `knowledge-base/gates.yml` content into inline `gate_pool:`.
- Delete `knowledge-base/` (`gates.yml`, `languages/`, `_index.md`) after
  the rule markdown is confirmed redundant with `CLAUDE.md`/`CONTEXT.md`
  (no live `ground_rules` depend on `languages/rust.md`/`shell.md` — verify
  via grep across vault specs first; if any do, they resolve to
  `$WF_GENERAL_KB/languages/...` post-shim, so ensure equivalents exist
  there or accept the deprecation warning).

## Verification

1. `bash tests/test-task-manager.sh` — resolve_ground_rule_path: bare +
   legacy-prefixed paths, one-time warn, exit 7.
2. `bash tests/test-config-loader.sh` — inline `gate_pool` parse, walk-up
   skips `kind: repo-gate-pool`, self-hosting exception, no `WF_PROJECT_KB`.
3. `bash tests/run-all.sh` (or each touched test) — full suite green.
4. `cargo check --workspace && cargo test --workspace` — Rust unaffected
   (sanity; no Rust changes expected).
5. `grep -rn "WF_PROJECT_KB\|knowledge-base/gates.yml\|promote-rules" \
   --include='*.sh' --include='*.md' .` returns only ADR/audit history.
6. Dogfood end-to-end: from this repo, `source scripts/config-loader.sh &&
   wf_load_config` succeeds, `WF_GATE_POOL` points at `.workflow.yml`,
   `gate-ceiling.sh` computes a non-empty effective set from inline
   `gate_pool`.
7. Spawn `claude-md-compliance-checker` after edits — CLAUDE.md vs behavior.

## Critical files
- `scripts/config-loader.sh`, `scripts/config-loader.contract.md`
- `scripts/task-manager.sh`, `scripts/multi-repo-resolution.md`
- `scripts/gate-ceiling.sh`, `scripts/validate-impl.sh`
- `scripts/knowledge-base-rules.md`
- `commands/bootstrap.md`, `commands/review-findings.md`,
  `commands/learn-from-reports.md`, `commands/promote-rules.md` (delete)
- `templates/workflow.yml.template`, `templates/gates.yml.template` (delete),
  `templates/spec-config.yml.template`
- `CLAUDE.md`, `CONTEXT.md`, `docs/workflow-diagram.md`, `onboarding.md`
- `tests/test-task-manager.sh`, `tests/test-config-loader.sh`, fixtures
- `.workflow.yml` (dogfood), `knowledge-base/` (delete)
