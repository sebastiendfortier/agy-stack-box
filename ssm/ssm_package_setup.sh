#!/bin/bash
# Sourced by SSM as etc/profile.d/@PKGNAME@.sh — package root is one level up from etc/
# Idempotent per-user seeding: first load creates state; later loads change nothing.
if [ -z "${SSM_PKG_DIR:-}" ]; then
  _agy_stack_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
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
  # First load: seed templates. secrets.env is created 0600 ONLY if missing —
  # never overwritten on later loads; user fills it once.
  if [ -f "${_agy_stack_dir}/share/templates/env.example" ] && [ ! -f "$_agy_state/secrets.env" ]; then
    cp "${_agy_stack_dir}/share/templates/env.example" "$_agy_state/secrets.env"
    chmod 600 "$_agy_state/secrets.env"
  fi
  case "$-" in
    *i*) echo "agy-stack-box: first load — fill ${_agy_state}/secrets.env (OPENROUTER_API_KEY optional; IHUB_API_KEY required)" ;;
  esac
fi

# Per-uid ports are derived inside common.sh (uid-based, collision-free per host);
# nothing port-related to seed here. Documented formula:
#   proxy/obsidian triple: 30000 + (uid % 10000) * 3 .. +2
#   router:                20000 + (uid % 10000)

# Always-on harness text tracks the loaded package; replace on every load.
if [ -f "${_agy_stack_dir}/share/agent/AGENTS.md" ] && [ -n "${AGY_STACK_AGENTS:-${HOME}/.agy-stack/AGENTS.md}" ]; then
  _agy_agents="${AGY_STACK_AGENTS:-${HOME}/.agy-stack/AGENTS.md}"
  mkdir -p "$(dirname "$_agy_agents")"
  cp -f "${_agy_stack_dir}/share/agent/AGENTS.md" "$_agy_agents"
fi

case "$-" in
  *i*) echo "agy-stack-box: loaded (agy-ide | agy-cli | agy-app | agy-stop | agy-update)" ;;
esac
unset _agy_stack_dir _agy_state _agy_agents
