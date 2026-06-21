#!/usr/bin/env bash
# select-agents.sh — deterministic keyword -> agent/tier-force selection.
#
# Single source of truth for the keyword tables that /propose and /explore
# previously grepped freehand in command prose (the keyword tables were
# duplicated across both commands and re-interpreted every run; see the
# determinism-opportunities finding). Same input -> same flags, testable.
#
# Usage: select-agents.sh <file> [<file>...]
#   Reads the given text files (e.g. spec.md, prd.md, or a process-substitution
#   capture of the conversation) and prints flag lines to stdout:
#     WF_SPAWN_BACKEND=0|1   backend-architecture keywords present
#     WF_SPAWN_UX=0|1        UI keywords present (spawn UX Architect)
#     WF_SPAWN_UI=0|1        mirrors WF_SPAWN_UX (UI Designer pairs with UX)
#     WF_SPAWN_AI=0|1        ML/AI keywords present
#     WF_TIER_FORCED=        'medium' when a hard-rule keyword appears, else empty
#
# Callers read the flags and spawn the matching agent / apply the tier floor;
# they do NOT re-derive the tables. Missing/unreadable input files are skipped
# (best-effort, matching the prose that tolerated an absent prd.md).
# shellcheck disable=SC1090,SC1091
set -euo pipefail

# --- Keyword tables (the data; do not scatter copies into command prose) ------
# Whole-word, case-insensitive match (grep -iwE) so 'api' does not fire on
# 'rapidly' and 'DB' does not fire on 'adblock'. Each '|' alternative is
# word-bounded independently, so multi-word and hyphenated keywords work too.
BACKEND_KW='database|DB|schema|migration|API|endpoint|REST|GraphQL|infrastructure|server|backend|queue|cache'
UI_KW='UI|frontend|component|layout|CSS|design system|responsive|mobile|page|screen|form|modal|dashboard'
AI_KW='model|ML|machine learning|AI|training|inference|embeddings|neural|LLM|fine-tune|dataset'
# Hard-rule keywords that force tier >= medium (CLAUDE.md "Hard rules force >=medium").
TIER_FORCE_KW='auth|security|migration|api|schema|crypto'

usage() { echo "Usage: select-agents.sh <file> [<file>...]" >&2; exit 2; }
[[ $# -ge 1 ]] || usage

# Concatenate readable inputs. '-r' (not '-f') so process substitution
# (/dev/fd/NN) is accepted while genuinely-missing paths are skipped.
corpus=""
for f in "$@"; do
  [[ -r "$f" ]] || continue
  corpus+="$(cat -- "$f")"$'\n'
done

# match <pattern> -> 0 if any whole-word keyword present in the corpus.
# A trailing optional 's' is spliced onto every alternative so common plurals
# ('APIs', 'endpoints', 'schemas', 'models') match too — the prior freehand LM
# grep caught those, and dropping them would silently narrow agent spawning.
# Here-string (not a pipe) avoids SIGPIPE on the producer under pipefail.
match() { local pat="${1//|/s?|}s?"; grep -iqwE -- "$pat" <<<"$corpus"; }

backend=0; ui=0; ai=0; tier_forced=""
if match "$BACKEND_KW"; then backend=1; fi
if match "$UI_KW"; then ui=1; fi
if match "$AI_KW"; then ai=1; fi
if match "$TIER_FORCE_KW"; then tier_forced="medium"; fi

printf 'WF_SPAWN_BACKEND=%s\n' "$backend"
printf 'WF_SPAWN_UX=%s\n' "$ui"
printf 'WF_SPAWN_UI=%s\n' "$ui"
printf 'WF_SPAWN_AI=%s\n' "$ai"
printf 'WF_TIER_FORCED=%s\n' "$tier_forced"
