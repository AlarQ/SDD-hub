#!/usr/bin/env bash
# decide.sh — deterministic workflow decision predicates.
#
# Single source of truth for priority-ordered flag checks that command prose
# (/validate, /validate-impl, /implement) previously re-derived freehand every
# run (see the determinism-opportunities "Skip / decision predicates" finding).
# Inputs are env vars already exported by config-loader.sh; output is a named
# verdict + reason string. Same env -> same verdict, testable.
#
# Usage: decide.sh <decision>
#   Reads loader-exported env and prints two lines to stdout:
#     VERDICT=<name>
#     REASON=<string>   (empty when no reason applies)
#
# Decisions:
#   coverage-skip        /validate Phase 3 + Step 0.5 preview. Priority chain
#                        over WF_SPEC_TIER / WF_COVERAGE_AUDIT / WF_VALIDATE_SCOPE:
#                          tier==small        -> skip / tier_small
#                          coverage_audit==false -> skip / config_off
#                          validate_scope==per-spec -> skip / scope=per-spec
#                          else               -> run  / (empty)
#   validate-impl-skip   /validate-impl Step 0 tier early-exit:
#                          tier==small -> skip / tier_small
#                          else        -> run  / (empty)
#   impl-context         /implement step 8 track branching (which architecture
#                        artifacts to read):
#                          track==technical -> technical / docs/adr/+CONTEXT.md
#                          else (feature)   -> feature   / spec.md+design.md
#
# The priority order lives here once; callers read VERDICT/REASON and act
# (emit the gate_skip/validate_impl_skipped event with REASON, read the named
# artifacts) — they do NOT re-derive the chain.
# shellcheck disable=SC1090,SC1091
set -euo pipefail

usage() { echo "Usage: decide.sh <coverage-skip|validate-impl-skip|impl-context>" >&2; exit 2; }

emit() { printf 'VERDICT=%s\nREASON=%s\n' "$1" "${2:-}"; }

decide_coverage_skip() {
  # Priority-ordered (first match wins), mirroring /validate Phase 3 step 1.
  if [[ "${WF_SPEC_TIER:-}" == "small" ]]; then
    emit skip tier_small
  elif [[ "${WF_COVERAGE_AUDIT:-true}" == "false" ]]; then
    emit skip config_off
  elif [[ "${WF_VALIDATE_SCOPE:-per-task}" == "per-spec" ]]; then
    emit skip scope=per-spec
  else
    emit run ""
  fi
}

decide_validate_impl_skip() {
  if [[ "${WF_SPEC_TIER:-}" == "small" ]]; then
    emit skip tier_small
  else
    emit run ""
  fi
}

decide_impl_context() {
  if [[ "${WF_SPEC_TRACK:-feature}" == "technical" ]]; then
    emit technical "docs/adr/+CONTEXT.md"
  else
    emit feature "spec.md+design.md"
  fi
}

[[ $# -ge 1 ]] || usage

case "$1" in
  coverage-skip)       decide_coverage_skip ;;
  validate-impl-skip)  decide_validate_impl_skip ;;
  impl-context)        decide_impl_context ;;
  *) echo "decide.sh: unknown decision '$1'" >&2; usage ;;
esac
