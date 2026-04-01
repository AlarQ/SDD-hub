# Style Rules

## Function and Module Size
1. **Small functions** — target < 50 lines per function; extract helper functions when a function grows beyond this
2. **Small modules** — target < 100 lines per file; split into focused modules when a file grows beyond this
3. **Avoid deep nesting** — max 3 levels of indentation; use early returns, guard clauses, or extraction to flatten

## Naming Conventions
4. **Files**: `lowercase-with-dashes` (e.g., `user-service.ts`, `auth-middleware.py`)
5. **Functions**: `verbPhrases` — start with a verb describing the action (e.g., `getUser`, `validateEmail`, `parseConfig`)
6. **Predicates**: `is`/`has`/`can` prefix (e.g., `isValid`, `hasPermission`, `canAccess`)
7. **Variables**: descriptive names, `const` by default; avoid abbreviations except well-known ones (`id`, `url`, `db`)
8. **Constants**: `UPPER_SNAKE_CASE` (e.g., `MAX_RETRIES`, `DEFAULT_TIMEOUT`)

## Anti-Patterns to Avoid
9. **No god modules** — a module that knows too much or does too much; split by responsibility
10. **No global mutable state** — use immutability by default; create new data rather than mutating existing structures
