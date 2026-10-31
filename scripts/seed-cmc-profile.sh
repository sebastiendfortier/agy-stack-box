#!/usr/bin/env bash
# Seed CMC / ECCC agent profile into agy-stack state/ (and host ~/.gemini when WIRE_HOST=1).
# Source of truth: KnowledgeBase/CodeVault/setup/cmc-profile/ (+ this script's embeds).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

WIRE_HOST="${WIRE_HOST:-1}"
VAULT_CMC="${CMC_PROFILE_SRC:-$HOME/KnowledgeBase/CodeVault/setup/cmc-profile}"
VAULT_GLOSSARY="${CMC_GLOSSARY_SRC:-$HOME/KnowledgeBase/CodeVault/glossary}"

mkdir -p \
  "$STATE_DIR/gemini/GEMINI.md.d" \
  "$STATE_DIR/gemini/antigravity/skills/cmc-profile" \
  "$STATE_DIR/gemini/config/skills/cmc-profile" \
  "$STATE_DIR/gemini/config/agents" \
  "$STATE_DIR/gemini/antigravity/agents"

# --- Always-on rules (does not replace ponytail AGENTS.md) ---
cat >"$STATE_DIR/gemini/GEMINI.md.d/cmc-profile.md" <<'EOF'
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

## Network
Workstation: OpenRouter BYOK OK. HPC: prefer local Qwen; do not assume egress. Work code stays off personal cloud AI products.

## Memory → Obsidian CodeVault
`agent-sessions/`, `glossary/`, `adrs/`, `lessons/`, `runbooks/`. Session end: short summary note.
EOF

# --- Full profile copy (reference) ---
if [[ -f "$VAULT_CMC/AGENTS.md" ]]; then
  cp -a "$VAULT_CMC/AGENTS.md" "$STATE_DIR/gemini/antigravity/skills/cmc-profile/AGENTS.md"
  cp -a "$VAULT_CMC/AGENTS.md" "$STATE_DIR/gemini/config/skills/cmc-profile/AGENTS.md"
fi

cat >"$STATE_DIR/gemini/antigravity/skills/cmc-profile/SKILL.md" <<'EOF'
---
name: cmc-profile
description: CMC/ECCC Dev harness — safety, modes (Architect/Code/Ops/Science/Docs), bilingual, HPC-aware. Use for government/CMC work, MarimoHub/k3s/PBS/pixi, MSC data, or when redacting infra.
---

# CMC profile skill

Follow `AGENTS.md` in this skill folder and always-on `GEMINI.md.d/cmc-profile.md`.

## Quick checks before deploy claims
1. Env manager (pixi/conda) + sitestore quota
2. Scheduler policy (PBS Pro vs Slurm) for this cluster
3. Rootless / k3s constraints (no sudo)
4. Auth (FreeIPA) without logging secrets or host fingerprints
5. Local Qwen vs OpenRouter based on egress

## Redaction
Replace real hosts, queues, and absolute HPC paths with placeholders in any text that may leave the machine.
EOF
cp -a "$STATE_DIR/gemini/antigravity/skills/cmc-profile/SKILL.md" \
  "$STATE_DIR/gemini/config/skills/cmc-profile/SKILL.md"

# --- Named mode agents ---
write_agent() {
  local name="$1" body="$2"
  printf '%s\n' "$body" >"$STATE_DIR/gemini/config/agents/${name}.md"
  printf '%s\n' "$body" >"$STATE_DIR/gemini/antigravity/agents/${name}.md"
}

write_agent architect '# Architect mode
Plan first. Ask clarifying questions. Prefer /grill-me style alignment.
No mass file edits until the user accepts the plan.
Capture the plan in Obsidian `adrs/` or `runbooks/` when non-trivial.
Redact HPC fingerprints. Tone: structured, not caveman-short on the plan itself.'

write_agent code '# Code mode
Implement the accepted plan on a feature branch.
Readable, human-maintainable diffs. Ponytail laziness: smallest complete change.
Do not force-push. Batch-approve OK on feature branches.
Soft-fail: if FR/EN comments conflict, ask once.'

write_agent ops '# Ops mode
Diagnose → propose fix → wait for explicit OK before applying.
Domains: PBS/Slurm jobs, rootless k3s, pixi/sitestore, FreeIPA auth, quotas.
Never mass-submit jobs, touch production paths, or `rm -rf` without confirm.
Prefer local Qwen on HPC; no assume egress.
Log outcome to `agent-sessions/`.'

write_agent science '# Science mode
GRIB/NetCDF/FST/icechunk/xarray careful handling.
Validate / dry-run before mutate. Preserve bit-reproducibility and golden tests.
Teaching tone when explaining formats. Soften caveman.'

write_agent docs '# Docs mode
Teaching / explanatory. English default; French when asked or when audience is FR.
Runbooks, ADRs, bilingual PR/commit text.
Soften ponytail/caveman. Write into CodeVault when lasting.'

# --- Glossary pointer ---
mkdir -p "$STATE_DIR/gemini/antigravity/skills/cmc-profile/refs"
if [[ -d "$VAULT_GLOSSARY" ]]; then
  cp -a "$VAULT_GLOSSARY/." "$STATE_DIR/gemini/antigravity/skills/cmc-profile/refs/" 2>/dev/null || true
fi

# Ensure GEMINI.md mentions CMC if missing
GEMINI_STATE="$STATE_DIR/gemini/GEMINI.md"
if [[ -f "$GEMINI_STATE" ]] && ! grep -q 'CMC / ECCC' "$GEMINI_STATE" 2>/dev/null; then
  cat >>"$GEMINI_STATE" <<'EOF'

## CMC / ECCC
Always-on rules live in `GEMINI.md.d/cmc-profile.md`. Invoke skill `cmc-profile` or modes Architect/Code/Ops/Science/Docs for CMC work. Prefer vault paths under CodeVault for lasting notes.
EOF
fi

if [[ "$WIRE_HOST" == "1" && -d "$HOME/.gemini" ]]; then
  info "Mirroring CMC profile into host ~/.gemini"
  mkdir -p "$HOME/.gemini/GEMINI.md.d" \
    "$HOME/.gemini/antigravity/skills/cmc-profile" \
    "$HOME/.gemini/config/skills/cmc-profile" \
    "$HOME/.gemini/config/agents" \
    "$HOME/.gemini/antigravity/agents"
  cp -a "$STATE_DIR/gemini/GEMINI.md.d/cmc-profile.md" "$HOME/.gemini/GEMINI.md.d/"
  cp -a "$STATE_DIR/gemini/antigravity/skills/cmc-profile/." "$HOME/.gemini/antigravity/skills/cmc-profile/"
  cp -a "$STATE_DIR/gemini/config/skills/cmc-profile/." "$HOME/.gemini/config/skills/cmc-profile/"
  cp -a "$STATE_DIR/gemini/config/agents/." "$HOME/.gemini/config/agents/"
  cp -a "$STATE_DIR/gemini/antigravity/agents/." "$HOME/.gemini/antigravity/agents/"
  if [[ -f "$GEMINI_STATE" ]]; then
    cp -a "$GEMINI_STATE" "$HOME/.gemini/GEMINI.md"
  fi
fi

info "CMC profile seeded:"
info "  $STATE_DIR/gemini/GEMINI.md.d/cmc-profile.md"
info "  skills/cmc-profile + agents: architect code ops science docs"
info "  vault source: $VAULT_CMC"
