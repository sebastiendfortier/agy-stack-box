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
export VAULT_IN_CONTAINER PROXY_PORT OBSIDIAN_REST_PORT OBSIDIAN_HTTPS_PORT
info "Ports for this user (uid=$(id -u)): PROXY_PORT=$PROXY_PORT OBSIDIAN_REST_PORT=$OBSIDIAN_REST_PORT OBSIDIAN_HTTPS_PORT=$OBSIDIAN_HTTPS_PORT"

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

# Obsidian open-vault registry: use the real host path (also bind-mounted into the instance)
OBS_CFG_DIR="$STATE_DIR/home/.config/obsidian"
mkdir -p "$OBS_CFG_DIR"
python3 - "$OBS_CFG_DIR/obsidian.json" "$VAULT_HOST_PATH" <<'PY'
import json, pathlib, sys, time, hashlib
dest, vault = pathlib.Path(sys.argv[1]), sys.argv[2]
vid = hashlib.md5(vault.encode()).hexdigest()[:16]
data = {"vaults": {}, "language": "en"}
if dest.exists():
    try:
        data = json.loads(dest.read_text())
    except Exception:
        pass
data.setdefault("vaults", {})
data["vaults"][vid] = {"path": vault, "ts": int(time.time() * 1000), "open": True}
# Only one open vault
for k, v in data["vaults"].items():
    if k != vid and isinstance(v, dict):
        v["open"] = False
dest.write_text(json.dumps(data))
print(dest)
PY

# Relative symlink so ~/.gemini resolves both on the host and inside the bind.
mkdir -p "$STATE_DIR/home"
rm -f "$STATE_DIR/home/.gemini"
ln -sfn ../gemini "$STATE_DIR/home/.gemini"

# Sync Local REST API listen ports (+ api key) so multi-user hosts do not share 27123.
EXAMPLE_REST="$ROOT/config/templates/obsidian-local-rest-api.data.json.example"
VAULT_PLUGIN_DATA="$VAULT_HOST_PATH/.obsidian/plugins/obsidian-local-rest-api/data.json"
if [[ ! -f "$VAULT_PLUGIN_DATA" ]]; then
  info "Note: install Obsidian Local REST API in the vault and set apiKey to match OBSIDIAN_API_KEY."
  info "Example shape: $EXAMPLE_REST"
else
  python3 - "$VAULT_PLUGIN_DATA" "$OBSIDIAN_REST_PORT" "$OBSIDIAN_HTTPS_PORT" "$OBSIDIAN_API_KEY" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
insecure, secure, key = int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
data = json.loads(path.read_text())
data["insecurePort"] = insecure
data["port"] = secure
data["enableInsecureServer"] = True
if key:
    data["apiKey"] = key
path.write_text(json.dumps(data, indent=2) + "\n")
print(f"updated {path}: insecurePort={insecure} port={secure}")
PY
fi

info "Config ready under $STATE_DIR"
info "Next: ./scripts/fetch-apps.sh   # IDE + Obsidian + agy into state/apps"
info "Then:  ./scripts/build-sif.sh && ./scripts/start-services.sh"
