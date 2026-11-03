#!/usr/bin/env bash
# Build the agy-stack-box SSM package (same convention as cmds-pi-agent).
#
# Layout produced:
#   agy-stack-box_<version>_all/
#     bin/                     agy-ide agy-cli agy-app agy-stop agy-update
#     share/lib/common.sh      shared host-side helpers (copy of scripts/common.sh)
#     share/container/         agy-stack-box.sif (optional at build time)
#     share/agent/AGENTS.md    always-on harness text
#     share/templates/         secrets.env.tmpl + config templates
#     share/manifest/UPSTREAM.txt  pinned upstream source URLs
#     etc/profile.d/<pkg>.sh   SSM load-time environment + per-user seeding
#     .ssm.d/control.json      package metadata
#   dist/agy-stack-box_<version>_all.ssm   (tar.gz)
#
# Usage:
#   ./ssm/make_ssm_package.sh [--allow-missing-sif]
# Env: VERSION (default YYYY.MM.DD), SIF_SRC (default apptainer/agy-stack.sif)
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${DIR}/.." && pwd)"
VERSION="${VERSION:-$(date +%Y.%m.%d)}"
PLAT=all
NAME=agy-stack-box
PKGNAME="${NAME}_${VERSION}_${PLAT}"
OUT="${ROOT}/dist"
ALLOW_MISSING_SIF=0
[[ "${1:-}" == "--allow-missing-sif" ]] && ALLOW_MISSING_SIF=1

SIF_SRC="${SIF_SRC:-${ROOT}/apptainer/agy-stack.sif}"

rm -rf "${OUT:?}/${PKGNAME}" "${OUT:?}/${PKGNAME}.ssm"
mkdir -p "${OUT}/${PKGNAME}/bin" \
         "${OUT}/${PKGNAME}/share/lib" \
         "${OUT}/${PKGNAME}/share/container" \
         "${OUT}/${PKGNAME}/share/agent" \
         "${OUT}/${PKGNAME}/share/templates" \
         "${OUT}/${PKGNAME}/share/manifest" \
         "${OUT}/${PKGNAME}/etc/profile.d" \
         "${OUT}/${PKGNAME}/.ssm.d"

# --- bin launchers (thin wrappers around scripts/ logic) ---------------------
for launcher in agy-ide agy-cli agy-app agy-stop agy-update; do
  cp "${DIR}/wrappers/${launcher}" "${OUT}/${PKGNAME}/bin/${launcher}"
done
chmod 755 "${OUT}/${PKGNAME}/bin/"*

# --- share ------------------------------------------------------------------
cp "${ROOT}/scripts/common.sh" "${OUT}/${PKGNAME}/share/lib/common.sh"
if [[ -f "${ROOT}/harness/cmc-profile/AGENTS.md" ]]; then
  cp "${ROOT}/harness/cmc-profile/AGENTS.md" "${OUT}/${PKGNAME}/share/agent/AGENTS.md"
else
  echo "warn: harness/cmc-profile/AGENTS.md not found; share/agent/ left empty" >&2
fi
# Templates: everything the profile.d seeder may copy on first load.
cp "${ROOT}"/config/templates/*.tmpl "${OUT}/${PKGNAME}/share/templates/" 2>/dev/null || true
cp "${ROOT}"/config/templates/env.example "${OUT}/${PKGNAME}/share/templates/" 2>/dev/null || true

# Upstream pin list (human-readable; full version table lands in Phase 5).
cat > "${OUT}/${PKGNAME}/share/manifest/UPSTREAM.txt" <<'EOF'
# agy-stack-box upstream components (pin sources; checked by agy-update)
# antigravity-ide  <UPSTREAM-IDE-URL>
# antigravity-app  <UPSTREAM-APP-URL>
# agy-cli          <UPSTREAM-CLI-URL>
# obsidian         <UPSTREAM-OBSIDIAN-URL>
# openrouter proxy <UPSTREAM-PROXY-URL>
EOF

# --- SIF --------------------------------------------------------------------
if [[ -f "$SIF_SRC" ]]; then
  cp "$SIF_SRC" "${OUT}/${PKGNAME}/share/container/agy-stack-box.sif"
elif [[ $ALLOW_MISSING_SIF -eq 1 ]]; then
  echo "warn: SIF not found at $SIF_SRC — building structure-only package" >&2
  rmdir "${OUT}/${PKGNAME}/share/container"
else
  echo "error: SIF not found at $SIF_SRC (set SIF_SRC or use --allow-missing-sif)" >&2
  exit 1
fi

# --- profile.d loader -------------------------------------------------------
sed "s/@PKGNAME@/${PKGNAME}/g" "${DIR}/ssm_package_setup.sh" \
  > "${OUT}/${PKGNAME}/etc/profile.d/${PKGNAME}.sh"
chmod 755 "${OUT}/${PKGNAME}/etc/profile.d/${PKGNAME}.sh"

# --- control.json (python3; schema matches sibling packages) -----------------
python3 - "$OUT/$PKGNAME" "$VERSION" <<'PY'
import json, os, sys
from datetime import datetime, timezone
pkg, version = sys.argv[1], sys.argv[2]
# x-build-host/user are intentionally NOT the real values: the package is
# published to a shared SSM domain, and a cluster node name + login name in
# control.json would fingerprint the build environment (same rule as the
# redaction gate in validate_ssm_package.sh).
control = {
    "name": "agy-stack-box", "version": version, "platform": "all",
    "maintainer": "CMDS",
    "description": "CMDS agy stack (Antigravity IDE/App/CLI + router in Apptainer)",
    "x-build-date": datetime.now(timezone.utc).isoformat(),
    "x-build-host": "<REDACTED>",
}
with open(os.path.join(pkg, ".ssm.d", "control.json"), "w") as f:
    json.dump(control, f, indent=2); f.write("\n")
print("control written")
PY

# --- tarball (sorted members for reproducibility) ----------------------------
tar -C "$OUT" -czf "${OUT}/${PKGNAME}.ssm" \
  --sort=name --owner=0 --group=0 "$PKGNAME"
chmod 644 "${OUT}/${PKGNAME}.ssm"
rm -rf "${OUT:?}/${PKGNAME}"
echo "Built ${OUT:?}/${PKGNAME}.ssm"
