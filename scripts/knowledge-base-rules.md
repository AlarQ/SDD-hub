# Knowledge-Base Rules

Shared prerequisites and `ground_rules` path-resolution rules. Linked from every
workflow command (`/explore`, `/propose`, `/implement`, `/validate`, `/pr-review`,
`/review-and-ship`, `/learn-from-reports`) instead of duplicating KB instructions
inline. Canonical resolver: `scripts/task-manager.sh` `resolve_ground_rule_path`.
Multi-repo machinery: `scripts/multi-repo-resolution.md`.

## Single knowledge base

One KB: the **general KB** at `$WF_GENERAL_KB` (from `general_kb_path` in
`.workflow.yml`). Required — loader exits 2 if absent. Holds all rules: security,
architecture, testing, style, language, and project conventions. The workflow
feedback loop (`/review-and-ship`, `/learn-from-reports`, `/capture-rule`) writes
learned rules **here** (ADR-0002 — single KB replaces the old dual layer).

There is no separate project KB and no `knowledge-base/` directory in any repo
or in the vault. Gates fold inline into `.workflow.yml` (`gate_pool:`); see
`scripts/config-loader.contract.md`.

## ground_rules paths

Task `ground_rules` entries are **bare paths relative to `$WF_GENERAL_KB`**:

```
security/general.md   →  $WF_GENERAL_KB/security/general.md
languages/rust.md     →  $WF_GENERAL_KB/languages/rust.md
```

New rule files use the path shape `<category>/<file>.md` under `$WF_GENERAL_KB`.

### Legacy prefixes (deprecated, ADR-0002)

Old specs may carry `general:` / `project:` / `repo:<name>:` / `repo:<name>` prefixes.
`resolve_ground_rule_path` strips any such prefix, resolves the remainder under
`$WF_GENERAL_KB`, and emits a once-per-process deprecation warning. No spec
rewrites are required — the strip-prefix shim keeps old specs working. Migrate
entries to bare paths when convenient; the warning is the only signal.

`task-manager.sh validate` returns exit 7 if `WF_GENERAL_KB` is unset, keeping
the loader and task validator symmetric (see `config-loader.contract.md`).

## Prerequisites

- Source `scripts/config-loader.sh` and run `wf_load_config --spec <feature>`
  before resolving any `ground_rules` (sets `WF_GENERAL_KB`, repo bindings).
- Vault mode requires a `<feature>` — gate/KB commands pass `--require-spec`;
  no spec under vault → exit 4 (no silent gate skip).
- Multi-repo specs require each task to declare a `repo:` field; resolve the
  per-task repo via `scripts/multi-repo-resolution.md` before running gates.
