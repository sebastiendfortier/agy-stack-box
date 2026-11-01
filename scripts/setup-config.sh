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

# Fresh HPC clone: create the vault path before load_secrets validates it.
_vault="$(grep -E '^[[:space:]]*VAULT_HOST_PATH=' "$SECRETS_FILE" | tail -1 | cut -d= -f2-)"
_vault="${_vault%$'\r'}"; _vault="${_vault%\"}"; _vault="${_vault#\"}"; _vault="${_vault%\'}"; _vault="${_vault#\'}"
if [[ -n "$_vault" && ! -d "$_vault" ]]; then
  mkdir -p "$_vault"
  info "Created vault directory: $_vault (stubs come from harness/ via init-vault.sh)"
fi

load_secrets
export VAULT_IN_CONTAINER PROXY_PORT OBSIDIAN_REST_PORT OBSIDIAN_HTTPS_PORT ROUTER_PORT
info "Ports for this user (uid=$(id -u)): PROXY_PORT=$PROXY_PORT OBSIDIAN_REST_PORT=$OBSIDIAN_REST_PORT OBSIDIAN_HTTPS_PORT=$OBSIDIAN_HTTPS_PORT ROUTER_PORT=$ROUTER_PORT"

# Router bearer token: generated once and kept in secrets.env so re-running
# setup does not invalidate the apiKey already baked into custom_models.json.
if ! grep -qE '^[[:space:]]*ROUTER_TOKEN=' "$SECRETS_FILE"; then
  ROUTER_TOKEN="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
  {
    printf '\n# Capability-escalation router (auto-generated; rotate to invalidate).\n'
    printf 'ROUTER_TOKEN=%s\n' "$ROUTER_TOKEN"
  } >>"$SECRETS_FILE"
  info "Generated ROUTER_TOKEN in $SECRETS_FILE"
fi
export ROUTER_TOKEN

# Seed defaults if empty after first edit check
if [[ -z "${OPENROUTER_API_KEY}" || -z "${OBSIDIAN_API_KEY}" || -z "${VAULT_HOST_PATH}" ]]; then
  die "fill OPENROUTER_API_KEY, OBSIDIAN_API_KEY, and VAULT_HOST_PATH in $SECRETS_FILE"
fi

render_template "$ROOT/config/templates/custom_models.json.tmpl" \
  "$STATE_DIR/gemini/antigravity/custom_models.json"

# Escalation router: source + config land in state/ so they are visible inside
# the instance at $AGY_STATE without rebuilding the SIF.
mkdir -p "$STATE_DIR/router"
cp -f "$ROOT/scripts/model-router.mjs" "$STATE_DIR/router/model-router.mjs"
render_template "$ROOT/config/templates/model-router.config.json.tmpl" \
  "$STATE_DIR/router/config.json"
chmod 700 "$STATE_DIR/router"
info "Model router config: $STATE_DIR/router/config.json (SG Qwen -> openrouter/auto)"

# iHub: substitute placeholders left by render_template; optionally refresh from live catalog.
# IHUB_API_KEY may come from secrets.env or the ambient shell — never print or commit it.
# IHUB_BASE_URL is site-specific — set it in secrets.env, never hardcode it here.
IHUB_BASE_URL="${IHUB_BASE_URL:-}"
export IHUB_BASE_URL
if [[ -n "${IHUB_API_KEY:-}" && -z "$IHUB_BASE_URL" ]]; then
  die "IHUB_API_KEY is set but IHUB_BASE_URL is empty — add IHUB_BASE_URL=<your iHub proxy URL> to secrets.env"
fi
export IHUB_API_KEY="${IHUB_API_KEY:-}"
python3 - "$STATE_DIR/gemini/antigravity/custom_models.json" <<'PY'
import json, os, pathlib, sys, urllib.error, urllib.request

dest = pathlib.Path(sys.argv[1])
text = dest.read_text()
key = os.environ.get("IHUB_API_KEY", "")
base = os.environ.get("IHUB_BASE_URL", "").rstrip("/")
enabled = "true" if key else "false"
# Escape for JSON string contexts (placeholder sits inside "...").
text = text.replace("{{IHUB_API_KEY}}", json.dumps(key)[1:-1])
text = text.replace("{{IHUB_BASE_URL}}", json.dumps(base)[1:-1])
text = text.replace("{{IHUB_ENABLED}}", enabled)
data = json.loads(text)

def entry_for(mid: str, mode: str | None) -> dict:
    slug = mid.replace("/", "-")
    is_embed = (mode or "").lower() == "embedding" or "embed" in mid.lower()
    pretty = mid
    for prefix in ("ihub/", "sg/"):
        if pretty.startswith(prefix):
            pretty = pretty[len(prefix) :]
            break
    display = f"iHub {pretty}"
    if mid.startswith("sg/"):
        display = f"iHub SG {pretty}"
    if is_embed:
        display = f"{display} (embedding)"
    return {
        "name": f"models/{slug}",
        "displayName": display,
        "provider": "openai",
        "apiFormat": "openai",
        "apiUrl": f"{base}/embeddings" if is_embed else f"{base}/chat/completions",
        "apiKey": key,
        "externalModelName": mid,
        "enabled": bool(key),
        "contextWindow": 8192 if is_embed else 131072,
        "maxOutputTokens": 0 if is_embed else 16384,
        "timeout": 120000 if is_embed else 300000,
        "maxRetries": 2,
    }

def is_ihub_model(m: dict) -> bool:
    ext = str(m.get("externalModelName") or "")
    name = str(m.get("name") or "")
    return (
        ext.startswith("ihub/")
        or ext.startswith("sg/")
        or name.startswith("models/ihub-")
        or name.startswith("models/sg-")
    )

if key:
    try:
        req = urllib.request.Request(
            f"{base}/models",
            headers={"Authorization": f"Bearer {key}", "Accept": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=20) as resp:
            catalog = json.loads(resp.read().decode())
        live = catalog.get("data") or catalog.get("models") or []
        by_ext = {
            m.get("externalModelName"): m
            for m in data.get("models", [])
            if is_ihub_model(m)
        }
        kept = [m for m in data.get("models", []) if not is_ihub_model(m)]
        for item in live:
            mid = item.get("id") or item.get("name")
            if not mid:
                continue
            mode = item.get("mode")
            prev = by_ext.get(mid)
            fresh = entry_for(mid, mode)
            if prev:
                # Preserve user-tuned windows if present; refresh URLs/key/enabled/id.
                for k in ("contextWindow", "maxOutputTokens", "timeout", "maxRetries"):
                    if k in prev:
                        fresh[k] = prev[k]
                fresh["displayName"] = prev.get("displayName") or fresh["displayName"]
            kept.append(fresh)
            by_ext.pop(mid, None)
        # Keep any static ihub entries not returned by catalog (still keyed/enabled).
        for leftover in by_ext.values():
            leftover["apiKey"] = key
            leftover["enabled"] = True
            leftover["apiUrl"] = leftover.get("apiUrl", "").replace("{{IHUB_BASE_URL}}", base)
            kept.append(leftover)
        data["models"] = kept
        print(f"iHub: refreshed {len(live)} model(s) from {base}/models", file=sys.stderr)
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, json.JSONDecodeError, OSError) as exc:
        print(f"iHub: catalog fetch failed ({exc.__class__.__name__}); using static template entries", file=sys.stderr)
else:
    print("iHub: IHUB_API_KEY unset — iHub models rendered disabled", file=sys.stderr)

dest.write_text(json.dumps(data, indent=2) + "\n")
os.chmod(dest, 0o600)
print(dest)
PY

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

# Bootstrap the local vault from harness/ (no workstation vault needed on HPC).
"$SCRIPT_DIR/init-vault.sh" "$VAULT_HOST_PATH"

sync_gemini_to_home
info "Config ready under $STATE_DIR (custom_models synced to ~/.gemini/antigravity)"
info "Next: ./scripts/agy-ide | ./scripts/agy-cli | ./scripts/agy-app  (apps are in the SIF)"
