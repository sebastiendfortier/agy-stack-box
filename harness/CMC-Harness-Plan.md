---
title: CMC Harness Plan (from questionnaire)
created: 2026-10-31
status: active
source: setup/CMC-Agent-Setup-Questionnaire.md
---

# CMC Harness Plan

Built from your filled answers. Unsure blanks → **assumed defaults** (safe, reversible).

## Profile snapshot

| Axis | You |
|------|-----|
| Role | CMC Dev + dissemination/open data + platform; also ops-adjacent |
| Strength | Ship/port clean human-readable code; first-try deploys (MarimoHub / k3s / FreeIPA / pixi / PBS / Qwen) |
| Surfaces | Antigravity IDE + `agy` CLI primary; VS Code / OpenCode / pi secondary; Cursor optional exit |
| Models | OpenRouter BYOK + HPC Qwen when good enough; budget ~$20–100/mo |
| Memory pain | **5/5** — vault = runbooks, ADRs, lessons, glossary, artifacts |
| Safety | No secrets/PII/pre-release/infra fingerprints to external models; no force-push; no prod; no mass jobs; confirm `rm -rf` |
| Tone | Ultra terse default; teaching mode for docs/science; bilingual EN/FR when writing for others |

**Antigravity App 2.0:** still a real product (multi-agent desktop, no IDE). Useful later for overnight/parallel; not required for phase 1.

## Assumed defaults (because unsure)

| Topic | Default until you say otherwise |
|-------|----------------------------------|
| Tenure / A4 | Veteran domain + mixed tooling |
| Private gov source to external models | Allowed for **non-secret** code via BYOK; still redact hosts/paths/keys/pre-release |
| Primary language ★ | Python 3 + Bash; Fortran/C when touching models |
| Scheduler primary | **PBS Pro** for user job policies (MarimoHub); Slurm when that cluster says so |
| Scratch / `/space` paths | Leave as placeholders; fill on HPC via `cmds-agent-mcp` / sitestore once reachable |
| Production read-only paths | Entire operational run trees + shared `/space` write → **ask first** |
| L3 90-day awesome | MarimoHub path works end-to-end + agent remembers CMC constraints without re-explaining |
| L5 anti-goals | No Cursor lock-in; no harness that leaks HPC layout; no unreadable AI sludge code |
| Routing specifics | Plan = stronger OpenRouter model; bulk = Qwen local when tool-calling OK; trivia = cheapest local/OpenRouter |

## Dual profile (M6)

```
CMC profile     → work code, PBS/k3s/pixi, redaction rules, MSC skills
Personal/OSS    → agy-stack-box, public GitHub, freer BYOK
```

Global: `state/gemini/` (agy-stack) + `~/.gemini` overlays  
Per-repo: `.agents/` where GitLab/GitHub policy allows  
Vault: `KnowledgeBase/CodeVault` (session logs, ADRs, lessons, glossary)

## Modes (named)

| Mode | When | Tone | Guardrails |
|------|------|------|------------|
| **Architect** | `/grill-me`, legacy overhauls, MarimoHub/k3s design | Structured, ask then plan | No mass apply |
| **Code** | Feature/port/refactor | Ultra + clean readable code | Feature branch OK; human-readable > clever |
| **Ops** | Deploy, PBS, FreeIPA, k3s, quotas | Diagnose → propose → wait | No prod writes; no mass `qsub` |
| **Science** | GRIB/NetCDF/FST/icechunk, bit-repro | Careful, cite formats | Prefer validate/dry-run |
| **Docs** | Runbooks, bilingual notes, mentoring | Teaching, clear EN (FR on request) | Soften caveman |

Always-on base: ponytail ultra + caveman ultracave, **except Docs/Science** (softened).

## Safety harness (always)

Never send to external models:
- passwords / API keys
- PII
- pre-release forecast products
- hostnames, queue names, absolute HPC paths that fingerprint infra
- unpublished research

Shell:
- confirm before `rm -rf`, force-push (prefer never), prod paths, mass job submit
- ask before reading secret files; secrets stay in `state/secrets.env` / password manager

Network:
- workstation: OpenRouter OK
- HPC: prefer local Qwen; no assume egress

## Skills backlog (priority)

**P0 — unlock your stated north star**
1. `ops-k3s-rootless` — rootless → k3s migration patterns (GitLab-built images)
2. `ops-pbs-user-jobs` — PBS Pro user policy–aware job scripts (GPU/CPU Marimo)
3. `ops-pixi-sitestore` — pixi envs on sitestore; quota-aware
4. `ops-freeipa-auth` — auth notes without leaking realm/host detail
5. `vault-session-log` — end-of-task summary → Obsidian

**P1 — MSC / data platform**
6. `msc-grib-netcdf` — inspect/summarize
7. `msc-fst-rpn` — FST helpers
8. `msc-opendata-ogc` — Datamart / GeoMet checklist
9. `cmc-io` / `cmc-postproc` / `cmc-stats` / `cmc-weather` / `cmc-viz` / `cmc-colormaps` / `rerun-geo` / `aether` — wire when repos visible
10. Reuse **cmds-agent-mcp** skills (ssm, hcron, explainers) on HPC instead of reinventing

**P2 — quality of life**
11. Bilingual commit/PR templates  
12. Glossary: MODEX, WINGS, + grow from vault  
13. Hooks: lint/format, tests on touch, forbidden-path block, acronym nudge  

## MCP roadmap

| Phase | Tools |
|-------|--------|
| Now | Obsidian Local REST (vault memory) |
| Next | Browser MCP; weather/plot helpers |
| On HPC | cmds-agent-mcp; wiki/turbovec search; Datamart-safe query wrappers |

## Dream tasks → phased delivery

| Your example | Phase |
|--------------|-------|
| Deploy MarimoHub rootless k3s + FreeIPA + pixi + Qwen + per-user PBS Marimo | **Flagship** — Architect then Ops |
| Docker rootless services → k3s from GitLab CI | After MarimoHub patterns solid |
| Icechunk benchmark | Science skill + dedicated repo `.agents/` |
| MCP chatbot (OKF docs + turbovec + private wiki) | After wiki MCP reachable on HPC |
| SPI-like viz web UI | After cmc-viz / aether visibility |
| HPC quota/user/group dashboards | Ops + management tooling; careful with infra fingerprinting |
| Maestro suite + Mojo in-memory stack | Later; needs suite access |

## Implementation sequence

### Phase 0 — this week (laptop / current box)
1. Mark questionnaire `status: partial` (honest). ✅
2. Seed CMC profile under vault + agy-stack sync paths: ✅
   - `scripts/seed-cmc-profile.sh` → `state/gemini/config/rules/cmc-profile.md`
   - skill `cmc-profile` + agents Architect / Code / Ops / Science / Docs
   - glossary starter + `agent-sessions/`
3. Antigravity IDE started on `~/src/agy-stack-box` (proxy `:33000`). ✅

### Phase 1 — agy-stack as daily driver
1. `start-services` + IDE/CLI on `~/src/agy-stack-box`
2. CMC vs Personal profile switch documented
3. OpenRouter defaults + placeholder for HPC Qwen endpoint
4. Hooks: no-force-push, confirm destructive, session summary → vault

### Phase 2 — HPC overlay
1. Discover sitestore / scratch / cmds-agent-mcp (no hardcoded secrets/hosts in git)
2. Point bulk coding at local Qwen; plan/hard tasks at OpenRouter when on egress network
3. MarimoHub flagship: grill-me → plan note in vault → implement in worktree

### Phase 3 — MSC skills + self-improve inside Antigravity
1. Per-repo `.agents/` for cmc-* libraries
2. Light Propose–Probe–Compose on skills (Harness² *ideas*, Antigravity-only — your choice)
3. Overnight scheduled agents only after audit logging feels good

## Success metrics (practical)

- [ ] Deploy attempt #1 for a contained service needs ≤1 retry for env/path issues
- [ ] Agent cites vault glossary / prior lesson instead of re-asking MODEX/WINGS
- [ ] No infra fingerprint or secret appears in OpenRouter payloads (spot-check logs)
- [ ] Output readable by non-AI colleagues without rewrite
- [ ] Session summaries land in Obsidian without manual copy-paste

## Open items (only if/when you know)

- Exact Qwen endpoint id (`qwen3.8 27b` / north mini)
- Sitestore + scratch canonical paths
- cmds-agent-mcp install location on HPC
- Which clusters are PBS vs Spersurm for MarimoHub v1
- Production path denylist (even coarse)

---

**Next action:** seed Phase 0 profile files in the vault (and mirror into agy-stack `state/gemini` when you start the IDE).
