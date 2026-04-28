# Shared config fixtures

Used by `tests/test-config-paths.sh` (T001) and `tests/test-config-loader.sh` (T002).

- `workflow-valid.yml`, `workflow-vault.yml` — well-formed `.workflow.yml` examples.
- `gates-valid.yml`, `gates-duplicate-id.yml` — gate-registry examples.
- `spec-config-valid.yml` — well-formed per-spec `config.yml`.
- `spec-config-unknown-gate.yml` — references an ID absent from `gates-valid.yml`; loader must exit 4.
- `billion-laughs.yml` — YAML alias bomb; loader must exit 5 via `timeout 5 yq`.
- `nested/deep/cwd` — used to exercise `find_workflow_root` walk-up from a nested cwd.
- `symlink-ancestor/` — symlink escape case for `realpath_safe`.
