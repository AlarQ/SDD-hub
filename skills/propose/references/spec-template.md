# Canonical spec.md shape (MANDATORY)

This file is the SINGLE SOURCE OF TRUTH for the spec.md shape. Generate spec.md exactly per the structure below.

spec.md uses structured sections so wire detail stays scannable/diffable. FR prose is **intent only** — no URLs, no status codes, no schema columns.

**FR block** — 1–3 sentences of intent + ref block. Refs are required when the FR maps to a contract / table / scenario:

```
### FR-2: Idempotent Category create
A user creating a Category with the same `(parent_id, name)` they already own
gets the existing row, not a duplicate. Concurrent creates resolve to one row.

**Contracts:** EP-CAT-CREATE
**Data:** category
**Scenarios:** idempotent-create-new, idempotent-create-existing, concurrent-create
```

**`## API Contracts` section** — one block per endpoint. **Skip the whole section if the spec has no endpoints.** Endpoint id grammar: `EP-<DOMAIN>-<VERB>` (uppercase, kebab).

```
### EP-CAT-CREATE — POST /v1/qanda/categories
**Auth:** session
**FRs:** FR-2, FR-6

**Request body**
```json
{ "name": "string", "parent_id": "UUID?" }
```

| Status | When | Body |
|--------|------|------|
| 201 | new row inserted | `Category { id, name, parent_id }` |
| 200 | existing row matched | `Category { id, name, parent_id }` |
| 404 | parent_id not owned by caller | `{ code: "category_not_found" }` |
| 400 | name invalid | `{ code: "validation_error" }` |
```

**`## Data Model` section** — one block per table/collection. **Skip the whole section if the spec changes no schema.** Migration sub-block only when destructive/multi-step.

```
### `category`
**FRs:** FR-1, FR-7

| Column | Type | Null | Default | Notes |
|--------|------|------|---------|-------|
| id | UUID | no | gen_random_uuid() | PK |
| user_id | UUID | no | — | FK users(id) ON DELETE CASCADE |
| parent_id | UUID | yes | — | FK category(id) ON DELETE RESTRICT |
| name | text | no | — | CHECK length 1..200, lowercase |

**Constraints**
- UNIQUE (user_id, parent_id, lower(name))
- INDEX (user_id, parent_id)

**Migration** (FR-7)
- File 1 (gated by `ALLOW_DESTRUCTIVE_MIGRATION`): …
- File 2: …
```

**Required spec.md section order:** `## Overview` → `## Functional Requirements` (FR blocks) → `## API Contracts` (conditional) → `## Data Model` (conditional) → `## Scenarios` (BDD with scenario ids referenced by FR blocks) → `## Security Scenarios` → `## User Flow` (medium/large). Tier-agnostic — conditional sections are driven by **endpoint/schema presence**, not tier.

**Hard rules** for spec.md authoring:
- FR prose ≤3 sentences. No URLs, status codes, JSON shapes, SQL, or column lists inside an FR.
- Every endpoint in scope appears as exactly one `### EP-…` block under `## API Contracts`.
- Every table/collection touched appears as exactly one `### \`tablename\`` block under `## Data Model`.
- Each BDD scenario gets a kebab-case `scenario-id` referenced from FR blocks via `**Scenarios:**`.

## User Flow Diagram (medium + large tiers)

After `## Security Scenarios`, add a `## User Flow` section containing one Mermaid `sequenceDiagram` block synthesized from the primary happy-path BDD scenario. Actor = end user; participants = the user-visible system surfaces named in spec.md (UI, API, store, external services). Every participant label MUST be a term defined elsewhere in spec.md. Style conventions per `docs/workflow-diagram.md` (solid arrows for direct flow, dashed `-->>` for async/return). Skip on `small`.
