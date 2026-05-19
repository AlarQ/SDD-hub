Bootstrap workflow config. A vault is set up **once**; each target code repo
is set up **once**. There is no project knowledge-base — project knowledge
lives in `CLAUDE.md` / `CONTEXT.md` / `docs/adr/`. Gates fold inline into
`.workflow.yml` (`gate_pool:` array).

Accepts optional flags as `$ARGUMENTS`: `--force` to overwrite an existing
`.workflow.yml`, `--repair` to fill only missing fields.

## Prerequisites
1. Read and follow `$WF_GENERAL_KB/_rules.md` — general KB prerequisite only.

## Step A0 — Pick mode

Ask via `AskUserQuestion` (per `~/.claude/scripts/ask-user-protocol.md`):

- **question:** "What are you bootstrapping?"
- **options:**
  - `vault-init` — this directory is the master-brain vault that will hold
    all specs. Write a thin-pointer `.workflow.yml` only. **No** `gate_pool`
    here — gates live in the target code repos.
  - `repo-gate-init` — this directory is a target code repo bound by a vault
    spec. Write a thin `.workflow.yml` carrying `kind: repo-gate-pool` + an
    inline seeded `gate_pool:`. No vault workflow settings.
  - `repo` — standalone single-repo project (specs live in-repo, repo mode).
    Write a full `.workflow.yml` with an inline `gate_pool:` array.

Branch on the answer: `vault-init` → Step V only. `repo-gate-init` → Step R
only. `repo` → Step A only.

## Step V — Vault init (thin pointer)

1. Refuse if `pwd` is a git work tree: "Vault mode requires a non-repo
   directory. cd to your vault and re-run `/bootstrap`." (`git rev-parse
   --show-toplevel` succeeding inside `pwd` = refuse.)
2. Loop with `AskUserQuestion` to collect default repo bindings — for each:
   `name` (kebab-case `^[a-z0-9][a-z0-9_-]{0,31}$`), `path` (absolute or
   `~`-prefixed), `role` (free text; one `primary` selects default git/PR
   context). Stop when the user picks `Done`. Verify each `path` resolves to a
   git work tree (`git -C "<path>" rev-parse --show-toplevel`); refuse the
   entry on failure. These are optional — an empty list is allowed.
3. `.workflow.yml` existence handling: same idempotent / `--force` / `--repair`
   symlink-safe rules as Step A (steps A1–A3 below apply identically).
4. Write `.workflow.yml` from `~/.claude/templates/workflow.yml.template` as a
   **thin pointer** — touch only `.workflow.yml`. Set:
   - `spec_storage_mode: vault`
   - `spec_storage: projects/{project}/specs` (the `{project}` token is
     substituted per-spec from `--project` / per-spec `config.yml project:`)
   - `general_kb_path: <abs path to the general knowledge base>` (required)
   - `validate_scope:` and `tiers:` as desired (defaults fine)
   - `default_repos:` from the bindings collected in V2 (omit if none)
   Do **not** write `gate_pool`.
   - **Self-hosting exception:** if a `default_repos[]` entry resolves to the
     vault root dir itself, you MAY add an inline `gate_pool:` array (this
     repo's case). Otherwise the vault stays gateless.
5. Emit `repo_bound` per accepted binding:
   ```bash
   bash "$HOME/.claude/scripts/monitor.sh" log_event "_bootstrap" repo_bound "" \
     "$(printf '{"repo":"%s","path":"%s","role":"%s"}' "$name" "$path" "$role")"
   ```
6. Report: "Vault initialized. No gate_pool here. Run `/bootstrap`
   (repo-gate-init) once inside each target code repo."

## Step R — Repo gate init (target code repo)

Run inside a target code repo bound by a vault spec. Writes a thin
`.workflow.yml` carrying only the gate pool — no vault workflow settings.

1. Confirm `pwd` is a git work tree. If not, refuse: "repo-gate-init must run
   inside the target git repo."
   - Defensive guard: if a `.workflow.yml` is found walking up from `pwd` and it
     declares `spec_storage_mode: vault`, refuse: "this is the vault root, not a
     target code repo — run repo-gate-init inside the bound code repo instead."
2. `.workflow.yml` existence handling: same idempotent / `--force` / `--repair`
   symlink-safe rules as Step A (A1–A3).
3. Ask which languages this project uses (`AskUserQuestion`).
4. Write `$repo/.workflow.yml` (touch only this file). It is a **thin
   repo-gate-pool marker**, not a full workflow config:
   ```yaml
   kind: repo-gate-pool
   gate_pool:
     - { id: <lang>-lint,  command: "<lint cmd>",  applies_to: [<lang>], category: style,   blocking: true }
     - { id: <lang>-test,  command: "<test cmd>",  applies_to: [<lang>], category: testing, blocking: true }
   ```
   Seed one `gate_pool` entry per validation command for each selected
   language. The `kind: repo-gate-pool` marker makes the config loader skip
   this file when walking up for the real workflow config (vault owns that).
5. Report: "Repo gate-init complete: .workflow.yml (kind: repo-gate-pool)
   written with seeded gate_pool. Add project gates before running `/explore`
   from the vault."

## Step A — Write `.workflow.yml` (repo mode)

1. Check if `.workflow.yml` already exists at repo root.
   - If it **exists** and no `--force` / `--repair`: print current contents and
     stop this section (idempotent).
   - If it **exists** and `--repair`: verify `.workflow.yml` is not a symlink
     (`[[ ! -L .workflow.yml ]]`); if it is, refuse. Then read current fields;
     write only missing fields (never overwrite present values); go to A4.
   - If it **exists** and `--force`: go to A2.
   - If it **does not exist**: go to A3.
2. (`--force`) Resolve target with `realpath --no-symlinks`. If it differs from
   `$(pwd)/.workflow.yml` (symlink), refuse: "ERROR: .workflow.yml target is a
   symlink — refusing to overwrite." Show a `diff` against the template. Ask
   single-key confirmation before overwriting.
3. (fresh) Verify `$(pwd)/.workflow.yml` is not a symlink; if it is, refuse.
4. Write `.workflow.yml` from `~/.claude/templates/workflow.yml.template`.
   Touch only `.workflow.yml`. Leave `spec_storage_mode` commented (defaults
   to `repo`). Set a valid `general_kb_path` (required key). Ask which
   languages this project uses and write an inline `gate_pool:` array — one
   entry per validation command:
   ```yaml
   gate_pool:
     - { id: <lang>-lint,  command: "<lint cmd>",  applies_to: [<lang>], category: style,   blocking: true }
     - { id: <lang>-test,  command: "<test cmd>",  applies_to: [<lang>], category: testing, blocking: true }
   ```
5. Report: "Wrote .workflow.yml with inline gate_pool — add project gates
   before /explore." (or "Updated" for --force/--repair).
