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

# validate_id <string>
#   Canonical gate/agent/feature id regex: ^[a-zA-Z0-9_-]{1,64}$
#   Returns 0 on match, 1 otherwise. Silent on success; stderr message on reject.
validate_id() {
  local value="${1:-}"
  if [[ "$value" =~ ^[a-zA-Z0-9_-]{1,64}$ ]]; then
    return 0
  fi
  echo "ERROR: validate_id: rejected id: ${value:-<empty>}" >&2
  return 1
}
