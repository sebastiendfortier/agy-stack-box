#!/usr/bin/env bash
# Seed CMC / ECCC agent profile into agy-stack state/ (and host ~/.gemini when WIRE_HOST=1).
# Source of truth: KnowledgeBase/CodeVault/setup/cmc-profile/.
# Fallback: harness/ in this repo, so a fresh clone on HPC works without a vault.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

WIRE_HOST="${WIRE_HOST:-1}"
SEED_DIR="${CMC_SEED_DIR:-$ROOT/harness}"
VAULT_ROOT="${CMC_VAULT_ROOT:-${VAULT_HOST_PATH:-$HOME/KnowledgeBase/CodeVault}}"
VAULT_EXPLICIT=0
[[ -n "${CMC_VAULT_ROOT:-}${VAULT_HOST_PATH:-}" ]] && VAULT_EXPLICIT=1
VAULT_CMC="${CMC_PROFILE_SRC:-$VAULT_ROOT/setup/cmc-profile}"
VAULT_GLOSSARY="${CMC_GLOSSARY_SRC:-$VAULT_ROOT/glossary}"
PROFILE_SRC="$VAULT_CMC"
[[ -f "$PROFILE_SRC/AGENTS.md" ]] || PROFILE_SRC="$SEED_DIR/cmc-profile"
GLOSSARY_SRC="$VAULT_GLOSSARY"
[[ -d "$GLOSSARY_SRC" ]] || GLOSSARY_SRC="$SEED_DIR/glossary"
PLAN_SRC="$VAULT_ROOT/setup/CMC-Harness-Plan.md"
[[ -f "$PLAN_SRC" ]] || PLAN_SRC="$SEED_DIR/CMC-Harness-Plan.md"

mkdir -p \
  "$STATE_DIR/gemini/config/rules" \
  "$STATE_DIR/gemini/config/skills/cmc-profile" \
  "$STATE_DIR/gemini/config/agents"

# --- Always-on rule (does not replace ponytail AGENTS.md) ---
# `trigger: always_on` is what the CLI/App actually loads. A bare
# GEMINI.md.d/ drop-in is not read by any surface, so don't emit one.
cat >"$STATE_DIR/gemini/config/rules/cmc-profile.md" <<'EOF'
---
trigger: always_on
---
# CMC / ECCC profile (always on)

Clean, human-readable code — colleagues may not use AI. Prefer first-try deploys: check env, paths, quotas, scheduler policy before claiming done.

## Modes (say which you want)
- **Architect** — plan / grill-me; no mass edits
- **Code** — feature-branch implement; readable > clever
- **Ops** — diagnose → propose → wait (PBS, k3s, pixi, FreeIPA)
- **Science** — GRIB/NetCDF/FST/icechunk; validate before mutate
- **Docs** — teaching tone; EN default, FR on request; soften caveman

Default tone: ultra terse (ponytail/caveman). Soften for Docs/Science.

## Never send to external models
Passwords/keys, PII, pre-release forecast products, hostnames/queues/absolute paths that fingerprint HPC, unpublished research. Use placeholders: `<LOGIN_NODE>`, `<QUEUE>`, `<SITESTORE>`.

## Shell / git
Confirm before `rm -rf`, mass job submit, production paths. Never force-push. Ask before reading secret files.

## PBS
All job list/status queries go through the `cmds-agent` MCP cache tools (`pbs_list_jobs`, `pbs_job_status`). Never run raw `qstat` (protects PBS Pro). If the `cmds-agent` MCP is not connected, say so instead of falling back to qstat.

## Network
Workstation: OpenRouter BYOK OK. HPC: prefer local Qwen; do not assume egress. Work code stays off personal cloud AI products.

## Memory → Obsidian CodeVault
`agent-sessions/`, `glossary/`, `adrs/`, `lessons/`, `runbooks/`. Session end: short summary note.
Plan / questionnaire: `harness/` in agy-stack-box; vault copies under `setup/` (questionnaire status: partial).
EOF

# --- Full profile copy (reference) ---
if [[ -f "$PROFILE_SRC/AGENTS.md" ]]; then
  cp -a "$PROFILE_SRC/AGENTS.md" "$STATE_DIR/gemini/config/skills/cmc-profile/AGENTS.md"
else
  info "warning: no CMC profile AGENTS.md in $VAULT_CMC or $SEED_DIR/cmc-profile"
fi

cat >"$STATE_DIR/gemini/config/skills/cmc-profile/SKILL.md" <<'EOF'
---
name: cmc-profile
description: CMC/ECCC Dev harness — safety, modes (Architect/Code/Ops/Science/Docs), bilingual, HPC-aware. Use for government/CMC work, MarimoHub/k3s/PBS/pixi, MSC data, or when redacting infra.
---

# CMC profile skill

Follow `AGENTS.md` in this skill folder and the always-on rule `config/rules/cmc-profile.md`.

## Quick checks before deploy claims
1. Env manager (pixi/conda) + sitestore quota
2. Scheduler policy (PBS Pro vs Slurm) for this cluster
3. Rootless / k3s constraints (no sudo)
4. Auth (FreeIPA) without logging secrets or host fingerprints
5. Local Qwen vs OpenRouter based on egress

## Redaction
Replace real hosts, queues, and absolute HPC paths with placeholders in any text that may leave the machine.
EOF

# --- Named mode agents (YAML frontmatter required for invoke_subagent) ---
AGENTS_SRC="${CMC_AGENTS_SRC:-}"
if [[ -z "$AGENTS_SRC" ]]; then
  if [[ -d "$VAULT_CMC/agents" ]]; then
    AGENTS_SRC="$VAULT_CMC/agents"
  elif [[ -d "$ROOT/harness/cmc-profile/agents" ]]; then
    AGENTS_SRC="$ROOT/harness/cmc-profile/agents"
  fi
fi
if [[ -n "${AGENTS_SRC:-}" && -d "$AGENTS_SRC" ]]; then
  info "Seeding agents from $AGENTS_SRC"
  for f in "$AGENTS_SRC"/*.md; do
    [[ -f "$f" ]] || continue
    cp -a "$f" "$STATE_DIR/gemini/config/agents/$(basename "$f")"
  done
else
  info "No agents dir at vault/harness — keeping existing state agents if any"
fi

# --- Glossary + plan pointers ---
mkdir -p "$STATE_DIR/gemini/config/skills/cmc-profile/refs"
if [[ -d "$GLOSSARY_SRC" ]]; then
  cp -a "$GLOSSARY_SRC/." "$STATE_DIR/gemini/config/skills/cmc-profile/refs/" 2>/dev/null || true
fi
if [[ -f "$PLAN_SRC" ]]; then
  cp -a "$PLAN_SRC" "$STATE_DIR/gemini/config/skills/cmc-profile/refs/CMC-Harness-Plan.md"
fi

# --- Vault: reuse an existing one, or bootstrap a local vault on a fresh HPC clone ---
if [[ -d "$VAULT_ROOT" || "${VAULT_EXPLICIT:-0}" == "1" ]]; then
  "$SCRIPT_DIR/init-vault.sh" "$VAULT_ROOT"
else
  info "No vault at $VAULT_ROOT — using repo harness/ only"
  info "  set VAULT_HOST_PATH (or run ./scripts/init-vault.sh /path) to bootstrap one"
fi

# Ensure GEMINI.md mentions CMC if missing
GEMINI_STATE="$STATE_DIR/gemini/GEMINI.md"
if [[ -f "$GEMINI_STATE" ]] && ! grep -q 'CMC / ECCC' "$GEMINI_STATE" 2>/dev/null; then
  cat >>"$GEMINI_STATE" <<'EOF'

## CMC / ECCC
Always-on rules live in `config/rules/cmc-profile.md`. Invoke skill `cmc-profile` or modes Architect/Code/Ops/Science/Docs for CMC work. Prefer vault paths under CodeVault for lasting notes.
EOF
fi

if [[ "$WIRE_HOST" == "1" && -d "$HOME/.gemini" ]]; then
  info "Mirroring CMC profile into host ~/.gemini"
  mkdir -p "$HOME/.gemini/config/rules" \
    "$HOME/.gemini/config/skills/cmc-profile" \
    "$HOME/.gemini/config/agents"
  cp -a "$STATE_DIR/gemini/config/rules/." "$HOME/.gemini/config/rules/"
  cp -a "$STATE_DIR/gemini/config/skills/cmc-profile/." "$HOME/.gemini/config/skills/cmc-profile/"
  cp -a "$STATE_DIR/gemini/config/agents/." "$HOME/.gemini/config/agents/"
  if [[ -f "$GEMINI_STATE" ]]; then
    cp -a "$GEMINI_STATE" "$HOME/.gemini/GEMINI.md"
  fi
fi

info "CMC profile seeded:"
info "  $STATE_DIR/gemini/config/rules/cmc-profile.md"
info "  skills/cmc-profile + agents: architect code ops science docs"
info "  profile source: $PROFILE_SRC"
info "  glossary source: $GLOSSARY_SRC"
info "  vault: $VAULT_ROOT"
