Bootstrap the project-specific knowledge-base for a new project.

## Prerequisites
1. Read and follow `~/.claude/knowledge-base-rules.md` — check general KB prerequisite only (project KB doesn't exist yet, this command creates it)

## Steps
1. Check if `knowledge-base/` already exists — if yes, report and stop (don't overwrite)
2. Read `~/.claude/knowledge-base/_index.md`. Summarize to the user which categories and topics are already covered by the general KB (security, architecture, testing, style, documentation, code-review, any language files). Keep this list in context for all subsequent steps — do not create project rules that duplicate these topics.
3. Create the directory structure:
   - `knowledge-base/_index.md`
   - `knowledge-base/languages/`
   - `knowledge-base/conventions/`
4. Ask the user which languages this project uses
5. Create language files with `validation_tools` frontmatter for each selected language. For languages already covered by a general KB file (e.g. `~/.claude/knowledge-base/languages/rust.md`), only add rules that are project-specific — do not re-state rules already present in the general KB file.
6. Generate `_index.md` listing all created files with descriptions
7. Report what was created

The general knowledge base (security, architecture, testing, style rules) is installed globally at `~/.claude/knowledge-base/` by `setup.sh` and applies to all projects automatically. This command creates only project-specific rules:

- `languages/` — per-language validation tool definitions and language-specific patterns
- `conventions/` — project-specific conventions discovered over time (via `/review-findings` feedback loop)

Target: ~5-10 rules per file. Rules should be specific and actionable — each rule should be something a validation gate can check against.
