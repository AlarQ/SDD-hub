---
id: "008"
name: "Config inferencer agent definition"
status: todo
blocked_by: ["001"]
max_files: 2
estimated_files:
  - agents/engineering/engineering-config-inferencer.md
  - tests/test-inferencer-schema.sh
test_cases:
  - "Inferencer output parses as valid spec config.yml"
  - "All emitted gate IDs resolve in gates.yml"
  - "All emitted agent IDs resolve under agent_pool"
  - "Inferencer prompt forbids reading .env*, *.pem, id_*, .git/config"
  - "Timeout fallback path produces manual-entry prompt or default template"
  - "Schema-shape test passes (no golden fixtures per design risk)"
  - "Negative-shape: given Cargo.toml-only signals, output MUST include >=1 gate with applies_to containing rust AND MUST NOT include python/js-only gates"
  - "Inferencer inputs and outputs logged to monitor events for offline review"
ground_rules:
  - general:security/general.md
  - general:architecture/general.md
  - general:testing/principles.md
  - general:documentation/general.md
---

## Description

New agent at `agents/engineering/engineering-config-inferencer.md` (ID: `engineering/config-inferencer`). Reads repo signal files, `gates.yml`, `agent_pool` directory listing, and the spec PRD/description. Outputs a draft `specs/<feature>/config.yml` matching the schema in `design.md §Backend Design`.

## Inputs (allowed)

- `Cargo.toml`, `package.json`, `go.mod`, `requirements.txt`, `pyproject.toml`, `go.sum` (language detection)
- `knowledge-base/gates.yml` (gate ID universe)
- `agent_pool` directory listing (agent ID universe)
- Spec PRD / description

## Inputs (forbidden — secret hygiene)

`.env*`, `*.pem`, `id_*`, `.git/config`. Agent prompt explicitly excludes these. Documented in agent definition.

## Output Contract

YAML matching `specs/<feature>/config.yml` schema:
- `tags: [list]`
- `gates: [list of valid IDs]`
- `agents: { phase: [list of valid IDs] }`

All IDs must resolve at validation time — schema-shape test enforces this without locking on specific values (LLM nondeterminism, per design MEDIUM risk).

## Fallback

Inferencer timeout or error → user is shown a manual-entry prompt; if skipped, a default template is written. Documented in agent definition.

## Implementation Notes

- No golden-fixture tests. Schema shape only.
- Test wraps a recorded sample output through `yq` validation against the spec config schema.
