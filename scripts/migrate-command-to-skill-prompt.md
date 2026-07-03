Migrate `commands/<NAME>.md` to `skills/<NAME>/SKILL.md` in dev-workflow-repo.

Pattern (established by the workflow-summary pilot, PR #71):

1. Read `commands/<NAME>.md` in full.
2. Create `skills/<NAME>/SKILL.md` with this frontmatter prepended:
   ```yaml
   ---
   name: <NAME>
   description: <first line of the old command file, verbatim>
   disable-model-invocation: true
   ---
   ```
   - `disable-model-invocation: true` always — these are user-typed only, never
     auto-fired by the agent or chained by another skill (repo rule: "no
     command auto-invokes another").
   - If the command takes arguments, add an `args:` block documenting them
     (name + description + required). This is documentation only — do NOT
     rewrite any `$ARGUMENTS` parsing logic in the body. Keep `$ARGUMENTS`
     exactly as it appears today, including in user-facing message strings
     (e.g. `"Run /validate $ARGUMENTS next."`).
3. Copy the rest of the old file's body verbatim below the frontmatter — no
   wording changes.
4. Delete `commands/<NAME>.md`.
5. `setup.sh` needs no edit — its install loops glob `commands/*.md` and
   `skills/*/` generically.
6. Grep the repo for other files that reference `commands/<NAME>.md` by path
   (CLAUDE.md, onboarding.md, plan.md, docs/workflow-diagram.md) and repoint
   them to `skills/<NAME>/SKILL.md`.
7. Ship via `/quick-ship` on its own branch/PR (one command per PR, matching
   the pilot).

Full plan (batch order, cross-cutting cleanup after the last one):
/Users/ernestbednarczyk/.claude/plans/mossy-percolating-globe.md
