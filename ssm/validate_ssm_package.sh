#!/usr/bin/env bash
# Build + validate the agy-stack-box SSM package locally. NO publishing.
# Exit non-zero on any failed check.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${DIR}/.." && pwd)"
VERSION="${VERSION:-$(date +%Y.%m.%d)}"
ALLOW_MISSING_SIF=""
[[ "${1:-}" == "--allow-missing-sif" ]] && ALLOW_MISSING_SIF="--allow-missing-sif"

PASS=0; FAIL=0
ck() { # ck <name> <cmd...>
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "PASS  $name"; PASS=$((PASS+1))
  else
    echo "FAIL  $name"; FAIL=$((FAIL+1))
  fi
}

echo "== build =="
bash "$DIR/make_ssm_package.sh" $ALLOW_MISSING_SIF
PKGNAME="agy-stack-box_${VERSION}_all"
SSM="${ROOT}/dist/${PKGNAME}.ssm"
[[ -f "$SSM" ]] || { echo "FATAL: $SSM not built"; exit 1; }

TMP="$(mktemp -d "${ROOT}/state/apptainer-tmp/validate.XXXXXX")"
tar -xzf "$SSM" -C "$TMP"
PKGDIR="$TMP/$PKGNAME"

echo "== structure =="
ck "control.json exists"            test -f "$PKGDIR/.ssm.d/control.json"
ck "profile.d loader exists"        test -f "$PKGDIR/etc/profile.d/${PKGNAME}.sh"
ck "common.sh copied"               test -f "$PKGDIR/share/lib/common.sh"
ck "AGENTS.md present"              test -f "$PKGDIR/share/agent/AGENTS.md"
for b in agy-ide agy-cli agy-app agy-stop agy-update; do
  ck "bin/$b exec" test -x "$PKGDIR/bin/$b"
done

echo "== metadata =="
ck "control.json parses" python3 -c "import json;json.load(open('$PKGDIR/.ssm.d/control.json'))"
ck "control name ok" python3 -c "import json,sys;sys.exit(0 if json.load(open('$PKGDIR/.ssm.d/control.json'))['name']=='agy-stack-box' else 1)"
ck "control version ok" python3 -c "import json,sys;sys.exit(0 if json.load(open('$PKGDIR/.ssm.d/control.json'))['version']=='$VERSION' else 1)"

echo "== redaction gate (committed files must carry no site paths/secrets) =="
# Scan everything that would be committed from ssm/ (not the SIF, not dist/).
leak() { grep -rInE '/fs/|hpcr[0-9]|sk8s1|science\.gc\.ca|sk-or-v1|IHUB_API_KEY=sk-' "$@"; }
# Scan committed sources (ssm/ minus this validator, which contains the pattern
# itself) plus the packaged bin/ and etc/ trees.
scan_src=$(find "$DIR" -name validate_ssm_package.sh -prune -o -type f -print)
if leak $scan_src "$PKGDIR/bin" "$PKGDIR/etc" >/dev/null 2>&1; then
  echo "FAIL  redaction (leaks found)"; FAIL=$((FAIL+1))
  leak "$DIR" "$PKGDIR/bin" "$PKGDIR/etc" | head -5
else
  echo "PASS  redaction"; PASS=$((PASS+1))
fi

echo "== loader idempotency smoke =="
HOME_SMOKETMP="$(mktemp -d "${ROOT}/state/apptainer-tmp/validate.XXXXXX")"
if SSM_PKG_DIR="$PKGDIR" HOME="$HOME_SMOKETMP" bash "$PKGDIR/etc/profile.d/${PKGNAME}.sh" >/dev/null 2>&1 \
   && SSM_PKG_DIR="$PKGDIR" HOME="$HOME_SMOKETMP" bash "$PKGDIR/etc/profile.d/${PKGNAME}.sh" >/dev/null 2>&1; then
  if [[ -d "$HOME_SMOKETMP/.agy-stack/state" && -f "$HOME_SMOKETMP/.agy-stack/state/secrets.env" ]]; then
    perm=$(stat -c '%a' "$HOME_SMOKETMP/.agy-stack/state")
    permf=$(stat -c '%a' "$HOME_SMOKETMP/.agy-stack/state/secrets.env")
    if [[ "$perm" == "700" && "$permf" == "600" ]]; then
      echo "PASS  loader seeds state 700 + secrets 600"; PASS=$((PASS+1))
    else
      echo "FAIL  loader perms (state=$perm secrets=$permf)"; FAIL=$((FAIL+1))
    fi
  else
    echo "FAIL  loader did not seed state"; FAIL=$((FAIL+1))
  fi
else
  echo "FAIL  loader errored"; FAIL=$((FAIL+1))
fi
rm -rf "$HOME_SMOKETMP" "$TMP"

echo
echo "RESULT: $PASS passed, $FAIL failed"
exit $(( FAIL > 0 ? 1 : 0 ))
