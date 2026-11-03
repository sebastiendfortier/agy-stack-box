#!/usr/bin/env bash
# Test the GUI host gate (require_vis_host) without launching any instance.
# A fake `hostname` binary lets us simulate vis and non-vis hosts.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/agy-visgate.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

pass=0 fail=0

# Expect exit code $1 with output containing $2 when running $3 (a bash -c snippet).
check() {
  local want_code="$1" want_out="$2" snippet="$3"
  local out code
  out="$(bash -c "$snippet" 2>&1)"; code=$?
  if [[ "$code" == "$want_code" ]] && [[ "$out" == *"$want_out"* ]]; then
    echo "ok   : $snippet"
    pass=$((pass + 1))
  else
    echo "FAIL : $snippet (code=$code, want=$want_code)"
    echo "      output: $out"
    fail=$((fail + 1))
  fi
}

# Fake hostname that prints a fixed short name.
fake_hostname() {
  local dir="$TMP/fakebin-$1" name="$2"
  mkdir -p "$dir"
  cat > "$dir/hostname" <<EOF
#!/bin/sh
echo "$name"
EOF
  chmod +x "$dir/hostname"
  echo "$dir"
}

VIS_BIN="$(fake_hostname vis hpcr7-vis1)"
IN_BIN="$(fake_hostname in hpcr7-in1)"
AZ_BIN="$(fake_hostname az azathoth2)"

# 1. Function-level: vis host passes, others die with the pointer message.
check 0 "" "
  export PATH='$VIS_BIN':\"\$PATH\"
  source '$ROOT/scripts/common.sh'
  require_vis_host
"
check 1 "run on hpcr-vis hosts only" "
  export PATH='$IN_BIN':\"\$PATH\"
  source '$ROOT/scripts/common.sh'
  require_vis_host
"
check 1 "Use 'agy-cli' here" "
  export PATH='$AZ_BIN':\"\$PATH\"
  source '$ROOT/scripts/common.sh'
  require_vis_host
"

# 2. Override: AGY_FORCE_GUI_HOST=1 lets any host through.
check 0 "" "
  export PATH='$AZ_BIN':\"\$PATH\" AGY_FORCE_GUI_HOST=1
  source '$ROOT/scripts/common.sh'
  require_vis_host
"

# 3. Launcher level: agy-app / agy-ide refuse on a non-vis host before doing
#    any secrets/instance work; agy-cli must NOT be gated (it gets past the
#    gate and fails later for an unrelated reason, e.g. missing secrets).
check 1 "run on hpcr-vis hosts only" "
  export PATH='$IN_BIN':\"\$PATH\"
  exec '$ROOT/scripts/agy-app'
"
check 1 "run on hpcr-vis hosts only" "
  export PATH='$IN_BIN':\"\$PATH\"
  exec '$ROOT/scripts/agy-ide'
"
out="$(PATH="$IN_BIN:$PATH" AGY_STACK_STATE="$TMP/empty-state" "$ROOT/scripts/agy-cli" --version 2>&1 || true)"
if [[ "$out" != *"run on hpcr-vis hosts only"* ]]; then
  echo "ok   : agy-cli not gated on non-vis host"
  pass=$((pass + 1))
else
  echo "FAIL : agy-cli was gated on a non-vis host"
  fail=$((fail + 1))
fi

# 4. SSM wrapper layout: bin/agy-app + share/lib/common.sh must carry the gate.
PKG="$TMP/ssmpkg"
mkdir -p "$PKG/bin" "$PKG/share/lib"
cp "$ROOT/ssm/wrappers/agy-app" "$PKG/bin/agy-app"
cp "$ROOT/ssm/wrappers/agy-ide" "$PKG/bin/agy-ide"
cp "$ROOT/scripts/common.sh" "$PKG/share/lib/common.sh"
chmod +x "$PKG"/bin/*
check 1 "run on hpcr-vis hosts only" "
  export PATH='$AZ_BIN':\"\$PATH\"
  exec '$PKG/bin/agy-app'
"
check 1 "run on hpcr-vis hosts only" "
  export PATH='$AZ_BIN':\"\$PATH\"
  exec '$PKG/bin/agy-ide'
"

echo
echo "vis-host-gate: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
