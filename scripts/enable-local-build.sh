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

# Permit CNI bridge for private-net instances (strict isolation mode).
CONF=/etc/singularity/singularity.conf
if [[ -f "$CONF" ]]; then
  echo "Permitting CNI bridge for $USER_NAME in $CONF ..."
  "${SUDO[@]}" cp -a "$CONF" "$CONF.bak.agy-stack" 2>/dev/null || true
  "${SUDO[@]}" python3 - "$USER_NAME" <<'PY'
import re, sys
from pathlib import Path
user = sys.argv[1]
p = Path("/etc/singularity/singularity.conf")
text = p.read_text()

def set_line(text, key, value):
    pat = re.compile(rf"^#?\s*{re.escape(key)}\s*=.*$", re.M)
    line = f"{key} = {value}"
    return pat.sub(line, text, count=1) if pat.search(text) else text + f"\n{line}\n"

text = set_line(text, "allow net users", user)
text = set_line(text, "allow net networks", "bridge")
p.write_text(text)
print("singularity.conf network ACL updated")
PY
fi

# CNI plugins often look for iptables on a short PATH (need /usr/bin, not only /usr/sbin).
for b in iptables iptables-restore iptables-save ip6tables ip6tables-restore ip6tables-save; do
  if [[ -x "/usr/sbin/$b" && ! -e "/usr/bin/$b" ]]; then
    "${SUDO[@]}" ln -sfn "/usr/sbin/$b" "/usr/bin/$b"
  fi
done

echo
echo "One-time host setup done."
echo
echo "Sudo later?"
echo "  - This script is for Ubuntu laptops that CAN sudo. Skip it entirely on HPC."
echo "  - Build SIF (fakeroot): no sudo after this one-time script."
echo "  - Daily run: AGY_NET_MODE=host (default) — never needs sudo; ports stay on 127.0.0.1."
echo "  - AGY_NET_MODE=bridge: optional; often needs sudo/CNI on desktops; not for HPC without admin."
echo
echo "Next (laptop):"
echo "  ./scripts/build-sif.sh && ./scripts/start-services.sh"
echo "HPC: copy the .sif, skip this script, run start-services (host net)."
