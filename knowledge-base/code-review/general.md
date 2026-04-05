# Code Review Guidelines

## Rules

- **Review code as you'd want yours reviewed** — thoroughly but kindly
- **Focus on code, not person** — explain WHY something should change, suggest improvements
- **Prioritize security issues first** — check for hardcoded secrets, injection vulnerabilities, missing validation
- **Use severity levels** — Critical (must fix), Warning (should fix), Suggestion (nice to have)
- **Review within 24 hours** — don't block unnecessarily, prioritize critical issues
- **Acknowledge good work** — note positive patterns alongside issues

## Review Checklist

### Functionality
- Does what it's supposed to do
- Edge cases handled
- Error cases handled
- No obvious bugs

### Code Quality
- Clear, descriptive naming
- Functions small and focused
- No unnecessary complexity
- Follows project coding standards
- No duplication

### Security
- Input validation present
- No SQL/XSS injection vulnerabilities
- No hardcoded secrets
- Sensitive data handled properly
- Auth/authorization appropriate

### Testing
- Tests present for new/changed code
- Happy path, edge cases, and error cases covered
- All tests pass

### Performance
- No obvious performance issues
- Efficient algorithms
- Resources properly managed

### Maintainability
- Easy to understand
- Complex logic documented
- Follows project conventions
- Easy to modify/extend

## Report Format

```markdown
## Code Review: {Feature/PR Name}

**Summary:** {Brief overview}
**Assessment:** Approve / Needs Work / Requires Changes

### Issues Found

#### Critical (Must Fix)
- **File:** `src/auth.js:42`
  **Issue:** {description}
  **Fix:** {suggestion}

#### Warnings (Should Fix)
- ...

#### Suggestions (Nice to Have)
- ...

### Positive Observations
- {what was done well}

### Recommendations
- {next steps}
```

## Common Issues by Severity

### Critical
- Hardcoded credentials
- SQL/XSS injection vulnerabilities
- Missing input validation
- Exposed sensitive data

### Warning
- Large functions (>50 lines)
- Deep nesting (>3 levels)
- Code duplication
- Missing tests or low coverage (<80%)

### Suggestion
- Naming improvements
- Minor refactoring opportunities
- Documentation gaps
