---
feature: monitoring-enhancement
status: draft
created: 2026-04-12
---

# Spec: Wire Monitor Context into Workflow Commands

## Overview

Wire the existing monitoring infrastructure into the `/implement` and `/ship` slash commands so that `.monitor-context` is set/cleared during the task lifecycle. Additionally, close the path-traversal vulnerability where the `feature` parameter flows unsanitized into file path construction in `monitor.sh`.

## Functional Specification

### 1. `/implement` Sets Monitor Context

When `/implement` begins executing a task (after setting status to `in-progress`), it calls:

```
~/.claude/scripts/monitor.sh set_context <feature> <task_id>
```

This creates `.monitor-context` in the project root with the active feature and task ID. The PostToolUse hook (`monitor-tool-calls.sh`) reads this file to determine whether to log events.

### 2. `/ship` Clears Monitor Context

After `/ship` successfully creates a PR (Step 7), it calls:

```
~/.claude/scripts/monitor.sh clear_context
```

This removes `.monitor-context`, stopping event logging for the completed task.

### 3. Feature Name Validation in `monitor.sh`

Apply the existing `validate_id` function to the `feature` parameter in:
- `get_monitor_file()` — the path construction choke point
- `set_context()` — the context persistence choke point

The `validate_id` regex (`^[a-zA-Z0-9_-]+$`) blocks path separators, parent directory traversal, null bytes, and shell metacharacters.

## Scenarios

### Context Lifecycle

#### Scenario: Monitor context is set when implementation starts
- **Given** a task with `status: todo` is selected by task-manager.sh
- **When** `/implement` sets the task status to `in-progress`
- **Then** `monitor.sh set_context <feature> <task_id>` is called
- **And** `.monitor-context` contains `feature=<name>` and `task=<task_id>`

#### Scenario: Monitor context is cleared after PR creation
- **Given** a task has been validated and is ready to ship
- **When** `/ship` successfully creates a PR via `gh pr create`
- **Then** `monitor.sh clear_context` is called
- **And** `.monitor-context` no longer exists in the project root

#### Scenario: Monitor context persists on /ship failure
- **Given** `.monitor-context` exists with an active task
- **When** `/ship` fails before PR creation (e.g., push fails)
- **Then** `.monitor-context` is NOT cleared
- **And** monitoring continues for the in-flight task

#### Scenario: Monitor context is overwritten by next task
- **Given** a stale `.monitor-context` exists from a previously interrupted task
- **When** `/implement` starts the next task
- **Then** `set_context` overwrites the stale file with the new feature/task
- **And** no manual cleanup is required

### Input Validation

#### Scenario: Valid feature name is accepted
- **Given** a feature name matching `^[a-zA-Z0-9_-]+$`
- **When** `set_context` is called with this feature name
- **Then** the context file is created successfully
- **And** no error is raised

#### Scenario: Feature name with path traversal is rejected
- **Given** a feature name containing `../` (e.g., `../../etc`)
- **When** any public API function is called with this feature name
- **Then** the function returns exit code 1
- **And** an error message is printed to stderr: "ERROR: Invalid feature: must be alphanumeric, hyphens, or underscores"
- **And** no file is created or modified

#### Scenario: Feature name with slashes is rejected
- **Given** a feature name containing `/` (e.g., `my/feature`)
- **When** `set_context` or `get_monitor_file` is called
- **Then** the function returns exit code 1
- **And** no path outside `specs/` is constructed

#### Scenario: Empty feature name is rejected
- **Given** an empty string passed as the feature parameter
- **When** any public function is called
- **Then** the bash `${1:?Usage:...}` guard fires
- **And** the function exits with an error message

#### Scenario: Feature name with spaces is rejected
- **Given** a feature name containing spaces (e.g., `my feature`)
- **When** `set_context` or `get_monitor_file` is called
- **Then** `validate_id` rejects it
- **And** the function returns exit code 1

## Security Scenarios

### Path Traversal Prevention

#### Scenario: Path traversal via get_monitor_file is blocked
- **Given** a malicious feature value `../../etc/passwd`
- **When** `get_monitor_file` is called with this value
- **Then** `validate_id` rejects the value before any path construction occurs
- **And** the file system is not accessed with the malicious path

#### Scenario: Poisoned context file does not enable second-order injection
- **Given** `.monitor-context` somehow contains `feature=../../etc`
- **When** `read_context` returns this value to the PostToolUse hook
- **And** the hook calls `log_event` with the poisoned feature
- **Then** `get_monitor_file` validates the feature and rejects it
- **And** no file is written outside `specs/`

#### Scenario: Task ID validation remains enforced
- **Given** a task ID containing path characters (e.g., `../task`)
- **When** `set_context` is called with this task ID
- **Then** the existing `validate_id "$task_id"` check rejects it
- **And** context file is not written

### Data Handling

#### Scenario: Monitor context contains no sensitive data
- **Given** `/implement` calls `set_context`
- **When** `.monitor-context` is created
- **Then** it contains only the feature name and task ID
- **And** no secrets, tokens, or credentials are stored

#### Scenario: Monitor context is excluded from version control
- **Given** a project using this workflow
- **When** `.monitor-context` exists in the project root
- **Then** the file is matched by `.gitignore` patterns
- **And** `git status` does not show it as untracked

## Edge Cases

1. **No project root found**: `find_project_root` traverses to `/` without finding `specs/`. Both `set_context` and `clear_context` handle this gracefully (error message or silent no-op respectively).

2. **Feature spec directory doesn't exist**: `get_monitor_file` constructs the path but doesn't create it. `write_event` will fail if the directory doesn't exist. This is pre-existing behavior — the specs directory structure must exist before monitoring logs to it.

3. **Concurrent tool calls during monitoring**: The PostToolUse hook runs per tool call. If multiple tool calls fire rapidly, `write_event` appends lines sequentially (bash file appends are atomic for reasonable line lengths on local filesystems).

4. **Feature name at maximum length**: `validate_id` has no length limit. Extremely long feature names are technically valid but may cause issues with filesystem path length limits. This is acceptable — feature names are human-chosen and practically short.

## Error Scenarios

1. **monitor.sh not installed**: If `~/.claude/scripts/monitor.sh` doesn't exist, the bash command fails. This means setup.sh was not run. The error is visible to the user.

2. **Permission denied on .monitor-context**: If the project root is read-only, `set_context` fails. This is an unusual edge case for local development.

3. **yq not installed**: `monitor.sh` does NOT depend on `yq` — it uses pure bash. No external dependency risk.

## Applicable Ground Rules

- `general:security/general.md` — Rules 1, 3, 8 (input validation, injection prevention, path traversal)
- `general:architecture/general.md` — Rules 2, 4, 5 (single responsibility, clear interfaces, validate at boundaries)
- `general:style/general.md` — Rules 1, 2, 4, 5 (function size, module size, naming)
- `general:languages/shell.md` — 150-line module limit (accepted deviation documented in ADR-003)
