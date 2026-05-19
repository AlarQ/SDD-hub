# Workflow glossary

Canonical definitions for the configurable-workflow terms used by `/validate`, `/validate-impl`, and the config loader. Single source of truth; commands MUST link here instead of restating definitions.

## Terms

- **ceiling** — the eligible gate set for a spec: gate IDs listed in `specs/<feature>/config.yml gates:` (exported as `WF_SPEC_GATES`). Upper bound; no gate outside this set runs.
- **effective-set** — per-task intersection: `ceiling ∩ gates applicable to task ground_rules` (language + category match). Computed fresh each task by `wf_compute_effective_set`. Used by `/validate`.
- **spec-union** — union of effective-sets over every task in the spec. Computed once by `wf_compute_union_set` for `/validate-impl` Step 2.
- **repo mode** — `spec_storage_mode: repo` (default): specs live inside the code repo; one inline `gate_pool:` in `.workflow.yml`.
- **vault mode** — `spec_storage_mode: vault`: specs live in a master-brain vault whose `.workflow.yml` is a **thin pointer**. No vault gates/KB; each spec binds code repos via per-spec `repos[]`.
- **thin pointer** — a vault `.workflow.yml` carrying only workflow settings + `general_kb_path`; declares no `gate_pool` (except the self-hosting exception).
- **bound repo** — a code repo listed in a spec's `config.yml repos[]` (`name → path → role`). Owns its own thin `.workflow.yml` (`kind: repo-gate-pool`, inline `gate_pool:`).
- **project segment / `{project}` token** — a literal `{project}` in `spec_storage` (vault), substituted per-spec with the project name (from `--project` or `config.yml project:`), e.g. `projects/{project}/specs`.
- **gate-id union (vault)** — in vault mode a spec's `gates:` are validated against the union of all bound repos' `.workflow.yml gate_pool[]` ids (no single pool exists).

## Usage rule

Do not use the bare word "union" in command prose for either ceiling or effective-set — reserve it for **spec-union** only.
