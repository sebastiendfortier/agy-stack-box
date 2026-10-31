# agy-stack-box

A **slim** Singularity / Apptainer image (~runtime only) plus host-fetched apps under `state/apps/`, all running inside a **privately networked** instance:

- **In the SIF:** OpenRouter BYOK proxy + Node + Electron shared libs
- **In `state/apps/` (via `fetch-apps.sh`):** Antigravity IDE, Obsidian AppImage, `agy` CLI

Proxy and Obsidian REST stay on instance loopback only (`127.0.0.1:50999` / `:27123`).

## Clone on RHEL (or Ubuntu with Singularity CE)

```bash
git clone https://github.com/sebastiendfortier/agy-stack-box.git
cd agy-stack-box
```

### Host prerequisites

- `apptainer` **or** `singularity` (CE 3.11+), with ability to `instance start --net --network bridge` (often needs fakeroot/root + CNI)
- X11 or Wayland for IDE/Obsidian windows
- Disk for a multi‑GB SIF + Electron state
- An Obsidian vault on the host with **Local REST API** installed (API key will match `OBSIDIAN_API_KEY`)

#### Ubuntu 24.04 local builds

Ubuntu sets `kernel.apparmor_restrict_unprivileged_userns=1`, which breaks `singularity build --fakeroot` (`mount namespace requires privileges`). One-time fix (sudo):

```bash
./scripts/enable-local-build.sh
```

Then `./scripts/build-sif.sh` works as your normal user.

### 1. Configure (secrets stay local)

```bash
./scripts/setup-config.sh          # creates state/secrets.env
# edit state/secrets.env:
#   OPENROUTER_API_KEY=...
#   OBSIDIAN_API_KEY=...
#   VAULT_HOST_PATH=/path/to/vault
./scripts/setup-config.sh          # render custom_models + MCP + IDE settings
./scripts/fetch-apps.sh            # download IDE + Obsidian + agy into state/apps (~0.5GB+)
```

Never commit `state/` or `secrets.env`.

### 2. Build the slim image

```bash
./scripts/enable-local-build.sh   # once on Ubuntu 24.04+
./scripts/build-sif.sh            # fakeroot + zstd; does NOT embed IDE/Obsidian/agy
```

Pinned BYOK proxy: `antigravity-add-model` @ `f793635`. App URLs are in `scripts/fetch-apps.sh`.

### 3. Run

```bash
./scripts/start-services.sh        # instance + proxy + Obsidian
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
scripts/                         # host orchestration
config/templates/                # secret-free templates
state/                           # local only (gitignored)
```

## Networking model

`start-services.sh` runs:

```text
singularity/apptainer instance start --net --network bridge ...
```

- Instance has its own netns + NAT egress (OpenRouter HTTPS works)
- Services bind instance loopback only
- Host cannot reach `:50999` / `:27123` unless it `exec`s into the instance (what the start-ide/cli scripts do)

If `--net` fails on your site, fix CNI/fakeroot first — this project intentionally does not fall back to host networking.

## Obsidian vault

1. Point `VAULT_HOST_PATH` at your vault directory.
2. Install community plugin **Local REST API**.
3. Set the plugin API key to the same value as `OBSIDIAN_API_KEY`.
4. Prefer insecure HTTP on `27123` listening on localhost (see `config/templates/obsidian-local-rest-api.data.json.example`).

MCP is rendered to `state/gemini/antigravity/mcp_config.json` as `http://127.0.0.1:27123/mcp/`.

## License / third party

- Google Antigravity IDE & CLI: Google’s terms
- Obsidian: Obsidian’s terms
- antigravity-add-model: its upstream license
- This repo’s scripts/templates: MIT
