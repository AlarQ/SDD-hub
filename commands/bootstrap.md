Bootstrap workflow config and/or the project knowledge-base. Two distinct
modes — a vault is set up **once**; each target code repo is set up **once**.

Accepts optional flags as `$ARGUMENTS`: `--force` to overwrite an existing
`.workflow.yml`, `--repair` to fill only missing fields.

## Prerequisites
1. Read and follow `$WF_GENERAL_KB/_rules.md` — general KB prerequisite only
   (project KB may not exist yet; repo-gate-init creates it).

## Step A0 — Pick mode

Ask via `AskUserQuestion` (per `~/.claude/scripts/ask-user-protocol.md`):

- **question:** "What are you bootstrapping?"
- **options:**
  - `vault-init` — this directory is the master-brain vault that will hold
    all specs. Write a thin-pointer `.workflow.yml` only. **No** gates.yml or
    knowledge-base/ is created here — those live in the target code repos.
  - `repo-gate-init` — this directory is a target code repo bound by a vault
    spec. Create its `knowledge-base/` + `gates.yml`. Do **not** write a
    `.workflow.yml` (the vault owns it).
  - `repo` — standalone single-repo project (specs live in-repo, repo mode).
    Write `.workflow.yml` **and** `knowledge-base/` + `gates.yml`.

Branch on the answer: `vault-init` → Step V only. `repo-gate-init` → Step R
only. `repo` → Step A then Step B then Step C (legacy single-repo flow).

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
   Do **not** write `gate_pool`, do **not** create `knowledge-base/` or
   `gates.yml` in the vault.
5. Emit `repo_bound` per accepted binding:
   ```bash
   bash "$HOME/.claude/scripts/monitor.sh" log_event "_bootstrap" repo_bound "" \
     "$(printf '{"repo":"%s","path":"%s","role":"%s"}' "$name" "$path" "$role")"
   ```
6. Report: "Vault initialized. gates.yml + knowledge-base/ are NOT created
   here. Run `/bootstrap` (repo-gate-init) once inside each target code repo."

## Step R — Repo gate init (target code repo)

Run inside a target code repo bound by a vault spec. Creates the repo's gate
registry + project KB. Does **not** write `.workflow.yml`.

1. Confirm `pwd` is a git work tree. If not, refuse: "repo-gate-init must run
   inside the target git repo."
   - Defensive guard: if a `.workflow.yml` is found walking up from `pwd` and it
     declares `spec_storage_mode: vault`, refuse: "this is the vault root, not a
     target code repo — run repo-gate-init inside the bound code repo instead."
     (Prevents `gates.yml`/`knowledge-base/` from ever landing in the vault.)
2. Create the project knowledge-base (same as Step B steps 1–7 below) and the
   gate registry (same as Step C below), in this repo.
3. Do **not** create or modify `.workflow.yml` here — the vault owns workflow
   config; gates/KB resolve per-task from this repo via the spec's `repos[]`.
4. Report: "Repo gate-init complete: knowledge-base/ + gates.yml created. Add
   project gates before running `/explore` from the vault."

## Step A — Write `.workflow.yml` (repo mode only)

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
   to `repo`). Set a valid `general_kb_path` (required key).
5. Report: "Wrote .workflow.yml" (or "Updated" for --force/--repair).

## Step B — Write project knowledge-base

1. If `knowledge-base/` already exists — skip to B6 (do not overwrite).
2. Read `$WF_GENERAL_KB/_index.md`. Summarize covered categories/topics to the
   user; do not create project rules that duplicate them.
3. Create: `knowledge-base/_index.md`, `knowledge-base/languages/`,
   `knowledge-base/conventions/`.
4. Ask which languages this project uses.
5. Create language files (no frontmatter) per selected language — only
   project-specific rules beyond the general KB. Add executable gate entries
   (one per validation command) to `knowledge-base/gates.yml` with `id`,
   `command`, `applies_to: [<language>]`, `category`, `blocking: true`.
6. Generate `_index.md` listing all created files with descriptions.
7. Report what was created.

Target: ~5-10 rules per file. Each rule should be something a gate can check.

## Step C — Write gate registry

1. If `knowledge-base/gates.yml` already exists — skip (idempotent).
2. Write `knowledge-base/gates.yml` from `~/.claude/templates/gates.yml.template`.
3. Report: "Wrote knowledge-base/gates.yml — add project gates before /explore."
