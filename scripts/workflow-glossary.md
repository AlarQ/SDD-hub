# Workflow glossary

Canonical definitions for the configurable-workflow terms used by `/validate`, `/validate-impl`, and the config loader. Single source of truth; commands MUST link here instead of restating definitions.

## Terms

- **ceiling** — the eligible gate set for a spec: gate IDs listed in `specs/<feature>/config.yml gates:` (exported as `WF_SPEC_GATES`). Upper bound; no gate outside this set runs.
- **effective-set** — per-task intersection: `ceiling ∩ gates applicable to task ground_rules` (language + category match). Computed fresh each task by `wf_compute_effective_set`. Used by `/validate`.
- **spec-union** — union of effective-sets over every task in the spec. Computed once by `wf_compute_union_set` for `/validate-impl` Step 2.

## Usage rule

Do not use the bare word "union" in command prose for either ceiling or effective-set — reserve it for **spec-union** only.
