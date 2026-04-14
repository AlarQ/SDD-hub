---
id: "005"
name: "TUI config parsers and models"
status: blocked
blocked_by: ["001"]
max_files: 9
estimated_files:
  - workflow-tui/src/model/workflow_config.rs
  - workflow-tui/src/model/spec_config.rs
  - workflow-tui/src/model/gate.rs
  - workflow-tui/src/parse/workflow_config.rs
  - workflow-tui/src/parse/spec_config.rs
  - workflow-tui/src/parse/gates.rs
  - workflow-tui/src/model/mod.rs
  - workflow-tui/src/parse/mod.rs
  - workflow-tui/Cargo.toml
test_cases:
  - "parse::workflow_config::load walks up from nested cwd"
  - "parse::workflow_config::load rejects ../../etc spec_storage path traversal"
  - "parse::spec_config::parse returns Ok(None) for missing file (legacy spec)"
  - "parse::gates::parse rejects duplicate gate IDs"
  - "parse::gates::parse rejects unknown applies_to enum value"
  - "parse::gates::parse rejects unknown category enum value"
  - "parse::spec_config::parse rejects unknown gate ID referencing gates.yml"
  - "parse::spec_config::parse rejects unknown agent ID referencing agent_pool"
  - "Parser never panics on malformed YAML input (returns Result::Err)"
  - "Parity: Rust parsers read shared fixtures from tests/fixtures/config/ (via CARGO_MANIFEST_DIR/../tests/fixtures/config) and reach same verdicts as shell loader"
  - "CI check fails if workflow-tui/tests/fixtures/config/ duplicates files from the shared set"
ground_rules:
  - general:languages/rust.md
  - general:architecture/general.md
  - general:security/general.md
  - general:testing/principles.md
---

## Description

Add Rust models and parsers for the three new YAML files. Pure data in `model/`; all IO and validation in `parse/`. Schema validation must agree with the shell loader (T2) so the TUI and shell scripts compute the same eligible gate set.

## Modules

### `model/`
- `workflow_config.rs` — `struct WorkflowConfig { spec_storage, gate_pool, agent_pool }`.
- `spec_config.rs` — `struct SpecConfig { tags, gates, agents: HashMap<Phase, Vec<String>> }`; `enum Phase { Explore, Propose, Implement, Validate, PrReview }`.
- `gate.rs` — `struct Gate { id, command, applies_to: Vec<Language>, category: Category, blocking }`.

### `parse/`
- `workflow_config.rs` — **only** locator of `.workflow.yml`. Walks up via `std::fs::canonicalize`. Symlink-ancestor rejection, path validation matching shell loader.
- `spec_config.rs` — per-spec parser. Returns `Ok(None)` when file missing.
- `gates.rs` — gates.yml parser. Rejects duplicates, unknown enums.

## Implementation Notes

- No `.unwrap()` in production code; use `Result<T, GateError>` (or domain-specific error enums via `thiserror`).
- Referential integrity check: `parse::spec_config` must reject IDs not present in the loaded `gates.yml` and `agent_pool` directory listing.
- Add `serde_yml` dep if not already present (Cargo.toml may need a single line).
- Pure parser functions — no global state, no env reads.
