Capture an ad-hoc rule from the current conversation into the general knowledge base.

## Purpose

Lets the user crystallize an insight that emerged organically — from a code review, a cross-repo pattern, a PR discussion, files just read, a correction the user just made — into a durable rule in the **general KB** (`$WF_GENERAL_KB/`). Unlike `/review-findings` and `/learn-from-reports` (which write general-KB rules mined from spec validation reports), this command captures an ad-hoc rule directly from the current conversation, with no active spec required.

> **Durability note:** Changes to `$WF_GENERAL_KB/` are local to this machine. Running `setup.sh --force` from the dev-workflow repo will overwrite them. To make a captured rule permanent, commit it to the general-KB source (the vault/repo backing `$WF_GENERAL_KB`).

## Invocation

```
/capture-rule [optional free-text seed or context refs]
```

`$ARGUMENTS` is optional. When present, treat it as seed context: a rule sketch, a topic hint, a PR URL, a file path, a commit ref, or any combination. When absent, mine the current conversation for the insight to capture.

## Prerequisites

1. Read and follow `$WF_GENERAL_KB/_rules.md` for general KB prerequisites.
2. Read `$WF_GENERAL_KB/_index.md` to understand existing coverage, categories, and file layout.

## Steps

### Step 0 — Prereq check

Verify `$WF_GENERAL_KB/` exists (directory present, `_index.md` readable). If not, print:

```
General knowledge base not found at $WF_GENERAL_KB/.
Run `setup.sh` from the dev-workflow repo first.
```

and exit immediately. Do not proceed to context gathering.

### Step 1 — Gather context

Synthesize a candidate rule from any combination of the following signals. Use whatever is available; do not require all sources.

- `$ARGUMENTS` if provided (rule sketch, topic hint, refs)
- Recent conversation turns — corrections the user made, decisions reached, patterns identified, anti-patterns called out
- Files referenced or read during this session (cite paths)
- PR or commit URLs mentioned — fetch with `gh pr view <num> --json title,body,comments` or `gh api` when useful
- Code paths or function names discussed

If signal is too thin to draft a coherent rule, ask the user (via `AskUserQuestion` per `~/.claude/scripts/ask-user-protocol.md`) for the specific insight they want to capture, then proceed.

Draft a candidate with:
- **Title** — short imperative phrase
- **Body** — 1–5 bullets in imperative voice, no project-specific names/paths
- **Rationale** — one sentence: why this is universal
- **Citations** — files / PRs / conversation excerpts that motivated it (kept for the user's confirmation step; not written into the rule file)

### Step 2 — Dedup scan

Read `$WF_GENERAL_KB/_index.md`. For categories plausibly related to the candidate (security, architecture, code-review, languages/`<lang>`, testing, style, documentation, or any new one), read the matching files and semantically compare existing sections to the candidate.

If one or more near-matches surface, invoke `AskUserQuestion` once with options:
- `Merge into <existing-section>` — append candidate bullets to the existing section in place
- `Skip` — abandon (already covered); exit cleanly with a summary
- `Add anyway` — proceed to Step 3 as a new rule despite overlap

If no near-matches, proceed directly to Step 3.

### Step 3 — Target placement

Decide where the rule belongs. Two cases:

**3a. Fits an existing category/file.**
Score the candidate against existing files listed in `_index.md`. If one is a clear fit, propose appending a new `## <Section>` to that file.

**3b. No good fit — propose new file (or new category).**
If no existing file matches the candidate's theme (low semantic overlap), the command **MUST** propose creating a new file rather than force-fitting. Determine:
- Whether an existing category directory applies (e.g., the rule is about security but no current file covers the angle → new file under `security/`)
- Or whether a new category directory is warranted (e.g., observability, performance, deployment — none currently exist → new `observability/spans.md`)

Invoke `AskUserQuestion` with options (one tool call):
- `Use existing <path>` — best-fit file (only if 3a found a plausible one)
- `Create new <category>/<file>.md` — recommended target
- `Edit names` — open-ended follow-up `AskUserQuestion` for revised category/file name

### Step 4 — Confirm rule body

Display the final rule preview (title, target path, body bullets, rationale, citations) and invoke `AskUserQuestion`:
- `Accept` — apply Step 5
- `Edit` — open-ended `AskUserQuestion` for revised title/body, then re-confirm
- `Reject` — discard and exit

### Step 5 — Write

On Accept:

a. **File.** If the target file exists, read it first, then append `## <Section>` plus the bullets. If the file does not exist:
   - Create parent directories as needed (`mkdir -p` via Bash)
   - Scaffold the file starting with `# <Topic>` header (match existing general KB style — see `$WF_GENERAL_KB/security/general.md` or `$WF_GENERAL_KB/languages/rust/error-handling.md` for shape)
   - Then append the rule section
   - **No frontmatter.** General KB files are plain markdown.

b. **Index.** Update `$WF_GENERAL_KB/_index.md` — preserve the existing table format. Add a new row `| <category>/<file>.md | <Category Title> | <one-line description> |` for new files, or leave existing rows untouched when appending to an existing file. If the description for an existing file is now stale because the appended section materially expands its scope, update the description in place.

c. **General KB only.** This command only ever writes under `$WF_GENERAL_KB/`, regardless of cwd.

### Step 6 — Report and next step

Print:
```
Rule captured: <target-path>
Section: ## <Section>
Bullets: N

Run /capture-rule again to add another, or continue your work.
Remember: changes live in $WF_GENERAL_KB/ only on this machine.
Open a PR in the dev-workflow repo to make it permanent.
```

## Constraints

- **General KB only.** Only ever write under `$WF_GENERAL_KB/`.
- **No spec/feature coupling.** Runs from any cwd, any repo, with or without an active spec.
- **No frontmatter** on rule files.
- **No agent spawning** — main command does synthesis directly.
- **No monitor events** — this is not part of spec flow.
- **All prompts use `AskUserQuestion`** per `~/.claude/scripts/ask-user-protocol.md`. No plain-text menus.
- **Universal phrasing only.** Reject (or revise during Edit) rules that reference project-specific names, paths, internal systems, or team process. If the candidate cannot be made universal, suggest the user capture it via `/review-findings` / `/learn-from-reports` from a relevant spec instead.
