Promote project knowledge-base rules to the general knowledge base.

## Purpose

Graduates rules from the project KB (`knowledge-base/`) to the general KB (`~/.claude/knowledge-base/`) when they prove universally applicable across all repositories. This is the **only command permitted to write to the general KB**. Promoted rules become available on this machine to every project that uses the spec-driven workflow.

> **Durability note:** Changes to `~/.claude/knowledge-base/` are local to this machine. Running `setup.sh --force` from the dev-workflow repo will overwrite them. To make a promotion permanent, open a PR in the dev-workflow repo adding the rule to its `knowledge-base/` directory.

## Prerequisites

1. Read and follow `~/.claude/knowledge-base-rules.md` for knowledge base prerequisites and resolution rules.
2. Read `~/.claude/knowledge-base/_index.md` (general KB) to understand existing coverage — use this to filter out already-covered rules.
3. Read `knowledge-base/_index.md` (project KB) to enumerate all project-specific rule files.

## Steps

1. **Collect project rules.** Read every file listed in `knowledge-base/_index.md`. For each file, collect all individual rule entries with their source file path and category. Skip files whose entire content is already fully covered by an existing general KB file in the same category.

2. **Assess generality.** For each collected rule, mark it as a promotion candidate if **all** of the following hold:
   - Encodes a universal engineering principle (security, architecture, testing, naming, error handling, code quality) not tied to a specific library, framework version, internal system, or team process.
   - Not a duplicate of a rule already present in the general KB.
   - Stated in language that applies to *any* repository, not just this one (no project-specific names, paths, or tooling).

2b. **Auto-remove project-KB duplicates.** For every rule collected in Step 1 that was filtered out because it duplicates an existing general KB rule at the rule level (not merely file-level coverage): automatically remove the duplicate entry from the project KB file without user review. If removing leaves the file empty or header-only, delete the file and remove its row from `knowledge-base/_index.md`. Report: "Removed N duplicate rule(s) from project KB (already present in general KB): [list of rule summaries]." This cleanup runs before the candidate review below.

3. **Present candidates as a single batched review.** If no candidates qualify, report: "No rules qualify for promotion." and stop.

   For each candidate, display:
   - Source file in project KB (`knowledge-base/<category>/<file>.md`)
   - Rule text (exact)
   - Proposed target in general KB (`~/.claude/knowledge-base/<category>/<file>.md`) — mirror the source category/file where a match exists; propose a sensible new path when the category is new
   - One-sentence rationale for why it qualifies
   - Ask: **Accept / Reject / Edit?**
     - **Accept:** apply in step 4
     - **Reject:** discard candidate, move on
     - **Edit:** prompt for revised rule text or target path, then apply as accepted
   - **Stop and wait for user response between candidates.**

4. **Apply accepted promotions.** For each accepted candidate:
   a. If the target general KB file exists, read it first, then append the rule. If it does not exist, create it with an appropriate title header matching the general KB style.
   b. Update `~/.claude/knowledge-base/_index.md` — add or update the row for the target file (preserve existing table format).
   c. **Remove from project KB.** Remove the rule entry from its source file automatically — keeping it in both bases is pointless duplication and causes the project version to silently shadow the general one. If removing leaves the file empty or header-only, delete the file and remove its row from `knowledge-base/_index.md`.

5. **Report summary.** "Promoted N rules to general KB (A accepted, R rejected, E edited). Removed N corresponding entries from project KB."
