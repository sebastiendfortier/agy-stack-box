#!/usr/bin/env python3
"""Deploy the agy-stack-box SSM to the CMDS SSM domain.

The domain root comes from the environment (SSM_DOMAIN_ROOT) — never hardcoded,
this repo is public. Publishes to <root>/master, creates a dated version dir,
flips `latest` atomically, prunes old versions (keep 3 by default).

Usage:
  SSM_DOMAIN_ROOT=/path ssm/deploy_ssm_package.py [--dry-run] [--prune-only]
Env:
  SSM_DOMAIN_ROOT    (required) domain directory, e.g. <SSM-DOMAIN-ROOT>
  SSM_DEPLOY_SSH_TARGET (optional) remote user@host; unset = deploy locally
  VERSION            (optional) overrides the version in dist/
  KEEP_SSM_VERSIONS  (optional, default 3)
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path

NAME = "agy-stack-box"
VERSION = os.environ.get("VERSION", "")
KEEP = int(os.environ.get("KEEP_SSM_VERSIONS", "3"))
DOMAIN_ROOT = os.environ.get("SSM_DOMAIN_ROOT", "")
SSH_TARGET = os.environ.get("SSM_DEPLOY_SSH_TARGET", "")

if KEEP < 1:
    raise ValueError("KEEP_SSM_VERSIONS must be at least 1")
if not DOMAIN_ROOT:
    print(
        "error: SSM_DOMAIN_ROOT is not set.\n"
        "  This repo is public — the deploy target is never hardcoded.\n"
        "  Export it, e.g.:  export SSM_DOMAIN_ROOT=<SSM-DOMAIN-ROOT>",
        file=sys.stderr,
    )
    sys.exit(2)

ROOT = Path(__file__).resolve().parents[1]
if not VERSION:
    # Derive the version from the newest built artifact in dist/.
    dist = ROOT / "dist"
    artifacts = sorted(dist.glob(f"{NAME}_*_all.ssm"))
    if not artifacts:
        print(f"error: no {NAME}_*_all.ssm in {dist} — run ssm/make_ssm_package.sh first", file=sys.stderr)
        sys.exit(1)
    VERSION = artifacts[-1].name[len(NAME) + 1 : -len("_all.ssm")]

PKG = f"{NAME}_{VERSION}_all"

# Shared by publish and prune-only runs. YYYY.MM.DD dirs sort lexically.
PRUNE_SNIPPET = r"""
KEEP={keep}
PKGNAME={name}
cd "$DOMAIN_ROOT"
mapfile -t VERS < <(compgen -G '[0-9][0-9][0-9][0-9]\.[0-9][0-9]\.[0-9][0-9]' | sort -r)
if [ "${{#VERS[@]}}" -gt "$KEEP" ]; then
  for old in "${{VERS[@]:$KEEP}}"; do
    if [ -L latest ] && [ "$(readlink latest)" = "$old" ]; then
      echo "SSM_PRUNE_SKIP latest=$old"
      continue
    fi
    echo "SSM_PRUNE $old"
    if [ -d master ]; then
      ssm uninstall -d "$(cd master && pwd -P)" -p "${{PKGNAME}}_${{old}}_all" 2>/dev/null || true
      rm -rf "master/${{PKGNAME}}_${{old}}_all"
    fi
    rm -f "ssm_packages/${{PKGNAME}}_${{old}}_all.ssm"
    rm -rf "$old"
  done
fi
echo "SSM_KEEP $(compgen -G '[0-9][0-9][0-9][0-9]\.[0-9][0-9]\.[0-9][0-9]' | sort -r | tr '\n' ' ')"
""".format(
    keep=KEEP, name=NAME
)


def run(cmd: list[str] | str, **kw):
    print("+", cmd if isinstance(cmd, str) else " ".join(cmd))
    return subprocess.run(cmd, check=True, **kw)


def ssh_remote(script_body: str, dry_run: bool) -> None:
    if dry_run:
        print("--- dry run: remote script ---")
        print(script_body)
        return
    fd, script = tempfile.mkstemp(suffix=".sh", prefix="agy_stack_deploy_")
    os.close(fd)
    path = Path(script)
    path.write_text(script_body)
    os.chmod(path, 0o755)
    try:
        remote_script = f"/tmp/{path.name}"
        run(["scp", "-o", "BatchMode=yes", str(path), f"{SSH_TARGET}:{remote_script}"])
        run(
            [
                "ssh",
                "-o",
                "BatchMode=yes",
                SSH_TARGET,
                f"ORDENV_SESSION_TYPE=interactive ORDENV_SETUP=0 bash -i -l -c 'bash {remote_script}'",
            ]
        )
    finally:
        path.unlink(missing_ok=True)


def local_publish(dest: Path, dry_run: bool) -> None:
    steps = f"""set -e
DOMAIN_ROOT="{DOMAIN_ROOT}"
mkdir -p "$DOMAIN_ROOT"
cd "$DOMAIN_ROOT"
if [ ! -d master ]; then ssm created -d master; fi
cd master
ssm uninstall -d "$(pwd -P)" -p {PKG} 2>/dev/null || true
ssm install -d "$(pwd -P)" -p {PKG} -f {dest}
cd ..
mkdir -p ssm_packages
cp -f {dest} ssm_packages/{PKG}.ssm || true
VERDIR="{VERSION}"
rm -rf "$VERDIR"
mkdir -p "$VERDIR"
ssm created -d "$VERDIR"
ssm publish --verbose -pp all -d "$(pwd -P)/master" -p {PKG} -P "$(pwd -P)/$VERDIR"
# Atomic latest flip: symlink to temp name, then rename over the old link.
ln -sfn "$VERDIR" "${{DOMAIN_ROOT}}/.latest.tmp"
mv -Tf "${{DOMAIN_ROOT}}/.latest.tmp" "${{DOMAIN_ROOT}}/latest"
echo "SSM_PUBLISH_OK $DOMAIN_ROOT/$VERDIR"
echo "SSM_LATEST_OK $DOMAIN_ROOT/latest -> $VERDIR"
"""
    if dry_run:
        print("--- dry run: local publish script ---")
        print(steps)
        # Preview exactly what executes after publish: prune runs as a
        # separate bash -c invocation (same content as the SSH path's tail).
        print("--- dry run: local prune script (runs after publish) ---")
        print(f'cd "{DOMAIN_ROOT}"\n{PRUNE_SNIPPET}')
        return
    fd, script = tempfile.mkstemp(suffix=".sh", prefix="agy_stack_publish_")
    os.close(fd)
    path = Path(script)
    path.write_text(steps)
    os.chmod(path, 0o755)
    try:
        run(["bash", str(path)])
    finally:
        path.unlink(missing_ok=True)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dry-run", action="store_true", help="print the publish script, do not run it")
    ap.add_argument("--prune-only", action="store_true", help="only prune old dated versions (no publish)")
    args = ap.parse_args()

    if args.prune_only:
        if SSH_TARGET:
            ssh_remote(f'#!/bin/bash\nset -e\nDOMAIN_ROOT="{DOMAIN_ROOT}"\n{PRUNE_SNIPPET}\n', args.dry_run)
        else:
            local_prune = f'#!/bin/bash\nset -e\nDOMAIN_ROOT="{DOMAIN_ROOT}"\ncd "$DOMAIN_ROOT"\n{PRUNE_SNIPPET}\n'
            if args.dry_run:
                print("--- dry run: prune script ---")
                print(local_prune)
            else:
                run(["bash", "-c", local_prune])
        print("prune completed")
        return 0

    ssm_path = ROOT / "dist" / f"{PKG}.ssm"
    if not ssm_path.exists():
        run(["bash", str(ROOT / "ssm" / "make_ssm_package.sh")], cwd=str(ROOT))
    if not ssm_path.is_file():
        raise FileNotFoundError(ssm_path)
    os.chmod(ssm_path.resolve(), 0o644)
    print(f"Package {ssm_path.resolve()} (keep last {KEEP})")
    if SSH_TARGET:
        ssh_remote(
            f"""#!/bin/bash
set -e
DOMAIN_ROOT="{DOMAIN_ROOT}"
mkdir -p "$DOMAIN_ROOT"
cd "$DOMAIN_ROOT"
if [ ! -d master ]; then ssm created -d master; fi
cd master
ssm uninstall -d "$(pwd -P)" -p {PKG} 2>/dev/null || true
ssm install -d "$(pwd -P)" -p {PKG} -f {ssm_path.resolve()}
cd ..
mkdir -p ssm_packages
cp -f {ssm_path.resolve()} ssm_packages/{PKG}.ssm || true
VERDIR="{VERSION}"
rm -rf "$VERDIR"
mkdir -p "$VERDIR"
ssm created -d "$VERDIR"
ssm publish --verbose -pp all -d "$(pwd -P)/master" -p {PKG} -P "$(pwd -P)/$VERDIR"
ln -sfn "$VERDIR" "${{DOMAIN_ROOT}}/.latest.tmp"
mv -Tf "${{DOMAIN_ROOT}}/.latest.tmp" "${{DOMAIN_ROOT}}/latest"
echo "SSM_PUBLISH_OK $DOMAIN_ROOT/$VERDIR"
echo "SSM_LATEST_OK $DOMAIN_ROOT/latest -> $VERDIR"
{PRUNE_SNIPPET}
""",
            args.dry_run,
        )
    else:
        local_publish(ssm_path.resolve(), args.dry_run)
        if not args.dry_run:
            run(["bash", "-c", f'cd "{DOMAIN_ROOT}"\n{PRUNE_SNIPPET}'])
    print("deploy completed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
