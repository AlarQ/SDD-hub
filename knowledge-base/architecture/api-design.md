# API Design Principles

## Rules

- **Resource-based URLs** — use nouns not verbs (`GET /users`, not `GET /getUsers`)
- **Appropriate HTTP methods** — GET (read), POST (create), PUT (replace), PATCH (partial update), DELETE (remove)
- **Standard status codes** — 200/201/204 for success; 400/401/403/404/409/422 for client errors; 500/503 for server errors
- **Consistent response format** — standardize `{ data, meta, error }` structure across all endpoints
- **Paginate collections** — always support `page`, `pageSize`, and return total count
- **Support filtering and sorting** — `?status=active&sort=createdAt:desc`
- **Shallow nesting** — `GET /users/123/posts` is fine; `GET /users/123/posts/456/comments/789` is not (use `GET /comments/789`)
- **Version your API** — URL versioning (`/v1/users`) or header versioning; plan for breaking changes
- **HTTPS everywhere** — encrypt all API traffic
- **Validate all inputs** — never trust client data; use schema validation (Zod, JSON Schema)
- **Implement rate limiting** — prevent abuse and ensure fair usage
- **Use caching when applicable** — implement ETags, Cache-Control headers where caching makes sense (not all endpoints benefit from caching)

## Response Formats

### Success
```json
{ "data": { ... }, "meta": { "timestamp": "..." } }
```

### Error
```json
{ "error": { "code": "VALIDATION_ERROR", "message": "...", "details": [...] } }
```

### Collection
```json
{ "data": [...], "meta": { "total": 100, "page": 1, "pageSize": 20 }, "links": { "self": "...", "next": "..." } }
```

## Anti-Patterns

- Exposing internal/sequential IDs — use UUIDs or opaque identifiers
- Returning too much data — support field selection
- Ignoring idempotency — PUT/PATCH/DELETE should be idempotent
- Inconsistent naming — pick camelCase or snake_case and stick with it
- No rate limiting — protect against abuse
- Verbose error messages — don't leak implementation details
- Synchronous long operations — use async jobs with polling/webhooks

## Versioning Strategy

- Communicate deprecation via `Deprecation` and `Sunset` response headers
- Provide migration guides for breaking changes
- Support at least one previous version during transition
