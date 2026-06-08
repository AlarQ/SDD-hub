<!--
  Findings report template — ecosystem-agnostic.

  Bundled with the audit-finding skill so reports have a stable format in ANY repo
  (Cargo, npm/pnpm, Go, Python, .NET, Gradle/Maven, …), independent of whether the
  repo has its own reports/_TEMPLATE.md.

  Optionally consumed by:
    - address-findings skill        — reads each finding's body to plan + implement the fix
    - a scheduler script, e.g.        scripts/address-reports.sh — parses `^## ` headings,
                                       spawns one worker / PR per open finding
  Neither consumer is required. The format below IS the contract; consumers are optional.
  If a repo ships its own reports/_TEMPLATE.md, that local file wins where it differs.

  Hard rules (violating these breaks any scheduler that parses the report):
    1. Each finding is exactly one H2 (`## …`). No nested H2s inside a finding.
    2. Heading text must be unique after slugify (lowercase, non-alnum → `-`).
       Author convention: `## [Category] Short title`.
    3. Body MUST contain: **Severity**, **Files**, **Problem**, **Fix** (in that order).
    4. Reserved H2s, auto-skipped by parsers: `## Summary`, `## Already Resolved`.
       Do NOT invent other meta-H2s — they'd be picked up as findings.
    5. No YAML frontmatter.
    6. Report filenames within reports/ must be distinct: `<category>-<unit>.md`.
       A "unit" is the code unit the finding lives in — crate / package / module /
       project / service, whatever the repo's ecosystem calls it.
    7. Closing a finding:
         - Scheduler-driven: leave the heading alone; the scheduler appends
           ` — RESOLVED (YYYY-MM-DD, #PR)` on worker success.
         - Manual: append the same suffix, or move the item into `## Already Resolved`.

  Delete this comment block when authoring a real report.
-->

# Findings: `<unit>`

**Date**: YYYY-MM-DD
**Scope**: <files / dirs / unit covered>

---

## Summary

<Optional. One paragraph framing the audit. Skipped by parsers.>

---

## [<Category>] <Short, unique title>

**Severity**: High | Medium | Low

**Files**:
- `path/to/file.ext:42`
- `path/to/other.ext` (lines 10-25)

**Problem**:
<What is wrong and why it matters. Code snippet OK.>

```
// minimal example showing the smell (use the repo's language)
```

**Fix**:
<Concrete remediation. Name the target file/location. Used as the starting point for the plan.>

---

## [<Category>] <Next finding title>

**Severity**: …

**Files**:
- `…`

**Problem**: …

**Fix**: …

---

## Already Resolved

<Optional. Bucket for items closed before any scheduler era. Skipped by parsers.>

- `[Category] Foo` — closed YYYY-MM-DD in #99
