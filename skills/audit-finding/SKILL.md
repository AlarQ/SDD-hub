---
name: audit-finding
description: Capture a code finding (smell, DRY break, layering/boundary violation, coupling, naming, dead code, security issue, etc.) into a `reports/<category>-<unit>.md` file, then fan out parallel Explore sub-agents across every other code unit (crate / package / module / service) in the repo to hunt the same pattern and write a per-unit report wherever a confident match is found. Language- and ecosystem-agnostic — works in Cargo, npm/pnpm, Go, Python, .NET, Gradle/Maven monorepos, or any multi-package layout. Use this skill whenever the user describes a code issue they found, says things like "I found a smell in X", "this looks bad in package Y", "report this finding", "log this and check the other packages/crates/modules", "/audit-finding", or otherwise asks to record AND propagate a finding across a repo. Prefer this skill over manually writing a single report whenever the user implies the issue might exist elsewhere in the repo.
---

# audit-finding

Capture one code finding, write it as a report H2, then propagate the hunt across every sibling code unit in the repo in parallel.

The skill is **ecosystem-agnostic**. The one Rust-specific concept in the old version — the "crate" — is generalized to a **code unit**: the smallest independently-meaningful package/module directory the repo's ecosystem recognizes. A code unit is a crate in Cargo, a package in npm/pnpm, a module in Go, a package in Python, a project in .NET, a module in Gradle/Maven, and so on.

The report format this skill writes is defined in **`references/report-template.md`** (bundled with the skill, so it works in any repo, with or without a local `reports/_TEMPLATE.md`). Read it before writing your first report in a session.

## When this fires

User describes an issue they found in the repo — a smell, a layering violation, a DRY break, a naming inconsistency, a missing boundary, a coupling/depth problem, a security issue, anything. They want it recorded **and** want to know whether the same pattern exists elsewhere.

If the user only wants a single report with no fan-out, ask first — this skill always propagates.

## What you do

Five steps, in order: **detect workspace shape → extract → write primary report → fan out in parallel → summarize.**

### Step 0 — Detect the workspace shape

You need two things before anything else: the **unit set** (every code unit in the repo, each a fan-out target) and a way to map a file path to its **owning unit**.

A code unit is a directory containing an ecosystem **package marker**. Detect by markers, not by hard-coded folder names — folder conventions vary, markers don't:

| Ecosystem | Package marker (file in unit dir) | Common layout |
|-----------|-----------------------------------|---------------|
| Rust | `Cargo.toml` | `crates/*`, `apps/*` |
| JS/TS | `package.json` | `packages/*`, `apps/*` |
| Go | `go.mod` (multi-module) — else top-level pkg dirs | `cmd/*`, `internal/*`, `pkg/*` |
| Python | `pyproject.toml` / `setup.py` / `setup.cfg` — else dir with `__init__.py` | `src/*`, top-level packages |
| .NET | `*.csproj` | projects under the solution |
| JVM | `build.gradle(.kts)` / `pom.xml` (module) | gradle/maven modules |

**Algorithm** (works for the table above *and* ecosystems not listed — Elixir `mix.exs`, Ruby `*.gemspec`, etc.):

1. Identify the repo's marker filename(s): check the root for a workspace manifest (root `Cargo.toml [workspace]`, root `package.json` with `workspaces`, `pnpm-workspace.yaml`, `go.work`, `*.sln`, `settings.gradle*`) and infer the marker from it. If there is no workspace manifest, pick the marker matching whatever package manifests you find in the tree.
2. Find every directory containing that marker → that is the **unit set**. A unit's name = its directory basename. If two units share a basename, disambiguate with a path-based slug (e.g. `core-utils` for `libs/core/utils`) — report filenames must stay distinct.
3. **Owning unit of a file** = nearest ancestor directory of that file which is in the unit set.

Use a quick discovery command rather than guessing — enumerate from ground truth:

```bash
fd -t f Cargo.toml | grep -v '^Cargo.toml$'      # Rust
fd -t f package.json -E node_modules             # JS/TS
fd -t f go.mod                                   # Go
fd -t f 'pyproject.toml|setup.py|setup.cfg'      # Python
```

(Substitute `find` if `fd` is absent.)

**Ambiguity → ask (`AskUserQuestion`).** Auto-detect first; only prompt when the result is unusable:

- No markers found anywhere, or the only "unit" is the repo root (flat single-package repo). Then there is nothing to fan out across — ask whether to treat top-level source directories (e.g. `src/<x>`, `lib/<x>`) as units, offering the detected candidates, or to write a single report with no fan-out.
- Markers found but the layout is mixed/surprising (markers nested deep, or both a root manifest and per-dir manifests). Show the inferred unit list and ask the user to confirm or correct it before spawning agents.

Keep these prompts terse — one batched question, best-guess candidates as options plus a free-text fallback.

### Step 1 — Extract fields

The report format requires per finding: **Severity**, **Files**, **Problem**, **Fix**, plus a `## [<Category>] <Title>` heading. Also need the **source unit** (the unit the finding lives in) because it drives the report filename.

Parse the user's freeform description for:

- **File paths** — anything that looks like a repo-relative path, optionally with `:line`. Map the first one to its owning unit (Step 0).
- **Source unit** — derived from the first file path's owning unit.
- **Severity hint** — words like "critical", "high", "minor", "small", "nit", "blocker".
- **Category hint** — words like "DRY", "duplication", "layering", "boundary", "error handling", "naming", "depth", "coupling", "leaky abstraction", "dead code", "security". Use a kebab-case slug.
- **Title** — a short, specific phrase from the description (the *what*, not the *where*).
- **Problem** — the user's own explanation of what is wrong.
- **Fix** — the user's own suggestion, if given.

For any field you cannot confidently extract, use `AskUserQuestion`. Batch related missing fields into one call. Option sets:

- Severity: `High` / `Medium` / `Low`.
- Category: present 2–3 inferred candidates (kebab-case slugs) + free-text fallback. **Stay consistent with slugs already used in `reports/`** — list the directory first and reuse an existing slug if one fits.
- Source unit: if the description has no file paths, ask which unit (offer the unit set from Step 0).
- Title / Problem / Fix: ask only if absent or one-word vague.

Do not invent a Fix the user did not gesture at. If they have no fix in mind, ask.

### Step 2 — Write the primary report

**Target path**: `reports/<category-slug>-<source-unit-slug>.md`. Filenames must stay distinct within `reports/` (see constraint 6).

Follow the format in **`references/report-template.md`**. If the repo also has a `reports/_TEMPLATE.md`, prefer the repo's version where it differs — it is the local source of truth. Quick recap of the format:

**If the report file does not exist**, create with this header (no comment block, no YAML frontmatter):

```markdown
# Findings: `<source-unit>`

**Date**: <today, YYYY-MM-DD>
**Scope**: `<source-unit>`

---
```

**Then append the finding** as a single H2:

```markdown
## [<Category>] <Title>

**Severity**: <High|Medium|Low>

**Files**:
- `<path>:<line>` (or just `<path>` if no line)
- `<additional file>` (lines X-Y)

**Problem**:
<User's explanation. Code snippet in a fenced block if helpful.>

**Fix**:
<Concrete remediation pointing at file/location.>

---
```

**Dedup rule**: compute the heading slug (lowercase, non-alphanumeric → `-`, collapse runs of `-`, trim). If a heading with that exact slug already exists in the file, **skip the write** and warn the user that the finding was already reported. Do not mutate existing H2s. Do not invent meta-H2s — the only reserved ones are `## Summary` and `## Already Resolved`.

### Step 3 — Fan out across other units

Fan-out targets = the **unit set from Step 0, minus the source unit**. Non-code entries are excluded automatically, since the unit set is marker-derived.

Spawn one `Explore` sub-agent per target **in parallel** — a single message with multiple `Agent` tool calls. This is the default and the fast path; do not serialize parallel-capable work.

**Fallback when sub-agents are unavailable** (e.g. you are already running inside a sub-agent that cannot spawn its own, or the `Agent` tool is absent): do the fan-out **inline** — search each other unit yourself for the same pattern, applying the identical confidence rule, and write the per-unit reports directly. The output contract (which reports get written, where) is what matters; whether the search ran in parallel agents or inline does not change the result.

Each sub-agent prompt must include:

- The finding's **Category**, **Title**, **Problem**, **Fix**, and the original **Files** as the exemplar.
- The target unit's path.
- The expected report path: `reports/<category-slug>-<target-unit-slug>.md`.
- The slug of the primary H2, so the sub-agent can apply the same dedup rule.
- The template body shape (copy the H2 block from Step 2).
- Explicit confidence rule: **only write a report when it can cite a concrete `file:line` analogue.** Vague structural similarity is not enough. Uncertain → return `NO MATCH` with one sentence of rationale and write nothing.
- Output contract: return one of `MATCH <path>:<line> — <report-path> [created|appended|skipped]` or `NO MATCH — <one-line reason>`.

Sub-agents are read-only with respect to source code; their only write is the per-unit report.

### Step 4 — Summary table

After every sub-agent returns, print a table:

| Unit | Outcome | Report |
|------|---------|--------|
| `<unit>` | created / appended / skipped (slug exists) / no match | `reports/<slug>-<unit>.md` or `—` |

Group `no match` rows at the bottom. Mention the primary report path explicitly at the top so the user can jump to it.

## Hard constraints (report-format contract)

These are pure-markdown rules — nothing ecosystem-specific. They keep each report self-describing and, where a downstream consumer exists (the `address-findings` skill, or a scheduler script like `scripts/address-reports.sh`), keep it parseable. **The skill does not require any such consumer to be present** — the format is the contract; the consumers are optional.

1. Each finding is exactly one H2. No nested H2s inside a finding.
2. Heading text must be unique after slugify within a file.
3. Body must contain **Severity**, **Files**, **Problem**, **Fix** in that order.
4. Reserved H2s, never invent others: `## Summary`, `## Already Resolved`.
5. No YAML frontmatter.
6. Report filenames within `reports/` must be distinct (`<category>-<unit>.md`) — a scheduler keys worktrees/branches off the basename, and even without one, distinct names keep findings navigable.
7. Closing a finding is not this skill's job — leave headings alone. A scheduler appends ` — RESOLVED (YYYY-MM-DD, #PR)` on success; manually, the same suffix or a move into `## Already Resolved` works.

This skill captures and propagates findings. It does **not** fix them. Fixing is `/address-findings` (or any flow that consumes these reports).

## Examples

**Rust (Cargo workspace):**

User: `/audit-finding DRY violation in crates/user/src/api/handlers.rs:42 — session lookup logic is repeated three times in this file, extract a helper`.

1. Step 0: markers = `Cargo.toml`; unit set = the crates + apps. Source unit = `user`.
2. Extract: category `dry-violations` (matches existing slug), title `repeated session lookup in handlers`, problem + fix from prose. Ask only for Severity.
3. Write `reports/dry-violations-user.md`.
4. Fan out one Explore agent per other unit, hunting the repeated session-lookup shape.
5. Summary — e.g. `ai`: appended, `events`: no match, `budget-app`: created.

**JS/TS (pnpm monorepo):**

User: `found a layering smell — packages/api/src/routes/orders.ts imports straight from packages/db/src/client, skipping the repository layer`.

1. Step 0: `pnpm-workspace.yaml` present → marker `package.json`; unit set = `packages/*`, `apps/*`. Source unit = `api`.
2. Extract: category `layering` (no existing slug in `reports/`), files `packages/api/src/routes/orders.ts`, title `route imports db client directly`, problem + fix from prose. Ask for Severity.
3. Write `reports/layering-api.md`.
4. Fan out one Explore agent per other package, hunting routes/handlers that reach past the repository layer into the db client.
5. Summary table.

## Notes on judgment

- The user is auditing manually and using you as leverage. Stay terse in field-extraction questions — one prompt, batched options, no chit-chat.
- If the user's description is very rich, prefer extracting silently over asking. Only ask for genuinely missing fields, or when Step 0 is genuinely ambiguous.
- If a sub-agent returns something borderline ("similar shape but different semantics"), trust the confidence rule and treat it as NO MATCH. False positives waste downstream fix cycles.
- If `reports/` does not exist, create it.
- If the repo has no package markers at all (a flat single-package repo), there is nothing to fan out across — say so and offer to write just the primary report.
