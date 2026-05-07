#!/usr/bin/env bash
set -euo pipefail

# task-manager.sh — Validates and updates task files for the spec-driven workflow.
# Uses yq for YAML frontmatter parsing/updating.
# Usage: task-manager.sh <command> [args...]

# === CANONICAL STATE MACHINE ===
# Executable source of truth for task states and transitions.
# Human-readable docs: plan.md § "Task State Machine"
# If you change states/transitions here, update plan.md to match.
VALID_STATUSES=("blocked" "todo" "in-progress" "implemented" "review" "done")
REQUIRED_SCALAR_FIELDS=("id" "name" "status" "max_files")
REQUIRED_ARRAY_FIELDS=("ground_rules" "test_cases" "blocked_by" "estimated_files")

# Resolve general KB base path by detecting installation context
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$SCRIPT_DIR" == "$HOME/.claude/scripts" ]]; then
  GENERAL_KB_BASE="$HOME/.claude/knowledge-base"
else
  GENERAL_KB_BASE="knowledge-base/_general"
fi

# Source config-paths.sh if available (gives find_workflow_root, wf_resolve_root)
_WF_TM_PATHS_LOADED=0
if [[ -f "$SCRIPT_DIR/config-paths.sh" ]]; then
  # shellcheck source=scripts/config-paths.sh
  source "$SCRIPT_DIR/config-paths.sh"
  _WF_TM_PATHS_LOADED=1
fi

# Detect repo root for absolute path resolution when invoked from a subdir.
# Priority: WF_REPO_ROOT env → .workflow.yml walk-up → git root → CWD
_wf_tm_detect_repo_root() {
  [[ -n "${WF_REPO_ROOT:-}" ]] && { printf '%s' "$WF_REPO_ROOT"; return 0; }
  if [[ "$_WF_TM_PATHS_LOADED" == "1" ]]; then
    local root
    if root="$(wf_resolve_root "$PWD" 2>/dev/null)"; then printf '%s' "$root"; return 0; fi
  fi
  local git_root
  if git_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then printf '%s' "$git_root"; return 0; fi
  printf '%s' "$PWD"
}

# Lazy-evaluated — avoids source-time side effects (git rev-parse, dir walk)
: "${_WF_TM_REPO_ROOT:=$(_wf_tm_detect_repo_root)}"

# Source monitor.sh for event logging (guard: only if file exists)
MONITOR_AVAILABLE=false
if [[ -f "$SCRIPT_DIR/monitor.sh" ]]; then
  source "$SCRIPT_DIR/monitor.sh"
  MONITOR_AVAILABLE=true
fi

# Source submodules
# shellcheck source=scripts/task-status.sh
source "$SCRIPT_DIR/task-status.sh"
# shellcheck source=scripts/task-unblock.sh
source "$SCRIPT_DIR/task-unblock.sh"

# Emit a task_transition event if monitoring is active.
emit_transition_event() {
  local task_id="$1" from_status="$2" to_status="$3" task_file="$4"
  [[ "$MONITOR_AVAILABLE" = "true" ]] || return 0
  local ctx mon_feature
  if ctx="$(read_context 2>/dev/null)"; then
    mon_feature="$(echo "$ctx" | head -1)"
    [[ -n "$mon_feature" ]] || return 0
    local repo_field
    repo_field=$(read_frontmatter "$task_file" '.repo' 2>/dev/null || echo "null")
    [[ "$repo_field" == "null" ]] && repo_field=""
    local payload
    if [[ -n "$repo_field" ]]; then
      payload=$(printf '{"from_status":"%s","to_status":"%s","task_file":"%s","repo":"%s"}' \
        "$(escape_json_string "$from_status")" \
        "$(escape_json_string "$to_status")" \
        "$(escape_json_string "$task_file")" \
        "$(escape_json_string "$repo_field")")
    else
      payload=$(printf '{"from_status":"%s","to_status":"%s","task_file":"%s"}' \
        "$(escape_json_string "$from_status")" \
        "$(escape_json_string "$to_status")" \
        "$(escape_json_string "$task_file")")
    fi
    log_event "$mon_feature" "task_transition" "$task_id" "$payload" \
      || echo "WARN: monitor event emission failed" >&2
  fi
}

# Emit spec_last_task_done when the final task in a feature transitions to done.
# Idempotent: skips if a prior spec_audit_done or spec_last_task_done already exists
# on the feature's .monitor.jsonl.
maybe_emit_spec_last_task_done() {
  local task_file="$1" new_status="$2"
  [[ "$new_status" == "done" ]] || return 0
  [[ "$MONITOR_AVAILABLE" = "true" ]] || return 0

  local tasks_dir feature_dir feature monitor_file
  tasks_dir="$(dirname "$task_file")"
  feature_dir="$(dirname "$tasks_dir")"
  feature="$(basename "$feature_dir")"
  monitor_file="$feature_dir/.monitor.jsonl"

  local f task_status non_done=0
  for f in "$tasks_dir"/*.md; do
    [[ -f "$f" ]] || continue
    task_status=$(read_frontmatter "$f" ".status" 2>/dev/null) || continue
    [[ "$task_status" != "done" ]] && non_done=$((non_done + 1))
  done
  [[ "$non_done" -eq 0 ]] || return 0

  if [[ -f "$monitor_file" ]]; then
    # Guard semantics (T017 update): if newest of {spec_audit_done, spec_reaudit_requested}
    # is spec_audit_done, suppress emission. spec_reaudit_requested newer than any prior
    # spec_audit_done (or no spec_audit_done at all) → guard clear, allow emission.
    local newest
    newest=$(grep -oE '"category":"(spec_audit_done|spec_reaudit_requested)"' "$monitor_file" 2>/dev/null | tail -1 || true)
    [[ "$newest" == *spec_audit_done* ]] && return 0
    grep -q '"category":"spec_last_task_done"' "$monitor_file" 2>/dev/null && return 0
  fi

  log_event "$feature" "spec_last_task_done" "" \
    "$(printf '{"tasks_dir":"%s"}' "$(escape_json_string "$tasks_dir")")" \
    || echo "WARN: spec_last_task_done emission failed" >&2
}

# Valid transitions: from -> to
get_allowed_transitions() {
  case "$1" in
    blocked)     echo "todo" ;;
    todo)        echo "in-progress" ;;
    in-progress) echo "implemented" ;;
    implemented) echo "review done" ;;
    review)      echo "implemented done" ;;
    done)        echo "" ;;
    *)           echo "" ;;
  esac
}

usage() {
  cat <<'EOF'
Usage: task-manager.sh <command> [args...]

Commands:
  validate <task-file>           Validate task file structure and fields
  set-status <task-file> <status> Update task status (validates transition)
  unblock <tasks-directory>      Check blocked tasks, unblock if dependencies are done
  next <tasks-directory>         Get next eligible task (status: todo)
  create-followup <feature> <fr-id> <description>
                                  Auto-create a follow-up task from a spec-audit finding
  check-unvalidated <tasks-dir>  Check for tasks with status: implemented or review
  status <tasks-directory>       Show status dashboard with dependencies and health diagnostics
  init-fix <slug>                Scaffold specs/fixes/<slug>/fix.md from template (used by /fix)
  help                           Show this help message
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

check_yq() {
  command -v yq >/dev/null 2>&1 || die "yq is not installed. Run: brew install yq"
}

# Portable yq with 5-second timeout — delegates to canonical wf_with_timeout
# (config-paths.sh). Falls back to bare `yq` if config-paths.sh wasn't sourced
# (defensive — every caller already sources it via the bootstrap above).
_wf_yq() {
  if command -v wf_with_timeout >/dev/null 2>&1; then wf_with_timeout 5 yq "$@"
  else yq "$@"; fi
}

# Extract YAML frontmatter from a markdown file and pass it to yq.
# Uses `yq --front-matter=process` so a markdown HR (`---`) inside the task
# body never confuses frontmatter extraction (sed-between-`---` does).
read_frontmatter() {
  local file="$1"
  local expression="${2:-.}"
  _wf_yq --front-matter=extract eval "$expression" "$file"
}

# Resolve a prefixed ground_rules path to a real file path (absolute).
resolve_ground_rule_path() {
  local prefixed_path="$1"
  local project_kb="${_WF_TM_REPO_ROOT}/knowledge-base"
  case "$prefixed_path" in
    general:*) echo "$GENERAL_KB_BASE/${prefixed_path#general:}" ;;
    project:*) echo "$project_kb/${prefixed_path#project:}" ;;
    repo:*)
      # repo:<name>:<rel-path> — resolves under that bound repo's knowledge-base/
      local rest="${prefixed_path#repo:}" repo_name="${rest%%:*}" rel="${rest#*:}"
      local repo_root=""
      if command -v wf_repo_path >/dev/null 2>&1; then
        repo_root="$(wf_repo_path "$repo_name" 2>/dev/null || true)"
      fi
      if [[ -z "$repo_root" ]]; then
        # Best-effort: search WF_REPO_NAMES / WF_REPO_PATHS directly
        if [[ -n "${WF_REPO_NAMES:-}" && -n "${WF_REPO_PATHS:-}" ]]; then
          local _i=0 _n
          while IFS= read -r _n; do
            if [[ "$_n" == "$repo_name" ]]; then
              repo_root="$(printf '%s\n' "$WF_REPO_PATHS" | sed -n "$((_i+1))p")"
              break
            fi
            _i=$((_i + 1))
          done <<<"$WF_REPO_NAMES"
        fi
      fi
      [[ -n "$repo_root" ]] || { echo "/dev/null/unresolved-repo:$repo_name"; return 0; }
      echo "$repo_root/knowledge-base/$rel"
      ;;
    *)         echo "$project_kb/$prefixed_path" ;;
  esac
}

# Update a field in the YAML frontmatter of a markdown file.
update_frontmatter() {
  local file="$1"
  local expression="$2"
  local second_delim
  second_delim=$(grep -n '^---$' "$file" | sed -n '2p' | cut -d: -f1)
  [ -z "$second_delim" ] && die "Cannot find frontmatter end delimiter in $file"
  local frontmatter
  frontmatter=$(sed -n "2,$((second_delim - 1))p" "$file")
  local body
  body=$(tail -n +"$((second_delim + 1))" "$file")
  local updated_frontmatter
  updated_frontmatter=$(echo "$frontmatter" | _wf_yq eval "$expression" -)
  {
    echo "---"
    echo "$updated_frontmatter"
    echo "---"
    [ -n "$body" ] && printf '%s\n' "$body"
  } > "$file"
}

# Resolve the spec dir for a task file (parent of tasks/) and return its repo
# name allowlist (newline-sep). Empty stdout means spec declares no repos[].
_wf_tm_spec_repo_names() {
  local task_file="$1" spec_cfg
  spec_cfg="$(dirname "$(dirname "$task_file")")/config.yml"
  [[ -f "$spec_cfg" ]] || return 0
  _wf_yq e -r '(.repos // []) | .[].name' "$spec_cfg" 2>/dev/null || true
}

# If the task's spec declares repos[], require task.repo to be one of them.
validate_repo_field() {
  local file="$1" allowlist task_repo
  allowlist="$(_wf_tm_spec_repo_names "$file")"
  [[ -z "$allowlist" ]] && return 0
  task_repo=$(read_frontmatter "$file" '.repo')
  if [[ "$task_repo" == "null" || -z "$task_repo" ]]; then
    die "Spec declares repos[]; task missing required field 'repo' in $file"
  fi
  grep -Fxq -- "$task_repo" <<<"$allowlist" || \
    die "Task 'repo: $task_repo' not in spec repos[] allowlist [$(echo "$allowlist" | tr '\n' ' ')] in $file"
}

# Validate required scalar and array fields, status, and max_files.
validate_required_fields() {
  local file="$1"
  for field in "${REQUIRED_SCALAR_FIELDS[@]}"; do
    local value
    value=$(read_frontmatter "$file" ".$field")
    if [ "$value" = "null" ] || [ -z "$value" ]; then
      die "Missing required field '$field' in $file"
    fi
  done
  for field in "${REQUIRED_ARRAY_FIELDS[@]}"; do
    local value
    value=$(read_frontmatter "$file" ".$field | type")
    if [ "$value" != "!!seq" ]; then
      die "Missing or non-array field '$field' in $file (must be a YAML array)"
    fi
  done
  local status
  status=$(read_frontmatter "$file" ".status")
  local valid=false
  for s in "${VALID_STATUSES[@]}"; do [ "$status" = "$s" ] && valid=true; done
  [ "$valid" = "true" ] || die "Invalid status '$status' in $file. Valid: ${VALID_STATUSES[*]}"
  local max_files
  max_files=$(read_frontmatter "$file" '.max_files')
  [[ "$max_files" =~ ^[0-9]+$ ]] || die "max_files must be a number in $file"
  [ "$max_files" -le 20 ] || die "max_files exceeds 20 in $file"
}

# Warn if ground_rules paths don't resolve to real files.
validate_ground_rules() {
  local file="$1"
  local rules_count
  rules_count=$(read_frontmatter "$file" '.ground_rules | length')
  for ((i = 0; i < rules_count; i++)); do
    local rule_path resolved_path
    rule_path=$(read_frontmatter "$file" ".ground_rules[$i]")
    resolved_path=$(resolve_ground_rule_path "$rule_path")
    [ -f "$resolved_path" ] || echo "WARNING: ground_rules path not found: $rule_path -> $resolved_path (in $file)"
  done
}

# Validate a task file has correct structure
cmd_validate() {
  local file="${1:-}"
  [ -z "$file" ] && die "Usage: task-manager.sh validate <task-file>"
  if [ ! -f "$file" ] && [[ "$file" != /* ]]; then
    local abs_candidate="$_WF_TM_REPO_ROOT/$file"
    [ -f "$abs_candidate" ] && file="$abs_candidate"
  fi
  [ -f "$file" ] || die "Task file not found: $file"
  local delim_count
  delim_count=$(grep -c '^---$' "$file" || true)
  [ "$delim_count" -lt 2 ] && die "Task file missing YAML frontmatter delimiters: $file"
  validate_required_fields "$file"
  validate_ground_rules "$file"
  validate_repo_field "$file"
  local status
  status=$(read_frontmatter "$file" ".status")
  if [ "$status" = "blocked" ]; then
    local blocked_count
    blocked_count=$(read_frontmatter "$file" '.blocked_by | length')
    [ "$blocked_count" -gt 0 ] || die "Task has status 'blocked' but empty blocked_by: $file"
  fi
  echo "OK: $file"
}

# Update task status with transition validation
cmd_set_status() {
  local file="${1:-}"
  local new_status="${2:-}"
  [ -z "$file" ] || [ -z "$new_status" ] && die "Usage: task-manager.sh set-status <task-file> <new-status>"
  [ -f "$file" ] || die "Task file not found: $file"
  cmd_validate "$file" > /dev/null
  local valid=false
  for s in "${VALID_STATUSES[@]}"; do [ "$new_status" = "$s" ] && valid=true; done
  [ "$valid" = "true" ] || die "Invalid status '$new_status'. Valid: ${VALID_STATUSES[*]}"
  local current_status task_id
  current_status=$(read_frontmatter "$file" ".status")
  task_id=$(read_frontmatter "$file" ".id")
  local allowed
  allowed=$(get_allowed_transitions "$current_status")
  local transition_valid=false
  for target in $allowed; do [ "$target" = "$new_status" ] && transition_valid=true; done
  [ "$transition_valid" = "true" ] || die "Invalid transition: '$current_status' -> '$new_status' in $file. Allowed from '$current_status': $allowed"
  update_frontmatter "$file" ".status = \"$new_status\""
  echo "Status updated: $current_status -> $new_status ($file)"
  emit_transition_event "$task_id" "$current_status" "$new_status" "$file"
  maybe_emit_spec_last_task_done "$file" "$new_status"
}

# Create a follow-up task auto-generated from a spec-audit accepted finding (T017).
# Validates FR id against spec.md FR allowlist (security boundary — Odium may hallucinate).
# Inherits ground_rules from spec.md "## Applicable Ground Rules" section.
cmd_create_followup() {
  local feature="${1:-}" fr_id="${2:-}" description="${3:-}"
  [ -z "$feature" ] || [ -z "$fr_id" ] || [ -z "$description" ] && \
    die "Usage: task-manager.sh create-followup <feature> <fr-id> <description>"
  [[ "$fr_id" =~ ^FR-[0-9]+$ ]] || die "Invalid fr-id format: '$fr_id' (expected FR-N)"
  [[ "$feature" =~ ^[a-zA-Z0-9_-]+$ ]] || die "Invalid feature name: '$feature'"

  local storage spec_dir spec_md tasks_dir
  if command -v get_spec_storage >/dev/null 2>&1; then
    storage="$(get_spec_storage 2>/dev/null)" || storage="$_WF_TM_REPO_ROOT/specs"
  else
    storage="$_WF_TM_REPO_ROOT/specs"
  fi
  spec_dir="$storage/$feature"
  spec_md="$spec_dir/spec.md"
  tasks_dir="$spec_dir/tasks"
  [ -f "$spec_md" ] || die "spec.md not found: $spec_md"
  [ -d "$tasks_dir" ] || die "tasks dir not found: $tasks_dir"

  local allowlist
  allowlist=$(grep -oE '^### FR-[0-9]+:' "$spec_md" | sed 's/^### //;s/://' | sort -u)
  [ -n "$allowlist" ] || die "No FR-N headings found in $spec_md"
  if ! printf '%s\n' "$allowlist" | grep -qx "$fr_id"; then
    {
      echo "ERROR: Unknown FR id '$fr_id' for feature '$feature' (consulted $spec_md)"
      echo "Known FR ids:"
      printf '%s\n' "$allowlist"
    } >&2
    return 1
  fi

  local last_id next_id
  last_id=$(ls "$tasks_dir"/*.md 2>/dev/null | sed -n 's|.*/\([0-9]\{3\}\)-.*|\1|p' | sort -n | tail -1)
  if [ -z "$last_id" ]; then next_id="001"
  else next_id=$(printf "%03d" $((10#$last_id + 1))); fi

  local rules
  rules=$(awk '/^## Applicable Ground Rules/{flag=1; next} /^## /{flag=0} flag' "$spec_md" \
    | grep -oE '`(general|project):[^`]+`' \
    | tr -d '`' \
    | awk '!seen[$0]++')
  [ -n "$rules" ] || die "No ground_rules parsed from '## Applicable Ground Rules' in $spec_md"

  local slug task_name task_file
  slug=$(printf '%s' "$description" | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-50)
  [ -n "$slug" ] || slug="followup"
  local fr_id_lower
  fr_id_lower=$(printf '%s' "$fr_id" | tr '[:upper:]' '[:lower:]')
  task_name="${fr_id_lower}-${slug}"
  task_file="$tasks_dir/${next_id}-${task_name}.md"
  [ -e "$task_file" ] && die "Refusing to overwrite existing task file: $task_file"

  {
    echo "---"
    echo "id: \"$next_id\""
    printf 'name: "Follow-up for %s: %s"\n' "$fr_id" "${description//\"/\\\"}"
    echo "status: todo"
    echo "blocked_by: []"
    echo "max_files: 5"
    echo "estimated_files: []"
    echo "test_cases: []"
    echo "ground_rules:"
    while IFS= read -r r; do [ -n "$r" ] && echo "  - $r"; done <<< "$rules"
    echo "---"
    echo
    echo "## Description"
    echo
    echo "Auto-created follow-up for **$fr_id** from spec audit (verdict=reopen)."
    echo
    echo "Original FR finding: $description"
  } > "$task_file"

  cmd_validate "$task_file" >/dev/null || { rm -f "$task_file"; die "Generated follow-up task failed validation"; }
  echo "$task_file"
}

# Check for unvalidated work
cmd_check_unvalidated() {
  local dir="${1:-}"
  [ -z "$dir" ] && die "Usage: task-manager.sh check-unvalidated <tasks-directory>"
  [ -d "$dir" ] || die "Tasks directory not found: $dir"
  local found=false
  for task_file in "$dir"/*.md; do
    [ -f "$task_file" ] || continue
    local status id
    status=$(read_frontmatter "$task_file" ".status")
    id=$(read_frontmatter "$task_file" ".id")
    if [ "$status" = "implemented" ] || [ "$status" = "review" ]; then
      echo "Task $id ($task_file): status is '$status'"
      found=true
    fi
  done
  [ "$found" = "true" ] && return 1 || return 0
}

# Main dispatch (only when run directly, not when sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
check_yq

cmd_init_fix() {
  local slug="${1:?Usage: task-manager.sh init-fix <slug>}"
  [[ "$slug" =~ ^[a-z][a-z0-9-]{0,63}$ ]] || die "Invalid slug: $slug (expected ^[a-z][a-z0-9-]{0,63}$)"
  # Resolve fixes dir under spec_storage. Source loader best-effort.
  local storage="${WF_SPEC_STORAGE:-}"
  if [[ -z "$storage" ]] && [[ -f "$HOME/.claude/scripts/config-loader.sh" ]]; then
    # shellcheck source=/dev/null
    source "$HOME/.claude/scripts/config-loader.sh" 2>/dev/null
    wf_load_config 2>/dev/null && storage="$WF_SPEC_STORAGE"
  fi
  [[ -n "$storage" ]] || die "Cannot resolve spec_storage (run /bootstrap)"
  local dir="$storage/fixes/$slug"
  mkdir -p "$dir"
  local fix_file="$dir/fix.md"
  if [[ -f "$fix_file" ]]; then
    echo "EXISTS: $fix_file" >&2
    return 0
  fi
  local tmpl="$HOME/.claude/templates/fix.md.template"
  [[ -f "$tmpl" ]] || die "Template missing: $tmpl"
  local now; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  sed -e "s|<SLUG>|$slug|g" -e "s|<ISO-8601>|$now|g" -e "s|<TEST_NAME>|TBD|g" \
    "$tmpl" > "$fix_file"
  echo "$fix_file"
}

case "${1:-help}" in
  validate)         shift; cmd_validate "$@" ;;
  set-status)       shift; cmd_set_status "$@" ;;
  unblock)          shift; cmd_unblock "$@" ;;
  next)             shift; cmd_next "$@" ;;
  create-followup)  shift; cmd_create_followup "$@" ;;
  check-unvalidated) shift; cmd_check_unvalidated "$@" ;;
  status)           shift; cmd_status "$@" ;;
  init-fix)         shift; cmd_init_fix "$@" ;;
  help|--help|-h)   usage ;;
  *)                die "Unknown command: $1. Run 'task-manager.sh help' for usage." ;;
esac
fi
