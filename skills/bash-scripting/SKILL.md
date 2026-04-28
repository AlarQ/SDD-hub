---
name: bash-scripting
description: >
  Expert guidance for writing and refining bash scripts. Covers script structure,
  error handling, argument parsing, security, shellcheck validation, and modern CLI tools.
  Use when asked to write a new bash script or improve an existing one.
user-invokable: true
args:
  - name: task
    description: Description of the script to write, or path to an existing script to refine
    required: false
---

Write or refine a bash script. All technical substance stays; only noise is cut.

## Detect Mode

Check the `$task` argument:
- If it's a **file path** that exists → **Refine mode**: read the script first, then jump to the Refine section below.
- If it's a **description** or empty → **New script mode**: proceed top to bottom.

## Gather Requirements

Before writing anything, confirm:
- **Purpose**: what does the script do?
- **Inputs**: args, flags, stdin, env vars?
- **Outputs**: stdout, files, exit codes?
- **Target OS**: macOS, Linux, both?
- **Error behavior**: exit on first error, or collect and report?

If any of these are unclear from context, STOP and call AskUserQuestion before proceeding.

## Script Foundation

Every script starts with this skeleton:

```bash
#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

readonly EXIT_SUCCESS=0
readonly EXIT_FAILURE=1
readonly EXIT_INVALID_ARGS=2

log_info()  { echo "[INFO]  $*"; }
log_error() { echo "[ERROR] $*" >&2; }
die()       { log_error "$@"; exit "$EXIT_FAILURE"; }

cleanup() {
    local code=$?
    rm -f "${temp_file:-}"
    exit "$code"
}
trap cleanup EXIT
```

Rules:
- `set -euo pipefail` — always, no exceptions
- `SCRIPT_DIR` / `SCRIPT_NAME` — always readonly
- Exit code constants — define before use
- `cleanup` trap — always, even if no temp files yet (add them later without forgetting the trap)

## Argument Parsing

Always include `--help`. Use `getopts` with long-option passthrough:

```bash
usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [options] <required-arg>

Options:
    -h, --help       Show this help message
    -v, --verbose    Enable verbose output
    -o, --output DIR Output directory (default: ./output)

Examples:
    $SCRIPT_NAME input.txt
    $SCRIPT_NAME -v -o /tmp/out input.txt
EOF
}

parse_args() {
    VERBOSE=false
    OUTPUT_DIR="./output"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)    usage; exit "$EXIT_SUCCESS" ;;
            -v|--verbose) VERBOSE=true; shift ;;
            -o|--output)  [[ $# -gt 1 ]] || die "-o requires an argument"; OUTPUT_DIR="$2"; shift 2 ;;
            --output=*)   OUTPUT_DIR="${1#*=}"; shift ;;
            --)           shift; break ;;
            -*)           die "Unknown option: $1" ;;
            *)            break ;;
        esac
    done

    [[ $# -ge 1 ]] || { usage; exit "$EXIT_INVALID_ARGS"; }
    INPUT_FILE="$1"
}
```

## Input Validation

Always validate before doing work:

```bash
validate_inputs() {
    [[ -f "$INPUT_FILE" ]] || die "File not found: $INPUT_FILE"
    [[ -r "$INPUT_FILE" ]] || die "File not readable: $INPUT_FILE"
    mkdir -p "$OUTPUT_DIR" || die "Cannot create output directory: $OUTPUT_DIR"
}
```

For user-supplied strings used in commands, sanitize:
```bash
[[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]] || die "Invalid name format: $name"
```

## Implementation Rules

Write logic in pure functions with `local` variables.

**Always:**
- Quote all variable expansions: `"$var"`, `"${array[@]}"`
- Use `[[ ]]` not `[ ]` for conditionals
- Use `$(command)` not `` `command` ``
- Use `while IFS= read -r line` to read files line by line
- Use `find ... -print0 | while IFS= read -r -d '' f` for file iteration
- Check command existence: `command -v git &>/dev/null || die "git not found"`
- Use `mktemp` for temp files: `temp_file=$(mktemp)`

**Prefer modern tools when available:**
- `rg` over `grep -r` for recursive search
- `fd` over `find` for file discovery
- `jq` for JSON, `yq` for YAML
- `bat` for syntax-highlighted output in interactive scripts

**Never:**
- Parse `ls` output
- Use `eval` on user input
- Use bare `$var` where word-splitting matters
- Use backticks

## Security Checklist

Before finishing, verify:
- [ ] No `eval` on external input
- [ ] All temp files created with `mktemp`, cleaned up in `trap`
- [ ] User-supplied strings sanitized before use in commands
- [ ] No hardcoded credentials or secrets
- [ ] File paths validated before open/read/write
- [ ] Permissions checked (`-r`, `-w`, `-x`) before operations

## ShellCheck Gate — MANDATORY

Run shellcheck and fix all issues before delivering:

```bash
shellcheck -s bash -C auto <path/to/script>
```

- Fix every reported issue — no exceptions, no ignores without documented reason
- Re-run after each fix batch until output is clean
- If a finding requires `# shellcheck disable=SCxxxx`, add a comment explaining why

## main() Wiring

Always call logic through `main "$@"`:

```bash
main() {
    parse_args "$@"
    validate_inputs
    # ... core logic ...
    log_info "Done."
}

main "$@"
```

---

## Refine Mode

When given an existing script, follow this sequence:

### 1. Read the Script

Read the full file. Do not guess at content.

### 2. Audit for Issues

Check systematically:

| Issue | What to look for |
|-------|-----------------|
| Missing strict mode | No `set -euo pipefail` at top |
| Unquoted variables | `$var` without quotes in risky contexts |
| Missing --help | No `-h` / `--help` flag |
| No cleanup trap | Temp files with no `trap cleanup EXIT` |
| Backtick substitution | `` `cmd` `` instead of `$(cmd)` |
| `[ ]` instead of `[[ ]]` | Single-bracket conditionals in bash |
| `ls` parsing | `for f in $(ls ...)` |
| Missing `local` | Variables in functions without `local` |
| No input validation | Args used without existence/type checks |
| `eval` on user input | Security risk |

### 3. Apply Fixes

Edit the file with targeted changes. Don't rewrite working logic — only fix identified issues.

### 4. ShellCheck Gate

Run shellcheck on the modified file. Fix all new issues. Re-run until clean.

### 5. Report Changes

Summarize what was fixed:
- List each issue category that had fixes
- Note any intentional shellcheck disables with reasons
- Flag anything that couldn't be fixed without behavioral changes (ask user)
