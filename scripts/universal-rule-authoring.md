# Universal Rule Authoring

Canonical guidance for drafting general knowledge-base rules. Sourced by `/learn-from-reports`, `/review-and-ship`, and `/capture-rule`. Every rule written to `$WF_GENERAL_KB/` MUST follow this doc.

A general-KB rule is a **universal convention** — it must read as advice for any project in any repo, not as commentary on a specific finding or codebase.

## Universal phrasing

- **Imperative voice.** "Validate external input at boundaries", not "We should validate…" or "This function should…".
- **No repo provenance.** Strip every token tied to the source repo: file paths, module names, struct/class/function/variable names, package names, internal domain terms, ticket ids, team names, process references. Phrase about the **class** of issue, not the instance.
- **Standalone readability.** A reader who never saw the source finding must understand the rule and know when it applies.
- **No conversational scaffolding.** No "as we discussed", "after the recent bug", "going forward". Rules are timeless.

If the only meaningful version of the rule requires repo specifics to make sense, it does not belong in general KB — see Rejection criterion below.

## How-broad check

Universal phrasing (above) strips repo *identity*; this check fixes the rule's *altitude* — how broadly the underlying failure applies. De-identifying and generalizing are not the same act: a rule with every symbol renamed can still be pinned to one instance-shaped situation, and it will still fire only there.

State the rule as broadly as it stays true, then probe: *would this fire, unchanged, in an unrelated codebase or language?* If it names a specific type, call, table, or framework, it's still too narrow — broaden it. If you can't broaden it without losing the point, and the narrowness isn't essential (below), **drop it** (see Rejection criterion).

**Essential specificity (the escape).** A constraint may stay only if removing it makes the rule *wrong* — i.e. it would fire where there's no bug. For each constraint, delete it and ask: wrong now, or just broader? Wrong → keep. Just broader → drop the word. Default is to drop: a constraint survives only if you can name the case where removing it makes the rule fire on a non-bug.

## Snippet policy

Snippets are **illustration, not proof**. They show the shape of the rule.

- **Synthetic only.** Invent minimal examples. Use generic identifiers: `foo`, `bar`, `baz`, `User`, `Order`, `Service`, `processOrder`, `fetchUser`, `doThing`. Never copy or anonymize code from the source repo.
- **Language-tagged fenced blocks.** ` ```python ` / ` ```rust ` / ` ```ts ` etc., so syntax highlighting works downstream.
- **Bad/good pair when contrasting.** When the rule says "do X, not Y", show both — clearly labeled (`// Bad` / `// Good`).
- **Minimal.** Smallest snippet that conveys the pattern. Strip imports, error handling, comments not on the rule's axis. Aim for under ~15 lines per side.
- **No repo-specific APIs.** Use standard-library or pseudocode constructs. If the rule is framework-specific (e.g. a React hook rule), the framework primitive is fine; the surrounding domain code is not.

## When to include a snippet

Include a snippet when the rule is a **code pattern**:

- API misuse, idiom, anti-pattern, type-system usage, error-handling shape, concurrency pattern, validation pattern.

Skip the snippet when the rule is **process or meta**:

- Commit hygiene, review etiquette, naming-only conventions, documentation policies, dependency-management process.

When in doubt, skip — a noisy snippet is worse than none.

## Pre-write checklist

Before presenting any candidate rule to the user:

1. **Token strip.** Scan the draft rule and any snippet for tokens lifted from the source finding (file basenames, symbol names, domain nouns). Remove them.
2. **How-broad check.** State the rule at the highest altitude its failure mode still holds; would it fire unchanged in an unrelated codebase? If it names a specific type/call/table/framework, broaden it — or drop if it can't broaden and the narrowness isn't essential. See How-broad check.
3. **Standalone read.** Re-read the rule with no finding context. Does it still make sense? If not, generalize further or drop.
4. **Snippet audit.** Confirm any snippet uses only generic identifiers and standard constructs.
5. **Universal-check line.** Report `pass` or list specific concerns on the candidate card before asking the user to Accept/Reject/Edit.

## Rejection criterion

**Drop the candidate** when either trigger fires:

**(a) Needs repo-specifics.** The insight only holds in the source repo, or generalizing it strips out the actual lesson.

**(b) Too narrow, can't broaden, narrowness not essential.** The rule fails the How-broad check and the essential-specificity escape doesn't save it: you can't state it at an altitude that fires in another codebase, and no constraint holding it down is essential (removing the constraint makes the rule *broader*, not *wrong*). A technically-correct but over-constrained rule is a spurious-finding generator — dropping it is the honest outcome. Burden of proof is on *keeping* each constraint, not the author's sense of importance: delete the word — wrong, or just broader? broader → drop.

When dropping, suggest the user capture it locally instead:

- Repo-level domain decision → `docs/adr/NNNN-*.md`
- Repo glossary / convention → `CONTEXT.md`
- Spec-scoped decision → `specs/<feature>/design.md ## Architecture Decision Records`

A rule that cannot be made universal is not a general-KB rule — forcing it pollutes the KB for every other project.
