#!/usr/bin/env bash
set -euo pipefail

# setup.sh — Install the spec-driven dev workflow into ~/.claude/
# Run from the dev-workflow repository root.

# Colors
if [ -t 1 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  BLUE='\033[0;34m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  DIM='\033[2m'
  RESET='\033[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' DIM='' RESET=''
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
COMMANDS_DIR="$CLAUDE_DIR/commands"
SCRIPTS_DIR="$CLAUDE_DIR/scripts"
AGENTS_DIR="$CLAUDE_DIR/agents"
HOOKS_DIR="$CLAUDE_DIR/hooks"
TEMPLATES_DIR="$CLAUDE_DIR/templates"
KB_DIR="$CLAUDE_DIR/knowledge-base"
KB_RULES="$CLAUDE_DIR/knowledge-base-rules.md"
FORCE=false

if [[ "${1:-}" == "--force" || "${1:-}" == "-f" ]]; then
  FORCE=true
fi

echo -e "${BOLD}${BLUE}=== Spec-Driven Dev Workflow Setup ===${RESET}"
echo ""

# 1. Check yq dependency
if ! command -v yq >/dev/null 2>&1; then
  echo -e "${RED}ERROR: yq is not installed.${RESET}"
  echo "  Install: brew install yq"
  exit 1
fi
echo -e "${GREEN}[ok]${RESET} yq installed ${DIM}($(yq --version))${RESET}"

# 2. Create directories
mkdir -p "$COMMANDS_DIR"
mkdir -p "$SCRIPTS_DIR"
mkdir -p "$AGENTS_DIR"
mkdir -p "$HOOKS_DIR"
mkdir -p "$TEMPLATES_DIR"
mkdir -p "$KB_DIR/security"
mkdir -p "$KB_DIR/architecture"
mkdir -p "$KB_DIR/testing"
mkdir -p "$KB_DIR/style"
mkdir -p "$KB_DIR/documentation"
mkdir -p "$KB_DIR/code-review"
mkdir -p "$KB_DIR/languages"

# Helper: copy file with overwrite protection
safe_copy() {
  local src="$1" dest="$2"
  local name
  name=$(basename "$src")
  if [ -f "$dest" ] && [ "$FORCE" = false ]; then
    if diff -q "$src" "$dest" >/dev/null 2>&1; then
      echo -e "  ${DIM}[skip]${RESET} $name ${DIM}(identical)${RESET}"
    else
      echo -e "  ${YELLOW}[CONFLICT]${RESET} $name already exists and differs — skipped"
      echo -e "             Use ${BOLD}--force${RESET} to overwrite, or diff manually:"
      echo "             diff \"$src\" \"$dest\""
      return 1
    fi
  else
    cp "$src" "$dest"
    echo -e "  ${GREEN}[ok]${RESET} $name"
  fi
  return 0
}

# 3. Copy slash commands
echo ""
echo -e "${CYAN}Installing slash commands to $COMMANDS_DIR/${RESET}"
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
echo -e "${CYAN}Installing scripts to $SCRIPTS_DIR/${RESET}"
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
echo -e "${CYAN}Installing agents to $AGENTS_DIR/${RESET}"
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

# 6. Copy hooks
echo ""
echo -e "${CYAN}Installing hooks to $HOOKS_DIR/${RESET}"
for hook_file in "$SCRIPT_DIR/hooks/"*.sh; do
  [ -f "$hook_file" ] || continue
  name=$(basename "$hook_file")
  if ! safe_copy "$hook_file" "$HOOKS_DIR/$name"; then
    conflicts=$((conflicts + 1))
    conflict_files+=("$name")
  fi
  [ -f "$HOOKS_DIR/$name" ] && chmod +x "$HOOKS_DIR/$name"
done

# 7. Copy templates
echo ""
echo -e "${CYAN}Installing templates to $TEMPLATES_DIR/${RESET}"
for tpl_file in "$SCRIPT_DIR/templates/"*; do
  [ -f "$tpl_file" ] || continue
  name=$(basename "$tpl_file")
  if ! safe_copy "$tpl_file" "$TEMPLATES_DIR/$name"; then
    conflicts=$((conflicts + 1))
    conflict_files+=("$name")
  fi
done

# 8. Copy general knowledge base
echo ""
echo -e "${CYAN}Installing general knowledge base to $KB_DIR/${RESET}"
safe_copy "$SCRIPT_DIR/knowledge-base/_index.md" "$KB_DIR/_index.md" || {
  conflicts=$((conflicts + 1))
  conflict_files+=("_index.md")
}
for kb_subdir in security architecture testing style documentation code-review languages; do
  for kb_file in "$SCRIPT_DIR/knowledge-base/$kb_subdir/"*.md; do
    [ -f "$kb_file" ] || continue
    name=$(basename "$kb_file")
    if ! safe_copy "$kb_file" "$KB_DIR/$kb_subdir/$name"; then
      conflicts=$((conflicts + 1))
      conflict_files+=("$name")
    fi
  done
done

# 9. Copy knowledge base rules
echo ""
echo -e "${CYAN}Installing knowledge base rules to $KB_RULES${RESET}"
if ! safe_copy "$SCRIPT_DIR/knowledge-base-rules.md" "$KB_RULES"; then
  conflicts=$((conflicts + 1))
  conflict_files+=("knowledge-base-rules.md")
fi

# 10. Verify
echo ""
echo -e "${BOLD}${BLUE}=== Verification ===${RESET}"

errors=0

# Check commands
for cmd in bootstrap explore propose implement validate review-findings ship quick-ship pr-review spec-status workflow-summary continue-task research; do
  if [ -f "$COMMANDS_DIR/$cmd.md" ]; then
    echo -e "${GREEN}[ok]${RESET} /$cmd command"
  else
    echo -e "${RED}[FAIL]${RESET} /$cmd command missing"
    errors=$((errors + 1))
  fi
done

# Check scripts
for script in task-manager.sh pre-commit-hook.sh; do
  if [ -x "$SCRIPTS_DIR/$script" ]; then
    echo -e "${GREEN}[ok]${RESET} $script"
  else
    echo -e "${RED}[FAIL]${RESET} $script not executable"
    errors=$((errors + 1))
  fi
done

# Check agents (root)
for agent_file in "$SCRIPT_DIR/agents/"*.md; do
  [ -f "$agent_file" ] || continue
  name=$(basename "$agent_file" .md)
  case "$name" in CONTRIBUTING|INTEGRATION_PLAN|LICENSE|README) continue ;; esac
  if [ -f "$AGENTS_DIR/$name.md" ]; then
    echo -e "${GREEN}[ok]${RESET} $name agent"
  else
    echo -e "${RED}[FAIL]${RESET} $name agent missing"
    errors=$((errors + 1))
  fi
done
# Check agents (categorized)
for agent_subdir in "$SCRIPT_DIR/agents/"*/; do
  [ -d "$agent_subdir" ] || continue
  subdir_name=$(basename "$agent_subdir")
  case "$subdir_name" in scripts) continue ;; esac
  for agent_file in "$agent_subdir"*.md; do
    [ -f "$agent_file" ] || continue
    name=$(basename "$agent_file" .md)
    if [ -f "$AGENTS_DIR/$subdir_name/$name.md" ]; then
      echo -e "${GREEN}[ok]${RESET} $subdir_name/$name agent"
    else
      echo -e "${RED}[FAIL]${RESET} $subdir_name/$name agent missing"
      errors=$((errors + 1))
    fi
  done
done

# Check hooks
for hook in block-git-hook-bypass block-dismissive-language; do
  if [ -x "$HOOKS_DIR/$hook.sh" ]; then
    echo -e "${GREEN}[ok]${RESET} $hook hook"
  else
    echo -e "${RED}[FAIL]${RESET} $hook hook missing or not executable"
    errors=$((errors + 1))
  fi
done

# Check templates
for tpl in settings.json CLAUDE.md gitignore-additions.txt; do
  if [ -f "$TEMPLATES_DIR/$tpl" ]; then
    echo -e "${GREEN}[ok]${RESET} $tpl template"
  else
    echo -e "${RED}[FAIL]${RESET} $tpl template missing"
    errors=$((errors + 1))
  fi
done

# Check knowledge base rules
if [ -f "$KB_RULES" ]; then
  echo -e "${GREEN}[ok]${RESET} knowledge-base-rules.md"
else
  echo -e "${RED}[FAIL]${RESET} knowledge-base-rules.md missing"
  errors=$((errors + 1))
fi

# Check general knowledge base
if [ -f "$KB_DIR/_index.md" ]; then
  echo -e "${GREEN}[ok]${RESET} general knowledge base"
else
  echo -e "${RED}[FAIL]${RESET} general knowledge base missing"
  errors=$((errors + 1))
fi
for kb_file in security/general.md architecture/general.md architecture/api-design.md architecture/code-analysis.md testing/principles.md style/general.md documentation/general.md code-review/general.md languages/rust.md languages/typescript.md languages/nextjs.md languages/scala.md; do
  if [ -f "$KB_DIR/$kb_file" ]; then
    echo -e "${GREEN}[ok]${RESET} knowledge-base/$kb_file"
  else
    echo -e "${RED}[FAIL]${RESET} knowledge-base/$kb_file missing"
    errors=$((errors + 1))
  fi
done

echo ""
if [ "$conflicts" -gt 0 ]; then
  echo -e "${BOLD}${YELLOW}=== $conflicts conflict(s) ===${RESET}"
  echo "Skipped files with local changes:"
  for f in "${conflict_files[@]}"; do
    echo -e "  ${YELLOW}-${RESET} $f"
  done
  echo ""
  echo -e "Re-run with ${BOLD}--force${RESET} to overwrite, or diff manually."
  echo ""
fi

if [ "$errors" -gt 0 ]; then
  echo -e "${RED}Setup failed with $errors error(s). Check the output above.${RESET}"
  exit 1
elif [ "$conflicts" -gt 0 ]; then
  echo -e "${YELLOW}Setup partial — $conflicts file(s) skipped due to conflicts.${RESET}"
else
  echo -e "${GREEN}Setup complete. All files installed.${RESET}"
fi

echo ""
echo -e "${BOLD}Next steps:${RESET}"
echo -e "  1. Open a target project in Claude Code"
echo -e "  2. Run ${CYAN}/bootstrap${RESET} to create the knowledge-base"
echo -e "  3. To activate hooks, copy the settings template to your project:"
echo -e "     ${DIM}cp ~/.claude/templates/settings.json <project>/.claude/settings.json${RESET}"
echo -e "  4. Follow the workflow: ${CYAN}/explore${RESET} -> ${CYAN}/propose${RESET} -> ${CYAN}/implement${RESET} -> ${CYAN}/validate${RESET} -> ${CYAN}/review-findings${RESET} -> ${CYAN}/ship${RESET}"
echo -e "  5. Use ${CYAN}/spec-status <feature>${RESET} anytime to see the dashboard"
echo -e "  6. Use ${CYAN}/continue-task <feature>${RESET} to resume interrupted work"
echo -e "  7. Use ${CYAN}/research${RESET} to enter anti-hallucination research mode"
echo ""
echo -e "${BOLD}For GitHub Copilot users:${RESET}"
echo -e "  Run ${DIM}./setup-copilot.sh <project-path>${RESET} to install Copilot prompts, agents, and instructions"
