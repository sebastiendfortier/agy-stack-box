# HPC handoff

State: Phase 0 of `harness/CMC-Harness-Plan.md` is closed. Two local commits
(`efb4118`, `015c500`, plus this handoff) carry the tracked harness seeds and
the vault bootstrap. No workstation vault is required on HPC.

## 1. Clone

```bash
git clone https://github.com/sebastiendfortier/agy-stack-box.git
cd agy-stack-box
```

Requires: `apptainer` or `singularity` (CE 3.11+), X11/Wayland for GUI (or
ThinLinc/VNC/`ssh -X`), `node` + `npx` for `fetch-skills.sh`, disk under
`state/` (~1 GB), no sudo.

## 2. Reach the apps and image

Pick one path per component.

SIF:

```bash
# A. copy the prebuilt image from the workstation
scp workstation:src/agy-stack-box/apptainer/agy-stack.sif apptainer/

# B. or build on the cluster (no sudo)
./scripts/build-sif.sh
```

Apps (IDE, Obsidian, `agy`) — if the login node has no egress:

```bash
# on the workstation
rsync -a --relative src/agy-stack-box/state/apps user@hpc:src/agy-stack-box/state/
```

Otherwise run `./scripts/fetch-apps.sh` on a node with internet.

## 3. Configure

```bash
./scripts/setup-config.sh          # run 1: creates state/secrets.env (mode 600)
$EDITOR state/secrets.env          # OPENROUTER_API_KEY, OBSIDIAN_API_KEY, VAULT_HOST_PATH
./scripts/setup-config.sh          # run 2: renders configs + bootstraps the vault
```

- `VAULT_HOST_PATH` must be an absolute path (no `~`). Any writable directory
  works; `setup-config.sh` creates it and seeds `setup/`, `glossary/`,
  `agent-sessions/`, `adrs/`, `lessons/`, `runbooks/` from `harness/`.
- Keep ports unset in `secrets.env` on a shared node; per-uid defaults apply.
- Never commit `state/` or `secrets.env`.

## 4. Skills + CMC profile

```bash
./scripts/fetch-skills.sh          # ponytail + caveman into state/, host mirrors when WIRE_HOST=1
./scripts/seed-cmc-profile.sh      # vault first, harness/ fallback
```

`WIRE_HOST=0` keeps everything inside `state/`. Inspect what was written:

```bash
find state/gemini -path '*cmc-profile*' -type f
```

## 5. Run

```bash
./scripts/start-services.sh        # instance + proxy + Obsidian, host net, no sudo
./scripts/start-ide.sh             # GUI terminal
./scripts/start-cli.sh             # agy, default custom-openrouter-auto
./scripts/stop.sh
```

## Verify

```bash
# proxy health (port from the startup output / uid formula)
curl -fsS http://127.0.0.1:<PROXY_PORT>/healthz

# vault was seeded
ls "$VAULT_HOST_PATH/setup" "$VAULT_HOST_PATH/agent-sessions"

# profile landed
ls state/gemini/antigravity/skills/cmc-profile state/gemini/config/agents
```

## Known gaps (from review)

1. Proxy port is predictable (`30000 + uid%10000*3`) and the proxy has no token
   of its own. On a shared login node other users can reach loopback ports.
   Prefer a personal interactive node until this is tightened.
2. `fetch-apps.sh` downloads without checksum pinning.
3. Host `/usr` overlay hides the SIF's Node; the proxy needs host Node. Not
   listed in prerequisites yet.
4. `seed-cmc-profile.sh` with `WIRE_HOST=1` overwrites host `~/.gemini/GEMINI.md`.
5. HPC Qwen is scaffolded but disabled: set `QWEN_BASE_URL` / `QWEN_MODEL` in
   `state/secrets.env`, re-run `setup-config.sh`, then enable `models/local-qwen`.
6. No CI or shell tests yet.

## Next actions

- Phase 1: document CMC vs personal profile switching; add no-force-push and
  destructive-confirm hooks; session summary to vault.
- Phase 2: discover sitestore/scratch and `cmds-agent-mcp`; add local Qwen model
  entry; retry MarimoHub rootless k3s plan.
- Ask before production paths, mass job submission, or `rm -rf`; never force-push.

## Safety

Keep hostnames, queue names, absolute HPC paths, secrets, and pre-release
products out of prompts and out of this repo. Use placeholders: `<LOGIN_NODE>`,
`<QUEUE>`, `<SITESTORE>`.
