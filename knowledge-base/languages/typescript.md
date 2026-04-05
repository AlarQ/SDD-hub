# TypeScript Code Quality Standards

validation_tools:
  - npx tsc --noEmit
  - npm test

## Rules

- **Strict mode always** — `strict: true` in tsconfig.json with `noUncheckedIndexedAccess`
- **No `any`** — use `unknown` with type guards; `any` bypasses the type system entirely
- **No non-null assertion (`!`)** — handle null explicitly with optional chaining and nullish coalescing
- **Explicit return types on public APIs** — inference is fine for simple internal functions
- **Interface for object shapes, type for unions** — interfaces extend; types compose
- **Discriminated unions for state** — use a `status` field to narrow types safely
- **Result pattern for fallible operations** — `{ success: true, data } | { success: false, error }`

## Naming

- **Interfaces/Types**: `PascalCase` (UserRepository, ApiResponse)
- **Generics**: single letter (`T`, `K`) or descriptive (`TItem`, `TConfig`)
- **Enums**: `PascalCase` name and members; prefer `as const` objects over enums

## Type Safety Patterns

```typescript
// Use unknown + type guard instead of any
function isUser(data: unknown): data is User {
  return typeof data === 'object' && data !== null && 'id' in data;
}

// Discriminated union
type AsyncState<T> =
  | { status: 'loading' }
  | { status: 'success'; data: T }
  | { status: 'error'; error: string };

// Null safety
const userName = user?.profile?.name ?? 'Anonymous';
```

## Utility Types

- `Partial<T>` — for updates
- `Pick<T, K>` / `Omit<T, K>` — for subsets
- `Record<K, V>` — for dictionaries
- `ReturnType<typeof fn>` — extract return types

## Module Organization

- Export only what's needed — keep internals private
- Use barrel files (`index.ts`) for clean imports
- Explicit named exports over default exports

## Anti-Patterns

- `any` type — bypasses all type checking
- Non-null assertion (`!`) — hides potential null bugs
- `ts-ignore` without explanation
- `useEffect` for data fetching (use SWR/TanStack Query)
- Deep `as` casting chains — rethink the types
