Bootstrap the knowledge-base for a new project.

## Steps
1. Check if `knowledge-base/` already exists — if yes, report and stop (don't overwrite)
2. Create the directory structure:
   - `knowledge-base/_index.md`
   - `knowledge-base/security/`
   - `knowledge-base/architecture/`
   - `knowledge-base/languages/`
   - `knowledge-base/testing/`
   - `knowledge-base/style/`
3. Read `~/.claude/rules/code-quality.md` and `~/.claude/rules/security-patterns.md`
4. Seed initial rule files by migrating relevant rules from the global files:
   - `security/general.md` — from security-patterns.md (OWASP, validation, secret handling)
   - `architecture/general.md` — from code-quality.md (composition, modularity, boundaries)
   - `testing/principles.md` — from code-quality.md (testability, pure functions)
   - `style/general.md` — from code-quality.md (naming, module/function size)
5. Ask the user which languages this project uses
6. Create language files with `validation_tools` frontmatter for each selected language
7. Generate `_index.md` listing all created files with descriptions
8. Report what was created

Target: ~5-10 rules per file. Rules should be specific and actionable — each rule should be something a validation gate can check against.
