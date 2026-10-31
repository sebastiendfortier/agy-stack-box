#!/usr/bin/env bash
# Create state/, secrets.env, and rendered Gemini/IDE configs (no secrets in git).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

mkdir -p "$STATE_DIR"/{home,gemini/antigravity,gemini/config,logs,pids}
chmod 700 "$STATE_DIR"

EXAMPLE="$ROOT/config/templates/env.example"
if [[ ! -f "$SECRETS_FILE" ]]; then
  cp "$EXAMPLE" "$SECRETS_FILE"
  chmod 600 "$SECRETS_FILE"
  info "Created $SECRETS_FILE — edit it, then re-run this script."
  info "Required: OPENROUTER_API_KEY, OBSIDIAN_API_KEY, VAULT_HOST_PATH"
  exit 0
fi

load_secrets
export VAULT_IN_CONTAINER PROXY_PORT OBSIDIAN_REST_PORT

# Seed defaults if empty after first edit check
if [[ -z "${OPENROUTER_API_KEY}" || -z "${OBSIDIAN_API_KEY}" || -z "${VAULT_HOST_PATH}" ]]; then
  die "fill OPENROUTER_API_KEY, OBSIDIAN_API_KEY, and VAULT_HOST_PATH in $SECRETS_FILE"
fi

render_template "$ROOT/config/templates/custom_models.json.tmpl" \
  "$STATE_DIR/gemini/antigravity/custom_models.json"
render_template "$ROOT/config/templates/mcp_config.json.tmpl" \
  "$STATE_DIR/gemini/antigravity/mcp_config.json"
# CLI/global MCP location used by some agy builds
mkdir -p "$STATE_DIR/gemini/config"
cp -a "$STATE_DIR/gemini/antigravity/mcp_config.json" "$STATE_DIR/gemini/config/mcp_config.json"
chmod 600 "$STATE_DIR/gemini/config/mcp_config.json"

# IDE settings under the state home that the instance uses as $HOME
IDE_USER="$STATE_DIR/home/.config/Antigravity IDE/User"
mkdir -p "$IDE_USER"
render_template "$ROOT/config/templates/ide-settings.json.tmpl" "$IDE_USER/settings.json"

# Relative symlink so ~/.gemini resolves both on the host and inside the bind.
mkdir -p "$STATE_DIR/home"
rm -f "$STATE_DIR/home/.gemini"
ln -sfn ../gemini "$STATE_DIR/home/.gemini"

# Remind about Obsidian Local REST API plugin config in the vault
EXAMPLE_REST="$ROOT/config/templates/obsidian-local-rest-api.data.json.example"
VAULT_PLUGIN_DATA="$VAULT_HOST_PATH/.obsidian/plugins/obsidian-local-rest-api/data.json"
if [[ ! -f "$VAULT_PLUGIN_DATA" ]]; then
  info "Note: install Obsidian Local REST API in the vault and set apiKey to match OBSIDIAN_API_KEY."
  info "Example shape: $EXAMPLE_REST"
fi

info "Config ready under $STATE_DIR"
info "Next: ./scripts/fetch-apps.sh   # IDE + Obsidian + agy into state/apps"
info "Then:  ./scripts/build-sif.sh && ./scripts/start-services.sh"
