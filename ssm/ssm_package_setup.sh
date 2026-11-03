#!/bin/bash
# Sourced by SSM as etc/profile.d/@PKGNAME@.sh — package root is one level up from etc/
# Idempotent per-user seeding: first load creates state; later loads change nothing.
if [ -z "${SSM_PKG_DIR:-}" ]; then
  # Works from both layouts: installed package (etc/profile.d -> ../..) and the
  # repo checkout (ssm/ -> ..). Pick the ancestor that actually has share/ or config/.
  _d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  _agy_stack_dir=""
  for _cand in "$_d/../.." "$_d/.."; do
    _cand="$(cd "$_cand" 2>/dev/null && pwd)" || continue
    if [ -d "$_cand/share" ] || [ -d "$_cand/config/templates" ]; then
      _agy_stack_dir="$_cand"
      break
    fi
  done
  [ -n "$_agy_stack_dir" ] || _agy_stack_dir="$_d/.."
else
  _agy_stack_dir="${SSM_PKG_DIR}"
fi

export PATH="${_agy_stack_dir}/bin:${PATH}"
export AGY_STACK_ROOT="${_agy_stack_dir}"

# Per-user state (mode 700). Launchers read AGY_STACK_STATE; SIF lives in the package.
_agy_state="${AGY_STACK_STATE:-${HOME}/.agy-stack/state}"
export AGY_STACK_STATE="$_agy_state"
export SIF_PATH="${SIF_PATH:-${_agy_stack_dir}/share/container/agy-stack-box.sif}"

if [ ! -d "$_agy_state" ]; then
  mkdir -p "$_agy_state"
  chmod 700 "$_agy_state"
  chmod 700 "$(dirname "$_agy_state")"   # ~/.agy-stack itself too
  # First load: seed templates. secrets.env is created 0600 ONLY if missing —
  # never overwritten on later loads; user fills it once.
  for _tmpl in \
      "${_agy_stack_dir}/share/templates/env.example" \
      "${_agy_stack_dir}/config/templates/env.example"; do
    if [ -f "$_tmpl" ] && [ ! -f "$_agy_state/secrets.env" ]; then
      cp "$_tmpl" "$_agy_state/secrets.env"
      chmod 600 "$_agy_state/secrets.env"
      break
    fi
  done
  case "$-" in
    *i*) echo "agy-stack-box: first load — fill ${_agy_state}/secrets.env (OPENROUTER_API_KEY optional; IHUB_API_KEY required)" ;;
  esac
fi

# Per-uid ports are derived inside common.sh (uid-based, collision-free per host);
# nothing port-related to seed here. Documented formula:
#   proxy/obsidian triple: 30000 + (uid % 10000) * 3 .. +2
#   router:                20000 + (uid % 10000)

# First-load MCP config: render from the package templates using the user's
# secrets.env. Never overwrites an existing mcp_config.json — re-run
# share/lib/render-mcp-config.py manually after changing secrets. Skips
# silently when python3 is missing or no remote MCP URL is configured yet.
if [ -f "$_agy_state/secrets.env" ] && [ ! -f "$_agy_state/gemini/antigravity/mcp_config.json" ]; then
  (
    set -a
    # shellcheck disable=SC1090
    . "$_agy_state/secrets.env" 2>/dev/null
    # Obsidian values are optional for the remote servers; give the renderer
    # safe defaults so rendering succeeds on a fresh, half-filled secrets.env.
    # Must be set while `set -a` is on so python3 inherits them.
    : "${OBSIDIAN_API_KEY:=}"
    : "${OBSIDIAN_REST_PORT:=30001}"
    set +a
    command -v python3 >/dev/null 2>&1 || exit 0
    _tmpl=""
    for _c in "${_agy_stack_dir}/share/templates/mcp_config.json.tmpl" \
              "${_agy_stack_dir}/config/templates/mcp_config.json.tmpl"; do
      [ -f "$_c" ] && { _tmpl="$_c"; break; }
    done
    [ -n "$_tmpl" ] || exit 0
    [ -n "${CMDS_AGENT_MCP_URL:-}${WIKI_MCP_URL:-}${GITLAB_MCP_URL:-}" ] || exit 0
    mkdir -p "$_agy_state/gemini/antigravity" "$_agy_state/gemini/config"
    python3 "${_agy_stack_dir}/share/lib/render-mcp-config.py" \
      "$_tmpl" "$_agy_state/gemini/antigravity/mcp_config.json" || exit 0
    cp -a "$_agy_state/gemini/antigravity/mcp_config.json" \
          "$_agy_state/gemini/config/mcp_config.json"
    chmod 600 "$_agy_state/gemini/config/mcp_config.json"
    case "$-" in
      *i*) echo "agy-stack-box: rendered MCP config from ${_agy_state}/secrets.env" ;;
    esac
  )
fi

# Always-on harness text tracks the loaded package; replace on every load.
if [ -f "${_agy_stack_dir}/share/agent/AGENTS.md" ] && [ -n "${AGY_STACK_AGENTS:-${HOME}/.agy-stack/AGENTS.md}" ]; then
  _agy_agents="${AGY_STACK_AGENTS:-${HOME}/.agy-stack/AGENTS.md}"
  mkdir -p "$(dirname "$_agy_agents")"
  cp -f "${_agy_stack_dir}/share/agent/AGENTS.md" "$_agy_agents"
fi

case "$-" in
  *i*) echo "agy-stack-box: loaded (agy-ide | agy-cli | agy-app | agy-stop | agy-update)" ;;
esac
unset _agy_stack_dir _agy_state _agy_agents _d _cand _tmpl
