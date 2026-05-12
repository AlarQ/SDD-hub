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

# Back-compat shim — canonical impl lives in config-paths.sh as wf_with_timeout.
wf__timeout() { wf_with_timeout "$@"; }

wf__err()  { echo "ERROR: $*" >&2; }
wf__warn() { echo "WARN: $*"  >&2; }

wf__unset_partials() {
  unset WF_CONFIG_LOADED WF_REPO_ROOT WF_SPEC_STORAGE WF_GATE_POOL WF_AGENT_POOL \
        WF_GENERAL_KB \
        WF_CONFIG_FILE WF_SPEC_CONFIG_FILE WF_VALIDATE_SCOPE \
        WF_SPEC_GATES WF_SPEC_HAS_CONFIG \
        WF_SPEC_TIER WF_TIER_TASK_CEILING WF_TIER_FILE_CEILING WF_TIER_AGENT_SKIP \
        WF_SPEC_STORAGE_MODE WF_REPO_NAMES WF_REPO_PATHS WF_VAULT_ROOT
  local v
  while IFS= read -r v; do [[ -n "$v" ]] && unset "$v"; done \
    < <(compgen -v | grep '^WF_SPEC_AGENTS_' || true)
}

# wf__yq_json <file> -> stdout JSON; rc: 0 ok, 124 timeout, 90 yq missing, other parse error
# Emits a loud stderr line on missing yq so sourced callers that bypass
# wf_load_config (or silence its stderr) still surface the problem.
wf__yq_json() {
  if ! command -v yq >/dev/null 2>&1; then
    wf__err "yq not installed (required by config-loader.sh; brew install yq)"
    return 90
  fi
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
  if ! command -v yq >/dev/null 2>&1; then
    wf__err "yq not installed (required by config-loader.sh; brew install yq)"
    return 5
  fi
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

  local root vault_cfg=""
  if ! root="$(find_workflow_root "$PWD" 2>/dev/null)"; then
    # Vault-CWD fallback: when CWD has no `.workflow.yml` but holds
    # `specs/<feature>/config.yml` (master-brain vault layout), derive
    # WF_REPO_ROOT from one of the spec's `repos[]` entries.
    if [[ -z "$spec" ]]; then
      wf__err ".workflow.yml not found walking up from $PWD. Run /bootstrap to create it."
      wf__unset_partials
      return 2
    fi
    if ! vault_cfg="$(find_vault_spec_config "$spec" "$PWD" 2>/dev/null)"; then
      wf__err ".workflow.yml not found walking up from $PWD, and no vault spec config at $PWD/specs/$spec/config.yml. Run /bootstrap or /explore $spec."
      wf__unset_partials
      return 2
    fi
    local vault_root vault_json vault_repos_count chosen_idx="" chosen_path="" chosen_role="" i_role i_path rc=0
    vault_root="$(realpath -- "$PWD" 2>/dev/null)" || {
      wf__err "vault root unresolvable: $PWD"; wf__unset_partials; return 2
    }
    vault_json="$(wf__yq_json "$vault_cfg")"; rc=$?
    case "$rc" in
      0) ;;
      124) wf__err "$vault_cfg: yq timeout"; wf__unset_partials; return 5 ;;
      90)  wf__unset_partials; return 6 ;;
      *)   wf__err "$vault_cfg: malformed"; wf__unset_partials; return 4 ;;
    esac
    vault_repos_count="$(printf '%s' "$vault_json" | wf__timeout 5 yq e -r '(.repos // []) | length' - 2>/dev/null || echo 0)"
    [[ "$vault_repos_count" =~ ^[0-9]+$ ]] || vault_repos_count=0
    if [[ "$vault_repos_count" -eq 0 ]]; then
      wf__err "$vault_cfg: repos[] required for vault-CWD invocation"
      wf__unset_partials; return 4
    fi
    local vi
    for ((vi = 0; vi < vault_repos_count; vi++)); do
      i_role="$(printf '%s' "$vault_json" | wf__timeout 5 yq e -r ".repos[$vi].role // \"\"" - 2>/dev/null)"
      if [[ "$i_role" == "primary" ]]; then chosen_idx="$vi"; chosen_role="primary"; break; fi
    done
    [[ -z "$chosen_idx" ]] && chosen_idx=0
    i_path="$(printf '%s' "$vault_json" | wf__timeout 5 yq e -r ".repos[$chosen_idx].path // \"\"" - 2>/dev/null)"
    [[ -n "$i_path" ]] || { wf__err "$vault_cfg: repos[$chosen_idx].path missing"; wf__unset_partials; return 7; }
    [[ "$i_path" == *".."* ]] && { wf__err "$vault_cfg: repos[$chosen_idx].path has '..': $i_path"; wf__unset_partials; return 7; }
    case "$i_path" in
      "~"|"~/"*) chosen_path="${HOME}${i_path:1}" ;;
      /*)        chosen_path="$i_path" ;;
      *)         chosen_path="$vault_root/$i_path" ;;
    esac
    chosen_path="$(realpath -- "$chosen_path" 2>/dev/null)" || {
      wf__err "$vault_cfg: repos[$chosen_idx] path unresolvable: $i_path"
      wf__unset_partials; return 7
    }
    [[ -d "$chosen_path" && -f "$chosen_path/.workflow.yml" ]] || {
      wf__err "$vault_cfg: repos[$chosen_idx] missing .workflow.yml: $chosen_path"
      wf__unset_partials; return 7
    }
    WF_VAULT_ROOT="$vault_root"
    root="$chosen_path"
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

  if [[ -n "${WF_VAULT_ROOT:-}" ]]; then
    if [[ "$storage_abs" != "$WF_VAULT_ROOT" && "$storage_abs" != "$WF_VAULT_ROOT"/* ]]; then
      wf__warn "chosen repo's spec_storage ($storage_abs) lies outside vault CWD ($WF_VAULT_ROOT); vault-found spec config may not be re-discoverable via spec_storage."
    fi
  fi

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

  # general_kb_path — REQUIRED. No backward-compat default. Path is absolute and
  # may live outside repo (e.g. master-brain vault), so allowed-root check is skipped.
  local gkb_raw gkb_abs
  gkb_raw="$(wf__json_get "$cfg_json" '.general_kb_path' '')" || {
    wf__err "$WF_CONFIG_FILE: general_kb_path extraction failed"; wf__unset_partials; return 5
  }
  if [[ -z "$gkb_raw" ]]; then
    wf__err "$WF_CONFIG_FILE: general_kb_path is required (no default). Add: general_kb_path: <abs-path-to-general-knowledge-base>"
    wf__unset_partials; return 2
  fi
  if [[ "$gkb_raw" == *".."* ]]; then
    wf__err "$WF_CONFIG_FILE: general_kb_path has '..' segment: $gkb_raw"
    wf__unset_partials; return 2
  fi
  gkb_abs="$(wf__resolve_path "$gkb_raw" "$root")"
  gkb_abs="$(realpath_safe "$gkb_abs" 2>/dev/null)" || {
    wf__err "$WF_CONFIG_FILE: general_kb_path unresolvable: $gkb_raw"
    wf__unset_partials; return 2
  }
  [[ -d "$gkb_abs" ]] || {
    wf__err "$WF_CONFIG_FILE: general_kb_path not a directory: $gkb_abs"
    wf__unset_partials; return 2
  }
  WF_GENERAL_KB="$gkb_abs"

  scope="$(wf__json_get "$cfg_json" '.validate_scope' 'per-task')" || {
    wf__err "$WF_CONFIG_FILE: validate_scope extraction failed"; wf__unset_partials; return 5
  }
  validate_scope_enum_check "$scope" 2>/dev/null || {
    wf__err "$WF_CONFIG_FILE: validate_scope invalid: '$scope' (expected: per-task, per-spec, both)"
    wf__unset_partials; return 2
  }
  WF_VALIDATE_SCOPE="$scope"

  local storage_mode
  storage_mode="$(wf__json_get "$cfg_json" '.spec_storage_mode' 'repo')" || {
    wf__err "$WF_CONFIG_FILE: spec_storage_mode extraction failed"; wf__unset_partials; return 5
  }
  case "$storage_mode" in
    repo|vault) ;;
    *) wf__err "$WF_CONFIG_FILE: spec_storage_mode invalid: '$storage_mode' (expected: repo, vault)"
       wf__unset_partials; return 2 ;;
  esac
  WF_SPEC_STORAGE_MODE="$storage_mode"

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
      # T3 — best-effort gate_pool_dirty event when an active monitor context
      # exists. Loader must never fail on monitor unavailability; wrap so any
      # error is swallowed. Skipped silently when no .monitor-context (e.g.
      # outside a tracked /implement session).
      {
        local _gp_sha _ctx_file _ctx_feature=""
        _gp_sha="$(git -C "$root" hash-object -- "$WF_GATE_POOL" 2>/dev/null || echo "unknown")"
        _ctx_file="$root/.monitor-context"
        if [[ -f "$_ctx_file" ]]; then
          _ctx_feature="$(awk -F= '$1=="feature"{print $2; exit}' "$_ctx_file" 2>/dev/null)"
        fi
        if [[ -n "$_ctx_feature" && -f "$HOME/.claude/scripts/monitor.sh" ]]; then
          bash "$HOME/.claude/scripts/monitor.sh" log_event "$_ctx_feature" gate_pool_dirty "" \
            "$(printf '{"file":"%s","sha":"%s"}' "$WF_GATE_POOL" "$_gp_sha")" >/dev/null 2>&1 || true
        fi
      } 2>/dev/null || true
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
      validate_scope_enum_check "$spec_scope" 2>/dev/null || {
        wf__err "$spec_cfg: validate_scope invalid: '$spec_scope' (expected: per-task, per-spec, both)"
        wf__unset_partials; return 4
      }
      WF_VALIDATE_SCOPE="$spec_scope"
    fi

    # Tier resolution: spec config.yml `tier` (required) → ceilings from
    # spec.tier_ceiling override else .workflow.yml tiers.<tier>.
    local tier
    tier="$(wf__json_get "$spec_json" '.tier' '')" || {
      wf__err "$spec_cfg: tier extraction failed"; wf__unset_partials; return 5
    }
    case "$tier" in
      small|medium|large) ;;
      "") wf__err "$spec_cfg: tier required (small|medium|large). Re-run /explore step 0 or /config."; wf__unset_partials; return 4 ;;
      *)  wf__err "$spec_cfg: tier invalid: '$tier' (expected: small, medium, large)"; wf__unset_partials; return 4 ;;
    esac
    WF_SPEC_TIER="$tier"

    local tc fc as
    tc="$(wf__json_get "$spec_json" ".tier_ceiling.tasks" '')"
    fc="$(wf__json_get "$spec_json" ".tier_ceiling.files" '')"
    [[ -z "$tc" ]] && tc="$(wf__json_get "$cfg_json" ".tiers.${tier}.tasks" '')"
    [[ -z "$fc" ]] && fc="$(wf__json_get "$cfg_json" ".tiers.${tier}.files" '')"
    as="$(printf '%s' "$cfg_json" | wf__timeout 5 yq e -r ".tiers.${tier}.agent_skip[]?" - 2>/dev/null | tr '\n' ' ' | sed 's/ *$//')"
    WF_TIER_TASK_CEILING="$tc"
    WF_TIER_FILE_CEILING="$fc"
    WF_TIER_AGENT_SKIP="$as"

    # repos[] — multi-repo binding (optional under spec_storage_mode=repo,
    # required under vault). Validate each path is a git work tree.
    local repos_count name path role abs_path names_acc="" paths_acc=""
    repos_count="$(printf '%s' "$spec_json" | wf__timeout 5 yq e -r '(.repos // []) | length' - 2>/dev/null || echo 0)"
    [[ "$repos_count" =~ ^[0-9]+$ ]] || repos_count=0
    if [[ "$WF_SPEC_STORAGE_MODE" == "vault" && "$repos_count" -eq 0 ]]; then
      wf__err "$spec_cfg: repos[] required when spec_storage_mode=vault"
      wf__unset_partials; return 4
    fi
    local i
    for ((i = 0; i < repos_count; i++)); do
      name="$(printf '%s' "$spec_json" | wf__timeout 5 yq e -r ".repos[$i].name // \"\"" - 2>/dev/null)"
      path="$(printf '%s' "$spec_json" | wf__timeout 5 yq e -r ".repos[$i].path // \"\"" - 2>/dev/null)"
      role="$(printf '%s' "$spec_json" | wf__timeout 5 yq e -r ".repos[$i].role // \"\"" - 2>/dev/null)"
      [[ -n "$name" ]] || { wf__err "$spec_cfg: repos[$i].name missing"; wf__unset_partials; return 4; }
      [[ "$name" =~ ^[a-z0-9][a-z0-9_-]{0,31}$ ]] || {
        wf__err "$spec_cfg: repos[$i].name invalid: '$name' (expected ^[a-z0-9][a-z0-9_-]{0,31}$)"
        wf__unset_partials; return 4
      }
      [[ -n "$path" ]] || { wf__err "$spec_cfg: repos[$i].path missing"; wf__unset_partials; return 7; }
      [[ "$path" == *".."* ]] && { wf__err "$spec_cfg: repos[$i].path has '..': $path"; wf__unset_partials; return 7; }
      case "$path" in
        "~"|"~/"*) abs_path="${HOME}${path:1}" ;;
        /*)        abs_path="$path" ;;
        *)         abs_path="$WF_REPO_ROOT/$path" ;;
      esac
      abs_path="$(realpath_safe "$abs_path" 2>/dev/null)" || {
        wf__err "$spec_cfg: repos[$i] ($name) unresolvable: $path"; wf__unset_partials; return 7
      }
      [[ -d "$abs_path" ]] || {
        wf__err "$spec_cfg: repos[$i] ($name) not a directory: $abs_path"; wf__unset_partials; return 7
      }
      local _toplevel
      _toplevel="$(git -C "$abs_path" rev-parse --show-toplevel 2>/dev/null)" || {
        wf__err "$spec_cfg: repos[$i] ($name) not a git repo: $abs_path"; wf__unset_partials; return 7
      }
      # Strict-equality: reject pointing at a subdirectory of a different repo.
      _toplevel="$(realpath_safe "$_toplevel" 2>/dev/null)" || _toplevel=""
      [[ "$abs_path" == "$_toplevel" ]] || {
        wf__err "$spec_cfg: repos[$i] ($name) path is inside repo $_toplevel, not the toplevel: $abs_path"
        wf__unset_partials; return 7
      }
      # Duplicate-name check
      if grep -Fxq -- "$name" <<<"$names_acc" 2>/dev/null; then
        wf__err "$spec_cfg: repos[] duplicate name: $name"; wf__unset_partials; return 4
      fi
      names_acc+="${names_acc:+$'\n'}$name"
      paths_acc+="${paths_acc:+$'\n'}$abs_path"
    done
    WF_REPO_NAMES="$names_acc"
    WF_REPO_PATHS="$paths_acc"

    # Ground-rules cross-check: every `repo:<name>:` prefix in spec task
    # frontmatter must reference a name in WF_REPO_NAMES. Fail-closed here
    # (instead of letting commands silently skip an unresolved KB rule at gate
    # time). Skipped when no tasks/ dir yet (pre-/propose) or no repos[].
    if [[ -n "$names_acc" ]]; then
      local tasks_dir="$WF_SPEC_STORAGE/$spec/tasks"
      if [[ -d "$tasks_dir" ]]; then
        local bad_refs="" tf line ref refname
        while IFS= read -r tf; do
          # Extract first YAML frontmatter block (between leading --- and next ---).
          while IFS= read -r line; do
            # Match `repo:<name>:<rest>` tokens inside ground_rules entries.
            [[ "$line" =~ repo:([a-z0-9][a-z0-9_-]{0,31}): ]] || continue
            refname="${BASH_REMATCH[1]}"
            grep -Fxq -- "$refname" <<<"$names_acc" && continue
            ref="$(basename "$tf"):$refname"
            grep -Fxq -- "$ref" <<<"$bad_refs" 2>/dev/null && continue
            bad_refs+="${bad_refs:+$'\n'}$ref"
          done < <(awk '/^---[[:space:]]*$/{c++; next} c==1' "$tf" 2>/dev/null)
        done < <(find "$tasks_dir" -maxdepth 1 -type f -name '*.md' 2>/dev/null)
        if [[ -n "$bad_refs" ]]; then
          wf__err "$spec_cfg: ground_rules reference unknown repo names (known: $(echo "$names_acc" | tr '\n' ' ')):"
          while IFS= read -r ref; do wf__err "  $ref"; done <<<"$bad_refs"
          wf__unset_partials; return 7
        fi
      fi
    fi

    WF_SPEC_HAS_CONFIG=1
    export WF_SPEC_CONFIG_FILE WF_SPEC_GATES WF_SPEC_HAS_CONFIG \
           WF_SPEC_TIER WF_TIER_TASK_CEILING WF_TIER_FILE_CEILING WF_TIER_AGENT_SKIP \
           WF_REPO_NAMES WF_REPO_PATHS
  fi

  WF_CONFIG_LOADED=1
  export WF_CONFIG_LOADED WF_REPO_ROOT WF_SPEC_STORAGE WF_GATE_POOL \
         WF_AGENT_POOL WF_GENERAL_KB WF_CONFIG_FILE WF_VALIDATE_SCOPE WF_SPEC_STORAGE_MODE
  [[ -n "${WF_VAULT_ROOT:-}" ]] && export WF_VAULT_ROOT
  return 0
}

# wf_repo_path <name> — print abs path of bound repo by logical name. rc 1 if unknown.
# Requires WF_REPO_NAMES / WF_REPO_PATHS populated (i.e. wf_load_config --spec ran
# against a spec config.yml that declared repos[]).
wf_repo_path() {
  local want="${1:-}" n p
  [[ -n "$want" ]] || { wf__err "wf_repo_path: name required"; return 1; }
  [[ -n "${WF_REPO_NAMES:-}" ]] || { wf__err "wf_repo_path: no repos bound (load with --spec)"; return 1; }
  local -a names paths
  while IFS= read -r n; do names+=("$n"); done <<<"$WF_REPO_NAMES"
  while IFS= read -r p; do paths+=("$p"); done <<<"$WF_REPO_PATHS"
  local i
  for i in "${!names[@]}"; do
    [[ "${names[$i]}" == "$want" ]] && { printf '%s' "${paths[$i]}"; return 0; }
  done
  wf__err "wf_repo_path: unknown repo name: $want (known: $(echo "$WF_REPO_NAMES" | tr '\n' ' '))"
  return 1
}

# wf_for_each_repo <fn> — invoke <fn> NAME PATH for each bound repo.
# <fn> may be any shell function or external command. Stops on first non-zero.
wf_for_each_repo() {
  local fn="${1:-}" n p
  [[ -n "$fn" ]] || { wf__err "wf_for_each_repo: fn required"; return 1; }
  [[ -n "${WF_REPO_NAMES:-}" ]] || return 0
  local -a names paths
  while IFS= read -r n; do names+=("$n"); done <<<"$WF_REPO_NAMES"
  while IFS= read -r p; do paths+=("$p"); done <<<"$WF_REPO_PATHS"
  local i rc
  for i in "${!names[@]}"; do
    "$fn" "${names[$i]}" "${paths[$i]}" || { rc=$?; return "$rc"; }
  done
}

# _wf_snapshot_json
# Emits canonical JSON snapshot of current config state (gates + per-phase agents)
# from environment. Single source of truth for both wf_write_snapshot and
# wf_check_snapshot_drift. Requires python3.
_wf_snapshot_json() {
  python3 -c "
import os, json
gates = sorted(l for l in os.environ.get('WF_SPEC_GATES', '').splitlines() if l)
agents = {k[len('WF_SPEC_AGENTS_'):].lower(): sorted(v.split())
          for k, v in os.environ.items()
          if k.startswith('WF_SPEC_AGENTS_') and v}
print(json.dumps({'agents': agents, 'gates': gates}, sort_keys=True))
"
}

# wf_write_snapshot <outfile>
# Reads $WF_SPEC_GATES and all WF_SPEC_AGENTS_* env vars; writes normalized JSON
# {"agents": {...}, "gates": [...]} to <outfile>. Requires python3.
wf_write_snapshot() {
  local outfile="$1"
  _wf_snapshot_json > "$outfile"
}

# wf_check_snapshot_drift <snapfile>
# Re-reads current config state from env, compares against <snapfile>.
# Echoes SNAPSHOT_OK or SNAPSHOT_DRIFT; returns 0 for OK, 1 for drift.
# Exits 0 silently if <snapfile> is absent.
wf_check_snapshot_drift() {
  local snapfile="$1"
  [[ -f "$snapfile" ]] || return 0
  local current snapshot
  current="$(_wf_snapshot_json)"
  snapshot="$(cat "$snapfile")"
  if [[ "$current" == "$snapshot" ]]; then
    echo "SNAPSHOT_OK"
    return 0
  else
    echo "SNAPSHOT_DRIFT"
    return 1
  fi
}

# CLI mode — evaluable KEY=VAL lines for hooks that cannot source.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  case "${1:-}" in
    export)
      shift
      wf_load_config "$@" || exit $?
      # Explicit allowlist prevents pre-existing WF_* env vars from being re-exported
      # No `local` here — bash CLI mode top-level; local is invalid outside a function.
      # Use eval-based set-check for bash 3.2 compat ([[ -v ]] requires bash 4.2+)
      _wf_allowed_vars=(
        WF_CONFIG_LOADED WF_REPO_ROOT WF_SPEC_STORAGE WF_GATE_POOL WF_AGENT_POOL
        WF_GENERAL_KB
        WF_CONFIG_FILE WF_VALIDATE_SCOPE WF_SPEC_CONFIG_FILE WF_SPEC_GATES WF_SPEC_HAS_CONFIG
        WF_SPEC_TIER WF_TIER_TASK_CEILING WF_TIER_FILE_CEILING WF_TIER_AGENT_SKIP
        WF_SPEC_STORAGE_MODE WF_REPO_NAMES WF_REPO_PATHS WF_VAULT_ROOT
      )
      for var in "${_wf_allowed_vars[@]}"; do
        eval "[[ \"\${${var}+x}\" ]]" 2>/dev/null || continue
        val="${!var}"
        esc="${val//\'/\'\\\'\'}"
        printf "%s='%s'\n" "$var" "$esc"
      done
      # Also export any WF_SPEC_AGENTS_* vars set during spec load
      while IFS= read -r var; do
        [[ -z "$var" ]] && continue
        val="${!var-}"
        esc="${val//\'/\'\\\'\'}"
        printf "%s='%s'\n" "$var" "$esc"
      done < <(compgen -v | grep '^WF_SPEC_AGENTS_' | sort)
      ;;
    *)
      echo "Usage: $(basename "$0") export [--spec <feature>]" >&2
      exit 2
      ;;
  esac
fi
