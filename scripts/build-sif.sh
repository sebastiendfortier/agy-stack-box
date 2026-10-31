#!/usr/bin/env bash
# Build apptainer/agy-stack.sif from the definition (fakeroot by default).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
RT="$(resolve_runtime)"

# Ubuntu 24.04 blocks unprivileged userns by default; fakeroot needs it off.
if [[ "$(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2>/dev/null || echo 1)" != "0" ]]; then
  die "kernel.apparmor_restrict_unprivileged_userns is not 0. Run: ./scripts/enable-local-build.sh"
fi
if ! unshare -Urm true 2>/dev/null; then
  die "unshare -Urm failed. Run: ./scripts/enable-local-build.sh (reboot if still broken)"
fi

cd "$ROOT/apptainer"
OUT="$ROOT/apptainer/agy-stack.sif"
info "Building slim $OUT with $RT --fakeroot (IDE/Obsidian/agy stay in state/apps via fetch-apps.sh)..."
# Prefer zstd via env (Singularity CE 3.11 has no --mksquashfs-args flag).
export SINGULARITY_MKSQUASHFS_ARGS="${SINGULARITY_MKSQUASHFS_ARGS:--comp zstd -Xcompression-level 19}"
export APPTAINER_MKSQUASHFS_ARGS="${APPTAINER_MKSQUASHFS_ARGS:-$SINGULARITY_MKSQUASHFS_ARGS}"
# %files paths are relative to this directory
"$RT" build --fakeroot --force "$OUT" agy-stack.def
info "Built $OUT"
ls -lh "$OUT"
