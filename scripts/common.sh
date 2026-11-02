#!/usr/bin/env bash
# Shared helpers for agy-stack-box host scripts.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${AGY_STACK_STATE:-$ROOT/state}"
SECRETS_FILE="$STATE_DIR/secrets.env"
# Per-user + per-host defaults: instance/pids are host-local (vis vs ppp must not share).
_AGY_UID="$(id -u)"
HOST_ID="$(hostname -s 2>/dev/null | tr -c 'A-Za-z0-9._-' '_' || echo local)"
HOST_ID="${HOST_ID:-local}"
INSTANCE_NAME_DEFAULT="agy-stack-${USER:-$_AGY_UID}-${HOST_ID}"
# Stay in 30000–59999; three ports per uid bucket (proxy, Obsidian HTTP, Obsidian HTTPS).
# uid%10000 → 10k users before wrap; *3 keeps triples non-overlapping within the band.
# Same uid on vis+ppp can both use these ports — each binds its own 127.0.0.1.
_AGY_PORT_BASE=$((30000 + (_AGY_UID % 10000) * 3))
PROXY_PORT_DEFAULT="$_AGY_PORT_BASE"
OBSIDIAN_REST_PORT_DEFAULT="$((_AGY_PORT_BASE + 1))"
OBSIDIAN_HTTPS_PORT_DEFAULT="$((_AGY_PORT_BASE + 2))"
# Escalation router: one port per uid, in a band that cannot collide with the
# 30000–59999 proxy/Obsidian buckets above.
ROUTER_PORT_DEFAULT=$((20000 + (_AGY_UID % 10000)))
SIF_DEFAULT="$ROOT/apptainer/agy-stack.sif"
VAULT_IN_CONTAINER="/vault"
STATE_IN_CONTAINER="/agy-state"
# Shared FS-safe runtime dirs (sessions + service pids) under state/hosts/<host>/
HOST_RUNTIME_DIR="$STATE_DIR/hosts/$HOST_ID"
HOST_SESSIONS_DIR="$HOST_RUNTIME_DIR/sessions"
# Path inside the instance ($AGY_STATE/...) for pid files
HOST_PIDS_REL="hosts/$HOST_ID/pids"
AGY_IDLE_STOP_SEC="${AGY_IDLE_STOP_SEC:-60}"
# Real login home (for file pickers). Not state/home — that overlay made IDE see an empty $HOME.
HOST_HOME="${AGY_HOST_HOME:-$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f6)}"
HOST_HOME="${HOST_HOME:-${HOME:-}}"
# Canonical home (login home may be a symlink into a shared FS); Electron may resolve either.
HOST_HOME_REAL="$(readlink -f "$HOST_HOME" 2>/dev/null || echo "$HOST_HOME")"

die() { echo "error: $*" >&2; exit 1; }
info() { echo "$*"; }

# Site SINGULARITY_BINDPATH often includes /home,/fs — a full /home bind can shadow nested
# ~/.gemini overlays. Drop bare /home (and duplicates) for stack instance/exec; --home covers it.
sanitize_site_bindpath() {
  local var="$1" raw filtered="" part
  raw="${!var:-}"
  [[ -n "$raw" ]] || return 0
  IFS=',' read -ra _parts <<< "$raw"
  for part in "${_parts[@]}"; do
    part="${part#"${part%%[![:space:]]*}"}"
    part="${part%"${part##*[![:space:]]}"}"
    case "$part" in
      /home|/home:*) continue ;;
    esac
    [[ -n "$part" ]] || continue
    filtered+="${filtered:+,}$part"
  done
  export "$var=$filtered"
}

sanitize_site_bindpath APPTAINER_BINDPATH
sanitize_site_bindpath SINGULARITY_BINDPATH
sanitize_site_bindpath APPTAINER_BIND
sanitize_site_bindpath SINGULARITY_BIND

# App/IDE read ~/.gemini/antigravity on the real home; keep OpenRouter models/MCP there too.
sync_gemini_to_home() {
  local src="$STATE_DIR/gemini/antigravity" dest
  [[ -d "$src" ]] || return 0
  for dest in \
    "$HOST_HOME/.gemini/antigravity" \
    "$HOST_HOME_REAL/.gemini/antigravity"; do
    [[ -n "$dest" ]] || continue
    # If source and destination point to the exact same file/dir (e.g. bind mount or symlink), skip cp
    if [[ -d "$dest" ]] && python3 -c "import os, sys; sys.exit(0 if os.path.samefile(sys.argv[1], sys.argv[2]) else 1)" "$src" "$dest" 2>/dev/null; then
      continue
    fi
    mkdir -p "$dest"
    [[ -f "$src/custom_models.json" ]] && cp -a "$src/custom_models.json" "$dest/"
    [[ -f "$src/mcp_config.json" ]] && cp -a "$src/mcp_config.json" "$dest/"
  done
}

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

# True if secrets.env assigns this key (ignore ambient shell exports from old sessions).
secrets_has() {
  grep -qE "^[[:space:]]*$1=" "$SECRETS_FILE" 2>/dev/null
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
  if secrets_has INSTANCE_NAME; then
    : "${INSTANCE_NAME:?INSTANCE_NAME empty in secrets.env}"
  else
    INSTANCE_NAME="$INSTANCE_NAME_DEFAULT"
  fi
  # Ports: uid defaults unless explicitly set in secrets.env (not merely in the shell env).
  if secrets_has PROXY_PORT; then
    : "${PROXY_PORT:?PROXY_PORT empty in secrets.env}"
  else
    PROXY_PORT="$PROXY_PORT_DEFAULT"
  fi
  if secrets_has OBSIDIAN_REST_PORT; then
    : "${OBSIDIAN_REST_PORT:?OBSIDIAN_REST_PORT empty in secrets.env}"
  else
    OBSIDIAN_REST_PORT="$OBSIDIAN_REST_PORT_DEFAULT"
  fi
  if secrets_has OBSIDIAN_HTTPS_PORT; then
    : "${OBSIDIAN_HTTPS_PORT:?OBSIDIAN_HTTPS_PORT empty in secrets.env}"
  else
    OBSIDIAN_HTTPS_PORT="$OBSIDIAN_HTTPS_PORT_DEFAULT"
  fi
  # Capability-escalation router. Deliberately outside the 30000–59999 bucket
  # range so it never collides with another uid's proxy/Obsidian triple.
  if secrets_has ROUTER_PORT; then
    : "${ROUTER_PORT:?ROUTER_PORT empty in secrets.env}"
  else
    ROUTER_PORT="$ROUTER_PORT_DEFAULT"
  fi
  if secrets_has ROUTER_TOKEN; then
    : "${ROUTER_TOKEN:?ROUTER_TOKEN empty in secrets.env}"
  fi
  SIF_PATH="${SIF_PATH:-$SIF_DEFAULT}"
  # Optional colon/comma-separated extra binds (HPC scratch, projects, …), e.g. /scratch/$USER:/scratch/$USER
  AGY_EXTRA_BINDS="${AGY_EXTRA_BINDS:-}"
  # Overlay host /usr /bin /lib* so IDE/CLI see normal system tools (default on).
  # Set AGY_HOST_OS_TOOLS=0 to use only the Rocky SIF userspace.
  AGY_HOST_OS_TOOLS="${AGY_HOST_OS_TOOLS:-1}"
  AGY_HOST_PATH_BINDS="${AGY_HOST_PATH_BINDS:-1}"
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
    "{{ROUTER_PORT}}": os.environ.get("ROUTER_PORT", str(20000 + int(os.getuid()) % 10000)),
    "{{ROUTER_TOKEN}}": os.environ.get("ROUTER_TOKEN", ""),
    "{{IHUB_BASE_URL}}": os.environ.get("IHUB_BASE_URL", ""),
    "{{OBSIDIAN_REST_PORT}}": os.environ["OBSIDIAN_REST_PORT"],
    # Optional local Qwen endpoint (HPC); rendering still works when unset.
    "{{QWEN_BASE_URL}}": os.environ.get("QWEN_BASE_URL", "http://127.0.0.1:8000"),
    "{{QWEN_MODEL}}": os.environ.get("QWEN_MODEL", "qwen"),
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

# Overlay host OS userspace so base tools match the login node. Leaves SIF /opt alone.
# Wrappers live under /opt/agy-stack/host-scripts (not /usr/local) so this overlay is safe.
host_os_binds() {
  [[ "${AGY_HOST_OS_TOOLS:-1}" == "1" ]] || return 0
  local d
  for d in /usr /bin /sbin /lib /lib64 /lib32; do
    [[ -e "$d" ]] || continue
    printf '%s\n' "$d:$d"
  done
  for d in /etc/ssl /etc/ca-certificates /etc/pki /etc/alternatives; do
    [[ -e "$d" ]] || continue
    printf '%s\n' "$d:$d"
  done
}

# HPC/login PATH: module trees live outside the SIF. Bind every absolute PATH /
# LD_LIBRARY_PATH / MODULEPATH entry (and common software roots) so `module`-loaded
# tools resolve inside IDE terminals and agy.
host_path_binds() {
  [[ "${AGY_HOST_PATH_BINDS:-1}" == "1" ]] || return 0
  local p d root
  local -a cand=()
  # Explicit software roots often used on HPC.
  # Do NOT include /apps — that prefix is owned by the SIF (Node + apps).
  for d in /cvmfs /opt/software /opt/ohpc /opt/apps /soft /software /appl \
           /sw /gpfs /lustre /project /projects /scratch /work /data; do
    [[ -d "$d" ]] && cand+=("$d")
  done
  # Every directory on PATH / library / module paths (the entry itself — not /opt or /usr).
  local combined="${PATH:-}:${LD_LIBRARY_PATH:-}:${LIBRARY_PATH:-}:${MODULEPATH:-}:${PKG_CONFIG_PATH:-}:${CPATH:-}"
  local -a parts=()
  IFS=':' read -ra parts <<< "$combined"
  for p in "${parts[@]}"; do
    [[ -n "$p" && "$p" == /* ]] || continue
    if [[ -d "$p" ]]; then
      cand+=("$p")
      # Optional software prefix (e.g. /opt/software/gcc/12/bin → /opt/software/gcc/12 and /opt/software/gcc).
      # Never promote to /opt, /usr, /tmp, … — that would hide the SIF's /opt/agy-stack.
      root="$(dirname "$p")"
      case "$root" in
        /|/usr|/bin|/sbin|/lib|/lib64|/opt|/apps|/tmp|/var|/home|/Users|/private) ;;
        *) [[ -d "$root" ]] && cand+=("$root") ;;
      esac
    elif [[ -e "$p" ]]; then
      cand+=("$(dirname "$p")")
    fi
  done
  # Dedupe; skip home/state; skip OS roots (host_os_binds); never bind all of /opt or /usr.
  if ((${#cand[@]})); then
    printf '%s\n' "${cand[@]}" | awk -v home="${HOST_HOME:-}" -v state="${STATE_DIR:-}" '
      NF && $0 ~ /^\// && !seen[$0]++ {
        if (home != "" && ($0 == home || index($0, home "/") == 1)) next
        if (state != "" && ($0 == state || index($0, state "/") == 1)) next
        if ($0 == "/bin" || $0 == "/sbin" || $0 == "/usr" || $0 == "/opt" || $0 == "/apps" || $0 == "/tmp" || $0 == "/var") next
        if ($0 ~ /^\/usr\//) next
        if ($0 ~ /^\/apps\//) next
        print $0 ":" $0
      }'
  fi
}

# Prepare stack launcher names (agy, …) and bind over SIF /opt/agy-stack/host-scripts.
prepare_stack_bin() {
  local d="$STATE_DIR/stack-bin" s
  mkdir -p "$d"
  for s in agy antigravity-ide antigravity-app openrouter-proxy obsidian-stack; do
    cp -a "$ROOT/apptainer/rootfs-scripts/${s}.sh" "$d/$s"
    chmod +x "$d/$s"
  done
  cp -a "$ROOT/apptainer/rootfs-scripts/gui-session.sh" "$d/gui-session.sh"
  cp -a "$ROOT/apptainer/rootfs-scripts/resolve-app.sh" "$d/agy-resolve-app"
  chmod +x "$d/agy-resolve-app"
  # Built on the host: /usr and /lib inside the instance are the host's.
  local noshm_src="$ROOT/apptainer/rootfs-scripts/noshm.c" noshm_out="$d/libnoshm.so"
  if [[ ! -f "$noshm_out" || "$noshm_src" -nt "$noshm_out" ]]; then
    if ! gcc -shared -fPIC -O2 -o "$noshm_out" "$noshm_src" >/dev/null; then
      echo "warning: failed to build libnoshm.so (MIT-SHM guard disabled)" >&2
      rm -f "$noshm_out"
    fi
  fi
}

script_binds() {
  prepare_stack_bin
  # host-scripts exists in the SIF; directory bind replaces it with our named launchers.
  printf '%s\n' "$STATE_DIR/stack-bin:/opt/agy-stack/host-scripts"
}

# Stack-managed config layered onto the real home (HOME stays the real home for pickers).
config_binds() {
  [[ -n "$HOST_HOME" && -d "$HOST_HOME" ]] || return 0
  mkdir -p \
    "$STATE_DIR/gemini" \
    "$STATE_DIR/home/.config/Antigravity IDE" \
    "$STATE_DIR/home/.config/Antigravity" \
    "$STATE_DIR/home/.config/obsidian" \
    "$HOST_HOME/.config" \
    "$HOST_HOME/.gemini" \
    "$HOST_HOME_REAL/.config" \
    "$HOST_HOME_REAL/.gemini"
  # Bind gemini/config on both symlink and realpath homes (Electron may use either).
  printf '%s\n' "$STATE_DIR/gemini:$HOST_HOME/.gemini"
  if [[ "$HOST_HOME_REAL" != "$HOST_HOME" ]]; then
    printf '%s\n' "$STATE_DIR/gemini:$HOST_HOME_REAL/.gemini"
  fi
  printf '%s\n' "$STATE_DIR/home/.config/Antigravity IDE:$HOST_HOME/.config/Antigravity IDE"
  printf '%s\n' "$STATE_DIR/home/.config/Antigravity:$HOST_HOME/.config/Antigravity"
  printf '%s\n' "$STATE_DIR/home/.config/obsidian:$HOST_HOME/.config/obsidian"
  if [[ "$HOST_HOME_REAL" != "$HOST_HOME" ]]; then
    printf '%s\n' "$STATE_DIR/home/.config/Antigravity IDE:$HOST_HOME_REAL/.config/Antigravity IDE"
    printf '%s\n' "$STATE_DIR/home/.config/Antigravity:$HOST_HOME_REAL/.config/Antigravity"
    printf '%s\n' "$STATE_DIR/home/.config/obsidian:$HOST_HOME_REAL/.config/obsidian"
  fi
}

extra_binds() {
  local raw="${AGY_EXTRA_BINDS:-}" entry
  raw="${raw//,/ }"
  for entry in $raw; do
    [[ -n "$entry" ]] || continue
    printf '%s\n' "$entry"
  done
}

# Collect unique --bind specs from all bind helpers (order matters for overlays).
all_instance_binds() {
  local b
  printf '%s\n' "$STATE_DIR:$STATE_IN_CONTAINER"
  while IFS= read -r b; do [[ -n "$b" ]] && printf '%s\n' "$b"; done < <(vault_binds)
  while IFS= read -r b; do [[ -n "$b" ]] && printf '%s\n' "$b"; done < <(host_os_binds)
  while IFS= read -r b; do [[ -n "$b" ]] && printf '%s\n' "$b"; done < <(host_path_binds)
  while IFS= read -r b; do [[ -n "$b" ]] && printf '%s\n' "$b"; done < <(config_binds)
  while IFS= read -r b; do [[ -n "$b" ]] && printf '%s\n' "$b"; done < <(extra_binds)
  while IFS= read -r b; do [[ -n "$b" ]] && printf '%s\n' "$b"; done < <(script_binds)
  while IFS= read -r b; do [[ -n "$b" ]] && printf '%s\n' "$b"; done < <(display_binds)
}

# Singularity rejects --env HOME=...; use --home with the real login home.
instance_home_args() {
  [[ -n "$HOST_HOME" && -d "$HOST_HOME" ]] || die "HOST_HOME unset or missing (set AGY_HOST_HOME)"
  printf '%s\n' --home "$HOST_HOME"
}

# Pass login-shell tool env (modules / spack / conda / pixi) into the instance.
# Env every instance start / exec needs (ports, proxy URL, state paths, secrets).
instance_runtime_env() {
  local -n envargs=$1
  local v
  envargs+=(--env "CLOUD_CODE_URL=http://127.0.0.1:${PROXY_PORT}")
  envargs+=(--env "AGY_STATE=$STATE_IN_CONTAINER")
  envargs+=(--env "VAULT_PATH=$VAULT_IN_CONTAINER")
  envargs+=(--env "VAULT_HOST_PATH=${VAULT_HOST_PATH}")
  envargs+=(--env "PROXY_PORT=${PROXY_PORT}")
  envargs+=(--env "ROUTER_PORT=${ROUTER_PORT}")
  envargs+=(--env "OBSIDIAN_REST_PORT=${OBSIDIAN_REST_PORT}")
  envargs+=(--env "OPENROUTER_API_KEY=${OPENROUTER_API_KEY}")
  # Optional: lets the router's cheap tier authenticate. Empty keeps it unset.
  if [[ -n "${IHUB_API_KEY:-}" ]]; then
    envargs+=(--env "IHUB_API_KEY=${IHUB_API_KEY}")
  fi
  envargs+=(--env "OBSIDIAN_API_KEY=${OBSIDIAN_API_KEY}")
  # Stack launchers + Node >= 18, then login PATH (modules, conda, …).
  # New images: /apps/node. This image: /usr/local/bin/node, hidden by the host
  # /usr overlay, with the same Node 22 tree at $STATE_IN_CONTAINER/opt-node.
  # That directory is ahead of host PATH so `command -v node` cannot pick /bin/node v12.
  local node_path="/opt/agy-stack/host-scripts:/apps/node/bin"
  if [[ -x "$STATE_DIR/opt-node/bin/node" ]]; then
    node_path+=":${STATE_IN_CONTAINER}/opt-node/bin"
  fi
  node_path+=":/usr/local/bin:${PATH:-/usr/bin:/bin}"
  envargs+=(--env "PATH=${node_path}")
  envargs+=(--env "NODE_BIN=/apps/node/bin/node")
  for v in \
    LD_LIBRARY_PATH LIBRARY_PATH MODULEPATH LOADEDMODULES \
    MODULESHOME BASH_ENV ENV \
    LMOD_CMD LMOD_DIR LMOD_PKG LMOD_ROOT LMOD_SYSTEM_DEFAULT_MODULES \
    MANPATH INFOPATH CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH PKG_CONFIG_PATH \
    PYTHONPATH R_LIBS R_LIBS_USER JULIA_DEPOT_PATH \
    CMAKE_PREFIX_PATH ACLOCAL_PATH \
    CONDA_PREFIX CONDA_DEFAULT_ENV CONDA_PYTHON_EXE CONDA_EXE \
    MAMBA_ROOT_PREFIX PIXI_EXE PIXI_PROJECT_MANIFEST \
    CARGO_HOME RUSTUP_HOME GOPATH GOROOT \
    JAVA_HOME CUDA_HOME CUDA_PATH \
    CC CXX FC F77 MPICC MPICXX; do
    if [[ -n "${!v:-}" ]]; then
      envargs+=(--env "$v=${!v}")
    fi
  done
  if [[ -n "${DISPLAY:-}" ]]; then
    envargs+=(--env "DISPLAY=$DISPLAY")
  fi
  if [[ -n "${XAUTHORITY:-}" ]]; then
    envargs+=(--env "XAUTHORITY=$XAUTHORITY")
  fi
  if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    envargs+=(--env "WAYLAND_DISPLAY=$WAYLAND_DISPLAY")
  fi
  if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
    envargs+=(--env "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR")
  fi
  # Honor caller-configured proxy values; site-specific defaults belong in the
  # caller's environment, not in this reusable package.
  local _http_proxy="${http_proxy:-${HTTP_PROXY:-}}"
  local _https_proxy="${https_proxy:-${HTTPS_PROXY:-$_http_proxy}}"
  local _no_proxy="${no_proxy:-${NO_PROXY:-localhost,127.0.0.1,::1}}"
  # Comma-separated values CANNOT use singularity/apptainer --env (comma splits KEY=VAL list).
  # Pass them via APPTAINERENV_* / SINGULARITYENV_* instead.
  if [[ -n "$_http_proxy" ]]; then
    envargs+=(--env "http_proxy=$_http_proxy" --env "HTTP_PROXY=$_http_proxy")
  fi
  if [[ -n "$_https_proxy" ]]; then
    envargs+=(--env "https_proxy=$_https_proxy" --env "HTTPS_PROXY=$_https_proxy")
  fi
  envargs+=(--env "BROWSER=${BROWSER:-firefox}")
  export APPTAINERENV_no_proxy="$_no_proxy" SINGULARITYENV_no_proxy="$_no_proxy"
  export APPTAINERENV_NO_PROXY="$_no_proxy" SINGULARITYENV_NO_PROXY="$_no_proxy"
}

exec_in_instance() {
  local rt="$1"; shift
  local name="$1"; shift
  local -a args=(exec --pwd "$STATE_IN_CONTAINER")
  local b
  while IFS= read -r b; do
    [[ -n "$b" ]] && args+=(--bind "$b")
  done < <(all_instance_binds)
  while IFS= read -r b; do
    [[ -n "$b" ]] && args+=("$b")
  done < <(instance_home_args)
  instance_runtime_env args
  "$rt" "${args[@]}" "instance://$name" "$@"
}

# Register a client session (ide|app|cli). Cleared when the launcher exits.
client_session_begin() {
  local kind="${1:?kind}"
  mkdir -p "$HOST_SESSIONS_DIR" "$HOST_RUNTIME_DIR/pids"
  CLIENT_SESSION_FILE="$HOST_SESSIONS_DIR/${kind}.$$"
  printf '%s %s %s\n' "$(date -Iseconds 2>/dev/null || date)" "$kind" "$$" >"$CLIENT_SESSION_FILE"
  export CLIENT_SESSION_FILE
}

client_session_end() {
  [[ -n "${CLIENT_SESSION_FILE:-}" ]] && rm -f "$CLIENT_SESSION_FILE"
  CLIENT_SESSION_FILE=""
  schedule_idle_stop
}

# True if any ide/app/cli session files remain, or matching processes inside the instance.
clients_still_active() {
  local RT f
  mkdir -p "$HOST_SESSIONS_DIR"
  shopt -s nullglob
  for f in "$HOST_SESSIONS_DIR"/*; do
    [[ -f "$f" ]] && return 0
  done
  shopt -u nullglob
  RT="$(resolve_runtime)"
  instance_running "$RT" "$INSTANCE_NAME" || return 1
  exec_in_instance "$RT" "$INSTANCE_NAME" bash --noprofile --norc -c '
    pgrep -f "antigravity-ide|/Antigravity IDE/antigravity-ide" >/dev/null 2>&1 && exit 0
    pgrep -f "Antigravity-x64/antigravity" >/dev/null 2>&1 && exit 0
    # agy CLI binary (not openrouter-proxy / wrappers named agy-*)
    pgrep -f "/apps/agy/bin/agy|/opt/agy/bin/agy" >/dev/null 2>&1 && exit 0
    exit 1
  ' 2>/dev/null
}

# After last client exits: wait AGY_IDLE_STOP_SEC, then stop services if still idle.
schedule_idle_stop() {
  local wait_sec="${AGY_IDLE_STOP_SEC:-60}"
  mkdir -p "$HOST_RUNTIME_DIR"
  (
    # Only one reaper per host; others exit quietly.
    exec 9>"$HOST_RUNTIME_DIR/idle-stop.lock"
    flock -n 9 || exit 0
    sleep "$wait_sec"
    # Re-load secrets lightly for INSTANCE_NAME if needed
    if [[ -f "$SECRETS_FILE" ]]; then
      # shellcheck disable=SC1090
      set -a; source "$SECRETS_FILE"; set +a
    fi
    INSTANCE_NAME="${INSTANCE_NAME:-$INSTANCE_NAME_DEFAULT}"
    if clients_still_active; then
      exit 0
    fi
    info "No agy-ide/app/cli on $HOST_ID for ${wait_sec}s — stopping services."
    stop_services || true
  ) >/dev/null 2>&1 &
  disown || true
}

# Stop proxy/router/Obsidian inside the local instance, then the instance.
stop_services() {
  local RT
  RT="$(resolve_runtime)"
  if [[ -f "$SECRETS_FILE" ]]; then
    load_secrets 2>/dev/null || INSTANCE_NAME="${INSTANCE_NAME:-$INSTANCE_NAME_DEFAULT}"
  else
    INSTANCE_NAME="${INSTANCE_NAME:-$INSTANCE_NAME_DEFAULT}"
  fi
  if instance_running "$RT" "$INSTANCE_NAME"; then
    info "Stopping services inside '$INSTANCE_NAME'..."
    exec_in_instance "$RT" "$INSTANCE_NAME" bash --noprofile --norc -c "
      pids=\"\$AGY_STATE/${HOST_PIDS_REL}\"
      mkdir -p \"\$pids\"
      for name in obsidian proxy router; do
        f=\"\$pids/\${name}.pid\"
        if [[ -f \"\$f\" ]]; then
          pid=\$(cat \"\$f\" || true)
          if [[ -n \"\$pid\" ]] && kill -0 \"\$pid\" 2>/dev/null; then
            kill \"\$pid\" 2>/dev/null || true
            sleep 0.5
            kill -9 \"\$pid\" 2>/dev/null || true
          fi
          rm -f \"\$f\"
        fi
      done
      # Legacy unscoped pids (pre-host layout)
      for name in obsidian proxy router; do
        f=\"\$AGY_STATE/pids/\${name}.pid\"
        if [[ -f \"\$f\" ]]; then
          pid=\$(cat \"\$f\" || true)
          if [[ -n \"\$pid\" ]] && kill -0 \"\$pid\" 2>/dev/null; then
            kill \"\$pid\" 2>/dev/null || true
            kill -9 \"\$pid\" 2>/dev/null || true
          fi
          rm -f \"\$f\"
        fi
      done
      pkill -f \"/apps/obsidian/Obsidian|/opt/obsidian/Obsidian\" 2>/dev/null || true
      pkill -f \"desktop-service.mjs\" 2>/dev/null || true
      pkill -f \"model-router.mjs\" 2>/dev/null || true
      true
    " || true
    info "Stopping instance..."
    "$RT" instance stop "$INSTANCE_NAME" || true
  else
    info "Instance '$INSTANCE_NAME' is not running."
  fi
  # Host-side fallback: service processes orphaned outside the instance (e.g. after
  # a node restart wipes the instance registry) are invisible inside the container
  # but visible on the host. UID-scoped so we never touch other users' stacks.
  pkill -u "$(id -u)" -f "model-router.mjs" 2>/dev/null || true
  pkill -u "$(id -u)" -f "openrouter-proxy" 2>/dev/null || true
  rm -f "$HOST_RUNTIME_DIR/instance.name" "$STATE_DIR/instance.name"
  info "Stopped."
}

# Start instance + OpenRouter proxy + Obsidian if not already up (idempotent).
# Caller must load_secrets first.
ensure_services() {
  require_sif
  local RT NET_MODE DNS_FILE
  local -a start_args
  local b req _
  # Expanded into container shell snippets (host-scoped pid dir under $AGY_STATE).
  local _cpids="\$AGY_STATE/${HOST_PIDS_REL}"
  RT="$(resolve_runtime)"
  sync_gemini_to_home
  mkdir -p "$HOST_RUNTIME_DIR/pids" "$HOST_SESSIONS_DIR" "$STATE_DIR/logs"

  # Apps + Node are baked into the SIF under /apps, which is never host-bound.

  # AGY_NET_MODE=host (default): share host netns; proxy/Obsidian still bind 127.0.0.1
  #   (LAN-safe, no sudo, OpenRouter egress works).
  # AGY_NET_MODE=bridge: Singularity CNI private net (strict). On Ubuntu Singularity CE
  #   this often needs: sudo singularity instance start ... and may still lack egress.
  NET_MODE="${AGY_NET_MODE:-host}"

  if ! instance_running "$RT" "$INSTANCE_NAME"; then
    info "Starting instance '$INSTANCE_NAME' (AGY_NET_MODE=$NET_MODE)..."
    start_args=(instance start)
    case "$NET_MODE" in
      bridge)
        start_args+=(--net --network bridge)
        # systemd-resolved stub is unreachable inside a netns
        DNS_FILE="$STATE_DIR/resolv.conf"
        if [[ ! -f "$DNS_FILE" ]]; then
          printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' >"$DNS_FILE"
        fi
        start_args+=(--bind "$DNS_FILE:/etc/resolv.conf")
        ;;
      host) ;;
      *) die "AGY_NET_MODE must be host or bridge (got: $NET_MODE)" ;;
    esac
    while IFS= read -r b; do
      [[ -n "$b" ]] && start_args+=(--bind "$b")
    done < <(all_instance_binds)
    while IFS= read -r b; do
      [[ -n "$b" ]] && start_args+=("$b")
    done < <(instance_home_args)
    instance_runtime_env start_args
    info "Host tools: AGY_HOST_OS_TOOLS=${AGY_HOST_OS_TOOLS:-1} AGY_HOST_PATH_BINDS=${AGY_HOST_PATH_BINDS:-1} (PATH/modules passed through)"

    if [[ "$NET_MODE" == bridge ]]; then
      if ! "$RT" "${start_args[@]}" "$SIF_PATH" "$INSTANCE_NAME"; then
        if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
          info "unprivileged bridge start failed; retrying with passwordless sudo..."
          sudo "$RT" "${start_args[@]}" "$SIF_PATH" "$INSTANCE_NAME" \
            || die "bridge start failed. On HPC (no sudo) use default AGY_NET_MODE=host."
        else
          die "bridge CNI start failed and sudo is unavailable (typical on HPC). Use AGY_NET_MODE=host (default)."
        fi
      fi
    else
      "$RT" "${start_args[@]}" "$SIF_PATH" "$INSTANCE_NAME" \
        || die "instance start failed"
    fi
    echo "$INSTANCE_NAME" >"$HOST_RUNTIME_DIR/instance.name"
  else
    info "Instance '$INSTANCE_NAME' already running."
  fi

  # Non-login shells: login -lc pulls ordenv/profile and hides real errors in spam.
  local _sh=(bash --noprofile --norc -c)

  # Start OpenRouter BYOK proxy if not healthy
  if ! exec_in_instance "$RT" "$INSTANCE_NAME" \
    "${_sh[@]}" "curl -fsS --max-time 2 http://127.0.0.1:${PROXY_PORT}/healthz >/dev/null 2>&1"; then
    info "Starting OpenRouter BYOK proxy on 127.0.0.1:${PROXY_PORT}..."
    : >"$STATE_DIR/logs/proxy.log"
    exec_in_instance "$RT" "$INSTANCE_NAME" \
      "${_sh[@]}" "mkdir -p \"${_cpids}\" \"\$AGY_STATE/logs\" \"\$AGY_STATE/gemini/antigravity\"; nohup env PROXY_PORT=\"\$PROXY_PORT\" OPENROUTER_API_KEY=\"\$OPENROUTER_API_KEY\" AGY_STATE=\"\$AGY_STATE\" NODE_BIN=\"\${NODE_BIN:-/apps/node/bin/node}\" openrouter-proxy >>\"\$AGY_STATE/logs/proxy.log\" 2>&1 & echo \$! >\"${_cpids}/proxy.pid\""
    for _ in $(seq 1 30); do
      if exec_in_instance "$RT" "$INSTANCE_NAME" \
        "${_sh[@]}" "curl -fsS --max-time 2 http://127.0.0.1:${PROXY_PORT}/healthz >/dev/null 2>&1"; then
        break
      fi
      sleep 0.5
    done
    exec_in_instance "$RT" "$INSTANCE_NAME" \
      "${_sh[@]}" "curl -fsS --max-time 2 http://127.0.0.1:${PROXY_PORT}/healthz >/dev/null" \
      || die "proxy did not become healthy — see $STATE_DIR/logs/proxy.log"
  fi
  info "Proxy healthy on instance loopback :${PROXY_PORT}"

  # Capability-escalation router (optional; setup-config may install it under state/router).
  if [[ -f "$STATE_DIR/router/model-router.mjs" ]]; then
    if ! exec_in_instance "$RT" "$INSTANCE_NAME" \
      "${_sh[@]}" "curl -fsS --max-time 2 http://127.0.0.1:${ROUTER_PORT}/healthz >/dev/null 2>&1"; then
      info "Starting model router on 127.0.0.1:${ROUTER_PORT}..."
      : >"$STATE_DIR/logs/router.log"
      exec_in_instance "$RT" "$INSTANCE_NAME" \
        "${_sh[@]}" "mkdir -p \"${_cpids}\" \"\$AGY_STATE/logs\"; NODE_BIN=; for cand in /apps/node/bin/node \"\$AGY_STATE/opt-node/bin/node\" /usr/local/bin/node; do [[ -x \"\$cand\" ]] || continue; maj=\$(\"\$cand\" -p \"process.versions.node.split('.')[0]\" 2>/dev/null || echo 0); [[ \"\$maj\" -ge 18 ]] && NODE_BIN=\"\$cand\" && break; done; [[ -n \"\$NODE_BIN\" ]] || { echo \"error: no Node >= 18 for model router\" >>\"\$AGY_STATE/logs/router.log\"; exit 1; }; nohup env AGY_STATE=\"\$AGY_STATE\" ROUTER_PORT=\"\$ROUTER_PORT\" OPENROUTER_API_KEY=\"\$OPENROUTER_API_KEY\" NODE_BIN=\"\$NODE_BIN\" \"\$NODE_BIN\" \"\$AGY_STATE/router/model-router.mjs\" --config \"\$AGY_STATE/router/config.json\" >>\"\$AGY_STATE/logs/router.log\" 2>&1 & echo \$! >\"${_cpids}/router.pid\""
      for _ in $(seq 1 30); do
        if exec_in_instance "$RT" "$INSTANCE_NAME" \
          "${_sh[@]}" "curl -fsS --max-time 2 http://127.0.0.1:${ROUTER_PORT}/healthz >/dev/null 2>&1"; then
          break
        fi
        sleep 0.5
      done
      exec_in_instance "$RT" "$INSTANCE_NAME" \
        "${_sh[@]}" "curl -fsS --max-time 2 http://127.0.0.1:${ROUTER_PORT}/healthz >/dev/null" \
        || die "model router did not become healthy — see $STATE_DIR/logs/router.log"
    fi
    info "Model router healthy on instance loopback :${ROUTER_PORT}"
  fi

  # Start Obsidian AppImage (GUI + Local REST API plugin in the vault).
  # Headless nodes (ppp/login, SSH without -X) have no X11/Wayland: Electron cannot
  # open a display, so skip the GUI instead of failing silently on every start.
  # Vault stays bind-mounted (files/MCP unaffected). Override: AGY_FORCE_OBSIDIAN=1.
  if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" && "${AGY_FORCE_OBSIDIAN:-0}" != "1" ]]; then
    info "Headless ($HOST_ID): no display — skipping Obsidian GUI (vault still mounted at /vault)."
  elif ! exec_in_instance "$RT" "$INSTANCE_NAME" \
    "${_sh[@]}" "curl -fsS --max-time 2 http://127.0.0.1:${OBSIDIAN_REST_PORT}/ >/dev/null 2>&1 \
      || curl -fkSs --max-time 2 https://127.0.0.1:${OBSIDIAN_HTTPS_PORT}/ >/dev/null 2>&1"; then
    info "Starting Obsidian AppImage (vault=$VAULT_HOST_PATH)..."
    exec_in_instance "$RT" "$INSTANCE_NAME" \
      "${_sh[@]}" "mkdir -p \"${_cpids}\" \"\$AGY_STATE/logs\"
        if [[ -f \"${_cpids}/obsidian.pid\" ]]; then
          kill \"\$(cat \"${_cpids}/obsidian.pid\")\" 2>/dev/null || true
          sleep 0.5
        fi
        nohup obsidian-stack \"\${VAULT_HOST_PATH:-\$VAULT_PATH}\" >>\"\$AGY_STATE/logs/obsidian.log\" 2>&1 & echo \$! >\"${_cpids}/obsidian.pid\""
    info "Obsidian launched with preconfigured vault $VAULT_HOST_PATH"
    info "REST should listen on 127.0.0.1:${OBSIDIAN_REST_PORT} (insecure) inside the instance only."
  else
    info "Obsidian REST already responding on instance loopback."
  fi

  info "Services up on $HOST_ID."
}
