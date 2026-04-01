---
applyTo: "knowledge-base/**"
---

# Knowledge Base Rules

## Dual Knowledge Base Structure

Two knowledge bases work together:

### General KB (`knowledge-base/_general/`)
Universal rules installed by `setup-copilot.sh`. Contains:
- `security/` — OWASP, CWE, input validation, secret handling
- `architecture/` — DDD, module boundaries, coupling, layering
- `testing/` — TDD/BDD principles, coverage requirements
- `style/` — naming conventions, module/function size limits
- `_index.md` — flat listing of all general rule files

**Do not modify general KB files.** Updates come from re-running `setup-copilot.sh`.

### Project KB (`knowledge-base/`)
Project-specific rules created by `/bootstrap`. Contains:
- `languages/` — per-language rules with validation tool definitions
- `conventions/` — project-specific conventions discovered via `/review-findings`
- `_index.md` — flat listing of all project-specific rule files

### ground_rules Prefix Convention
Task `ground_rules` use prefixes to reference rules from either KB:
- `general:security/general.md` → `knowledge-base/_general/security/general.md`
- `project:languages/rust.md` → `knowledge-base/languages/rust.md`
- Unprefixed paths default to `project:`

## Language Files
Language files in `knowledge-base/languages/` have YAML frontmatter defining mandatory validation tools:
```yaml
---
validation_tools:
  lint: "cargo clippy -- -D warnings"
  test: "cargo test"
  coverage: "cargo tarpaulin --out json"
  audit: "cargo audit"
  security: "semgrep --config auto --json"
---
```

These tools are mandatory — `/validate` must run every listed tool. Skipping is not allowed.

## Rule Quality
- Target 5-10 rules per file
- Rules must be specific and actionable
- Each rule should be something a validation gate can check against
- Update `knowledge-base/_index.md` when adding or removing project rule files

## Feedback Loop
When a validation finding is rejected during `/review-findings` and reveals a project convention, a new rule should be added to the appropriate **project** knowledge-base file (`knowledge-base/`). Never modify the general KB (`knowledge-base/_general/`). This keeps the project knowledge-base growing with project-specific patterns.
