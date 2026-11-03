# HPC handoff (next open)

**This session ends on the workstation.** Next time you open the agent: you are on
HPC after cloning this repo. MalSteam II / Android / ONN stay on the workstation —
do not expect `adb` or `Documents/malsteam-ii` on the cluster.

State: Phase 0 of `harness/CMC-Harness-Plan.md` closed. App 2.0 and the other app binaries are baked into the SIF (`/apps` in current builds; older images use `/opt`). Launchers support both paths without per-user app downloads. CMC profile + frontmatter agents are seedable.

## 0. Before you leave the workstation (do once)

```bash
cd ~/src/agy-stack-box
git status   # commit App 2.0 + seed changes if not pushed yet
git push origin main

# Pre-stage the SIF for scp/rsync (login nodes often lack egress)
ls -lh apptainer/agy-stack.sif
```

Optional pack (run on workstation, then copy the tarball):

```bash
tar -C ~/src/agy-stack-box -cvf /tmp/agy-stack-image.tar \
  apptainer/agy-stack.sif
# scp /tmp/agy-stack-image.tar <hpc>:
```

## 1. Clone on HPC

```bash
git clone https://github.com/sebastiendfortier/agy-stack-box.git
cd agy-stack-box
```

Requires: `apptainer` or `singularity` (CE 3.11+), X11/Wayland or ThinLinc/VNC/`ssh -X`
for GUI, `node`+`npx` for skills (or skip host wire), disk under `state/`, **no sudo**. Prefer a personal interactive node (loopback proxy is
reachable by other users on a shared login node).

## 2. Complete image

```bash
# Copy prebuilt SIF OR build on-cluster
# scp workstation:.../apptainer/agy-stack.sif apptainer/
# OR: ./scripts/build-sif.sh
```

Confirm baked app binaries resolve inside the SIF. Resolver prefers `/apps` and supports the existing `/opt` image:

```bash
singularity exec apptainer/agy-stack.sif agy-resolve-app app
singularity exec apptainer/agy-stack.sif agy-resolve-app ide
singularity exec apptainer/agy-stack.sif agy-resolve-app agy
```

## 3. Configure (CMC-safe)

```bash
export WIRE_HOST=0                 # don't overwrite random host ~/.gemini on shared nodes
./scripts/setup-config.sh          # creates state/secrets.env (mode 600)
$EDITOR state/secrets.env
# Required: OPENROUTER_API_KEY, OBSIDIAN_API_KEY, VAULT_HOST_PATH (absolute, no ~)
# Optional HPC: QWEN_BASE_URL, QWEN_MODEL  then re-run setup-config to enable local-qwen
# Leave PROXY_PORT unset → per-uid defaults
./scripts/setup-config.sh          # render + bootstrap vault from harness/
```

Never commit `state/` or `secrets.env`. Redact `<LOGIN_NODE>`, `<QUEUE>`, `<SITESTORE>`
in chats that leave the machine.

## 4. Skills + CMC profile

```bash
WIRE_HOST=0 ./scripts/fetch-skills.sh
WIRE_HOST=0 ./scripts/seed-cmc-profile.sh
find state/gemini -path '*cmc-profile*' -type f | head
ls state/gemini/config/agents   # architect code ops science docs (YAML frontmatter)
```

## 5. Run on HPC

```bash
./scripts/agy-app                  # ensures services, then App 2.0 — multi-agent / plans
./scripts/agy-ide                  # IDE — edit code
./scripts/agy-cli                  # agy TUI
./scripts/agy-stop
```

First App/IDE project on HPC should be **this repo** or a CMC worktree under
sitestore — not MalSteam.

## 6. First HPC agent prompt (paste)

```text
Architect mode. We just cloned agy-stack-box on HPC (no sudo).
Read HPC-HANDOFF.md + harness/CMC-Harness-Plan.md.
1) Verify proxy health and that cmc-profile agents exist.
2) Discover (placeholders only in output): sitestore, scratch, scheduler (PBS vs Slurm), cmds-agent-mcp if present.
3) Propose Phase 1 hooks + enable local Qwen if QWEN_* set — no mass job submit, no prod paths.
```

## Verify

```bash
curl -fsS http://127.0.0.1:${PROXY_PORT:-33000}/healthz
ls "$VAULT_HOST_PATH/setup" "$VAULT_HOST_PATH/agent-sessions"
```

## Known gaps

1. Predictable loopback proxy ports on shared nodes — prefer personal node.
2. Current SIF contains app binaries under `/apps` (verified from the rebuilt image); older images use `/opt` and remain supported by the resolver.
3. Runtime smoke test is blocked: this Singularity install lacks a setuid installation, including under `--fakeroot`. The app already open is still running on its existing `/opt` image; it has not been stopped or replaced.
4. Host `/usr` overlay hides `/usr/local` Node in older images. The rebuilt SIF includes Node under `/apps/node`; validate at runtime before relying on that image.
5. `WIRE_HOST=1` overwrites host `GEMINI.md` — use `WIRE_HOST=0` on HPC.
6. Local Qwen scaffolded via `QWEN_BASE_URL` / `QWEN_MODEL`.

## Safety

No secrets/PII/pre-release products/infra fingerprints to external models.
Confirm before `rm -rf`, mass `qsub`/`sbatch`, production paths. Never force-push.
