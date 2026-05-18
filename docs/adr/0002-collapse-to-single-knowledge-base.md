# Collapse to a single (general) knowledge base

Status: accepted

The workflow shipped a **dual knowledge base**: a per-repo *Project KB*
(`knowledge-base/` holding `gates.yml` + `languages/*` + `conventions/*` rule
markdown) and a machine-wide *General KB* (`$WF_GENERAL_KB`). In practice
project-specific knowledge already lives in `CLAUDE.md`, `CONTEXT.md`, and
`docs/adr/` — the Project KB rule markdown was redundant. The only
non-redundant artifact in `knowledge-base/` was `gates.yml`, which is
*executable config*, not knowledge. The dual layer was also the single largest
source of complexity: the `general:`/`project:`/`repo:<name>:` prefix grammar,
per-task project-KB resolution, and the vault single/multi-repo ambiguity
(`exit 7`) were persistent footguns.

Decision: one KB (`$WF_GENERAL_KB`). The gate registry folds **inline** into
`.workflow.yml` as a `gate_pool:` array; in vault mode each bound code repo
gets a thin `.workflow.yml` (`kind: repo-gate-pool`). `ground_rules` become
bare `$WF_GENERAL_KB`-relative paths. The feedback loop
(`/review-findings`, `/learn-from-reports`) now writes learned rules to the
general KB. `/promote-rules` is deleted — graduation is a no-op.

## Considered Options

- **Keep the dual KB** — rejected: preserves the prefix grammar, per-task
  project-KB resolution, and vault `exit 7` ambiguity for a layer whose only
  unique content is already in `CLAUDE.md`/`CONTEXT.md`/`docs/adr/`.
- **Keep `gates.yml` as a file but drop the rule markdown** — rejected: keeps a
  standalone executable-config file and its discovery rules when it can live
  inline in `.workflow.yml` next to the rest of the workflow config; the
  per-repo `kind: repo-gate-pool` marker covers the vault multi-repo case.

## Consequences

- Loses project-scoped rule override on the same topic — acceptable, since
  project specifics now live in `CLAUDE.md`/`CONTEXT.md`/`docs/adr/`.
- Old specs keep working: `resolve_ground_rule_path` strips any legacy
  `general:`/`project:`/`repo:<name>:` prefix, resolves the remainder under
  `$WF_GENERAL_KB`, and emits a once-per-process deprecation warning. No spec
  files are rewritten.
- Vault `.workflow.yml` stays a thin gateless pointer **except** the
  self-hosting exception: it MAY carry `gate_pool` iff a `repos[]` entry
  resolves to the vault dir itself (this repo's dogfood case).
- Cross-references the configurable-workflow ADRs (ADR-002 gate registry,
  ADR-005 vault mode, ADR-006 multi-repo resolution in
  `specs/configurable-workflow/design.md`) — those gate/KB mechanics are
  superseded by this single-KB model.
- Reversing this means restoring the dual-layer resolver, the prefix grammar,
  and `/promote-rules` — meaningful cost, hence this record.
