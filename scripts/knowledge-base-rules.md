# Knowledge-Base Rules

Shared prerequisites, the `ground_rules` prefix convention, and path-resolution
rules. Linked from every workflow command (`/explore`, `/propose`, `/implement`,
`/validate`, `/pr-review`, `/review-findings`, `/learn-from-reports`) instead of
duplicating KB instructions inline. Canonical resolver: `scripts/task-manager.sh`
`resolve_ground_rule_path`. Multi-repo machinery: `scripts/multi-repo-resolution.md`.

## Two-layer knowledge base

- **General KB** — universal rules (security, architecture, testing, style).
  Root: `$WF_GENERAL_KB` (from `general_kb_path` in `.workflow.yml`). Required —
  loader exits 2 if absent. Never modified by the workflow feedback loop.
- **Project KB** — project-specific rules and conventions. Lives at
  `<repo>/knowledge-base/` inside each target code repo (never in the vault).
  New rules from `/review-findings` and `/learn-from-reports` always land here.

Project rules override general rules on the same topic.

## Prefix convention

Task `ground_rules` entries use a prefix that selects the resolution root:

| Prefix | Resolves under | Example |
|---|---|---|
| `general:` | `$WF_GENERAL_KB` | `general:security/general.md` |
| `project:` | the project KB root (see below) | `project:languages/rust.md` |
| `repo:<name>:` | that bound repo's `knowledge-base/` | `repo:backend:style/api.md` |
| *(unprefixed)* | same as `project:` | `style/general.md` |

New project-KB files use the path shape `knowledge-base/<category>/<file>.md`.

## Project-KB resolution

**Repo mode** (`spec_storage_mode: repo`): `project:`/unprefixed →
`<WF_REPO_ROOT>/knowledge-base/`. `WF_PROJECT_KB` carries this root.

**Vault mode** (`spec_storage_mode: vault`): the vault holds no `knowledge-base/`.
`WF_PROJECT_KB`/`WF_GATE_POOL` are empty; project KB + gates resolve **per task**
from the bound repo(s) in the per-spec `config.yml repos[]`. Resolution of a
bare `project:`/unprefixed rule depends on the bound-repo count:

- **Exactly one bound repo** — that repo is the implicit default; bare
  `project:`/unprefixed rules resolve to `<that-repo>/knowledge-base/`.
- **Two or more bound repos** — ambiguous; bare `project:`/unprefixed is
  **rejected (exit 7)**. Use `general:` or an explicit `repo:<name>:` prefix.
- **Zero bound repos** — nothing to resolve against; **rejected (exit 7)**.

`general:` always resolves regardless of repo count. `repo:<name>:` resolves
to that named repo's `knowledge-base/` (exit 7 if `<name>` not in `repos[]`).

`task-manager.sh validate` returns the same exit 7 for these rejections so the
loader and task validator stay symmetric (see `config-loader.contract.md`).

## Prerequisites

- Source `scripts/config-loader.sh` and run `wf_load_config --spec <feature>`
  before resolving any `ground_rules` (sets `WF_GENERAL_KB`, repo bindings).
- Vault mode requires a `<feature>` — gate/KB commands pass `--require-spec`;
  no spec under vault → exit 4 (no silent gate skip).
- Multi-repo specs require each task to declare a `repo:` field; resolve the
  per-task repo via `scripts/multi-repo-resolution.md` before running gates.
