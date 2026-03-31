#!/bin/bash
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command')

if echo "$COMMAND" | grep -qE '(--no-verify|--no-gpg-sign)'; then
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED: --no-verify and --no-gpg-sign are forbidden. Fix the failing hook instead."}}' | jq -c .
  exit 0
fi

exit 0
