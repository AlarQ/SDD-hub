Bootstrap the project-specific knowledge-base and workflow config for a new project.

Accepts optional flags as `$ARGUMENTS`: `--force` to overwrite existing `.workflow.yml`, `--repair` to fill only missing fields.

## Prerequisites
1. Read and follow `$WF_GENERAL_KB/_rules.md` — check general KB prerequisite only (project KB doesn't exist yet, this command creates it)

## Step A0 — Pick storage mode (vault vs repo)

Before writing `.workflow.yml`, ask via `AskUserQuestion` (per `~/.claude/scripts/ask-user-protocol.md`):

- **question:** "Where do specs live for this project?"
- **options:**
  - `repo` — specs/ live in this git repo (single-repo flow, default)
  - `vault` — specs/ live in this directory (e.g. master-brain Obsidian vault) and bind one or more external git repos for code

If the user picks `vault`:
1. Confirm `pwd` is **not** a git work tree (vault mode is incompatible with running from inside a code repo). If it is, refuse: "Vault mode requires running from a non-repo directory. cd to your vault and re-run `/bootstrap`."
2. Loop with `AskUserQuestion` to collect repo bindings — for each: `name` (kebab-case), `path` (absolute or `~`-prefixed), `role` (free text, e.g. `frontend`, `backend`, `ops`). Stop the loop when the user picks `Done`.
3. For each entry: verify `path` resolves to a git work tree (`git -C "<path>" rev-parse --show-toplevel`). Refuse the entry on failure.
4. Hold the bindings to write into `.workflow.yml` `default_repos:` in Step A.
5. Emit `repo_bound` per accepted entry:
   ```bash
   bash "$HOME/.claude/scripts/monitor.sh" log_event "_bootstrap" repo_bound "" \
     "$(printf '{"repo":"%s","path":"%s","role":"%s"}' "$name" "$path" "$role")"
   ```

Persist the chosen mode in memory for Step A as `STORAGE_MODE` (`repo` or `vault`).

## Step A — Write `.workflow.yml`

1. Check if `.workflow.yml` already exists at repo root.
   - If it **exists** and no `--force` / `--repair` flag: print current contents and stop this section (idempotent — no rewrite).
   - If it **exists** and `--repair`: verify `.workflow.yml` is not a symlink (`[[ ! -L .workflow.yml ]]`); if it is, refuse with the same error as above. Then read current fields; only write fields that are missing (never overwrite present values); go to A4.
   - If it **exists** and `--force`: go to A2.
   - If it **does not exist**: go to A3.

2. (`--force` path) Resolve `.workflow.yml` target path with `realpath --no-symlinks`. If the resolved path differs from `$(pwd)/.workflow.yml` (symlink detected), refuse and exit non-zero: "ERROR: .workflow.yml target is a symlink — refusing to overwrite."
   Show a `diff` between the existing file and `~/.claude/templates/workflow.yml.template`. Ask for single-key confirmation before overwriting.

3. (fresh path) Verify `$(pwd)/.workflow.yml` is not a symlink (`[[ ! -L .workflow.yml ]]`). If it is, refuse: same error as above.

4. Write `.workflow.yml` from `~/.claude/templates/workflow.yml.template`. Touch **only** `.workflow.yml` — no other files.
   - If `STORAGE_MODE=vault`: set `spec_storage_mode: vault` and `default_repos:` to the bindings collected in A0. Otherwise leave both fields commented (defaults to `repo`).

5. Report: "Wrote .workflow.yml" (or "Updated .workflow.yml" for --force/--repair).

## Step B — Write project knowledge-base

If `STORAGE_MODE=vault`: skip Step B entirely. The vault directory does not host a project KB; each bound repo keeps its own `knowledge-base/` (created by running `/bootstrap` inside that repo). Print: "Vault mode — skipping project KB. Run `/bootstrap` inside each bound repo to create its `knowledge-base/`."

1. Check if `knowledge-base/` already exists — if yes, skip to Step B6 (do not overwrite).
2. Read `$WF_GENERAL_KB/_index.md`. Summarize to the user which categories and topics are already covered by the general KB (security, architecture, testing, style, documentation, code-review, any language files). Keep this list in context for all subsequent steps — do not create project rules that duplicate these topics.
3. Create the directory structure:
   - `knowledge-base/_index.md`
   - `knowledge-base/languages/`
   - `knowledge-base/conventions/`
4. Ask the user which languages this project uses
5. Create language files (no frontmatter) for each selected language. For languages already covered by a general KB file (e.g. `$WF_GENERAL_KB/languages/rust.md`), only add rules that are project-specific — do not re-state rules already present in the general KB file. Then add executable gate entries (one per validation command) to `knowledge-base/gates.yml` with `id`, `command`, `applies_to: [<language>]`, `category`, and `blocking: true`. `gates.yml` is the canonical gate registry.
6. Generate `_index.md` listing all created files with descriptions
7. Report what was created

The general knowledge base (security, architecture, testing, style rules) is installed globally at `$WF_GENERAL_KB/` by `setup.sh` and applies to all projects automatically. This command creates only project-specific rules:

- `languages/` — language-specific patterns and rules (executable gates live in `knowledge-base/gates.yml`)
- `conventions/` — project-specific conventions discovered over time (via `/review-findings` feedback loop)

Target: ~5-10 rules per file. Rules should be specific and actionable — each rule should be something a validation gate can check against.

## Step C — Write gate registry

1. Check if `knowledge-base/gates.yml` already exists — if yes, skip (idempotent).
2. Write `knowledge-base/gates.yml` from `~/.claude/templates/gates.yml.template`.
3. Report: "Wrote knowledge-base/gates.yml — add project gates before running /explore."
