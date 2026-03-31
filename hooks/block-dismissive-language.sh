#!/usr/bin/env bash
# Stop hook: blocks Claude from stopping if the last assistant message
# contains dismissive or bypass language about issues.
set -euo pipefail

LAST_MSG=$(jq -r '.last_assistant_message // empty')

if [ -z "$LAST_MSG" ]; then
  exit 0
fi

PHRASES=(
  "pre-existing"
  "not our change"
  "not my code"
  "not caused by my"
  "not caused by our"
  "unrelated to our"
  "unrelated to my"
  "not related to our"
  "not related to my"
  "pre existing"
  "already broken"
  "not introduced by"
  "not from our code"
  "not from my code"
  "temporarily disable"
  "temporarily skip"
  "temporarily remove"
  "temporarily comment out"
  "disable the hook"
  "skip the hook"
  "disable the check"
  "skip the check"
  "disable pre-push"
  "disable pre-commit"
  "bypass the hook"
  "bypass the check"
)

for phrase in "${PHRASES[@]}"; do
  if echo "$LAST_MSG" | grep -qi "$phrase"; then
    cat <<'HOOK_JSON'
{
  "decision": "block",
  "reason": "BLOCKED: You used forbidden language. Either dismissive (\"pre-existing\", \"not our change\") or bypass language (\"temporarily disable\", \"skip the hook\"). Fix ALL issues unconditionally. Never dismiss errors. Never suggest disabling, skipping, or temporarily removing any check, hook, or safety mechanism. Fix the root cause instead."
}
HOOK_JSON
    exit 0
  fi
done
