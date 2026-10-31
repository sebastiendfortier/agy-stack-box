# agy-stack-box

A **slim** Singularity / Apptainer image (~runtime only) plus host-fetched apps under `state/apps/`:

- **In the SIF:** OpenRouter BYOK proxy + Node + Electron shared libs
- **In `state/apps/` (via `fetch-apps.sh`):** Antigravity IDE, Obsidian AppImage, `agy` CLI

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

Skip `enable-local-build.sh` and bridge mode. Build the SIF on a laptop (or CI), copy `apptainer/agy-stack.sif` onto the cluster, then:

```bash
./scripts/setup-config.sh
./scripts/fetch-apps.sh
./scripts/fetch-skills.sh     # ponytail + caveman into state/ (+ host Cursor/agy when WIRE_HOST=1)
./scripts/start-services.sh   # AGY_NET_MODE=host by default — no sudo
```

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
```

Never commit `state/` or `secrets.env`.

### Skills: ponytail + caveman

`fetch-skills.sh` installs [ponytail](https://github.com/DietrichGebert/ponytail) and [caveman](https://github.com/JuliusBrussee/caveman) into `state/gemini/` (instance `$HOME/.gemini`) so CLI/IDE inside the stack see them.

With `WIRE_HOST=1` (default) it also wires the **host** account:

- **Cursor:** always-on user rules (`~/.cursor/rules/ponytail.mdc`, `caveman-ultracave.mdc`) at **ultra** / **ultracave** — no `/ponytail` or `/caveman` needed
- **agy CLI:** plugins + always-on plugin rules (same modes)
- **Antigravity IDE:** skills + `AGENTS.md` / `GEMINI.md.d` always-on text

Set `WIRE_HOST=0` to only refresh `state/`. Defaults live in `~/.config/ponytail/config.json` and `~/.config/caveman/config.json`.

### 2. Get the slim image

Laptop (with fakeroot enabled once):

```bash
./scripts/build-sif.sh            # does NOT embed IDE/Obsidian/agy
```

HPC: copy a prebuilt `apptainer/agy-stack.sif` from your laptop/CI instead of building on the cluster.

Pinned BYOK proxy: `antigravity-add-model` @ `f793635`. App URLs are in `scripts/fetch-apps.sh`.

### 3. Run

```bash
./scripts/start-services.sh        # instance + proxy + Obsidian (no sudo)
./scripts/start-ide.sh             # another terminal
./scripts/start-cli.sh             # defaults to --model custom-openrouter-auto
./scripts/start-cli.sh models
./scripts/stop.sh
```

OpenRouter entries in the native picker / `agy models`:

- `OpenRouter Auto` (`custom-openrouter-auto`)
- `OpenRouter Gemini 2.5 Pro`
- `OpenRouter Claude Sonnet 4.5`

## Layout

```text
apptainer/agy-stack.def          # image definition
apptainer/rootfs-scripts/        # in-image wrappers (agy, ide, proxy, obsidian)
scripts/                         # host orchestration (incl. fetch-skills.sh)
config/templates/                # secret-free templates
state/                           # local only (gitignored): apps, gemini, secrets
```

## Networking model

Default (`AGY_NET_MODE=host`, recommended for HPC and most desktops):

- Shares the host network namespace — **no sudo, no CNI**
- Proxy / Obsidian still bind `127.0.0.1` only (not reachable from other machines on the LAN)
- OpenRouter egress uses the host’s normal outbound path
- Start-ide/cli still `exec` into the instance
- Instance name / ports are uid-derived (override with `INSTANCE_NAME`, `PROXY_PORT`, `OBSIDIAN_REST_PORT`)

### Multi-user / shared login node (honest limits)

On Linux, **all local users share the same `127.0.0.1`**. Host-net mode therefore:

- Avoids accidental **port interference** via per-uid defaults
- Does **not** stop another user on the *same* node from connecting to your loopback ports if they learn the port
- Obsidian is gated by `OBSIDIAN_API_KEY`; treat the OpenRouter proxy as sensitive (it can spend your key) — keep `state/` mode `700` / secrets `600`, and prefer a personal interactive node when possible

True per-user network isolation needs `AGY_NET_MODE=bridge` (private netns). That usually requires site-admin CNI / allow-net — **not** something normal HPC users can enable without sudo.

Optional strict mode (`AGY_NET_MODE=bridge`): CNI private netns. Needs a site that allows unprivileged CNI. Do **not** rely on this without sudo/root or a preconfigured allow-net ACL.

## Obsidian vault

1. Point `VAULT_HOST_PATH` at your **vault directory** (the folder that contains `.obsidian/`, e.g. `~/KnowledgeBase/CodeVault` — not the parent `KnowledgeBase`).
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
