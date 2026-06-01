#!/bin/bash
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command')

emit_deny() {
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED: git-hook bypasses are forbidden (--no-verify / -n, --no-gpg-sign, -c core.hooksPath=). Fix the failing hook instead."}}' | jq -c .
  exit 0
}

# Long-form bypass flags, anywhere in the command.
if echo "$COMMAND" | grep -qE '(--no-verify|--no-gpg-sign)'; then
  emit_deny
fi

# `-c core.hooksPath=<any value>` overrides the hooks dir, disabling hooks.
# Match the key regardless of its value (/dev/null, '', a bogus path, ...).
if echo "$COMMAND" | grep -qE -- '-c[[:space:]]+core\.hooksPath='; then
  emit_deny
fi

# Short `-n` form of --no-verify, but ONLY scoped to git subcommands that honor
# it: commit, merge, rebase. This avoids false positives on `-n` used by other
# tools (grep -n, echo -n, sort -n) and by other git subcommands (git log -n 5,
# where -n means "number of commits").
#
# Token shape: a short-flag cluster `-<letters>n<letters>` as a whole word
# (preceded by start/whitespace, followed by whitespace/end) so `-n`, `-nm`,
# and `-vn` match but `--no-...` long flags and substrings do not.
if echo "$COMMAND" \
  | grep -qE '(^|[[:space:]])git([[:space:]]+[^[:space:]]+)*[[:space:]]+(commit|merge|rebase)([[:space:]]|$)' \
  && echo "$COMMAND" \
  | grep -qE '(^|[[:space:]])-[a-zA-Z]*n[a-zA-Z]*([[:space:]]|$)'; then
  emit_deny
fi

exit 0
