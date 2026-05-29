# Delegate the `/implement` TDD loop to a per-Task specialist subagent

Status: accepted

## Context

`/implement` ran the entire red-green-refactor loop (steps 9–11) **inline in the
main session**: the main agent read source files, wrote tests, wrote code, ran
the suite, and debugged — all in one context that grows unbounded across a Task.
For non-trivial Tasks this is the dominant context-consumer of the whole
workflow, and main carries that weight through the post-impl quality check, the
draft PR, and into the next command.

A specialist subagent running in its own isolated context could absorb the
heavy code-writing, returning only a compact summary. Two questions had to be
settled: *who* writes the code, and *how much* of the loop they own.

## Decision

Add a per-Task `implementer:` frontmatter field, set by the Senior Project
Manager at `/propose` and validated by `task-manager.sh`. It names the
specialist agent that owns the **whole TDD loop** (settled-backlog → red →
green → refactor) in its own context, or the reserved literal **`generalist`**
meaning "no subagent — the main session runs the loop inline" (today's exact
behavior).

- **Always set by the PM.** The PM picks a best-fit agent (`engineering/frontend-developer`
  for UI, `engineering/backend-architect` for server/API/data, other clear
  matches) or `generalist` when nothing fits. One Task = one implementer.
- **`task-manager.sh validate`** accepts `generalist` OR an agent-pool id
  resolvable via the canonical grammar (`<category>/<name>` →
  `<pool>/<category>/<category>-<name>.md`, bare `<name>` → `<pool>/<name>.md`);
  an unresolvable id is a hard FAIL (fail-closed). The field absent on a
  pre-existing Task is allowed and treated as inline (legacy grace).
- **Method injection, not baked-in.** Agent files stay generic and reusable.
  `/implement` builds the spawn prompt = a pointer to
  `~/.claude/skills/tdd/SKILL.md` + the settled backlog + scope +
  `ground_rules`/design/ADR **paths** + the required structured return. The
  specialist supplies the domain skill; `/implement` supplies the TDD method.
- **Split of labor.** Main keeps the cheap orchestration: serial gate, config,
  branch, monitor context, backlog settle (step 9), post-impl quality check on
  the `git diff`, draft PR. The specialist owns steps 10–11 and edits the same
  working tree at `WF_TASK_REPO_PATH` (serial execution, one Task in flight — no
  worktree isolation needed). Both paths converge at step 12.
- **Errors stay inline to the specialist.** It debugs within its own loop and
  escalates only by returning `status: blocked` (Claude Code's one-level
  nesting rule forbids a sub-sub-agent). The Ultrathink Debugger and the
  `tdd_red`/`tdd_green` monitor events remain on the `generalist`/inline path
  only.
- **Context hygiene is the payoff.** On the delegated path main must **not**
  read spec.md/design.md/`docs/adr/` bodies — it passes paths and lets the
  specialist read them. Main's per-Task footprint ≈ Task file + config + the
  specialist's compact return + `git diff` for QC.

## Considered Options

- **GREEN-only delegation** (main writes the RED test, specialist makes it
  pass) — rejected: keeps test-authoring (and the files it reads) in main, so
  context still grows roughly with Task size; the savings are marginal and the
  red/green handoff per behavior adds chatter.
- **Whole-Task delegation** (specialist also owns branch/PR/quality check) —
  rejected: pushes git + GitHub + state-machine concerns into a generic agent,
  duplicating orchestration that is cheap to keep in main and muddying the
  single owner of `.flow`/PR state.
- **Bake the TDD contract into the agent files** — rejected: couples every
  reusable specialist to this workflow's method; method injection keeps the
  agent pool generic and lets the contract evolve in one place (`/implement`).
- **Let the coder spawn Ultrathink Debugger itself** — rejected: Claude Code
  forbids one-level-deeper nesting; the specialist debugs inline and returns
  `blocked` instead.

## Consequences

- `+` Main-session context stays flat regardless of Task size — the headline win.
- `+` Specialist quality: a frontend/backend agent writes code in its domain.
- `+` Default/legacy behavior unchanged — `generalist`/absent runs today's exact
  inline path, so existing specs are untouched.
- `−` `tdd_red`/`tdd_green` monitor events are **not** emitted on the delegated
  path — the per-behavior TDD telemetry is lost for delegated Tasks.
- `−` `/validate-impl` Step 3a will trip its **advisory** (non-blocking) "no TDD
  evidence" finding for delegated Tasks; accepted as harmless noise (left as-is).
- `−` Extra spawn latency and a generic agent that needs the method injected
  each time vs. a purpose-built one.
- `−` A new Task-schema field and a new PM responsibility (changes the core
  `/implement` contract) — hence this record.
