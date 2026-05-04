Bootstrap the project-specific knowledge-base and workflow config for a new project.

Accepts optional flags as `$ARGUMENTS`: `--force` to overwrite existing `.workflow.yml`, `--repair` to fill only missing fields.

## Prerequisites
1. Read and follow `~/.claude/knowledge-base-rules.md` — check general KB prerequisite only (project KB doesn't exist yet, this command creates it)

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

5. Report: "Wrote .workflow.yml" (or "Updated .workflow.yml" for --force/--repair).

## Step B — Write project knowledge-base

1. Check if `knowledge-base/` already exists — if yes, skip to Step B6 (do not overwrite).
2. Read `~/.claude/knowledge-base/_index.md`. Summarize to the user which categories and topics are already covered by the general KB (security, architecture, testing, style, documentation, code-review, any language files). Keep this list in context for all subsequent steps — do not create project rules that duplicate these topics.
3. Create the directory structure:
   - `knowledge-base/_index.md`
   - `knowledge-base/languages/`
   - `knowledge-base/conventions/`
4. Ask the user which languages this project uses
5. Create language files (no frontmatter) for each selected language. For languages already covered by a general KB file (e.g. `~/.claude/knowledge-base/languages/rust.md`), only add rules that are project-specific — do not re-state rules already present in the general KB file. Then add executable gate entries (one per validation command) to `knowledge-base/gates.yml` with `id`, `command`, `applies_to: [<language>]`, `category`, and `blocking: true`. `gates.yml` is the canonical gate registry.
6. Generate `_index.md` listing all created files with descriptions
7. Report what was created

The general knowledge base (security, architecture, testing, style rules) is installed globally at `~/.claude/knowledge-base/` by `setup.sh` and applies to all projects automatically. This command creates only project-specific rules:

- `languages/` — language-specific patterns and rules (executable gates live in `knowledge-base/gates.yml`)
- `conventions/` — project-specific conventions discovered over time (via `/review-findings` feedback loop)

Target: ~5-10 rules per file. Rules should be specific and actionable — each rule should be something a validation gate can check against.

## Step C — Write gate registry

1. Check if `knowledge-base/gates.yml` already exists — if yes, skip (idempotent).
2. Write `knowledge-base/gates.yml` from `~/.claude/templates/gates.yml.template`.
3. Report: "Wrote knowledge-base/gates.yml — add project gates before running /explore."
