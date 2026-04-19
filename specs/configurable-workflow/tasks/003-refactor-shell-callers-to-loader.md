---
id: "003"
name: "Refactor monitor/task-manager/pre-commit to use config-loader"
status: todo
blocked_by: ["002"]
max_files: 6
estimated_files:
  - scripts/monitor.sh
  - scripts/task-manager.sh
  - scripts/pre-commit-hook.sh
  - tests/test-path-resolution.sh
  - tests/test-monitor-events.sh
  - tests/test-task-manager.sh
test_cases:
  - "monitor.sh writes events under $WF_SPEC_STORAGE/<feature>/.monitor.jsonl from nested cwd"
  - "monitor.sh accepts the four new event categories config_inferred, config_approved, agent_spawn, gate_skip"
  - "monitor.sh rejects unknown event categories"
  - "Monitor event with path under HOME renders with ~ prefix (no absolute paths leaked)"
  - "monitor.sh log_event rejects or truncates any event payload containing a YAML document body (multi-line value with leading '---' or a 'gates:' key); only event type + ID + git SHA permitted in the payload"
  - "task-manager.sh validate locates task file from deep subdir via walk-up"
  - "pre-commit-hook.sh walks up when run from subdir using git rev-parse --show-toplevel"
  - "Vault case: spec_storage=/tmp/vault, events land under /tmp/vault, never ./specs"
  - "Legacy repo (no .workflow.yml) still works via fallback flag"
  - "monitor.sh uses only $WF_SPEC_STORAGE when set (no global ~/specs fallback)"
  - "Integration seam: shell callers consume WF_* contract end-to-end from loader"
  - "pre-commit hook test uses real git init under tests/fixtures/nested-subdir-repo and invokes via git -C subdir with GIT_DIR set (not bare cd)"
  - "T003 CI matrix runs against BOTH default repo AND /tmp/vault repo in the same job"
ground_rules:
  - general:languages/shell.md
  - general:security/general.md
  - general:architecture/general.md
  - general:architecture/code-analysis.md
---

## Description

Refactor the three dogfood-sensitive shell callers to source the new loader (or `eval` its export mode in the git hook). Resolve all spec paths via `$WF_SPEC_STORAGE`. Add the four new monitor event categories. Keep a hardcoded `specs/` fallback behind an explicit env flag — to be removed in T11 once E2E is green.

**Risk: HIGH** per design — dogfood breakage during rollout. Land as a single atomic PR with E2E test against a throwaway repo before merge.

## Changes

- `monitor.sh` — replace `find_project_root` (currently scans for `specs/` dir at line ~32-42) with `find_workflow_root` (delegates to `config-paths.sh`). Add four new event categories. Redact `$HOME → ~` in event paths. Never embed raw YAML bodies. Delegate `validate_id` to the loader version when loaded; keep local copy for standalone source.
- `task-manager.sh` — read `$WF_SPEC_STORAGE` to locate task files. Legacy fallback flag.
- `pre-commit-hook.sh` — `eval "$(scripts/config-loader.sh export)"` once at start. Walk up from `$(git rev-parse --show-toplevel || pwd)`.
- `tests/test-path-resolution.sh` — invoked from a nested tmp dir to verify walk-up across all three callers.

## Implementation Notes

- `set -euo pipefail`; ≤150 lines per file (split if needed).
- The fallback flag lives only here, not in the loader. Loader is the canonical truth; these scripts wrap legacy behavior temporarily.
- Existing `tests/test-monitor.sh` and `tests/test-task-manager.sh` must stay green.
- Cross-project vault collision prevented: when `$WF_SPEC_STORAGE` is set, monitor uses *only* that path — no global `~/specs` fallback.

## New capability: monitor.sh category allowlist

Today `monitor.sh` only enforces an ID-shape regex on `category` (`validate_id "$category" "category"` — `[a-zA-Z0-9_-]+`). Any alphanumeric name passes. T003 introduces a **closed allowlist** in addition to the regex. This is a new capability, not a refactor.

**Post-T003 canonical allowlist** (preserve all names currently emitted by existing scripts/hooks, plus the four new ones):

Pre-existing (keep):
- `task_transition`, `phase`, `tool_call`, `context_read`, `agent_invocation`, `validation_result`, `finding_found`, `finding_accepted`, `finding_rejected`, `task_update`

Added by this task:
- `config_inferred`, `config_approved`, `agent_spawn`, `gate_skip`

(Later tasks — T014, T015, T017 — extend the allowlist with `spec_audit_start`, `spec_audit_done`, `spec_complete`, `spec_reopened`, `spec_last_task_done`. Each adding task updates the allowlist *and* adds a test case that its new category is accepted.)

Any emission of an unknown category → `log_event` exits non-zero and writes nothing to the JSONL file. Callers must be updated in the same PR that introduces a new category.
