# ADR: SSM Phase 1 acceptance — agy-stack-box package

- **Status**: Accepted (Architect verdict 2026-11-01, conditional gates all closed)
- **Branch**: `feat/ssm-phase1` — `b005c47` (Phase 1) → `42b4f45` (loader fix) → `7b4fb87` (SIGPIPE doc) → `e279dd7` (dry-run append) → `053ece4` (this ADR) → `70474c8` (PRUNE_SNIPPET quote fix)
- **Scope**: SSM packaging only (make / setup / deploy / validate / bin wrappers). Router rewrite, SIF app-baking, hooks = later phases (PLAN-SSM §roadmap).

## Decision 1 — Package layout (sibling parity)

`agy-stack-box_<version>_all/` follows the cmds-pi-agent / cmds-opencode-agent /
cmds-aider-agent convention: `bin/`, `share/{lib,container,agent,templates,manifest}`,
`etc/profile.d/<pkg>.sh`, `.ssm.d/control.json`. Built by `ssm/make_ssm_package.sh`
(sorted, normalized tarball; SIF copied from `apptainer/agy-stack.sif` when present,
`--allow-missing-sif` builds structure-only).

## Decision 2 — Deploy target is env-var only (public repo)

`SSM_DOMAIN_ROOT` is **never hardcoded** — the repo is public
(github.com:sebastiendfortier/agy-stack-box + gitlab mirror). Without it,
`ssm/deploy_ssm_package.py` exits **2** with a message pointing at the env var.
Committed files use placeholders (`<SSM_DOMAIN_ROOT>`, `<UPSTREAM-*-URL>`).
Publish flow: master install → dated version dir → atomic `latest` flip
(`ln -sfn` → `.latest.tmp` → `mv -Tf`) → prune (keep 3, `SSM_PRUNE_SKIP` guard
on latest's target **before** any rm). Local publish dry-run previews both the
publish script and the post-publish prune script (parity with SSH path).
Republishing the same date replaces that version dir.

## Decision 3 — control.json in python3, no bundled node

`.ssm.d/control.json` schema matches sibling packages; validated with
`python3 -c "import json,sys; json.load(open(sys.argv[1]))"` — avoids bundling
a node runtime just for a gate check.

## Decision 4 — uid-derived ports (collision-free per host)

- proxy/Obsidian triple: `30000 + (uid % 10000) * 3` … `+2`
- model router: `20000 + (uid % 10000)`

Ranges are disjoint ([30000,59999] vs [20000,29999]); `uid % 10000` is
injective within each family. Documented in the loader and README.

## Decision 5 — Loader fixes (`42b4f45`)

- **Root resolution**: works from installed package (`etc/profile.d` → `../..`)
  AND repo checkout (`ssm/` → `..`) via ancestor-detection loop (pick dir with
  `share/` or `config/templates`).
- **Parent perms**: `chmod 700` on `~/.agy-stack` itself, not only `state/`.
- **Template fallback**: `share/templates/env.example` then
  `config/templates/env.example`. `secrets.env` created 0600 only if missing —
  never overwritten; user fills it once.
- **SIGPIPE note** (`7b4fb87`): judge seeding by sourcing normally; piping a
  sourced script into `head` runs it in a pipeline subshell and SIGPIPE can
  truncate seeding. Test-harness artifact, not a loader bug.

## Known limitations

- **Runtime verification pending**: this sandbox is a nested container
  (singularity-session overlay root, gpfs `nosuid` home) — singularity 3.8.4
  cannot execute SIFs here ("No setuid installation found"). Static validation
  (14/14) stands; runtime smoke test belongs on the real host (Phase 2 item).
- **UPSTREAM.txt placeholders** (`<UPSTREAM-*-URL>`) resolve in Phase 5.
- **Pre-existing main-branch redaction matches** (build-sif.sh absolute-path
  checks, common.sh webproxy URL, mcp_config.tmpl internal URLs) — out of
  Phase 1 scope; hygiene task for maintainer decision before the repo goes public.

## Validation record

- `ssm/validate_ssm_package.sh`: **14/14 PASS** (twice, incl. real ~1 GB SIF;
  SIF ops under `state/apptainer-tmp`, not `/tmp` — tmpfs too small).
- Architect acceptance battery: gates [0]–[5], [7]–[10] PASS + [6] re-run
  PASS (dry-run verbatim + prune block) → **ACCEPTED**.
- Redaction grep: all Phase-1 files clean; matches only in pre-existing main files.

## Publish is a maintainer action

Nothing pushes or publishes automatically. The maintainer runs
`ssm/deploy_ssm_package.py` with `SSM_DOMAIN_ROOT` set when they say "deploy";
`latest` flips only on publish.
