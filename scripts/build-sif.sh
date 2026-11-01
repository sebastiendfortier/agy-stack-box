#!/usr/bin/env bash
# Build apptainer/agy-stack.sif from the definition (fakeroot by default).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
RT="$(resolve_runtime)"

# Ubuntu 24.04 blocks unprivileged userns by default; fakeroot needs it off.
# RHEL/HPC often lacks this sysctl — only enforce when the knobs exists.
_userns_restrict="$(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2>/dev/null || true)"
if [[ -n "${_userns_restrict}" && "${_userns_restrict}" != "0" ]]; then
  die "kernel.apparmor_restrict_unprivileged_userns is not 0. Run: ./scripts/enable-local-build.sh"
fi
unset _userns_restrict
if ! unshare -Urm true 2>/dev/null; then
  die "unshare -Urm failed. Run: ./scripts/enable-local-build.sh (reboot if still broken)"
fi

cd "$ROOT/apptainer"
OUT="$ROOT/apptainer/agy-stack.sif"
info "Building $OUT with $RT --fakeroot (IDE/App/Obsidian/agy baked under /opt)..."

# HPC sites often export APPTAINER_BIND / SINGULARITY_BIND* (home, scratch, project).
# Those break *builds* (wrong mounts inside %post / fakeroot) but are wanted at *run*
# time — start-services does not clear them. Clear bind-related vars only for build.
# Safe no-op on laptops that never set them.
unset_hpc_bind_env_for_build() {
  local v
  for v in \
    APPTAINER_BIND SINGULARITY_BIND \
    APPTAINER_BINDPATH SINGULARITY_BINDPATH \
    APPTAINER_BIND_PATH SINGULARITY_BIND_PATH \
    APPTAINER_BINDPREPEND SINGULARITY_BINDPREPEND \
    APPTAINER_BINDAPPEND SINGULARITY_BINDAPPEND \
    APPTAINER_HOME SINGULARITY_HOME \
    APPTAINER_PWD SINGULARITY_PWD \
    APPTAINER_WORKDIR SINGULARITY_WORKDIR \
    APPTAINER_SCRATCHDIR SINGULARITY_SCRATCHDIR; do
    if [[ -n "${!v:-}" ]]; then
      info "build: unsetting $v (was set — typical HPC; kept for run)"
      unset "$v"
    fi
  done
}
unset_hpc_bind_env_for_build

# Fakeroot RPM unpack fails on many shared FS ("Inappropriate ioctl for device").
# Prefer an explicit local TMPDIR; if unset on /fs sitestore, use /tmp.
_tmpdir="${APPTAINER_TMPDIR:-${SINGULARITY_TMPDIR:-${TMPDIR:-}}}"
if [[ -z "${_tmpdir}" && "$ROOT" == /fs/* ]]; then
  _tmpdir="/tmp/agy-stack-build-${USER}-$$"
  mkdir -p "$_tmpdir"
  export APPTAINER_TMPDIR="$_tmpdir" SINGULARITY_TMPDIR="$_tmpdir"
  info "build: using local TMPDIR=$_tmpdir (sitestore breaks fakeroot rpm unpack)"
  # shellcheck disable=SC2064
  trap "rm -rf '$_tmpdir'" EXIT
elif [[ -n "${_tmpdir}" && ("$_tmpdir" == /fs/* || "$_tmpdir" == /home/*) ]]; then
  info "warning: TMPDIR=$_tmpdir looks shared — if rpm unpack fails, set APPTAINER_TMPDIR to node-local /tmp"
fi
unset _tmpdir

# Prefer zstd via env (Singularity CE 3.11 has no --mksquashfs-args flag).
export SINGULARITY_MKSQUASHFS_ARGS="${SINGULARITY_MKSQUASHFS_ARGS:--comp zstd -Xcompression-level 19}"
export APPTAINER_MKSQUASHFS_ARGS="${APPTAINER_MKSQUASHFS_ARGS:-$SINGULARITY_MKSQUASHFS_ARGS}"
# %files paths are relative to this directory
"$RT" build --fakeroot --force "$OUT" agy-stack.def
info "Built $OUT"
ls -lh "$OUT"
