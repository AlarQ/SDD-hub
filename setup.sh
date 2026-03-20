#!/usr/bin/env bash
set -euo pipefail

# setup.sh — Install the spec-driven dev workflow into ~/.claude/
# Run from the dev-workflow repository root.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
COMMANDS_DIR="$CLAUDE_DIR/commands"
SCRIPTS_DIR="$CLAUDE_DIR/scripts"

echo "=== Spec-Driven Dev Workflow Setup ==="
echo ""

# 1. Check yq dependency
if ! command -v yq >/dev/null 2>&1; then
  echo "ERROR: yq is not installed."
  echo "  Install: brew install yq"
  exit 1
fi
echo "[ok] yq installed ($(yq --version))"

# 2. Create directories
mkdir -p "$COMMANDS_DIR"
mkdir -p "$SCRIPTS_DIR"

# 3. Copy slash commands
echo ""
echo "Installing slash commands to $COMMANDS_DIR/"
for cmd_file in "$SCRIPT_DIR/commands/"*.md; do
  [ -f "$cmd_file" ] || continue
  name=$(basename "$cmd_file")
  cp "$cmd_file" "$COMMANDS_DIR/$name"
  echo "  [ok] $name"
done

# 4. Copy scripts
echo ""
echo "Installing scripts to $SCRIPTS_DIR/"
for script_file in "$SCRIPT_DIR/scripts/"*.sh; do
  [ -f "$script_file" ] || continue
  name=$(basename "$script_file")
  cp "$script_file" "$SCRIPTS_DIR/$name"
  chmod +x "$SCRIPTS_DIR/$name"
  echo "  [ok] $name"
done

# 5. Verify
echo ""
echo "=== Verification ==="

errors=0

# Check commands
for cmd in bootstrap explore propose implement validate review-findings pr-review; do
  if [ -f "$COMMANDS_DIR/$cmd.md" ]; then
    echo "[ok] /$cmd command"
  else
    echo "[FAIL] /$cmd command missing"
    errors=$((errors + 1))
  fi
done

# Check scripts
if [ -x "$SCRIPTS_DIR/task-manager.sh" ]; then
  echo "[ok] task-manager.sh"
else
  echo "[FAIL] task-manager.sh not executable"
  errors=$((errors + 1))
fi

echo ""
if [ "$errors" -eq 0 ]; then
  echo "Setup complete. All files installed."
  echo ""
  echo "Next steps:"
  echo "  1. Open a target project in Claude Code"
  echo "  2. Run /bootstrap to create the knowledge-base"
  echo "  3. Follow the workflow: /explore -> /propose -> /implement -> /validate -> /review-findings"
else
  echo "Setup completed with $errors error(s). Check the output above."
  exit 1
fi
