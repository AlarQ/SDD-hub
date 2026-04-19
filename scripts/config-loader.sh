#!/usr/bin/env bash
# config-loader.sh — sourced loader for .workflow.yml, gates.yml, per-spec config.yml.
# ADR-006: sourced; ADR-005: walk-up .workflow.yml; fail closed on every error path.
# Depends only on config-paths.sh (leaf). Sources no other workflow script.
# shellcheck disable=SC1090,SC1091,SC2088,SC2317,SC2034

if [[ "${WF_CONFIG_LOADED:-0}" == "1" && -z "${WF_RELOAD:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi

_wf_loader_dir() { cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd; }
source "$(_wf_loader_dir)/config-paths.sh"

wf__timeout() {
  # wf__timeout SECS CMD... -> stdout of CMD; rc 124 on timeout.
  if command -v timeout >/dev/null 2>&1;  then command timeout "$@"; return $?; fi
  if command -v gtimeout >/dev/null 2>&1; then command gtimeout "$@"; return $?; fi
  perl -e '
    my $t = shift @ARGV;
    my $pid = fork();
    if (!$pid) { exec(@ARGV) or exit 127 }
    local $SIG{ALRM} = sub { kill 9, $pid; waitpid $pid, 0; exit 124 };
    alarm $t; waitpid $pid, 0; exit ($? >> 8);
  ' -- "$@"
}

wf__err()  { echo "ERROR: $*" >&2; }
wf__warn() { echo "WARN: $*"  >&2; }

wf__unset_partials() {
  unset WF_CONFIG_LOADED WF_REPO_ROOT WF_SPEC_STORAGE WF_GATE_POOL WF_AGENT_POOL \
        WF_CONFIG_FILE WF_SPEC_CONFIG_FILE WF_VALIDATE_SCOPE \
        WF_SPEC_GATES WF_SPEC_HAS_CONFIG
  local v
  while IFS= read -r v; do [[ -n "$v" ]] && unset "$v"; done \
    < <(compgen -v | grep '^WF_SPEC_AGENTS_' || true)
}

# wf__yq_json <file> -> stdout JSON; rc: 0 ok, 124 timeout, 90 yq missing, other parse error
wf__yq_json() {
  command -v yq >/dev/null 2>&1 || return 90
  wf__timeout 5 yq e -o=json '.' "$1" 2>/dev/null
}

wf__resolve_path() {
  local raw="$1" root="$2"
  case "$raw" in
    "~"|"~/"*) printf '%s' "${HOME}${raw:1}" ;;
    /*)        printf '%s' "$raw" ;;
    *)         printf '%s' "$root/$raw" ;;
  esac
}

wf__json_get() {
  # wf__json_get <json> <yq-path> [default]
  local json="$1" path="$2" def="${3:-}"
  local out
  out="$(printf '%s' "$json" | wf__timeout 5 yq e -r "$path // \"__WF_NULL__\"" - 2>/dev/null)" || return 5
  [[ "$out" == "__WF_NULL__" ]] && out="$def"
  printf '%s' "$out"
}

wf_load_config() {
  local spec=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --spec)        spec="${2:-}"; shift 2 ;;
      --no-defaults) shift ;;  # reserved; .workflow.yml is already required
      *) wf__err "wf_load_config: unknown arg: $1"; return 6 ;;
    esac
  done

  wf__inside_allowed_root() {
    # <abs_path> <repo_root> — true if path is within repo_root or $HOME/.claude/
    local p="$1" root="$2"
    [[ "$p" == "$root" || "$p" == "$root"/* \
       || "$p" == "$HOME/.claude" || "$p" == "$HOME/.claude"/* ]]
  }

  wf__resolve_pool_path() {
    # <raw> <repo_root> <field> — prints abs path on stdout; returns non-zero on reject
    local rr="$1" rt="$2" fn="$3" abs
    if [[ "$rr" == *".."* ]]; then
      wf__err "$WF_CONFIG_FILE: $fn has '..' segment: $rr"; return 1
    fi
    abs="$(wf__resolve_path "$rr" "$rt")"
    abs="$(realpath_safe "$abs" 2>/dev/null)" || {
      wf__err "$WF_CONFIG_FILE: $fn unresolvable: $rr"; return 1
    }
    wf__inside_allowed_root "$abs" "$rt" || {
      wf__err "$WF_CONFIG_FILE: $fn escapes allowed roots: $abs"; return 1
    }
    printf '%s' "$abs"
  }

  wf__resolve_agent_id() {
    # <agent_id> <agent_pool_abs> — prints resolved file path; non-zero on reject
    local id="$1" pool="$2"
    [[ "$id" == *..* ]] && { wf__err "agent id has '..': $id"; return 1; }
    [[ "$id" =~ ^[a-z0-9_-]+(/[a-z0-9_-]+)?$ ]] || {
      wf__err "agent id invalid: $id"; return 1
    }
    local path
    if [[ "$id" == */* ]]; then
      local cat="${id%%/*}" name="${id#*/}"
      path="$pool/$cat/$cat-$name.md"
    else
      path="$pool/$id.md"
    fi
    [[ -f "$path" ]] || { wf__err "agent not found: $id -> $path"; return 1; }
    printf '%s' "$path"
  }

  local root
  if ! root="$(find_workflow_root "$PWD" 2>/dev/null)"; then
    wf__err ".workflow.yml not found walking up from $PWD. Run /bootstrap to create it."
    wf__unset_partials
    return 2
  fi
  WF_REPO_ROOT="$root"
  WF_CONFIG_FILE="$root/.workflow.yml"
  if [[ ! -f "$WF_CONFIG_FILE" ]]; then
    wf__err ".workflow.yml missing at $root. Run /bootstrap to create it."
    wf__unset_partials
    return 2
  fi

  local cfg_json rc
  cfg_json="$(wf__yq_json "$WF_CONFIG_FILE")"; rc=$?
  case "$rc" in
    0) ;;
    124) wf__err "$WF_CONFIG_FILE: yq timeout"; wf__unset_partials; return 5 ;;
    90)  wf__err "yq not installed"; wf__unset_partials; return 6 ;;
    *)   wf__err "$WF_CONFIG_FILE: malformed YAML"; wf__unset_partials; return 2 ;;
  esac

  local raw storage_abs gate_pool_abs agent_pool_abs scope
  raw="$(wf__json_get "$cfg_json" '.spec_storage' 'specs/')" || {
    wf__err "$WF_CONFIG_FILE: spec_storage extraction failed"; wf__unset_partials; return 5
  }
  if [[ "$raw" == *".."* ]]; then
    wf__err "$WF_CONFIG_FILE: spec_storage has '..' segment: $raw"
    wf__unset_partials; return 2
  fi
  storage_abs="$(wf__resolve_path "$raw" "$root")"
  storage_abs="$(realpath_safe "$storage_abs" 2>/dev/null)" || {
    wf__err "$WF_CONFIG_FILE: spec_storage unresolvable: $raw"
    wf__unset_partials; return 2
  }
  [[ -d "$storage_abs" ]] || {
    wf__err "$WF_CONFIG_FILE: spec_storage not a directory: $storage_abs"
    wf__unset_partials; return 2
  }
  WF_SPEC_STORAGE="$storage_abs"

  raw="$(wf__json_get "$cfg_json" '.gate_pool' 'knowledge-base/gates.yml')" || {
    wf__err "$WF_CONFIG_FILE: gate_pool extraction failed"; wf__unset_partials; return 5
  }
  gate_pool_abs="$(wf__resolve_pool_path "$raw" "$root" gate_pool)" || { wf__unset_partials; return 2; }
  [[ -f "$gate_pool_abs" ]] || {
    wf__err "$WF_CONFIG_FILE: gate_pool not a file: $gate_pool_abs"
    wf__unset_partials; return 2
  }
  WF_GATE_POOL="$gate_pool_abs"

  raw="$(wf__json_get "$cfg_json" '.agent_pool' "$HOME/.claude/agents")" || {
    wf__err "$WF_CONFIG_FILE: agent_pool extraction failed"; wf__unset_partials; return 5
  }
  agent_pool_abs="$(wf__resolve_pool_path "$raw" "$root" agent_pool)" || { wf__unset_partials; return 2; }
  [[ -d "$agent_pool_abs" ]] || {
    wf__err "$WF_CONFIG_FILE: agent_pool not a directory: $agent_pool_abs"
    wf__unset_partials; return 2
  }
  WF_AGENT_POOL="$agent_pool_abs"

  scope="$(wf__json_get "$cfg_json" '.validate_scope' 'per-task')" || {
    wf__err "$WF_CONFIG_FILE: validate_scope extraction failed"; wf__unset_partials; return 5
  }
  case "$scope" in
    per-task|per-spec|both) WF_VALIDATE_SCOPE="$scope" ;;
    *) wf__err "$WF_CONFIG_FILE: validate_scope invalid: $scope"; wf__unset_partials; return 2 ;;
  esac

  # gates.yml parse
  local gates_json
  gates_json="$(wf__yq_json "$WF_GATE_POOL")"; rc=$?
  case "$rc" in
    0) ;;
    124) wf__err "$WF_GATE_POOL: yq timeout"; wf__unset_partials; return 5 ;;
    *)   wf__err "$WF_GATE_POOL: malformed"; wf__unset_partials; return 3 ;;
  esac

  local dup_ids
  dup_ids="$(printf '%s' "$gates_json" | wf__timeout 5 yq e -r '.gates[].id' - 2>/dev/null | sort | uniq -d)"
  if [[ -n "$dup_ids" ]]; then
    wf__err "$WF_GATE_POOL: duplicate gate ids: $(echo "$dup_ids" | tr '\n' ' ')"
    wf__unset_partials; return 3
  fi

  if command -v git >/dev/null 2>&1 && git -C "$root" rev-parse >/dev/null 2>&1; then
    if ! git -C "$root" diff --quiet -- "$WF_GATE_POOL" 2>/dev/null; then
      wf__warn "$WF_GATE_POOL has uncommitted modifications"
    fi
  fi

  WF_SPEC_CONFIG_FILE=""
  WF_SPEC_GATES=""
  if [[ -n "$spec" ]]; then
    validate_id "$spec" || { wf__err "invalid feature id: $spec"; wf__unset_partials; return 4; }
    local spec_cfg="$WF_SPEC_STORAGE/$spec/config.yml"
    [[ -f "$spec_cfg" ]] || {
      wf__err "per-spec config missing: $spec_cfg"
      wf__unset_partials; return 4
    }
    local spec_json
    spec_json="$(wf__yq_json "$spec_cfg")"; rc=$?
    case "$rc" in
      0) ;;
      124) wf__err "$spec_cfg: yq timeout"; wf__unset_partials; return 5 ;;
      *)   wf__err "$spec_cfg: malformed"; wf__unset_partials; return 4 ;;
    esac
    WF_SPEC_CONFIG_FILE="$spec_cfg"

    local known_ids gate_ids id bad=""
    known_ids="$(printf '%s' "$gates_json" | wf__timeout 5 yq e -r '.gates[].id' - 2>/dev/null || true)"
    gate_ids="$(printf '%s'  "$spec_json"  | wf__timeout 5 yq e -r '.gates[]?' - 2>/dev/null || true)"
    while IFS= read -r id; do
      [[ -z "$id" ]] && continue
      validate_id "$id" || { wf__err "$spec_cfg: invalid gate id: $id"; wf__unset_partials; return 4; }
      grep -Fxq -- "$id" <<<"$known_ids" || bad="$bad $id"
    done <<<"$gate_ids"
    if [[ -n "$bad" ]]; then
      wf__err "$spec_cfg: unknown gate ids:$bad"
      wf__unset_partials; return 4
    fi
    WF_SPEC_GATES="$gate_ids"

    local phases phase upper
    phases="$(printf '%s' "$spec_json" | wf__timeout 5 yq e -r '(.agents // {}) | keys | .[]' - 2>/dev/null || true)"
    while IFS= read -r phase; do
      [[ -z "$phase" ]] && continue
      case "$phase" in
        explore|propose|implement|validate|pr-review) ;;
        *) wf__err "$spec_cfg: unknown phase: $phase"; wf__unset_partials; return 4 ;;
      esac
      local aid resolved_agents=""
      while IFS= read -r aid; do
        [[ -z "$aid" ]] && continue
        wf__resolve_agent_id "$aid" "$WF_AGENT_POOL" >/dev/null || {
          wf__err "$spec_cfg: $phase: unresolved agent id: $aid"
          wf__unset_partials; return 4
        }
        resolved_agents+="${resolved_agents:+ }$aid"
      done < <(printf '%s' "$spec_json" | wf__timeout 5 yq e -r ".agents.\"$phase\"[]?" - 2>/dev/null)
      upper="$(echo "$phase" | tr '[:lower:]-' '[:upper:]_')"
      printf -v "WF_SPEC_AGENTS_${upper}" '%s' "$resolved_agents"
      export "WF_SPEC_AGENTS_${upper?}"
    done <<<"$phases"

    local spec_scope
    spec_scope="$(wf__json_get "$spec_json" '.validate_scope' '')" || {
      wf__err "$spec_cfg: validate_scope extraction failed"; wf__unset_partials; return 5
    }
    if [[ -n "$spec_scope" ]]; then
      case "$spec_scope" in
        per-task|per-spec|both) WF_VALIDATE_SCOPE="$spec_scope" ;;
        *) wf__err "$spec_cfg: validate_scope invalid: $spec_scope"; wf__unset_partials; return 4 ;;
      esac
    fi

    WF_SPEC_HAS_CONFIG=1
    export WF_SPEC_CONFIG_FILE WF_SPEC_GATES WF_SPEC_HAS_CONFIG
  fi

  WF_CONFIG_LOADED=1
  export WF_CONFIG_LOADED WF_REPO_ROOT WF_SPEC_STORAGE WF_GATE_POOL \
         WF_AGENT_POOL WF_CONFIG_FILE WF_VALIDATE_SCOPE
  return 0
}

# CLI mode — evaluable KEY=VAL lines for hooks that cannot source.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  case "${1:-}" in
    export)
      shift
      wf_load_config "$@" || exit $?
      while IFS= read -r var; do
        [[ -z "$var" ]] && continue
        val="${!var-}"
        esc="${val//\'/\'\\\'\'}"
        printf "%s='%s'\n" "$var" "$esc"
      done < <(compgen -v | grep '^WF_' | sort)
      ;;
    *)
      echo "Usage: $(basename "$0") export [--spec <feature>]" >&2
      exit 2
      ;;
  esac
fi
