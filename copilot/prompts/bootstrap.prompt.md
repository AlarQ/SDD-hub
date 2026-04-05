---
name: bootstrap
description: Create the project-specific knowledge-base for a new project
agent: 'agent'
---

Bootstrap the project-specific knowledge-base for a new project.

## Prerequisites
1. Check that `knowledge-base/_general/` (general knowledge base) exists — if not, refuse and say: "General knowledge base not found. Run `setup-copilot.sh` from the dev-workflow repo first."

## Steps
1. Check if `knowledge-base/` already exists (excluding `_general/`) — if project-specific files exist, report and stop (don't overwrite)
2. Create the directory structure:
   - `knowledge-base/_index.md`
   - `knowledge-base/languages/`
   - `knowledge-base/conventions/`
3. Ask the user which languages this project uses
4. Create language files with `validation_tools` frontmatter for each selected language
5. Generate `_index.md` listing all created files with descriptions
6. Report what was created

The general knowledge base (security, architecture, testing, style rules) is installed at `knowledge-base/_general/` by `setup-copilot.sh` and applies to all projects automatically. This command creates only project-specific rules:

- `languages/` — per-language validation tool definitions and language-specific patterns
- `conventions/` — project-specific conventions discovered over time (via `/review-findings` feedback loop)

Target: ~5-10 rules per file. Rules should be specific and actionable — each rule should be something a validation gate can check against.
