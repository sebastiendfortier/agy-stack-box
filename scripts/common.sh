#!/usr/bin/env bash
# Shared helpers for agy-stack-box host scripts.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${AGY_STACK_STATE:-$ROOT/state}"
SECRETS_FILE="$STATE_DIR/secrets.env"
# Per-user defaults so shared login nodes do not collide on instance name / ports.
_AGY_UID="$(id -u)"
INSTANCE_NAME_DEFAULT="agy-stack-${USER:-$_AGY_UID}"
# Stay in 30000–59999; two ports per uid bucket (proxy, then REST).
_AGY_PORT_BASE=$((30000 + (_AGY_UID % 15000) * 2))
PROXY_PORT_DEFAULT="$_AGY_PORT_BASE"
OBSIDIAN_REST_PORT_DEFAULT="$((_AGY_PORT_BASE + 1))"
SIF_DEFAULT="$ROOT/apptainer/agy-stack.sif"
VAULT_IN_CONTAINER="/vault"
STATE_IN_CONTAINER="/agy-state"

die() { echo "error: $*" >&2; exit 1; }
info() { echo "$*"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

# Prefer apptainer, fall back to singularity (CE).
resolve_runtime() {
  if [[ -n "${AGY_RUNTIME:-}" ]]; then
    require_cmd "$AGY_RUNTIME"
    echo "$AGY_RUNTIME"
    return
  fi
  if command -v apptainer >/dev/null 2>&1; then
    echo apptainer
  elif command -v singularity >/dev/null 2>&1; then
    echo singularity
  else
    die "need apptainer or singularity on PATH"
  fi
}

load_secrets() {
  [[ -f "$SECRETS_FILE" ]] || die "missing $SECRETS_FILE — run ./scripts/setup-config.sh first"
  # shellcheck disable=SC1090
  set -a
  # shellcheck disable=SC1091
  source "$SECRETS_FILE"
  set +a
  : "${OPENROUTER_API_KEY:?OPENROUTER_API_KEY unset in secrets.env}"
  : "${OBSIDIAN_API_KEY:?OBSIDIAN_API_KEY unset in secrets.env}"
  : "${VAULT_HOST_PATH:?VAULT_HOST_PATH unset in secrets.env}"
  [[ -d "$VAULT_HOST_PATH" ]] || die "VAULT_HOST_PATH is not a directory: $VAULT_HOST_PATH"
  INSTANCE_NAME="${INSTANCE_NAME:-$INSTANCE_NAME_DEFAULT}"
  PROXY_PORT="${PROXY_PORT:-$PROXY_PORT_DEFAULT}"
  OBSIDIAN_REST_PORT="${OBSIDIAN_REST_PORT:-$OBSIDIAN_REST_PORT_DEFAULT}"
  SIF_PATH="${SIF_PATH:-$SIF_DEFAULT}"
}

render_template() {
  local src="$1" dest="$2"
  python3 - "$src" "$dest" <<'PY'
import os, pathlib, sys
src, dest = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
text = src.read_text()
replacements = {
    "{{OPENROUTER_API_KEY}}": os.environ["OPENROUTER_API_KEY"],
    "{{OBSIDIAN_API_KEY}}": os.environ["OBSIDIAN_API_KEY"],
    "{{VAULT_HOST_PATH}}": os.environ["VAULT_HOST_PATH"],
    "{{VAULT_IN_CONTAINER}}": os.environ.get("VAULT_IN_CONTAINER", "/vault"),
    "{{PROXY_PORT}}": os.environ["PROXY_PORT"],
    "{{OBSIDIAN_REST_PORT}}": os.environ["OBSIDIAN_REST_PORT"],
}
for key, value in replacements.items():
    text = text.replace(key, value)
dest.parent.mkdir(parents=True, exist_ok=True)
dest.write_text(text)
os.chmod(dest, 0o600)
print(dest)
PY
}

instance_running() {
  local rt="$1" name="$2"
  "$rt" instance list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$name"
}

require_sif() {
  [[ -f "$SIF_PATH" ]] || die "missing image $SIF_PATH — build with: $(resolve_runtime) build apptainer/agy-stack.sif apptainer/agy-stack.def"
}

# Binds shared by every exec into the instance.
display_binds() {
  local binds=()
  if [[ -d /tmp/.X11-unix ]]; then
    binds+=("/tmp/.X11-unix:/tmp/.X11-unix")
  fi
  if [[ -n "${XAUTHORITY:-}" && -f "$XAUTHORITY" ]]; then
    binds+=("$XAUTHORITY:$XAUTHORITY")
  fi
  if [[ -n "${XDG_RUNTIME_DIR:-}" && -d "$XDG_RUNTIME_DIR" ]]; then
    binds+=("$XDG_RUNTIME_DIR:$XDG_RUNTIME_DIR")
  fi
  printf '%s\n' "${binds[@]}"
}

# Vault at /vault (scripts) AND at the real host path (Obsidian file picker / obsidian.json).
vault_binds() {
  printf '%s\n' "$VAULT_HOST_PATH:$VAULT_IN_CONTAINER"
  # Same directory again at the host path so GUI "Open folder" works inside the instance.
  if [[ "$VAULT_HOST_PATH" != "$VAULT_IN_CONTAINER" ]]; then
    printf '%s\n' "$VAULT_HOST_PATH:$VAULT_HOST_PATH"
  fi
}

# Overlay updated wrappers from the checkout onto the running SIF (no rebuild needed).
script_binds() {
  local s src
  for s in agy antigravity-ide openrouter-proxy obsidian-stack resolve-app; do
    src="$ROOT/apptainer/rootfs-scripts/${s}.sh"
    if [[ -f "$src" ]]; then
      if [[ "$s" == resolve-app ]]; then
        printf '%s\n' "$src:/usr/local/bin/agy-resolve-app"
      else
        printf '%s\n' "$src:/usr/local/bin/$s"
      fi
    fi
  done
}

# Singularity rejects --env HOME=...; use --home instead.
instance_home_args() {
  printf '%s\n' --home "$STATE_DIR/home:$STATE_IN_CONTAINER/home"
}

# Env every instance start / exec needs (ports, proxy URL, state paths, secrets).
instance_runtime_env() {
  local -n _out=$1
  _out+=(--env "CLOUD_CODE_URL=http://127.0.0.1:${PROXY_PORT}")
  _out+=(--env "AGY_STATE=$STATE_IN_CONTAINER")
  _out+=(--env "VAULT_PATH=$VAULT_IN_CONTAINER")
  _out+=(--env "VAULT_HOST_PATH=${VAULT_HOST_PATH}")
  _out+=(--env "PROXY_PORT=${PROXY_PORT}")
  _out+=(--env "OBSIDIAN_REST_PORT=${OBSIDIAN_REST_PORT}")
  _out+=(--env "OPENROUTER_API_KEY=${OPENROUTER_API_KEY}")
  _out+=(--env "OBSIDIAN_API_KEY=${OBSIDIAN_API_KEY}")
  if [[ -n "${DISPLAY:-}" ]]; then
    _out+=(--env "DISPLAY=$DISPLAY")
  fi
  if [[ -n "${XAUTHORITY:-}" ]]; then
    _out+=(--env "XAUTHORITY=$XAUTHORITY")
  fi
  if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    _out+=(--env "WAYLAND_DISPLAY=$WAYLAND_DISPLAY")
  fi
  if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
    _out+=(--env "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR")
  fi
}

exec_in_instance() {
  local rt="$1"; shift
  local name="$1"; shift
  local -a args=(exec --pwd "$STATE_IN_CONTAINER")
  local b
  while IFS= read -r b; do
    [[ -n "$b" ]] && args+=(--bind "$b")
  done < <(display_binds)
  # State + vault already bound at instance start; re-bind is harmless if paths match.
  args+=(--bind "$STATE_DIR:$STATE_IN_CONTAINER")
  while IFS= read -r b; do
    [[ -n "$b" ]] && args+=(--bind "$b")
  done < <(vault_binds)
  while IFS= read -r b; do
    [[ -n "$b" ]] && args+=(--bind "$b")
  done < <(script_binds)
  while IFS= read -r b; do
    [[ -n "$b" ]] && args+=("$b")
  done < <(instance_home_args)
  instance_runtime_env args
  "$rt" "${args[@]}" "instance://$name" "$@"
}
