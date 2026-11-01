# agy-stack-box SSM packaging

Builds and deploys the Antigravity stack (IDE / App / CLI + model router inside
an Apptainer SIF) as a CMDS SSM package, following the same convention as
`cmds-pi-agent` / `cmds-opencode-agent` / `cmds-aider-agent`.

## Layout (inside the `.ssm` tarball)

```
agy-stack-box_<version>_all/
  bin/                     agy-ide agy-cli agy-app agy-stop agy-update
  share/lib/common.sh      host-side helpers (copy of scripts/common.sh)
  share/container/         agy-stack-box.sif
  share/agent/AGENTS.md    always-on harness text
  share/templates/         secrets/config templates for first-load seeding
  share/manifest/UPSTREAM.txt  pinned upstream source URLs
  etc/profile.d/<pkg>.sh   SSM load-time environment + per-user seeding
  .ssm.d/control.json      package metadata
```

## Build + validate (local only, no publish)

```bash
./ssm/validate_ssm_package.sh --allow-missing-sif   # structure smoke
./ssm/validate_ssm_package.sh                        # full build with SIF
```

## Deploy (maintainer action)

The deploy target is **never hardcoded** (this repo is public):

```bash
export SSM_DOMAIN_ROOT=<SSM-DOMAIN-ROOT>
./ssm/deploy_ssm_package.py --dry-run   # inspect the publish script
./ssm/deploy_ssm_package.py             # publish + flip latest + prune (keep 3)
```

Optional: `SSM_DEPLOY_SSH_TARGET=user@host` to deploy via SSH,
`VERSION=x.y.z` to pin, `KEEP_SSM_VERSIONS=3` to change retention.

## First-load behaviour (per user)

`ssm use`/`r.load.dot ...latest` sources the profile.d loader, which:

1. Prepends the package `bin/` to `PATH`.
2. Creates `~/.agy-stack/state` (mode 700) on first load; **never overwrites**
   existing state or `secrets.env` (created 0600 only if missing).
   Note: judge seeding by sourcing the loader normally (`bash -c 'source ...'`).
   Piping a sourced script into `head`/`less` runs it in a pipeline subshell —
   `head` closes the pipe, SIGPIPE can kill the seeding mid-run. Test artifact,
   not a loader bug.
3. Copies the always-on `AGENTS.md` into `~/.agy-stack/`.
4. Ports are uid-derived (collision-free per host): proxy/Obsidian triple at
   `30000 + (uid % 10000) * 3`, router at `20000 + (uid % 10000)`.

## Update policy

Nothing auto-updates. A maintainer rebuilds the SIF with new upstream
binaries, runs the feature gates (PLAN-SSM §6), publishes a new dated version,
and flips `latest`. Rollback = repoint `latest`.
Republishing the same date replaces that version dir (`rm -rf` + recreate
before publish).
