# CMC / ECCC harness seed

Tracked copies of the Phase 0 harness artifacts from the plan, so a fresh clone
on HPC works without the Obsidian vault being present.

| Path | Mirrors vault |
|------|---------------|
| `CMC-Harness-Plan.md` | `setup/CMC-Harness-Plan.md` |
| `CMC-Agent-Setup-Questionnaire.md` | `setup/CMC-Agent-Setup-Questionnaire.md` (`status: partial`) |
| `cmc-profile/AGENTS.md` | `setup/cmc-profile/AGENTS.md` |
| `glossary/MODEX-WINGS.md` | `glossary/MODEX-WINGS.md` |
| `agent-sessions/README.md` | `agent-sessions/README.md` |

## How seeding picks sources

`scripts/seed-cmc-profile.sh` reads, in order:

1. `CMC_PROFILE_SRC` / `CMC_GLOSSARY_SRC` if set
2. `$VAULT_HOST_PATH` (or `CMC_VAULT_ROOT`, default `~/KnowledgeBase/CodeVault`)
3. this `harness/` folder

So the vault stays the source of truth on your workstation, and the repo copy
covers a clean HPC clone. When the vault directory exists, the script also
creates `agent-sessions/`, `glossary/`, `adrs/`, `lessons/`, `runbooks/` and
seeds missing stubs only — existing notes are never overwritten.

## Re-sync

After editing the vault, copy the same paths back into `harness/` and commit.
Redact real hostnames, queue names, absolute HPC paths, and secrets first; this
repository may be public.
