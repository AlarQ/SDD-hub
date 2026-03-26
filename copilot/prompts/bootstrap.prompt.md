---
name: bootstrap
description: Create the knowledge-base for a new project
agent: 'agent'
---

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
3. Seed initial rule files with general best practices:
   - `security/general.md` — OWASP, input validation, secret handling, least privilege
   - `architecture/general.md` — composition over inheritance, modularity, boundary design
   - `testing/principles.md` — testability, pure functions, Given/When/Then
   - `style/general.md` — naming conventions, module/function size limits
4. Ask the user which languages this project uses
5. Create language files with `validation_tools` frontmatter for each selected language
6. Generate `_index.md` listing all created files with descriptions
7. Report what was created

Target: ~5-10 rules per file. Rules should be specific and actionable — each rule should be something a validation gate can check against.
