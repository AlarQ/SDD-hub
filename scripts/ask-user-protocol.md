# Ask-User Protocol

Canonical rule for all workflow commands: every interactive prompt to the user MUST go through Claude Code's `AskUserQuestion` tool. Plain markdown question lists, `[A]/[B]/[C]` text menus, and "type your answer" prose prompts are not allowed.

## Why

Routes user decisions through the structured picker UI so the user clicks/selects rather than scrolling a long markdown wall and typing free text. Keeps each decision atomic and traceable.

## Rules

1. **Every decision = one AskUserQuestion call.** Approvals, accept/reject, scope picks, clarifications, "add as KB rule? yes/no" — all of them.
2. **Enumerable choices → `options`.** Map each menu entry (e.g. `Approve`, `Edit`, `Manual`, `Skip`) to one option with a short label and a one-line description.
3. **Open-ended clarifications → still use AskUserQuestion.** Provide best-guess options when possible plus an `Other` escape so the user can type a custom answer. If truly unbounded, use a single open-ended question with no options.
4. **Batch independent questions in a single call.** AskUserQuestion supports multiple questions per invocation — use it when questions don't depend on each other's answers.
5. **Sequential when dependent.** If question 2's options depend on question 1's answer, call AskUserQuestion twice.
6. **Status output stays plain.** Progress headers ("Group 3 of 12"), running tallies ("X accepted, Y rejected"), summaries, and config previews stay as regular markdown — only the *prompt that requires input* uses the tool.
7. **Reject reasoning.** When a user picks Reject, follow up with a second AskUserQuestion: a free-text "reason" question, plus an enumerable "Add as project KB rule?" yes/no.

## Fail-closed enforcement

Config writes (`specs/<feature>/config.yml`) and `/validate` runs MUST be gated by `AskUserQuestion`. If the tool cannot be invoked or returns no selection, abort the operation — do NOT fall through to a default. Print an explicit "Approval required — aborted" message and exit non-zero.

## Skipping condition

Do **not** route through AskUserQuestion when:
- The command runs non-interactively (background sub-agent, hook).
- The "question" is purely informational ("All N sub-agents completed.").
- A single-line ack would interrupt a sub-agent fix loop — let those run silently.

## Reference

Commands enforcing this protocol:
- `commands/explore.md` — config-inference approval, clarifying questions, scope forks
- `commands/review-findings.md` — accept/reject per finding group, reject reason + KB-rule prompts
- `commands/pr-review.md` — agent-finding accept/reject, PR-comment proposal accept/reject
