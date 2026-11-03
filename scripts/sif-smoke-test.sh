#!/usr/bin/env bash
# Read-only smoke test for the agy-stack SIF.
#
# Answers one question: is this image healthy enough to launch the stack?
# It never starts an instance, a GUI, or a container, and it never writes to
# the repo or to state. Safe to run while the app is up.
#
# Usage:
#   scripts/sif-smoke-test.sh [--sif PATH] [--timeout SECONDS]
#
# Where to run it:
#   * From a host shell (preferred): structural checks plus a real runtime
#     exec probe, which is the only way to prove the image boots here.
#   * Inside the running instance: structural checks and the baked /apps
#     layout; the runtime probe is skipped, because a container cannot nest
#     another runtime in this deployment.
#
# Exit: 0 = all checks passed (skips are allowed), 1 = at least one failure.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIF="${SIF_PATH:-$ROOT/apptainer/agy-stack.sif}"
DEF="$ROOT/apptainer/agy-stack.def"
EXEC_TIMEOUT="${SIF_SMOKE_TIMEOUT:-30}"

pass=0
fail=0
skipped=0
ok()      { printf '  PASS  %s\n' "$*"; pass=$((pass + 1)); }
bad()     { printf '  FAIL  %s\n' "$*"; fail=$((fail + 1)); }
warn()    { printf '  WARN  %s\n' "$*"; }
skipit()  { printf '  SKIP  %s\n' "$*"; skipped=$((skipped + 1)); }
section() { printf '\n%s\n' "$*"; }

usage() {
  sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 2
}

while (($#)); do
  case "$1" in
    --sif)     [[ -n "${2:-}" ]] || usage; SIF="$2"; shift 2 ;;
    --timeout) [[ -n "${2:-}" ]] || usage; EXEC_TIMEOUT="$2"; shift 2 ;;
    -h|--help) usage ;;
    *)         printf 'unknown argument: %s\n' "$1" >&2; usage ;;
  esac
done

inside_container() {
  [[ -n "${SINGULARITY_NAME:-}${APPTAINER_NAME:-}" ]]
}

# ---------------------------------------------------------------------------
section "1. Image file"
if [[ ! -e "$SIF" ]]; then
  bad "image not found: $SIF"
  section "Summary"
  printf '  %d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skipped"
  exit 1
fi
if [[ ! -f "$SIF" || ! -r "$SIF" ]]; then
  bad "image is not a readable regular file: $SIF"
else
  size=$(stat -c %s "$SIF" 2>/dev/null || echo 0)
  if ((size > 100 * 1024 * 1024)); then
    ok "readable, $(numfmt --to=iec --suffix=B "$size" 2>/dev/null || echo "$size bytes")"
  else
    bad "suspiciously small for a stack image: $size bytes (truncated copy?)"
  fi
  mtime=$(stat -c %y "$SIF" 2>/dev/null | cut -d. -f1)
  printf '        mtime: %s  (rebuilds happen on the build host, not here)\n' "$mtime"
fi

# A truncated or stale NFS handle shows up as a failed read, not as a bad size.
if timeout 20 head -c 1048576 "$SIF" >/dev/null 2>&1; then
  ok "header readable"
else
  bad "header read failed (truncation, permission, or stale NFS handle)"
fi
if timeout 20 tail -c 1048576 "$SIF" >/dev/null 2>&1; then
  ok "tail readable (file is not truncated)"
else
  bad "tail read failed (truncated image or stale NFS handle)"
fi

# ---------------------------------------------------------------------------
section "2. SIF structure (no privileges needed)"
if ! command -v singularity >/dev/null 2>&1 && ! command -v apptainer >/dev/null 2>&1; then
  skipit "no singularity/apptainer on PATH, cannot parse the image"
else
  sifbin=$(command -v apptainer || command -v singularity)
  if list_out=$(timeout 20 "$sifbin" sif list "$SIF" 2>&1); then
    if grep -q 'Container id:' <<<"$list_out"; then
      ok "SIF header parses ($sifbin)"
    else
      bad "SIF header unreadable: no container id"
    fi
    if grep -qE 'FS \(Squashfs' <<<"$list_out"; then
      ok "squashfs root filesystem partition present"
    else
      bad "no squashfs partition found (image layout changed or damaged)"
    fi
  else
    bad "sif list failed: $(tail -n 2 <<<"$list_out" | tr '\n' ' ')"
  fi
fi

# ---------------------------------------------------------------------------
section "3. Definition vs image drift"
if [[ ! -f "$DEF" ]]; then
  skipit "no definition file at $DEF"
elif [[ "$DEF" -nt "$SIF" ]]; then
  warn "agy-stack.def is newer than the SIF: rebuild on the build host before shipping"
else
  ok "definition is not newer than the image"
fi

# ---------------------------------------------------------------------------
section "4. Runtime probe"
if inside_container; then
  skipit "running inside the instance; nested runtime is unsupported here"
  printf '        rerun from a host shell (outside the container) for a real boot test\n'
else
  if command -v apptainer >/dev/null 2>&1; then
    rt=apptainer
  elif command -v singularity >/dev/null 2>&1; then
    rt=singularity
  else
    rt=""
  fi
  if [[ -z "$rt" ]]; then
    bad "no singularity/apptainer on PATH"
  else
    probe_err=$(timeout "$EXEC_TIMEOUT" "$rt" exec --cleanenv "$SIF" /bin/true 2>&1)
    probe_rc=$?
    if ((probe_rc == 0)); then
      ok "$rt exec /bin/true succeeded (image boots on this host)"
    elif ((probe_rc == 124)); then
      bad "$rt exec timed out after ${EXEC_TIMEOUT}s (stalled storage or hung runtime)"
    else
      bad "$rt exec failed (rc=$probe_rc): $(tail -n 2 <<<"$probe_err" | tr '\n' ' ')"
      printf '        note: run this from a host shell; a setuid/userns message here means\n'
      printf '        the runtime install is misconfigured, not that the image is broken\n'
    fi
  fi
fi

# ---------------------------------------------------------------------------
section "5. Baked stack layout"
if ! inside_container; then
  skipit "layout checks inspect the live instance; start the app to run them"
else
  for f in \
    /apps/node/bin/node \
    /apps/antigravity-app/Antigravity-x64/antigravity \
    /apps/agy \
    /opt/agy-stack/host-scripts/libnoshm.so
  do
    if [[ -x "$f" || -f "$f" ]]; then
      ok "present: $f"
    else
      bad "missing: $f"
    fi
  done
  if node_v=$(/apps/node/bin/node --version 2>/dev/null); then
    ok "node $node_v"
  else
    bad "node does not run: /apps/node/bin/node"
  fi
  vfile=/apps/antigravity-app/Antigravity-x64/version
  if [[ -r "$vfile" ]]; then
    printf '        electron bundle version: %s\n' "$(head -n1 "$vfile")"
  fi
fi

# ---------------------------------------------------------------------------
section "6. Launcher session markers (read-only)"
session_dirs=("$ROOT"/state/hosts/*/sessions)
if [[ ! -d "${session_dirs[0]}" ]]; then
  skipit "no session directory yet"
elif inside_container; then
  # Markers hold host PIDs; this PID namespace cannot see them, so every
  # liveness test would be a false "stale". Count them and say why.
  n=0
  for f in "${session_dirs[@]}"/*; do [[ -f "$f" ]] && n=$((n + 1)); done
  skipit "$n marker(s) present; liveness needs a host shell (PID namespaces differ)"
else
  live=0
  stale=0
  for f in "${session_dirs[@]}"/*; do
    [[ -f "$f" ]] || continue
    pid=$(awk '{print $NF}' "$f" 2>/dev/null)
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
      live=$((live + 1))
    else
      stale=$((stale + 1))
      warn "stale session marker: ${f##*/} (from $(cut -d' ' -f1 "$f")); launcher cleanup will remove it"
    fi
  done
  if ((live > 0)); then
    ok "$live live session marker(s)"
  fi
  if ((stale == 0 && live == 0)); then
    skipit "no session markers to check"
  fi
fi

# ---------------------------------------------------------------------------
section "Summary"
printf '  %d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skipped"
if ((fail > 0)); then
  printf '  RESULT: FAIL\n'
  exit 1
fi
printf '  RESULT: PASS\n'
exit 0
