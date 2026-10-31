#!/usr/bin/env bash
# Build apptainer/agy-stack.sif from the definition (must be run from a machine with build rights).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
RT="$(resolve_runtime)"
cd "$ROOT/apptainer"
OUT="$ROOT/apptainer/agy-stack.sif"
info "Building $OUT with $RT (this downloads IDE + Obsidian + npm deps; multi-GB)..."
# %files paths are relative to this directory
"$RT" build --force "$OUT" agy-stack.def
info "Built $OUT"
ls -lh "$OUT"
