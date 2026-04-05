---
id: "008"
name: "Update setup.sh to install monitor scripts and hook"
status: blocked
blocked_by:
  - "001"
  - "002"
max_files: 1
estimated_files:
  - setup.sh
test_cases:
  - "setup.sh installs monitor.sh to ~/.claude/scripts/"
  - "setup.sh installs monitor-tool-calls.sh to ~/.claude/hooks/"
  - "monitor.sh is executable after installation"
  - "monitor-tool-calls.sh is executable after installation"
  - "verification checks both new files"
  - "safe_copy protects existing files without --force"
ground_rules:
  - general:style/general.md
---

## Description

Update `setup.sh` to install the new monitoring scripts alongside existing commands and hooks.

## Changes

- `monitor.sh` installed to `~/.claude/scripts/monitor.sh` (executable)
- `monitor-tool-calls.sh` installed to `~/.claude/hooks/monitor-tool-calls.sh` (executable)
- Add verification checks in the verification section
- Both files use the existing `safe_copy` pattern for overwrite protection
