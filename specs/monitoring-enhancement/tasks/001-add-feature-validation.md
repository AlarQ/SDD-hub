---
id: "001"
name: add-feature-validation
title: Add feature name validation to monitor.sh choke points
status: done
pr_url: https://github.com/AlarQ/SDD-hub/pull/22
blocked_by: []
max_files: 3
estimated_files:
  - "scripts/monitor.sh"
  - "tests/test-monitor.sh"
  - ".gitignore"
ground_rules:
  - "general:security/general.md"
  - "general:architecture/general.md"
  - "general:style/general.md"
  - "general:languages/shell.md"
test_cases:
  - "set_context with valid feature name succeeds"
  - "set_context with path traversal feature rejects with exit 1"
  - "set_context with spaces in feature rejects with exit 1"
  - "set_context with empty feature fails via bash guard"
  - "get_monitor_file with slashes in feature rejects with exit 1"
  - "log_event with malicious feature is blocked by get_monitor_file validation"
  - "poisoned context file values are rejected by get_monitor_file when passed through log_event"
  - "set_context with different values overwrites previous context"
  - "set_context writes exactly feature and task lines, nothing else"
  - "set_context + read_context round-trip returns correct values"
  - "clear_context removes file created by set_context"
  - "task ID with path characters is rejected by existing validate_id"
  - ".gitignore matches .monitor-context pattern"
---

# Task: Add feature name validation to monitor.sh choke points

## Description

Add `validate_id "$feature" "feature" || return 1` to two functions in `scripts/monitor.sh`:
1. `get_monitor_file()` — before path construction (the path choke point)
2. `set_context()` — before writing the context file (the persistence choke point)

These are the two security surfaces identified in ADR-002. All other public functions (`log_event`, `start_phase`, `end_phase`) flow through `get_monitor_file`, so they are transitively protected.

## Files

- `scripts/monitor.sh`

## Acceptance Criteria

- `get_monitor_file` calls `validate_id "$feature" "feature" || return 1` as its first line
- `set_context` calls `validate_id "$feature" "feature" || return 1` before the existing `validate_id "$task_id"` check
- Valid feature names (`my-feature`, `auth_module`, `feature123`) pass through
- Path traversal (`../../etc/passwd`) is rejected with exit 1 and stderr message
- Slashes (`my/feature`) are rejected
- Spaces (`my feature`) are rejected
- `bash -n scripts/monitor.sh` passes
- `shellcheck scripts/monitor.sh` passes (or only pre-existing warnings)

## Implementation Notes

The change is exactly 2 lines of code added. Add a comment at the top of the Public API section noting the validation contract: "All public functions receiving a feature parameter must either validate_id it directly or flow through get_monitor_file which validates."

### Decisions Made

- Added `validate_id "$feature" "feature" || return 1` as the first line of `get_monitor_file()`, before `find_project_root` — path construction never happens with an invalid feature.
- Added `validate_id "$feature" "feature" || return 1` to `set_context()` before the existing `validate_id "$task_id"` check — feature validation is more fundamental and should short-circuit first.
- Added a doc comment block above the Public API section explaining the transitive protection contract (log_event, start_phase, end_phase are covered via get_monitor_file).
- Added `.monitor-context` to `.gitignore` — required by the spec and test-strategy.
- Tests use CLI mode (`"$MONITOR_SCRIPT" set_context ...`) for dispatch coverage as directed by test-strategy.md. Tests that need to call internal helpers (get_monitor_file, read_context) still source the script.
- `test_set_context_empty_feature_fails` verifies the `${1:?...}` bash guard fires — the empty string passes the regex trivially, so the guard is the actual protection. Test confirms non-zero exit only.
- ADR-003 accepted: monitor.sh is now ~225 lines, exceeding the 150-line shell limit. Documented in design.md.
