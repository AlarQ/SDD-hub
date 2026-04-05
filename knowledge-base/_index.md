# General Knowledge Base — Index

Universal rules that apply to all projects. Installed globally via `setup.sh`.

Project-specific rules live in each repository's `knowledge-base/` directory.

## Rules

| File | Category | Description |
|------|----------|-------------|
| `security/general.md` | Security | OWASP Top 10, CWE Top 25, input validation, secret handling, least privilege |
| `architecture/general.md` | Architecture | Composition, modularity, module boundaries, coupling, dependency direction |
| `architecture/api-design.md` | Architecture | REST/GraphQL API design, HTTP methods, status codes, versioning, rate limiting |
| `architecture/code-analysis.md` | Architecture | Systematic analysis framework: context, gather, patterns, impact, recommendations |
| `testing/principles.md` | Testing | Testability, pure functions, Given/When/Then, coverage expectations |
| `style/general.md` | Style | Naming conventions, function/module size limits, anti-patterns |
| `documentation/general.md` | Documentation | README structure, function docs, comments, API docs, what/why principles |
| `code-review/general.md` | Code Review | Review checklist, severity levels, report format, common issues |
| `languages/rust.md` | Languages | Ownership, error handling, async/await, DDD patterns, testing with tokio/sqlx |
| `languages/typescript.md` | Languages | Strict mode, type safety, discriminated unions, utility types, module organization |
| `languages/nextjs.md` | Languages | Server/Client Components, data fetching, Server Actions, App Router conventions |
| `languages/scala.md` | Languages | Immutability, ADTs, pattern matching, for-comprehensions, Cats Effect |
| `languages/shell.md` | Languages | 150-line module limit, python3 as test dependency, shellcheck validation |
