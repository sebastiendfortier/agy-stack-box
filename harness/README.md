# CMC / ECCC harness seed

Tracked copies of the Phase 0 harness artifacts, so a fresh clone on HPC works
without the workstation Obsidian vault.

| Path | Mirrors vault |
|------|---------------|
| `CMC-Harness-Plan.md` | `setup/CMC-Harness-Plan.md` |
| `CMC-Agent-Setup-Questionnaire.md` | `setup/CMC-Agent-Setup-Questionnaire.md` (`status: partial`) |
| `cmc-profile/AGENTS.md` | `setup/cmc-profile/AGENTS.md` |
| `glossary/MODEX-WINGS.md` | `glossary/MODEX-WINGS.md` |
| `agent-sessions/README.md` | `agent-sessions/README.md` |
| `vault-AGENTS.md` | vault root `AGENTS.md` |

## How seeding picks sources

`scripts/seed-cmc-profile.sh` reads, in order:

1. `CMC_PROFILE_SRC` / `CMC_GLOSSARY_SRC` if set
2. `$VAULT_HOST_PATH` (or `CMC_VAULT_ROOT`, default `~/KnowledgeBase/CodeVault`)
3. this `harness/` folder

So the vault stays the source of truth on your workstation, and the repo copy
covers a clean HPC clone.

## Bootstrapping a vault on HPC

`scripts/init-vault.sh [path]` creates the vault layout and copies missing stubs
from here:

```
AGENTS.md
setup/CMC-Harness-Plan.md
setup/CMC-Agent-Setup-Questionnaire.md
setup/cmc-profile/AGENTS.md
glossary/MODEX-WINGS.md
agent-sessions/README.md
adrs/ lessons/ runbooks/
```

It is idempotent and never overwrites existing notes. `setup-config.sh` calls it
automatically for `VAULT_HOST_PATH`, so a new HPC path is usable immediately.
`seed-cmc-profile.sh` calls it too when the vault is explicitly configured.

## Re-sync

After editing the vault, copy the same paths back into `harness/` and commit.
Redact real hostnames, queue names, absolute HPC paths, and secrets first; this
repository may be public.
