# Per-spec branch_strategy axis

Status: accepted

## Context

The spec-driven workflow hardcoded one git shape: a `feat/$FEATURE`
integration branch, a `feat/$FEATURE/{task-id}-{task-name}` sub-branch per
Task, and one draft PR per Task into the integration branch — baked into
`/implement`, `/ship`, `/pr-review`, `/continue-task`. For tightly-coupled
refactors and spikes the per-Task branch + per-Task PR overhead buys nothing:
the Tasks only make sense reviewed together, and the PR churn is pure friction.

## Decision

Add a per-spec axis `branch_strategy: per-task | single-branch` in
`specs/<feature>/config.yml` (sibling of `tier`/`track`/`validate_scope`),
inferred at `/explore` step 0 and user-approved. Absent → `per-task`.

- **per-task** — exactly the prior behavior. Fully backward compatible.
- **single-branch** — one `feat/$FEATURE` branch off `main`; no per-Task
  sub-branch; commits accumulate. Review is deferred: no per-Task draft PR.
  One spec PR is opened/readied at the **final** `/ship` (last Task), base
  `main`. TDD red/green/refactor commits are preserved on the shared branch
  (no squash). The `/implement` serial gate becomes "immediately-preceding
  Task status == done" instead of "previous PR merged".

`task_base_sha` (git HEAD at Task start, written to Task frontmatter via
`task-manager.sh set-base-sha`) is the linchpin: it drives `single-branch`
start-vs-mid detection in `/continue-task` and the quality/test-strategist
diff range (`${task_base_sha}..HEAD`). The config snapshot includes
`branch_strategy` so a mid-spec flip is caught by the existing `/ship` drift
check. Multi-repo: one `feat/$FEATURE` per bound repo, no sub-branches; the
spec PR fans out per bound repo at the last Task.

## Considered Options

- **Squash per-Task commits on the shared branch** — rejected: destroys the
  TDD red/green/refactor narrative and per-Task revert granularity the workflow
  deliberately preserves.
- **Per-Task PR with auto-merge into `feat/$FEATURE`** — rejected: keeps all
  the per-Task PR/branch machinery this axis exists to remove; auto-merge also
  defeats the human review gate without reducing churn meaningfully.
- **Keep only per-task (status quo)** — rejected: leaves tightly-coupled
  refactors/spikes paying per-Task PR overhead with no reviewability benefit.

## Consequences

- `+` Less branch/PR churn; one atomic spec PR for coupled work.
- `+` Default unchanged (`per-task`) — zero migration, existing specs intact.
- `−` No incremental per-Task review surface on `single-branch`; the GitHub
  human-gate central to the per-task model is removed mid-spec.
- `−` `/pr-review` is an inert clean dead-end mid-spec on `single-branch`
  ("no PR until final /ship; review deferred").
- `−` Harder rollback: accumulated commits cannot be re-split into per-Task
  PRs after the fact — hence this record.
- Reversing a `single-branch` spec to `per-task` mid-flight is not supported;
  the snapshot drift check forces the choice to be made once, at `/explore`.
