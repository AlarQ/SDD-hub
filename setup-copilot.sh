#!/usr/bin/env bash
set -euo pipefail

# setup-copilot.sh — Install the spec-driven dev workflow for GitHub Copilot
# Run from the dev-workflow repository root.
# Copies Copilot-native files into the target project's .github/ directory.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COPILOT_SRC="$SCRIPT_DIR/copilot"
FORCE=false
TARGET_DIR=""

usage() {
  echo "Usage: $0 [--force] <target-project-path>"
  echo ""
  echo "Install Copilot prompt files, agents, and instructions into a project."
  echo ""
  echo "Arguments:"
  echo "  <target-project-path>  Path to the project where .github/ files will be installed"
  echo ""
  echo "Options:"
  echo "  --force, -f  Overwrite existing files"
  exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force|-f) FORCE=true; shift ;;
    -h|--help) usage ;;
    *) TARGET_DIR="$1"; shift ;;
  esac
done

if [[ -z "$TARGET_DIR" ]]; then
  echo "ERROR: Target project path is required."
  echo ""
  usage
fi

# Resolve to absolute path
TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd)" || {
  echo "ERROR: Target directory does not exist: $TARGET_DIR"
  exit 1
}

GITHUB_DIR="$TARGET_DIR/.github"
SCRIPTS_DST="$TARGET_DIR/scripts"

echo "=== Copilot Workflow Setup ==="
echo "Source: $COPILOT_SRC"
echo "Target: $TARGET_DIR"
echo ""

# 1. Check prerequisites
if ! command -v yq >/dev/null 2>&1; then
  echo "ERROR: yq is not installed."
  echo "  Install: brew install yq"
  exit 1
fi
echo "[ok] yq installed"

if ! command -v gh >/dev/null 2>&1; then
  echo "WARNING: gh CLI is not installed. /ship and /pr-review require it."
  echo "  Install: brew install gh"
fi

# 2. Check source files exist
if [[ ! -d "$COPILOT_SRC" ]]; then
  echo "ERROR: Copilot source directory not found: $COPILOT_SRC"
  echo "  Run this script from the dev-workflow repository root."
  exit 1
fi

# 3. Create target directories
mkdir -p "$GITHUB_DIR/prompts"
mkdir -p "$GITHUB_DIR/agents"
mkdir -p "$GITHUB_DIR/instructions"
mkdir -p "$SCRIPTS_DST"

# Helper: copy file with overwrite protection
safe_copy() {
  local src="$1" dest="$2"
  local name
  name=$(basename "$src")
  if [ -f "$dest" ] && [ "$FORCE" = false ]; then
    if diff -q "$src" "$dest" >/dev/null 2>&1; then
      echo "  [skip] $name (identical)"
    else
      echo "  [CONFLICT] $name already exists and differs — skipped"
      echo "             Use --force to overwrite, or diff manually:"
      echo "             diff \"$src\" \"$dest\""
      return 1
    fi
  else
    cp "$src" "$dest"
    echo "  [ok] $name"
  fi
  return 0
}

# 4. Copy prompt files
echo ""
echo "Installing prompts to $GITHUB_DIR/prompts/"
conflicts=0
conflict_files=()
for prompt_file in "$COPILOT_SRC/prompts/"*.prompt.md; do
  [ -f "$prompt_file" ] || continue
  name=$(basename "$prompt_file")
  if ! safe_copy "$prompt_file" "$GITHUB_DIR/prompts/$name"; then
    conflicts=$((conflicts + 1))
    conflict_files+=("prompts/$name")
  fi
done

# 5. Copy agent files
echo ""
echo "Installing agents to $GITHUB_DIR/agents/"
for agent_file in "$COPILOT_SRC/agents/"*.agent.md; do
  [ -f "$agent_file" ] || continue
  name=$(basename "$agent_file")
  if ! safe_copy "$agent_file" "$GITHUB_DIR/agents/$name"; then
    conflicts=$((conflicts + 1))
    conflict_files+=("agents/$name")
  fi
done

# 6. Copy instruction files
echo ""
echo "Installing instructions to $GITHUB_DIR/instructions/"
for instr_file in "$COPILOT_SRC/instructions/"*.instructions.md; do
  [ -f "$instr_file" ] || continue
  name=$(basename "$instr_file")
  if ! safe_copy "$instr_file" "$GITHUB_DIR/instructions/$name"; then
    conflicts=$((conflicts + 1))
    conflict_files+=("instructions/$name")
  fi
done

# 7. Copy copilot-instructions.md
echo ""
echo "Installing repo-wide instructions to $GITHUB_DIR/"
if ! safe_copy "$COPILOT_SRC/copilot-instructions.md" "$GITHUB_DIR/copilot-instructions.md"; then
  conflicts=$((conflicts + 1))
  conflict_files+=("copilot-instructions.md")
fi

# 8. Copy scripts (task-manager.sh, pre-commit-hook.sh)
echo ""
echo "Installing scripts to $SCRIPTS_DST/"
for script_file in "$SCRIPT_DIR/scripts/"*.sh; do
  [ -f "$script_file" ] || continue
  name=$(basename "$script_file")
  if ! safe_copy "$script_file" "$SCRIPTS_DST/$name"; then
    conflicts=$((conflicts + 1))
    conflict_files+=("scripts/$name")
  fi
  [ -f "$SCRIPTS_DST/$name" ] && chmod +x "$SCRIPTS_DST/$name"
done

# 9. Verify
echo ""
echo "=== Verification ==="

errors=0

# Check prompts
for prompt in bootstrap explore propose implement validate review-findings ship pr-review spec-status workflow-summary; do
  if [ -f "$GITHUB_DIR/prompts/$prompt.prompt.md" ]; then
    echo "[ok] /$prompt prompt"
  else
    echo "[FAIL] /$prompt prompt missing"
    errors=$((errors + 1))
  fi
done

# Check agents
for agent in software-architect security-engineer code-quality compliance-checker ultrathink-debugger code-reviewer; do
  if [ -f "$GITHUB_DIR/agents/$agent.agent.md" ]; then
    echo "[ok] @$agent agent"
  else
    echo "[FAIL] @$agent agent missing"
    errors=$((errors + 1))
  fi
done

# Check instructions
if [ -f "$GITHUB_DIR/copilot-instructions.md" ]; then
  echo "[ok] copilot-instructions.md"
else
  echo "[FAIL] copilot-instructions.md missing"
  errors=$((errors + 1))
fi

# Check scripts
if [ -x "$SCRIPTS_DST/task-manager.sh" ]; then
  echo "[ok] task-manager.sh"
else
  echo "[FAIL] task-manager.sh not executable"
  errors=$((errors + 1))
fi

echo ""
if [ "$conflicts" -gt 0 ]; then
  echo "=== $conflicts conflict(s) ==="
  echo "Skipped files with local changes:"
  for f in "${conflict_files[@]}"; do
    echo "  - $f"
  done
  echo ""
  echo "Re-run with --force to overwrite, or diff manually."
  echo ""
fi

if [ "$errors" -gt 0 ]; then
  echo "Setup failed with $errors error(s). Check the output above."
  exit 1
elif [ "$conflicts" -gt 0 ]; then
  echo "Setup partial — $conflicts file(s) skipped due to conflicts."
else
  echo "Setup complete. All files installed."
fi

echo ""
echo "Next steps:"
echo "  1. Open the project in VS Code with GitHub Copilot"
echo "  2. Type / in Copilot Chat to see available prompts"
echo "  3. Run /bootstrap to create the knowledge-base"
echo "  4. Follow the workflow: /explore -> /propose -> /implement -> /validate -> /review-findings -> /ship"
echo "  5. Use /spec-status <feature> anytime to see the dashboard"
echo "  6. Invoke agents with @software-architect, @security-engineer, etc."
