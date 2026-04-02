# Next.js Code Quality Standards

validation_tools:
  - npx tsc --noEmit
  - npm test
  - npx next lint

## Rules

- **Server Components by default** — add `'use client'` only for interactivity, browser APIs, or React hooks
- **Server-side data fetching** — fetch in Server Components, not with `useEffect`
- **Server Actions for mutations** — use `'use server'` functions for form submissions and data mutations
- **Suspense boundaries for streaming** — wrap async content in `<Suspense>` with skeleton fallbacks
- **Parallel data fetching** — use `Promise.all` when fetching independent data
- **Validate inputs with Zod** — especially in Server Actions and API routes
- **Keep Client Components small** — position them as leaf nodes; pass server-fetched data as props

## Component Decision

```
Need to:
├── Fetch data on server? → Server Component
├── Access browser APIs? → Client Component
├── Handle user interactions? → Client Component
├── Use React hooks? → Client Component
└── Just render UI with props? → Server Component
```

## Data Fetching

- **Server Components**: `await fetch()` with `next: { revalidate }` or `next: { tags }`
- **Client Components**: SWR or TanStack Query (never raw `useEffect`)
- **Caching**: use `revalidateTag()` and `revalidatePath()` for on-demand revalidation

## App Router Conventions

```
app/
├── layout.tsx       # Root layout
├── page.tsx         # Route page
├── loading.tsx      # Route-level loading skeleton
├── error.tsx        # Route-level error boundary ('use client')
├── not-found.tsx    # Route-level 404
└── [id]/page.tsx    # Dynamic route
```

## Anti-Patterns

- `'use client'` on entire pages — push client boundary to smallest interactive component
- `useEffect` for data fetching — use server-side fetching or SWR/TanStack Query
- Prop drilling through Client Components — use composition (Server wraps Client)
- Missing Suspense boundaries — causes full-page loading instead of streaming
- `cache: 'no-store'` everywhere — use appropriate revalidation strategies
