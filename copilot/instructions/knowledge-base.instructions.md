---
applyTo: "knowledge-base/**"
---

# Knowledge Base Rules

## Structure
The knowledge-base contains actionable coding rules organized by category:
- `security/` — OWASP, CWE, input validation, secret handling
- `architecture/` — DDD, module boundaries, coupling, layering
- `languages/` — per-language rules with validation tool definitions
- `testing/` — TDD/BDD principles, coverage requirements
- `style/` — naming conventions, module/function size limits
- `_index.md` — flat listing of all rule files with one-line descriptions

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
- Update `_index.md` when adding or removing rule files

## Feedback Loop
When a validation finding is rejected during `/review-findings` and reveals a project convention, a new rule should be added to the appropriate knowledge-base file. This keeps the knowledge-base growing with project-specific patterns.
