# Code Analysis Framework

## Rules

- **Follow the process** — Context → Gather → Patterns → Impact → Recommendations
- **Be evidence-based** — base conclusions on code, not assumptions
- **Be specific** — include file paths, line numbers, and code snippets
- **Be actionable** — every finding should have a clear recommendation
- **Prioritize findings** — use severity levels (Critical / Warning / Suggestion)
- **Consider trade-offs** — document pros/cons of each recommendation

## Analysis Process

### 1. Understand Context
- What are we analyzing and why?
- What's the scope and constraints?

### 2. Gather Information
- Read relevant code and documentation
- Search for patterns and related issues
- Examine dependencies

### 3. Identify Patterns
- What's consistent across the codebase?
- What conventions are followed?
- What's inconsistent or unusual?

### 4. Assess Impact
- What are the implications and trade-offs?
- What could break? What are the risks?

### 5. Provide Recommendations
- What should be done and why?
- What are the alternatives?
- What's the priority?

## Analysis Report Format

```markdown
## Analysis: {Topic}

**Context:** {What and why}

**Findings:**
- {Key finding with evidence}

**Issues Identified:**
- Critical: {Must address}
- Warning: {Should address}
- Suggestion: {Nice to have}

**Recommendations:**
1. {Action} — {Rationale}

**Trade-offs:**
- {Approach}: {Pros/Cons}
```

## Common Analysis Types

- **Code Quality** — complexity, duplication, coverage, naming, error handling
- **Architecture** — dependencies, coupling/cohesion, separation of concerns, scalability
- **Bug Investigation** — reproduce, root cause, impact, proposed fix, edge cases
- **Pattern Discovery** — similar implementations, conventions, inconsistencies, standardization opportunities
