# Report Schema (Canonical)

Single source of truth for validation report YAML shape. All commands that read or write reports under `specs/<feature>/reports/` MUST conform to this schema. Do not restate the shape inline — link here.

Consumers: `commands/validate.md`, `commands/validate-impl.md`, `commands/review-and-ship.md`, `commands/learn-from-reports.md`.

## File location

`specs/<feature>/reports/<task-id>-<gate>.yaml` (per-task gate reports), `specs/<feature>/reports/spec-audit-<timestamp>.md` (spec-completion audit from `/validate-impl`).

## Top-level fields

```yaml
gate: <gate-id>            # e.g. shellcheck, security
task_id: <task-id>         # omitted on spec-level reports (spec-audit)
status: pass | findings | error
findings: []               # see Finding schema below
```

- `status: pass` iff `findings` is empty.
- `status: findings` iff at least one finding exists.
- `status: error` iff the gate/agent timed out or crashed — must be re-run before proceeding.

## Finding schema

```yaml
- id: <gate>-<n>           # stable within report
  severity: critical | high | medium | low | info
  category: <free-form>    # gate-specific
  title: <short>
  description: <detail>
  file: <path>             # relative to repo root
  lines: "<start>-<end>"
  code_snippet: <quoted text>
  fix_proposal: <concrete patch>
  rationale: <optional — why this is flagged: root cause / principle violated>
  impact: <optional — concrete consequence if shipped unfixed>
  references: <optional list — KB rule paths, CWE ids, doc URLs>
  confidence: <optional, llm only — high | medium | low>
  review_status: pending | accepted | rejected | noted
  source: tool | llm
  review_notes: <optional, set on reject>
  rule_added: <optional bool, set when a reject spawns a project-KB rule>
  auto_accepted: <optional bool, set when /review-and-ship auto-accepts + fixes mechanically>
```

### Field semantics

- `description` — *what* is wrong (the observation).
- `rationale` — *why* it is wrong (root cause, principle violated, KB rule logic). Optional but expected on `source: llm` findings.
- `impact` — *what breaks* if shipped unfixed (concrete, scoped — not generic warnings). Expected on `source: llm` findings.
- `references` — pointer list users can jump to: KB rule path (e.g. `general:security/general.md`), CWE id (e.g. `CWE-89`), or doc URL.
- `confidence` — LLM-source self-assessment of how certain the finding is. Guides reject heuristics in review.
- `auto_accepted` — set `true` by `/review-and-ship` when a finding lands in the auto bucket (mechanical category within cap, or a `coverage` gap) and its fix is applied by a spawned agent without a human prompt. Always paired with `review_status: accepted`. `/learn-from-reports` skips `auto_accepted` findings when mining KB-rule candidates (mechanical, low-signal).

Tool-source findings (shellcheck, lint) MAY omit `rationale` / `impact` / `confidence`. LLM-source findings SHOULD populate `rationale` and `impact`.

### Enums

- **severity** — `critical | high | medium | low | info`
- **review_status** — `pending` (default at write time), `accepted`, `rejected`, `noted` (informational)
- **source** — `tool` (deterministic gate output) or `llm` (advisory agent finding)

## Spec-audit reports (`/validate-impl`)

Markdown, not YAML. Frontmatter MUST contain:

```yaml
feature: <name>
timestamp: <iso8601>
scope: <summary>
verdict: complete | reopen
```

Body MUST contain an FR matrix section: one row per FR, marked `implemented | partial | missing`. `/review-and-ship` synthesizes one review unit per `missing` (severity `high`) or `partial` (severity `medium`) row, all with `source: llm`.

## Lifecycle

1. `/validate` / `/validate-impl` write reports with `review_status: pending` on every finding.
2. `/review-and-ship` mutates `review_status` to `accepted` / `rejected` / `noted` and may set `review_notes`, `rule_added`, `auto_accepted`.
3. `/learn-from-reports` mines reports for KB rule patterns **in place** (scoped by task-id). Reports are **retained** as a local audit trail — never deleted, here or anywhere else.
