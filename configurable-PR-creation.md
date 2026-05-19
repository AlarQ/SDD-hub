 Plan: branch_strategy per-spec config axis

     Context
  
     Grilling outcome: the spec-driven workflow has no configurable branch model.
     It hardcodes a per-task branch + per-task draft PR shape (feat/$FEATURE integration
     branch + feat/$FEATURE/{task-id}-{task-name} per task + one draft PR per task),
     baked into /implement, /ship, /pr-review, /continue-task. The user needs a
     second mode: one branch per spec, task commits accumulate, no per-task PR — for
     tightly-coupled refactors/spikes where per-task PR overhead is unwanted.

     Add a per-spec axis branch_strategy: per-task | single-branch (default
     per-task = today's behavior, fully backward compatible).

     Locked decisions (from grill)

     1. Axis branch_strategy, per-spec in specs/<feature>/config.yml (sibling of tier/track/validate_scope). Inferred at /explore step 0, user-approved. Absent →
     per-task.
     2. per-task = exactly current behavior.
     3. single-branch = one branch feat/$FEATURE off main; no per-task sub-branch; commits accumulate.
     4. Review deferred: no per-task draft PR. One spec PR opened/readied at the final /ship (last task). PR base = main.
     5. Commit shape: preserve TDD red/green/refactor commits on the shared branch (no squash).
     6. Serial gate: /implement preflight "previous PR merged" → "previous task status == done".

     Implementation Model

     The integration branch feat/$FEATURE exists in both modes. Only the per-task
     sub-branch and per-task PR are conditional. track is the structural template for
     the config plumbing (loader block, contract row, snapshot, inferencer slot, template
     comment, test pattern). Commands read ${WF_BRANCH_STRATEGY:-per-task}.

     validate-impl.md / validate.md need no change — they diff against
     merge-base main feat/$FEATURE..HEAD, valid in both modes.

     Steps

     Config plumbing — ✅ IMPLEMENTED (odium-validated, no findings)

     1. scripts/config-loader.sh — add WF_BRANCH_STRATEGY parse block after the track block (~L425): enum per-task|single-branch, ""→per-task,
     invalid→wf__unset_partials; return 4. Add to wf__unset_partials list (~L24), spec-block export (~L577), CLI _wf_allowed_vars (~L676).
     2. scripts/config-loader.contract.md — new env-var row after WF_SPEC_TRACK; extend exit-4 condition to mention branch_strategy.
     3. scripts/config-loader.sh snapshot — add branch_strategy to _wf_snapshot_json (~L628) so a mid-spec flip is caught by existing drift check (/ship
     ship.md:25-31). Update contract Helpers note.
     4. templates/spec-config.yml.template — commented branch_strategy: block mirroring track:.
     5. agents/engineering/engineering-config-inferencer.md — add branch_strategy to Output Contract schema (~L44), Block-2 YAML (~L152), Fallback default template
     (~L191); add a short Branch Strategy Inference Rubric after the Track rubric (default per-task; single-branch only on explicit "one branch/PR" or small
     tightly-coupled single-author refactor signal).
     6. commands/explore.md — verify only; inferred YAML flows through verbatim. Optional one-line note near track/tier prose. No new monitor event (rides existing
     config_approved).
     7. commands/config.md — no change (loader enum-validates, same as track); confirm.

     Command branching — ✅ IMPLEMENTED (odium-validated; 4 findings fixed: pr-review prereq ordering, continue-task step3 gate, ship task_base_sha nil guard, ship step renumber). Deviation: step 14 task-manager.sh got a new `set-base-sha` setter (frontmatter write required by step 8; hand-edit forbidden by repo rule).

     8. commands/implement.md (core):
       - Step 0: add WF_BRANCH_STRATEGY to echo + "This step uses" line.
       - Prereq 4 serial gate: per-task unchanged; single-branch → refuse unless immediately-preceding task status == done.
       - Steps 3–4 (ensure/checkout feat/$FEATURE): unchanged both modes.
       - Steps 5–6 (sub-branch existence/create): wrap in if per-task; single-branch stays on feat/$FEATURE.
       - Record task_base_sha = git rev-parse HEAD at task start (single-branch) into task frontmatter — linchpin for continue-task + quality-diff.
       - Quality/Test-Strategist diff ranges (L71, L102): per-task → feat/$FEATURE...HEAD; single-branch → ${task_base_sha}..HEAD. Reword L71 "merged task branches"
     → "completed tasks on feat/$FEATURE".
       - Draft-PR section (L121–138): per-task unchanged; single-branch → push feat/$FEATURE, no gh pr create, no pr_url, no pr_opened_draft.
       - Final instruction (L140–142): single-branch → "Task committed on feat/$FEATURE (review deferred). Run /validate." (omit /pr-review).
     9. commands/ship.md:
       - Step 0: add WF_BRANCH_STRATEGY.
       - Steps 1–3: single-branch → checkout feat/$FEATURE; no-op guard via ${task_base_sha}..HEAD empty → "no changes".
       - Step 6 push: single-branch pushes feat/$FEATURE.
       - Step 7 PR (critical): single-branch → only on last task (reuse spec_last_task_done signal): gh pr create --base main ready, spec-level title/body. Non-last
     → push only, no PR, print "next /implement". Guard pr_url persistence (Steps 9–10) to last task.
       - PR base asymmetry: per-task base=feat/$FEATURE; single-branch base=main. Called out explicitly.
       - Multi-repo: single-branch spec PR fans out per bound repo (mirror validate-impl per-repo fan-out); last-task is spec-global, PR creation
     per-repo-with-tasks.
     10. commands/quick-ship.md — no change (spec-less, branch-agnostic); confirm note.
     11. commands/pr-review.md:
       - Step 0: add WF_BRANCH_STRATEGY.
       - single-branch + no spec PR yet → refuse cleanly: "no PR until final /ship; review deferred."
       - single-branch + spec PR exists → resolve PR via gh pr view from feat/$FEATURE (not task-branch regex).
     12. commands/continue-task.md:
       - Add Step 0 config load (read WF_BRANCH_STRATEGY).
       - single-branch phase detection: start-vs-mid via ${task_base_sha}..HEAD; non-final done w/o pr_url = normal → "Ship needed" always after done (ship handles
     last-vs-non-last); final done + OPEN PR → "Merge spec PR".
     13. commands/validate-impl.md / validate.md — verify no change (diff range valid both modes; validate-impl opens no PR). Plan note only.
     14. scripts/task-manager.sh — verify no change (serial gate is /implement prose; spec_last_task_done already emitted). Plan note only.

     Docs (mandatory) — ✅ IMPLEMENTED (odium-validated; 3 findings fixed: command-chain Mermaid single-branch fork, Key Invariants per-strategy rewording, ADR Context/Decision headings)

     15. docs/workflow-diagram.md (CLAUDE.md:235 flow-change rule): split Git subgraph (L214–217) per strategy; add single-branch flow path (IMPL→TCHK→VAL, no
     DPR/PRR; SHIP→IMPL non-last, spec-PR-to-main last); update prose L14.
     16. CLAUDE.md — add branch_strategy bullet alongside tier/track/validate_scope axes.
     17. CONTEXT.md — glossary entry for branch_strategy (both values + default), matching track/tier style. (Grill skill: capture inline at implementation.)
     18. docs/adr/0003-branch-strategy.md — NEW ADR. Warranted: hard-to-reverse (accumulated commits can't re-split into per-task PRs), surprising (decision 4
     removes per-task GitHub review surface central to the human-gate model), real trade-off (PR/branch overhead vs incremental reviewability + per-task revert
     granularity). Outline: Context / Decision (axis + decisions 4,5,6) / Consequences (+less churn, atomic spec PR; −no incremental review, inert /pr-review
     mid-spec, harder rollback) / Alternatives (squash-per-task rejected by decision 5; per-task PR auto-merge rejected). Default stays per-task.

     Edge cases

     - task_base_sha is the linchpin for single-branch start/mid detection + quality diff — design in step 8, consume in 9/12.
     - /pr-review mid-spec single-branch = intended clean dead-end (don't crash branch regex).
     - Vault/multi-repo: one feat/$FEATURE per bound repo, no sub-branches; spec PR fans out per repo.
     - /validate-impl may run before the spec PR exists in single-branch — fine, diff range independent of PR.
     - Snapshot includes branch_strategy → /ship drift check catches mid-spec flip.

     Tests — ✅ IMPLEMENTED (odium-validated; 2 findings fixed: vacuous no-partial assertion restructured to pre-seed + capture rc separately; tautological inferencer enum test hardened — validate_schema_shape now enforces branch_strategy enum + negative case added. Snapshot/drift placed in test-config-loader.sh, not test-implement-context.sh, since that's the loader's test home — plan L109 text inconsistent but behavior covered.)

     - tests/test-config-loader.sh: branch_strategy default→per-task, single-branch exported, invalid→rc4 + vars unset, export --spec emits line. Model on
     test_loader_track_* (L608–619).
     - tests/test-inferencer-schema.sh: expect branch_strategy key in inferencer YAML.
     - Extend snapshot/drift test (tests/test-implement-context.sh) if step 3 adopted.
     - No new test files; extend existing per repo convention.

     Critical files

     - scripts/config-loader.sh, scripts/config-loader.contract.md
     - commands/implement.md, commands/ship.md, commands/continue-task.md, commands/pr-review.md
     - agents/engineering/engineering-config-inferencer.md
     - docs/workflow-diagram.md, CLAUDE.md, CONTEXT.md, docs/adr/0003-branch-strategy.md
     - templates/spec-config.yml.template, tests/test-config-loader.sh

     Verification

     1. bash tests/test-config-loader.sh — new branch_strategy cases green; existing green.
     2. bash tests/test-inferencer-schema.sh green.
     3. Manual: write a config.yml with branch_strategy: single-branch; scripts/config-loader.sh export --spec <f> shows WF_BRANCH_STRATEGY=single-branch; invalid
     value → exit 4, no WF_ vars set.
     4. Dry-run prose review of /implement→/validate→/ship single-branch path: confirm no gh pr create until last task, commits land on feat/$FEATURE, last /ship
     opens one PR base main.
     5. per-task regression: existing flow prose unchanged when branch_strategy absent.
     6. cargo check --workspace (no Rust change expected; sanity).
