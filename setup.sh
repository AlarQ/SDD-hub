#!/usr/bin/env bash
set -euo pipefail

# setup.sh — Install the spec-driven dev workflow into ~/.claude/
# Run from the dev-workflow repository root.

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

# 6. Copy hooks
echo ""
echo "Installing hooks to $HOOKS_DIR/"
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
echo "Installing templates to $TEMPLATES_DIR/"
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
echo "Installing general knowledge base to $KB_DIR/"
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
echo "Installing knowledge base rules to $KB_RULES"
if ! safe_copy "$SCRIPT_DIR/knowledge-base-rules.md" "$KB_RULES"; then
  conflicts=$((conflicts + 1))
  conflict_files+=("knowledge-base-rules.md")
fi

# 10. Verify
echo ""
echo "=== Verification ==="

errors=0

# Check commands
for cmd in bootstrap explore propose implement validate review-findings ship quick-ship pr-review spec-status workflow-summary continue-task research; do
  if [ -f "$COMMANDS_DIR/$cmd.md" ]; then
    echo "[ok] /$cmd command"
  else
    echo "[FAIL] /$cmd command missing"
    errors=$((errors + 1))
  fi
done

# Check scripts
for script in task-manager.sh pre-commit-hook.sh; do
  if [ -x "$SCRIPTS_DIR/$script" ]; then
    echo "[ok] $script"
  else
    echo "[FAIL] $script not executable"
    errors=$((errors + 1))
  fi
done

# Check root agents
for agent in code-quality-pragmatist claude-md-compliance-checker karen ui-ux-reviewer ultrathink-debugger; do
  if [ -f "$AGENTS_DIR/$agent.md" ]; then
    echo "[ok] $agent agent"
  else
    echo "[FAIL] $agent agent missing"
    errors=$((errors + 1))
  fi
done
# Check categorized agents
for agent in \
  engineering/engineering-security-engineer engineering/engineering-software-architect engineering/engineering-code-reviewer \
  engineering/engineering-ai-engineer engineering/engineering-backend-architect engineering/engineering-devops-automator \
  engineering/engineering-frontend-developer engineering/engineering-mobile-app-builder engineering/engineering-sre \
  engineering/engineering-technical-writer \
  design/design-ui-designer design/design-ux-architect design/design-ux-researcher \
  product/product-behavioral-nudge-engine product/product-feedback-synthesizer product/product-sprint-prioritizer \
  product/product-trend-researcher \
  project-management/project-management-project-shepherd project-management/project-manager-senior \
  testing/testing-accessibility-auditor testing/testing-api-tester testing/testing-evidence-collector \
  testing/testing-performance-benchmarker testing/testing-reality-checker testing/testing-test-results-analyzer \
  testing/testing-tool-evaluator testing/testing-workflow-optimizer; do
  if [ -f "$AGENTS_DIR/$agent.md" ]; then
    echo "[ok] $agent agent"
  else
    echo "[FAIL] $agent agent missing"
    errors=$((errors + 1))
  fi
done

# Check hooks
for hook in block-git-hook-bypass block-dismissive-language; do
  if [ -x "$HOOKS_DIR/$hook.sh" ]; then
    echo "[ok] $hook hook"
  else
    echo "[FAIL] $hook hook missing or not executable"
    errors=$((errors + 1))
  fi
done

# Check templates
for tpl in settings.json CLAUDE.md gitignore-additions.txt; do
  if [ -f "$TEMPLATES_DIR/$tpl" ]; then
    echo "[ok] $tpl template"
  else
    echo "[FAIL] $tpl template missing"
    errors=$((errors + 1))
  fi
done

# Check knowledge base rules
if [ -f "$KB_RULES" ]; then
  echo "[ok] knowledge-base-rules.md"
else
  echo "[FAIL] knowledge-base-rules.md missing"
  errors=$((errors + 1))
fi

# Check general knowledge base
if [ -f "$KB_DIR/_index.md" ]; then
  echo "[ok] general knowledge base"
else
  echo "[FAIL] general knowledge base missing"
  errors=$((errors + 1))
fi
for kb_file in security/general.md architecture/general.md architecture/api-design.md architecture/code-analysis.md testing/principles.md style/general.md documentation/general.md code-review/general.md languages/rust.md languages/typescript.md languages/nextjs.md languages/scala.md; do
  if [ -f "$KB_DIR/$kb_file" ]; then
    echo "[ok] knowledge-base/$kb_file"
  else
    echo "[FAIL] knowledge-base/$kb_file missing"
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
echo "  3. To activate hooks, copy the settings template to your project:"
echo "     cp ~/.claude/templates/settings.json <project>/.claude/settings.json"
echo "  4. Follow the workflow: /explore -> /propose -> /implement -> /validate -> /review-findings -> /ship"
echo "  5. Use /spec-status <feature> anytime to see the dashboard"
echo "  6. Use /continue-task <feature> to resume interrupted work"
echo "  7. Use /research to enter anti-hallucination research mode"
echo ""
echo "For GitHub Copilot users:"
echo "  Run ./setup-copilot.sh <project-path> to install Copilot prompts, agents, and instructions"
