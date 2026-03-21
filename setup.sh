#!/usr/bin/env bash
set -euo pipefail

# setup.sh — Install the spec-driven dev workflow into ~/.claude/
# Run from the dev-workflow repository root.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
COMMANDS_DIR="$CLAUDE_DIR/commands"
SCRIPTS_DIR="$CLAUDE_DIR/scripts"
AGENTS_DIR="$CLAUDE_DIR/agents"
FORCE=false

if [[ "${1:-}" == "--force" || "${1:-}" == "-f" ]]; then
  FORCE=true
fi

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
mkdir -p "$AGENTS_DIR"

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

# 3. Copy slash commands
echo ""
echo "Installing slash commands to $COMMANDS_DIR/"
conflicts=0
conflict_files=()
for cmd_file in "$SCRIPT_DIR/commands/"*.md; do
  [ -f "$cmd_file" ] || continue
  name=$(basename "$cmd_file")
  if ! safe_copy "$cmd_file" "$COMMANDS_DIR/$name"; then
    conflicts=$((conflicts + 1))
    conflict_files+=("$name")
  fi
done

# 4. Copy scripts
echo ""
echo "Installing scripts to $SCRIPTS_DIR/"
for script_file in "$SCRIPT_DIR/scripts/"*.sh; do
  [ -f "$script_file" ] || continue
  name=$(basename "$script_file")
  if ! safe_copy "$script_file" "$SCRIPTS_DIR/$name"; then
    conflicts=$((conflicts + 1))
    conflict_files+=("$name")
  fi
  [ -f "$SCRIPTS_DIR/$name" ] && chmod +x "$SCRIPTS_DIR/$name"
done

# 5. Copy agent definitions
echo ""
echo "Installing agents to $AGENTS_DIR/"
for agent_file in "$SCRIPT_DIR/agents/"*.md; do
  [ -f "$agent_file" ] || continue
  name=$(basename "$agent_file")
  # Skip non-agent files
  case "$name" in CONTRIBUTING.md|INTEGRATION_PLAN.md|LICENSE|README.md) continue ;; esac
  if ! safe_copy "$agent_file" "$AGENTS_DIR/$name"; then
    conflicts=$((conflicts + 1))
    conflict_files+=("$name")
  fi
done

# Copy agent subdirectories (engineering, testing, design, product, project-management)
for agent_subdir in "$SCRIPT_DIR/agents/"*/; do
  [ -d "$agent_subdir" ] || continue
  subdir_name=$(basename "$agent_subdir")
  # Skip non-agent directories
  case "$subdir_name" in scripts) continue ;; esac
  mkdir -p "$AGENTS_DIR/$subdir_name"
  for agent_file in "$agent_subdir"*.md; do
    [ -f "$agent_file" ] || continue
    name=$(basename "$agent_file")
    if ! safe_copy "$agent_file" "$AGENTS_DIR/$subdir_name/$name"; then
      conflicts=$((conflicts + 1))
      conflict_files+=("$name")
    fi
  done
done

# 6. Verify
echo ""
echo "=== Verification ==="

errors=0

# Check commands
for cmd in bootstrap explore propose implement validate review-findings ship pr-review spec-status workflow-summary; do
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

# Check core validation agents
for agent in code-quality-pragmatist claude-md-compliance-checker; do
  if [ -f "$AGENTS_DIR/$agent.md" ]; then
    echo "[ok] $agent agent"
  else
    echo "[FAIL] $agent agent missing"
    errors=$((errors + 1))
  fi
done
for agent in engineering-security-engineer engineering-software-architect engineering-code-reviewer; do
  if [ -f "$AGENTS_DIR/engineering/$agent.md" ]; then
    echo "[ok] $agent agent"
  else
    echo "[FAIL] $agent agent missing"
    errors=$((errors + 1))
  fi
done

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
echo "  1. Open a target project in Claude Code"
echo "  2. Run /bootstrap to create the knowledge-base"
echo "  3. Follow the workflow: /explore -> /propose -> /implement -> /validate -> /review-findings -> /ship"
echo "  4. Use /spec-status <feature> anytime to see the dashboard"
