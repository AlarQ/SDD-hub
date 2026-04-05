# Documentation Standards

## Rules

- **Document WHY, not WHAT** — code should be self-explanatory; comments explain decisions, trade-offs, and non-obvious behavior
- **Golden rule** — if users ask the same question twice, document it
- **Audience-focused** — write for users (what/how), developers (why/when), contributors (setup/conventions)
- **Show don't tell** — include code examples, real use cases, and expected output
- **Keep current** — update docs with code changes, remove outdated info, mark deprecations
- **Don't document the obvious** — `i++` doesn't need a comment; `getUser()` doesn't need "get user"

## README Structure

Every project README should follow:

1. **Project name** + brief description (1-2 sentences)
2. **Features** — key capabilities
3. **Installation** — setup commands
4. **Quick Start** — minimal working example
5. **Usage** — detailed examples
6. **API Reference** — if applicable
7. **Contributing** — link to CONTRIBUTING.md
8. **License**

## Function Documentation

- Document public API functions with purpose, parameters, return value, and example
- Skip documentation for internal/private helpers unless logic is complex
- Use language-native doc formats (JSDoc, rustdoc, scaladoc)

## Comments

### Good Comments

```
// HACK: API returns null instead of [], normalize it
// TODO: Use async/await when Node 18+ is minimum
// Calculate discount by tier (Bronze: 5%, Silver: 10%, Gold: 15%)
```

### Bad Comments

```
// Increment i
// Get user
// Set the value
```

## API Documentation

For each endpoint, document:
- Method + path
- Brief description
- Request body (with example)
- Response body (with example)
- Error codes and meanings
