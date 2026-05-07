#!/usr/bin/env bash
# config-paths.sh — leaf helpers for workflow path/ID primitives.
# No sourcing of any workflow script. Pure functions; safe to source repeatedly.
# Canonical home of validate_id regex (see ADR-002, T001).

set -euo pipefail

# find_workflow_root
#   Walk up from realpath($PWD) looking for a `.workflow.yml` marker.
#   Prints absolute path to the directory containing the marker on stdout.
#   Returns 0 on success, 1 if no marker found in any ancestor.
find_workflow_root() {
  local start dir
  start="$(realpath -- "${1:-$PWD}" 2>/dev/null)" || return 1
  dir="$start"
  while [[ -n "$dir" && "$dir" != "/" ]]; do
    if [[ -f "$dir/.workflow.yml" ]]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir="$(dirname -- "$dir")"
  done
  if [[ -f "/.workflow.yml" ]]; then
    printf '%s\n' "/"
    return 0
  fi
  return 1
}

# find_vault_spec_config <feature> [start_dir]
#   Probe for vault-hosted per-spec config at `<start>/specs/<feature>/config.yml`.
#   Used by config-loader.sh when no `.workflow.yml` is found via walk-up — i.e.
#   when commands run from a master-brain vault dir that itself carries no
#   `.workflow.yml` but holds spec definitions that bind external code repos.
#   Prints absolute path on stdout. Returns 0 on success, 1 otherwise.
find_vault_spec_config() {
  local feature="${1:-}" start="${2:-$PWD}"
  validate_id "$feature" feature 2>/dev/null || return 1
  local root cfg
  root="$(realpath -- "$start" 2>/dev/null)" || return 1
  cfg="$root/specs/$feature/config.yml"
  [[ -f "$cfg" ]] || return 1
  printf '%s\n' "$cfg"
}

# realpath_safe <path>
#   Normalize via realpath. Reject:
#     - missing path
#     - `..` segments in the input literal (pre-normalize guard)
#     - any ancestor directory that is a symlink resolving outside $HOME
#       and outside the current workflow root (if discoverable)
#   Prints the normalized absolute path on stdout. Returns non-zero on reject.
realpath_safe() {
  local input="${1:-}"
  if [[ -z "$input" ]]; then
    echo "ERROR: realpath_safe: empty path" >&2
    return 1
  fi

  # Literal `..` segment rejection — catches `../../etc` even if the final
  # realpath happens to land inside an allowed root.
  if [[ "$input" == *".."* ]]; then
    local seg
    local IFS='/'
    for seg in $input; do
      if [[ "$seg" == ".." ]]; then
        echo "ERROR: realpath_safe: '..' segment not allowed: $input" >&2
        return 1
      fi
    done
  fi

  local resolved
  resolved="$(realpath -- "$input" 2>/dev/null)" || {
    echo "ERROR: realpath_safe: cannot resolve: $input" >&2
    return 1
  }

  local home_real repo_real=""
  home_real="$(realpath -- "$HOME" 2>/dev/null)" || home_real="$HOME"
  repo_real="$(find_workflow_root "$PWD" 2>/dev/null || true)"
  # Fallback: under vault-CWD invocation the loader sets WF_REPO_ROOT to the
  # chosen bound repo even though PWD itself has no `.workflow.yml`. Honor it
  # so symlink-escape checks treat paths inside that repo as in-bounds.
  [[ -z "$repo_real" && -n "${WF_REPO_ROOT:-}" ]] && repo_real="$WF_REPO_ROOT"

  # Walk each ancestor of the *input* path and reject if any ancestor is a
  # symlink pointing outside $HOME AND outside the workflow root.
  local probe="$input" parent
  while [[ -n "$probe" && "$probe" != "/" && "$probe" != "." ]]; do
    if [[ -L "$probe" ]]; then
      local link_target
      link_target="$(realpath -- "$probe" 2>/dev/null)" || {
        echo "ERROR: realpath_safe: unresolvable symlink: $probe" >&2
        return 1
      }
      if [[ "$link_target" != "$home_real"/* && "$link_target" != "$home_real" ]] \
         && { [[ -z "$repo_real" ]] || [[ "$link_target" != "$repo_real"/* && "$link_target" != "$repo_real" ]]; }; then
        echo "ERROR: realpath_safe: symlink ancestor escapes allowed roots: $probe -> $link_target" >&2
        return 1
      fi
    fi
    parent="$(dirname -- "$probe")"
    [[ "$parent" == "$probe" ]] && break
    probe="$parent"
  done

  printf '%s\n' "$resolved"
}

# wf_resolve_root [start_dir]
#   Canonical root resolution: WF_REPO_ROOT env → .workflow.yml walk-up → specs/ walk-up.
#   Single source of truth; replaces private copies in monitor.sh and task-manager.sh.
wf_resolve_root() {
  if [[ -n "${WF_REPO_ROOT:-}" ]]; then printf '%s' "$WF_REPO_ROOT"; return 0; fi
  local root
  if root="$(find_workflow_root "${1:-$PWD}" 2>/dev/null)"; then printf '%s' "$root"; return 0; fi
  local dir="${1:-$PWD}"
  while [[ "$dir" != "/" ]]; do
    [[ -d "$dir/specs" ]] && { printf '%s' "$dir"; return 0; }
    dir="$(dirname "$dir")"
  done
  return 1
}

# wf_with_timeout SECS CMD...
#   Canonical timeout helper. Prefers `timeout`, then `gtimeout`, then a
#   perl-based fallback. Returns 124 on timeout (matching coreutils contract).
#   Exposed so config-loader.sh, task-manager.sh, and monitor.sh can share one impl.
wf_with_timeout() {
  if command -v timeout >/dev/null 2>&1; then command timeout "$@"; return $?; fi
  if command -v gtimeout >/dev/null 2>&1; then command gtimeout "$@"; return $?; fi
  perl -e '
    my $t = shift @ARGV;
    my $pid = fork();
    if (!$pid) { exec(@ARGV) or exit 127 }
    local $SIG{ALRM} = sub { kill 9, $pid; waitpid $pid, 0; exit 124 };
    alarm $t; waitpid $pid, 0; exit ($? >> 8);
  ' -- "$@"
}

# validate_id <value> [label]
#   Canonical gate/agent/feature id regex: ^[a-zA-Z0-9_-]{1,64}$
#   Returns 0 on match, 1 otherwise. Silent on success; stderr message on reject.
#   When [label] is provided, the stderr message reads `invalid <label> id '<value>'`
#   for human-readable validator failures (used by monitor.sh, monitor-validators.sh).
validate_id() {
  local value="${1:-}"
  local label="${2:-}"
  if [[ "$value" =~ ^[a-zA-Z0-9_-]{1,64}$ ]]; then
    return 0
  fi
  if [[ -n "$label" ]]; then
    echo "ERROR: invalid $label id '${value:-<empty>}'" >&2
  else
    echo "ERROR: validate_id: rejected id: ${value:-<empty>}" >&2
  fi
  return 1
}

# validate_scope_enum_check <value>
#   Validates value against the validate_scope enum: {per-task, per-spec, both}.
#   Returns 0 on match, 2 otherwise. Silent on success; stderr names the enum on reject.
validate_scope_enum_check() {
  local value="${1:-}"
  case "$value" in
    per-task|per-spec|both) return 0 ;;
    *) echo "ERROR: validate_scope_enum_check: invalid value '${value}'; expected one of: per-task, per-spec, both" >&2
       return 2 ;;
  esac
}
