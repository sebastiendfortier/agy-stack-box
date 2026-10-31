#!/usr/bin/env bash
# Enable unprivileged Singularity/Apptainer fakeroot builds on Ubuntu.
# Fixes: "Failed to create mount namespace: mount namespace requires privileges"
set -euo pipefail

if [[ "$(id -u)" -eq 0 ]]; then
  SUDO=()
else
  SUDO=(sudo)
  if ! sudo -n true 2>/dev/null; then
    if [[ -n "${SUDO_ASKPASS:-}" && -x "${SUDO_ASKPASS}" ]]; then
      SUDO=(sudo -A)
    else
      echo "This script needs sudo once to write /etc/sysctl.d/ and apply sysctl." >&2
    fi
  fi
fi

CONF=/etc/sysctl.d/99-agy-stack-userns.conf
echo "Writing $CONF ..."
"${SUDO[@]}" tee "$CONF" >/dev/null <<'EOF'
# Allow Singularity/Apptainer fakeroot builds (agy-stack-box)
# Ubuntu 23.10+/24.04 defaults this to 1, which breaks singularity build --fakeroot.
kernel.apparmor_restrict_unprivileged_userns = 0
EOF

echo "Applying sysctl..."
"${SUDO[@]}" sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 >/dev/null
sysctl kernel.apparmor_restrict_unprivileged_userns

# Subordinate IDs are required for fakeroot
USER_NAME="${SUDO_USER:-$USER}"
if ! grep -q "^${USER_NAME}:" /etc/subuid 2>/dev/null; then
  echo "Adding /etc/subuid mapping for $USER_NAME ..."
  "${SUDO[@]}" usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$USER_NAME"
fi

echo "Quick check: user+mount namespace..."
if unshare -Urm echo ok >/dev/null 2>&1; then
  echo "unshare -Urm: ok"
else
  echo "warning: unshare -Urm still failed; reboot may be required after sysctl change." >&2
fi

echo
echo "You can now build:"
echo "  ./scripts/build-sif.sh"
echo "  # or: singularity build --fakeroot apptainer/agy-stack.sif apptainer/agy-stack.def"
