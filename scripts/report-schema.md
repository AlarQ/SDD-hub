# Report Schema (Canonical)

Single source of truth for validation report YAML shape. All commands that read or write reports under `specs/<feature>/reports/` MUST conform to this schema. Do not restate the shape inline — link here.

Consumers: `commands/validate.md`, `commands/validate-spec.md`, `commands/validate-impl.md`, `commands/review-findings.md`, `commands/learn-from-reports.md`.

## File location

`specs/<feature>/reports/<task-id>-<gate>.yaml` (per-task gate reports), `specs/<feature>/reports/spec-review.yaml` (spec coherence audit), `specs/<feature>/reports/spec-audit-<timestamp>.md` (spec-completion audit from `/validate-impl`).

## Top-level fields

```yaml
gate: <gate-id>            # e.g. shellcheck, security, spec-review
task_id: <task-id>         # omitted on spec-level reports (spec-review, spec-audit)
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
  category: <free-form>    # gate-specific; spec-review uses a fixed enum (below)
  title: <short>
  description: <detail>
  file: <path>             # relative to repo root
  lines: "<start>-<end>"
  code_snippet: <quoted text>
  fix_proposal: <concrete patch>
  review_status: pending | accepted | rejected | noted
  source: tool | llm
  review_notes: <optional, set on reject>
  rule_added: <optional bool, set when a reject spawns a project-KB rule>
```

### Enums

- **severity** — `critical | high | medium | low | info`
- **review_status** — `pending` (default at write time), `accepted`, `rejected`, `noted` (informational)
- **source** — `tool` (deterministic gate output) or `llm` (advisory agent finding)

### Category enum (spec-review only)

`/validate-spec` constrains `category` to:

`contract | logic-gap | missing-piece | repo-misalignment | kb-compliance | task-graph | ambiguity | testability | traceability`

Other gates use free-form category strings.

## Spec-audit reports (`/validate-impl`)

Markdown, not YAML. Frontmatter MUST contain:

```yaml
feature: <name>
timestamp: <iso8601>
scope: <summary>
verdict: complete | reopen
```

Body MUST contain an FR matrix section: one row per FR, marked `implemented | partial | missing`. `/review-findings` synthesizes one review unit per `missing` (severity `high`) or `partial` (severity `medium`) row, all with `source: llm`.

## Lifecycle

1. `/validate` / `/validate-spec` / `/validate-impl` write reports with `review_status: pending` on every finding.
2. `/review-findings` mutates `review_status` to `accepted` / `rejected` / `noted` and may set `review_notes`, `rule_added`.
3. `/learn-from-reports` mines reports for KB rule patterns and owns deletion. Report deletion happens nowhere else.
