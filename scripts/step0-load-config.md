# Step 0 — Load Spec Config (canonical snippet)

Shared Step 0 contract referenced by all workflow commands. Eliminates per-command copy-paste of the loader invocation prose.

## Invocation

Each command runs Step 0 before any gate, agent spawn, or task transition:

```bash
bash -c 'source ~/.claude/scripts/config-loader.sh && wf_load_config --spec <feature> && printf "<VAR>=%s\n" "$<VAR>" ...'
```

Commands without a feature scope (e.g. `/config`) drop `--spec <feature>` and load repo-level config only.

The `printf` block is **command-specific**: each command echoes only the env vars it consumes downstream. The full exported set lives in the loader contract.

## Contract pointer

Loader env vars + exit codes: `~/.claude/scripts/config-loader.contract.md`. Commands MUST link there for the full table — never inline partial lists.

## Exit-code remediation

On non-zero exit, halt and print the loader error. Selected codes:

- **2** — repo-level config (`.workflow.yml`) missing or invalid → run `/bootstrap`.
- **4** — spec-level config (`specs/<feature>/config.yml`) missing or invalid → run `/explore <feature>` or `/config <feature>`.

See contract for the full code table.

## Usage in commands

Each command's Step 0 reduces to:

````markdown
## Step 0 — Load Spec Config

> See `~/.claude/scripts/step0-load-config.md` for canonical invocation and remediation. This step uses: `WF_FOO`, `WF_BAR`.

```bash
bash -c 'source ~/.claude/scripts/config-loader.sh && wf_load_config --spec $ARGUMENTS && printf "WF_FOO=%s\nWF_BAR=%s\n" "$WF_FOO" "${WF_BAR:-}"'
```
````

No prose duplication of the contract pointer or exit-code remediation — link only.
