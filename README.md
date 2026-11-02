# agy-stack-box

A Singularity / Apptainer image with apps baked under `/opt`:

- **In the SIF:** OpenRouter BYOK proxy + Node + Electron libs + Antigravity IDE, App 2.0, Obsidian AppImage, `agy` CLI
- **Optional override:** `./scripts/fetch-apps.sh` → `state/apps/` (preferred by `agy-resolve-app` when present)

Proxy and Obsidian REST bind loopback only. Default networking is **host net** (`AGY_NET_MODE=host`) — **no sudo**. Ports and instance name default **per-uid** so multiple users on one node do not collide.

## Clone on RHEL / HPC / Ubuntu

```bash
git clone https://github.com/sebastiendfortier/agy-stack-box.git
cd agy-stack-box
```

### Host prerequisites

- `apptainer` **or** `singularity` (CE 3.11+) — normal user `instance start` is enough
- X11 or Wayland for IDE/Obsidian windows (HPC: often via ThinLinc / VNC / SSH `-X`)
- Disk for the SIF + Electron state under `state/`
- An Obsidian vault on the host with **Local REST API** installed (API key will match `OBSIDIAN_API_KEY`)

#### HPC (no sudo)

Skip `enable-local-build.sh` and bridge mode. Prefer building the SIF on a laptop/CI, or on the cluster with `./scripts/build-sif.sh` (that script **unsets** `APPTAINER_BIND` / `SINGULARITY_BIND*` for the build only — HPC module binds often break `%post`; they stay in effect for `start-services` / run). Then:

```bash
./scripts/setup-config.sh     # creates a fresh local vault from harness/ if VAULT_HOST_PATH is new
./scripts/fetch-apps.sh
./scripts/fetch-skills.sh     # ponytail + caveman into state/ (+ host Cursor/agy when WIRE_HOST=1)
./scripts/seed-cmc-profile.sh # CMC modes + profile; prefers vault, falls back to harness/
./scripts/start-services.sh   # AGY_NET_MODE=host by default — no sudo (or just run agy-ide)
```

No workstation vault needed: `setup-config.sh` creates `VAULT_HOST_PATH` when missing and seeds `setup/`, `glossary/`, `agent-sessions/`, `adrs/`, `lessons/`, `runbooks/` from `harness/`. Re-run `./scripts/init-vault.sh [path]` any time to add missing stubs (never overwrites).

#### Ubuntu laptop local builds (sudo once)

Ubuntu 24.04+ sets `kernel.apparmor_restrict_unprivileged_userns=1`, which breaks `singularity build --fakeroot`. One-time laptop fix:

```bash
./scripts/enable-local-build.sh   # needs sudo once; not used on HPC
./scripts/build-sif.sh            # then as normal user
```

### 1. Configure (secrets stay local)

```bash
./scripts/setup-config.sh          # creates state/secrets.env
# edit state/secrets.env:
#   OPENROUTER_API_KEY=...
#   OBSIDIAN_API_KEY=...
#   VAULT_HOST_PATH=/path/to/vault
./scripts/setup-config.sh          # render custom_models + MCP + IDE settings
./scripts/fetch-apps.sh            # download IDE + Obsidian + agy into state/apps (~0.5GB+)
./scripts/fetch-skills.sh          # ponytail + caveman for CLI/IDE (and host Cursor if present)
./scripts/seed-cmc-profile.sh      # CMC profile/modes; vault first, then harness/
```

Never commit `state/` or `secrets.env`.

### Skills: ponytail + caveman

`fetch-skills.sh` installs [ponytail](https://github.com/DietrichGebert/ponytail) and [caveman](https://github.com/JuliusBrussee/caveman) into `state/gemini/` (instance `$HOME/.gemini`) so CLI/IDE inside the stack see them.

With `WIRE_HOST=1` (default) it also wires the **host** account:

- **Cursor:** always-on user rules (`~/.cursor/rules/ponytail.mdc`, `caveman-ultracave.mdc`) at **ultra** / **ultracave** — no `/ponytail` or `/caveman` needed
- **agy CLI:** plugins + always-on plugin rules (same modes)
- **Antigravity IDE:** skills + `config/rules/` always-on rules

Set `WIRE_HOST=0` to only refresh `state/`. Defaults live in `~/.config/ponytail/config.json` and `~/.config/caveman/config.json`.

### CMC harness (vault optional)

`harness/` holds tracked copies of the CMC plan, questionnaire (`status: partial`), profile, glossary stub, and `agent-sessions/` template. `seed-cmc-profile.sh` writes the always-on rule `config/rules/cmc-profile.md`, the `cmc-profile` skill, the Architect/Code/Ops/Science/Docs agents, and references for the glossary + plan.

Source order: vault (`$VAULT_HOST_PATH`) first, then `harness/`. Overrides: `CMC_VAULT_ROOT`, `CMC_PROFILE_SRC`, `CMC_GLOSSARY_SRC`, `CMC_SEED_DIR`. `init-vault.sh` bootstraps a local vault from `harness/` (called by `setup-config.sh`), so an HPC clone never depends on the workstation vault.

Redact hostnames, queues, absolute HPC paths, and secrets before committing changes under `harness/` — this repo may be public.

### 2. Get the slim image

Laptop (with fakeroot enabled once):

```bash
./scripts/build-sif.sh            # does NOT embed IDE/Obsidian/agy
```

HPC: copy a prebuilt `apptainer/agy-stack.sif`, or build on-cluster with `build-sif.sh` (clears bind env for build only).

Pinned BYOK proxy: `antigravity-add-model` @ `f793635`. App URLs are in `scripts/fetch-apps.sh`.

### 3. Run

```bash
./scripts/agy-ide                  # ensures instance + proxy + Obsidian, then IDE
./scripts/agy-app                  # Antigravity App 2.0 (multi-agent desktop, no IDE)
./scripts/agy-cli                  # defaults to --model custom-openrouter-auto
./scripts/agy-cli models
./scripts/agy-stop                 # or stop.sh (wrapper)
```

Headless nodes (SSH login/ppp, no X11/Wayland): `ensure_services` skips the Obsidian GUI automatically — the vault stays bind-mounted and the CLI/proxy/router are unaffected (`AGY_FORCE_OBSIDIAN=1` overrides). IDE/App still need a display; run them on vis/ThinLinc.

OpenRouter entries in the native picker / `agy models`:

- `OpenRouter Auto` (`custom-openrouter-auto`)
- `OpenRouter Gemini 2.5 Pro`
- `OpenRouter Claude Sonnet 4.5`

### When the paid rung is unavailable

`Auto (SG Qwen → OpenRouter)` (`custom-auto-ladder`) degrades instead of going blank:

| Situation | Result |
|---|---|
| Free tier answers | Answer, no OpenRouter spend |
| Hard task, OpenRouter reachable | Escalated answer |
| OpenRouter out of credits / key missing / down | Free tier's answer, `x-router-degraded` header, logged |
| Both tiers fail | HTTP 502 telling you to switch to a Google model (free with your Antigravity account) |
| No model credentials at all | HTTP 503 naming the missing variable |

The router cannot call Google's built-in models itself — they authenticate with the
Antigravity account, not an API key — so that last case is a message, not a reroute.
A failed escalation no longer marks the conversation sticky, so one dead OpenRouter
call cannot blank out the next five minutes of replies. Set `policy.fallbackDown: false`
in `state/router/config.json` to disable the fallback.

## Layout

```text
apptainer/agy-stack.def          # image definition
apptainer/rootfs-scripts/        # in-image wrappers (agy, ide, proxy, obsidian)
scripts/                         # host orchestration (incl. fetch-skills.sh)
harness/                         # tracked CMC plan/profile/glossary/agent-sessions seed
config/templates/                # secret-free templates
state/                           # local only (gitignored): apps, gemini, secrets
```

## Networking model

### What is isolated vs shared

This is a **Singularity/Apptainer instance** (full Linux rootfs for the stack), not a chroot that shares the host `/usr`:

| | Inside the instance |
|---|---|
| **Internet** | Shared with the host (`AGY_NET_MODE=host`) — OpenRouter/HTTPS work |
| **Your files** | Real `$HOME` + vault binds; add scratch/projects via `AGY_EXTRA_BINDS` |
| **OS tools** | Host `/usr` `/bin` `/lib*` overlaid by default (`AGY_HOST_OS_TOOLS=1`) |
| **HPC modules / PATH** | Login `PATH`, `LD_LIBRARY_PATH`, `MODULEPATH`, … are passed in; those directories (and common roots like `/cvmfs`, `/scratch`) are bind-mounted (`AGY_HOST_PATH_BINDS=1`) so `module load` tools work in IDE terminals and `agy` |
| **Stack apps** | IDE / Obsidian / `agy` / OpenRouter proxy from `state/apps` + SIF `/opt` |

Site `APPTAINER_BIND` / `SINGULARITY_BIND*` still apply at **run**; `build-sif.sh` unsets them only while **building**.

Default (`AGY_NET_MODE=host`, recommended for HPC and most desktops):

- Shares the host network namespace — **no sudo, no CNI**
- Proxy / Obsidian still bind `127.0.0.1` only (not reachable from other machines on the LAN)
- OpenRouter egress uses the host’s normal outbound path
- Start-ide/cli still `exec` into the instance
- **Multi-user ports:** `INSTANCE_NAME`, `PROXY_PORT`, `OBSIDIAN_REST_PORT`, and `OBSIDIAN_HTTPS_PORT` default from your uid so two users on one login node do not collide. Do **not** hardcode `50999` / `27123` in `secrets.env` on shared hosts. `setup-config.sh` writes the Obsidian plugin’s listen ports to match.
- `$HOME` inside the instance is your **real login home** (file pickers see your files). Stack config is overlaid onto `~/.gemini`, `~/.config/Antigravity IDE`, and `~/.config/obsidian` from `state/`. Add scratch/projects with `AGY_EXTRA_BINDS` in `secrets.env`.

### Multi-user / shared login node (honest limits)

On Linux, **all local users share the same `127.0.0.1`**. Host-net mode therefore:

- Avoids accidental **port interference** via per-uid defaults
- Does **not** stop another user on the *same* node from connecting to your loopback ports if they learn the port
- Obsidian is gated by `OBSIDIAN_API_KEY`; treat the OpenRouter proxy as sensitive (it can spend your key) — keep `state/` mode `700` / secrets `600`, and prefer a personal interactive node when possible

True per-user network isolation needs `AGY_NET_MODE=bridge` (private netns). That usually requires site-admin CNI / allow-net — **not** something normal HPC users can enable without sudo.

Optional strict mode (`AGY_NET_MODE=bridge`): CNI private netns. Needs a site that allows unprivileged CNI. Do **not** rely on this without sudo/root or a preconfigured allow-net ACL.

## Obsidian vault

1. Point `VAULT_HOST_PATH` at your **vault directory** (the folder that contains `.obsidian/`, e.g. `~/KnowledgeBase/CodeVault` — not the parent `KnowledgeBase`). On a fresh HPC clone, point it anywhere writable; `setup-config.sh` creates it and seeds the harness stubs.
2. Install community plugin **Local REST API**.
3. Set the plugin API key to the same value as `OBSIDIAN_API_KEY`.
4. Prefer insecure HTTP on localhost (port = `OBSIDIAN_REST_PORT`, uid-derived by default; see `config/templates/obsidian-local-rest-api.data.json.example`).

The stack bind-mounts the vault at `/vault` **and** at the same host path inside the instance, so Obsidian’s “Open folder” dialog works. Open `CodeVault` (or whatever `VAULT_HOST_PATH` is), not a parent folder that isn’t a vault.

MCP is rendered to `state/gemini/antigravity/mcp_config.json` as `http://127.0.0.1:${OBSIDIAN_REST_PORT}/mcp/`.

## License / third party

- Google Antigravity IDE & CLI: Google’s terms
- Obsidian: Obsidian’s terms
- antigravity-add-model: its upstream license
- This repo’s scripts/templates: MIT
