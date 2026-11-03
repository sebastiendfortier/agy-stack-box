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
ck "render-mcp-config.py copied"    test -f "$PKGDIR/share/lib/render-mcp-config.py"
ck "AGENTS.md present"              test -f "$PKGDIR/share/agent/AGENTS.md"
ck "AGENTS.md carries PBS rule"     grep -q "pbs_list_jobs" "$PKGDIR/share/agent/AGENTS.md"
ck "AGENTS.md bans raw qstat"       grep -q "qstat" "$PKGDIR/share/agent/AGENTS.md"
for b in agy-ide agy-cli agy-app agy-stop agy-update; do
  ck "bin/$b exec" test -x "$PKGDIR/bin/$b"
done

echo "== metadata =="
ck "control.json parses" python3 -c "import json;json.load(open('$PKGDIR/.ssm.d/control.json'))"
ck "control name ok" python3 -c "import json,sys;sys.exit(0 if json.load(open('$PKGDIR/.ssm.d/control.json'))['name']=='agy-stack-box' else 1)"
ck "control version ok" python3 -c "import json,sys;sys.exit(0 if json.load(open('$PKGDIR/.ssm.d/control.json'))['version']=='$VERSION' else 1)"

echo "== redaction gate (committed files must carry no site paths/secrets) =="
# Scan everything that would be committed from ssm/ (not the SIF, not dist/).
leak() {
  local path_pattern="/$(printf '%s' fs)/"
  local cluster_pattern="$(printf '%s' sk8s)1"
  local site_pattern="science$(printf '%s' .gc.ca)"
  local key_pattern="$(printf '%s' sk)-$(printf '%s' or)-$(printf '%s' v1)"
  grep -rInE "${path_pattern}|hpcr[0-9]|${cluster_pattern}|${site_pattern}|${key_pattern}|IHUB_API_KEY=sk-" "$@"
}
# Scan committed sources (ssm/ minus this validator, which contains the pattern
# itself) plus the packaged bin/, etc/ and .ssm.d/ trees (control.json has
# previously carried the real build host + user).
scan_src=$(find "$DIR" -name validate_ssm_package.sh -prune -o -type f -print)
if leak $scan_src "$PKGDIR/bin" "$PKGDIR/etc" "$PKGDIR/.ssm.d" >/dev/null 2>&1; then
  echo "FAIL  redaction (leaks found)"; FAIL=$((FAIL+1))
  leak "$DIR" "$PKGDIR/bin" "$PKGDIR/etc" "$PKGDIR/.ssm.d" | head -5
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

echo "== first-load MCP render smoke =="
# A fresh install whose secrets.env configures the cmds-agent MCP must end up
# with a rendered mcp_config.json (cmds-agent + bearer token), and a second
# load must not clobber it.
MCP_TMP="$(mktemp -d "${ROOT}/state/apptainer-tmp/validate.XXXXXX")"
MCP_STATE="$MCP_TMP/.agy-stack/state"
mkdir -p "$MCP_STATE/vault"
cat > "$MCP_STATE/secrets.env" <<'MCPSECRETS'
OPENROUTER_API_KEY=
OBSIDIAN_API_KEY=
VAULT_HOST_PATH=/nonexistent-ok-for-render
CMDS_AGENT_MCP_URL=https://cmds.example/skills-mcp
CMDS_AGENT_MCP_TOKEN=tok-validate
WIKI_MCP_URL=
GITLAB_MCP_URL=
MCPSECRETS
chmod 600 "$MCP_STATE/secrets.env"
if SSM_PKG_DIR="$PKGDIR" HOME="$MCP_TMP" AGY_STACK_STATE="$MCP_STATE" bash "$PKGDIR/etc/profile.d/${PKGNAME}.sh" >/dev/null 2>&1; then
  MCP_JSON="$MCP_STATE/gemini/antigravity/mcp_config.json"
  if [[ -f "$MCP_JSON" ]] && python3 -c "
import json, sys
d = json.load(open('$MCP_JSON'))
srv = d.get('mcpServers', {}).get('cmds-agent', {})
sys.exit(0 if srv.get('serverUrl') == 'https://cmds.example/skills-mcp'
             and srv.get('headers', {}).get('Authorization') == 'Bearer tok-validate' else 1)"; then
    # Idempotency: a user-edited config must survive the next load.
    echo '{}' > "$MCP_JSON"
    SSM_PKG_DIR="$PKGDIR" HOME="$MCP_TMP" AGY_STACK_STATE="$MCP_STATE" bash "$PKGDIR/etc/profile.d/${PKGNAME}.sh" >/dev/null 2>&1 || true
    if [[ "$(cat "$MCP_JSON")" == "{}" ]]; then
      echo "PASS  loader renders cmds-agent MCP + preserves edits"; PASS=$((PASS+1))
    else
      echo "FAIL  loader overwrote existing mcp_config.json"; FAIL=$((FAIL+1))
    fi
  else
    echo "FAIL  loader did not render cmds-agent MCP config"; FAIL=$((FAIL+1))
  fi
else
  echo "FAIL  loader errored (MCP smoke)"; FAIL=$((FAIL+1))
fi
rm -rf "$HOME_SMOKETMP" "$TMP" "$MCP_TMP"

# Gate: every shell script the deployer assembles must pass bash -n.
# Catches unterminated quotes in embedded snippets before a maintainer hits
# them months later on a real publish (SSM_KEEP echo once shipped unclosed).
GATE_TMP=$(mktemp -d)
SSM_DOMAIN_ROOT="<VALIDATION-ONLY>" python3 - "$GATE_TMP" <<'PYEOF' || echo "FAIL  deploy scripts assemblable" >&2
import sys, io, contextlib, pathlib, re
sys.path.insert(0, "ssm")
import deploy_ssm_package as d
outdir = pathlib.Path(sys.argv[1])
(outdir / "prune.sh").write_text(d.PRUNE_SNIPPET)
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    d.local_publish(pathlib.Path("/dev/null"), True)
sections, cur = {}, None
for line in buf.getvalue().splitlines():
    if line.startswith("--- dry run:"):
        cur = re.sub(r"\W+", "_", line.split(":", 1)[1].strip().split(" (")[0])
        sections[cur] = []
    elif cur:
        sections[cur].append(line)
for name, lines in sections.items():
    while lines and not lines[-1].strip():
        lines.pop()
    (outdir / f"{name}.sh").write_text("\n".join(lines) + "\n")
PYEOF
GATE_OK=1
for f in "$GATE_TMP"/*.sh; do
  [ -e "$f" ] || { echo "FAIL  no deploy scripts extracted"; FAIL=$((FAIL+1)); GATE_OK=0; break; }
  if bash -n "$f" 2>/dev/null; then
    echo "PASS  bash -n $(basename "$f")"; PASS=$((PASS+1))
  else
    echo "FAIL  bash -n $(basename "$f")"; FAIL=$((FAIL+1)); GATE_OK=0
  fi
done
[ "$GATE_OK" -eq 1 ] || true
rm -rf "$GATE_TMP"

echo
echo "RESULT: $PASS passed, $FAIL failed"
exit $(( FAIL > 0 ? 1 : 0 ))
