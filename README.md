# agy-stack-box

One **Singularity / Apptainer** image that runs, inside a **privately networked** instance:

- OpenRouter BYOK proxy ([antigravity-add-model](https://github.com/vahapogut/antigravity-add-model)) on `127.0.0.1:50999`
- Obsidian AppImage + Local REST API on `127.0.0.1:27123` (vault bind-mounted)
- Antigravity IDE 2.6.x (native Agent via `CLOUD_CODE_URL`)
- `agy` CLI (same proxy / models)

Host scripts only orchestrate the instance. Proxy and Obsidian ports are **not published** to the host or LAN; IDE and CLI `exec` into the same netns.

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

### 1. Configure (secrets stay local)

```bash
./scripts/setup-config.sh          # creates state/secrets.env
# edit state/secrets.env:
#   OPENROUTER_API_KEY=...
#   OBSIDIAN_API_KEY=...
#   VAULT_HOST_PATH=/path/to/vault
./scripts/setup-config.sh          # render custom_models + MCP + IDE settings
```

Never commit `state/` or `secrets.env`.

### 2. Build the image

Build needs network plus root or a working user-namespace/`--fakeroot` install (or `singularity build --remote` if your site provides a builder):

```bash
./scripts/build-sif.sh
# equivalent:
#   cd apptainer && singularity build agy-stack.sif agy-stack.def
```

Pinned inside the definition (edit `apptainer/agy-stack.def` `%post` to bump):

- Antigravity IDE **2.6.0** linux-x64
- Obsidian **1.14.5** AppImage
- `antigravity-add-model` @ `f793635`

### 3. Run

```bash
./scripts/start-services.sh        # instance + proxy + Obsidian
./scripts/start-ide.sh             # another terminal
./scripts/start-cli.sh             # defaults to --model custom-openrouter-auto
./scripts/start-cli.sh models      # list catalog (includes OpenRouter *)
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
