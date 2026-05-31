---
id: "010"
name: "coverage-feature"
status: implemented
blocked_by: []
ground_rules:
  - languages/shell/_index.md
---

# Coverage feature task

## Acceptance

| # | Given | When | Then |
|---|-------|------|------|
| 1 | a logged-out user | they submit valid credentials | a session starts |
| 2 | an expired token | a request arrives | re-authentication is required |

## Implements

| FR | FR-2, FR-5 |
