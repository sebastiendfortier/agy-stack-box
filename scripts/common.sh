#!/usr/bin/env bash
# Shared helpers for agy-stack-box host scripts.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${AGY_STACK_STATE:-$ROOT/state}"
SECRETS_FILE="$STATE_DIR/secrets.env"
# Per-user defaults so shared login nodes do not collide on instance name / ports.
_AGY_UID="$(id -u)"
INSTANCE_NAME_DEFAULT="agy-stack-${USER:-$_AGY_UID}"
# Stay in 30000–59999; three ports per uid bucket (proxy, Obsidian HTTP, Obsidian HTTPS).
# uid%10000 → 10k users before wrap; *3 keeps triples non-overlapping within the band.
_AGY_PORT_BASE=$((30000 + (_AGY_UID % 10000) * 3))
PROXY_PORT_DEFAULT="$_AGY_PORT_BASE"
OBSIDIAN_REST_PORT_DEFAULT="$((_AGY_PORT_BASE + 1))"
OBSIDIAN_HTTPS_PORT_DEFAULT="$((_AGY_PORT_BASE + 2))"
SIF_DEFAULT="$ROOT/apptainer/agy-stack.sif"
VAULT_IN_CONTAINER="/vault"
STATE_IN_CONTAINER="/agy-state"
# Real login home (for file pickers). Not state/home — that overlay made IDE see an empty $HOME.
HOST_HOME="${AGY_HOST_HOME:-$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f6)}"
HOST_HOME="${HOST_HOME:-${HOME:-}}"

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
  for d in /cvmfs /opt/software /opt/ohpc /opt/apps /soft /software /appl /apps \
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
        /|/usr|/bin|/sbin|/lib|/lib64|/opt|/tmp|/var|/home|/Users|/private) ;;
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
        if ($0 == "/bin" || $0 == "/sbin" || $0 == "/usr" || $0 == "/opt" || $0 == "/tmp" || $0 == "/var") next
        if ($0 ~ /^\/usr\//) next
        print $0 ":" $0
      }'
  fi
}

# Prepare stack launcher names (agy, …) and bind over SIF /opt/agy-stack/host-scripts.
prepare_stack_bin() {
  local d="$STATE_DIR/stack-bin" s
  mkdir -p "$d"
  for s in agy antigravity-ide openrouter-proxy obsidian-stack; do
    cp -a "$ROOT/apptainer/rootfs-scripts/${s}.sh" "$d/$s"
    chmod +x "$d/$s"
  done
  cp -a "$ROOT/apptainer/rootfs-scripts/resolve-app.sh" "$d/agy-resolve-app"
  chmod +x "$d/agy-resolve-app"
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
    "$STATE_DIR/home/.config/obsidian" \
    "$HOST_HOME/.config" \
    "$HOST_HOME/.gemini"
  printf '%s\n' "$STATE_DIR/gemini:$HOST_HOME/.gemini"
  printf '%s\n' "$STATE_DIR/home/.config/Antigravity IDE:$HOST_HOME/.config/Antigravity IDE"
  printf '%s\n' "$STATE_DIR/home/.config/obsidian:$HOST_HOME/.config/obsidian"
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
  envargs+=(--env "OBSIDIAN_REST_PORT=${OBSIDIAN_REST_PORT}")
  envargs+=(--env "OPENROUTER_API_KEY=${OPENROUTER_API_KEY}")
  envargs+=(--env "OBSIDIAN_API_KEY=${OBSIDIAN_API_KEY}")
  # Stack launchers first, then login PATH (modules, conda, ~/.local/bin, …).
  envargs+=(--env "PATH=/opt/agy-stack/host-scripts:${PATH:-/usr/bin:/bin}")
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
