---
title: CMC / ECCC Agent Setup Questionnaire
created: 2026-10-31
purpose: Tailor Antigravity IDE + CLI + Obsidian + OpenRouter/HPC harness
how_to_fill: Check boxes, pick one where noted, type short answers after `→`
status: partial
---

# CMC Agent Setup Questionnaire

> **How to fill (easy mode)**
> 1. Open this note in Obsidian.
> 2. Click checkboxes — no perfection needed.
> 3. For short answers, replace `→ …` with your text.
> 4. For scales, leave **one** number checked (1 = low / never, 5 = high / daily).
> 5. Skip anything you don’t know; mark `#unsure` in the answer line.
> 6. When done, set frontmatter `status: filled` and ping the agent (or paste the note).

**Progress (optional):** tick as you finish each part

- [ ] A — You & role
- [ ] B — Org & constraints (Gov Canada)
- [ ] C — Workstreams (research / dev / ops)
- [ ] D — Domains (NWP, data, dissemination…)
- [ ] E — Tech stack & legacy
- [ ] F — Environments (laptop / HPC / cloud)
- [ ] G — Repos & code layout
- [ ] H — Agent surfaces & UX
- [ ] I — Models & routing
- [ ] J — Memory (Obsidian / docs)
- [ ] K — Safety, secrets, compliance
- [ ] L — Pain points & success criteria
- [ ] M — Harness wishlist
- [ ] N — Free dump

---

## A — You & role

### A1. Name / handle (optional)
→ …

### A2. Team / branch
- [x] CMC Development (dev)
- [ ] CMC Research
- [x] CMC Operations / production support
- [x] Dissemination / data services
- [x] Open data / MSC Datamart / GeoMet
- [x] Cross-cutting / platform
- [ ] Other → …

### A3. Job mix (check all that apply; star ★ your top 2 by editing the line)
- [ ] Scientific research / experiments
- [ ] Forecast system development (NWP / post-processing)
- [x] Software engineering (libraries, APIs, services)
- [x] DevOps / CI / packaging / containers
- [ ] Operations support / incidents / on-call style work
- [x] Data pipelines / ETL / dissemination
- [x] Documentation / knowledge transfer
- [x] Mentoring / reviews
- [x] Management / coordination
- [ ] Other → …

### A4. How long in this domain?
- [ ] < 1 year
- [ ] 1–3 years
- [ ] 3–7 years
- [ ] 7+ years
- [ ] Mix of veteran domain + newer tooling

### A5. Languages you work in day to day (check)
- [x] English
- [x] French
- [x] Both (bilingual outputs matter)
- [ ] Agent should prefer → …

### A6. Typical week shape
- [x] Deep focus coding blocks
- [ ] Many small interrupts / tickets
- [x] Meetings-heavy with bursts of coding
- [x] Experiment → analyze → write cycle
- [x] Firefighting + maintenance
- [ ] Other → …

---

## B — Org & constraints (Government of Canada / ECCC / CMC)

### B1. Network reality (check all true)
- [x] Often on corporate / restricted network
- [x] Can reach public GitHub from workstation
- [x] Can reach OpenRouter / commercial LLM APIs from workstation
- [ ] LLM APIs only from home / personal machine
- [x] HPC nodes have no / limited egress
- [x] Must use approved proxies / gateways
- [x] Air-gapped or near air-gapped periods
- [ ] `#unsure` → …

### B2. Account / identity rules
- [x] Personal Google account OK for Antigravity
- [ ] Only enterprise / approved IdP
- [ ] Prefer no Google login — BYOK only
- [x] Must keep work code off personal cloud AI products
- [ ] Other → …

### B3. Data classification you touch (check all)
- [x] Public / open data
- [x] Internal unclassified
- [ ] Protected A / B (or equivalent)
- [x] Credentials / keys / tokens
- [x] Operational configs that must not leak
- [ ] Partner / commercial licensed data
- [ ] `#unsure` — treat everything as sensitive by default

### B4. What must NEVER go to an external model? (check)
- [ ] Source from private gov repos
- [x] Operational passwords / API keys
- [x] Personally identifiable info
- [x] Pre-release forecast products
- [x] Internal run configs / hostnames / paths that fingerprint infra
- [x] Unpublished research
- [ ] Everything except explicitly public snippets
- [ ] Other → …

### B5. Approved / preferred AI usage stance
- [x] Experiment freely on non-sensitive toys
- [x] OK on internal code if keys stay local / BYOK
- [ ] Only local / on-prem models for work code
- [ ] Need a clear “safe prompt” policy for the harness
- [x] Other → safe but workable…

### B6. Procurement / tooling politics (optional)
→ Any tools banned, preferred, or “use at own risk”? try to stay away from things that leak info about our hpc, i can use at my own risk knowing its secure…

---

## C — Workstreams (research / dev / ops)

Rate how often each appears (check one per row).

### C1. Research experiments
- [ ] 1 never  [X] 2 rare  [ ] 3 sometimes  [ ] 4 often  [ ] 5 daily

### C2. Feature / library development
- [ ] 1  [ ] 2  [ ] 3  [ X] 4  [ ] 5

### C3. Legacy modernization / refactor
- [ ] 1  [ ] 2  [ X] 3  [ ] 4  [ ] 5

### C4. CI, packaging, containers, modules
- [ ] 1  [ ] 2  [ ] 3  [ X] 4  [ ] 5

### C5. Ops debugging (failed jobs, queues, disks)
- [ ] 1  [ X] 2  [ ] 3  [ ] 4  [ ] 5

### C6. Dissemination / product delivery pipelines
- [ ] 1  [ ] 2  [ ] 3  [ X] 4  [ ] 5

### C7. Open data / public APIs / portals
- [ ] 1  [ ] 2  [ ] 3  [ X] 4  [ ] 5

### C8. Scientific validation / verification / scores
- [ ] 1  [ X] 2  [ ] 3  [ ] 4  [ ] 5

### C9. Docs, runbooks, onboarding notes
- [ ] 1  [ ] 2  [ ] 3  [X ] 4  [ ] 5

### C10. In one sentence: what should the agent be world-class at for *you*?
→ …creating and porting code efficiently,cleanly, human readable (some users dont use AI), cursor does a decent job but i know claude is better, i often have to spend long hours to deploy something, it never happens on the first try with cursor. example: im trying to deply marimohub on rootless kubernetes on our hpc, auth with freeipa to access our 4 clusters , use pixi for envs, our qwen for ai, esily manage files, run user jobs for each user to get their marimo instance on a compute node with gpu and cpu respeecting pbspro user policiess

---

## D — Domains (meteorology & MSC stack)

### D1. Forecast / model systems you touch
- [x] Global / regional NWP (e.g. GDPS, RDPS, or successors)
- [x] Ensemble systems
- [x] Nowcasting / radar / satellite
- [x] Ocean / ice / waves
- [x] Air quality / chemistry
- [x] Climate / longer-range
- [x] Statistical / ML post-processing
- [x] Downstream applications (alerts, road, aviation, marine…)
- [x] Not model-side — mostly software/data platform
- [ ] Other → …

### D2. Data formats & protocols (check all)
- [x] GRIB1 / GRIB2
- [x] NetCDF / CF
- [x] BUFR / TAC / IWXXM
- [x] GeoJSON / JSON / CSV
- [x] Shapefile / geopackage / COG
- [x] FST / RPN / CMC internal formats
- [x] Parquet / Arrow
- [x] Zarr
- [x] XML / SOAP legacy
- [x] Other → icechunk, geojson, covjson, geoparquet etc…

### D3. Libraries / stacks you live in
- [x] eccodes / wgrib2 / cdo / nco
- [x] xarray / cfgrib / iris
- [x] GDAL / rasterio / shapely / pyproj
- [x] RPN / librmn / fstpy / related
- [x] Django / Flask / FastAPI
- [x] Celery / Redis / Rabbit / Kafka
- [x] Spark / Dask
- [x] Docker / Podman / Singularity / Apptainer
- [x] Ansible / Terraform / Puppet / Salt
- [x] Other → k3s…

### D4. Dissemination & open data
- [x] MSC Datamart
- [x] GeoMet / OGC APIs / WMS / WCS
- [x] AMQP / MQTT / webhooks
- [x] S3-compatible object stores
- [ ] Internal dissemination buses
- [x] Partner feeds
- [ ] Other → …

### D5. Naming / domain jargon the agent must learn
→ List critical acronyms, systems, or “never confuse X with Y”: …MODEX WINGS

### D6. Example tasks you’d love to type to an agent (3–8 bullets)
- → …benchmark icechunk...
- → …create a chat bot backed by mcp with okf docs and turbovec for searching data sources like our private wiki
- → …deply a visualisation app that is like SPI but give it a web interface
- → …create a complete suite of dashboards for monitoring our hpc infra, quotas, users, groups and add a ttoll to help management decide where to allocate more quota when avaialable ind in the same pools or not
- → …transfer all doker rootless services to k3s and have the containers built from gittlab projects
- optimize a maestro suite using our new in memory processing stack (built in mojo)

---

## E — Tech stack & legacy

### E1. Languages (check + mark primary with ★ in the text)
- [x] Fortran (77 / 90 / 2003+)
- [x] C / C++
- [x] Python 2 legacy
- [x] Python 3
- [x] Bash / shell
- [x] Perl
- [ ] Java / JVM
- [x] JavaScript / TypeScript
- [x] Go / Rust
- [x] R
- [x] SQL
- [ ] Other → idl…

### E2. Build & dependency pain
- [x] Make / CMake / Autotools
- [x] Conda / mamba / pixi
- [ ] pip / poetry / uv
- [ ] Spack / EasyBuild / modules (Lmod)
- [ ] Vendor blobs / old RPMs
- [x] Mixed compilers (Intel / GNU / LLVM)
- [ ] Other → …

### E3. Legacy characteristics (be honest)
- [x] Sparse / outdated docs
- [x] Tribal knowledge in people’s heads
- [x] Giant mono-scripts
- [x] Fragile absolute paths
- [x] Mixed French/English comments
- [ ] Tests rare or slow
- [x] “Don’t touch, it works in ops”
- [x] Actually well-structured modern bits exist too
- [ ] Other → …

### E4. Testing reality
- [ ] Unit tests common
- [x] Integration / golden-file tests
- [x] Scientific bit-reproducibility matters
- [x] Visual / plot diffs
- [x] Mostly manual validation
- [x] CI exists and is trusted
- [ ] CI exists but flaky / ignored
- [ ] Other → …

### E5. Code review culture
- [ ] PR required
- [x] Pair / walkthrough
- [x] Push to shared branch with light review
- [ ] Ops hotfixes happen
- [ ] Other → …

---

## F — Environments (laptop / HPC / cloud)

### F1. Where you code (check all; ★ primary)
- [ ] Linux laptop (personal)
- [x] Linux workstation (work)
- [x] Windows + WSL
- [ ] macOS
- [x] Remote HPC login node
- [x] ThinLinc / VNC / remote desktop
- [x] VS Code / Cursor Remote SSH
- [ ] Other → …

### F2. HPC / batch
- [x] Slurm
- [x] PBS / Torque
- [ ] LSF
- [ ] Other scheduler → …
- [x] Interactive GPU / CPU queues
- [x] Singularity / Apptainer common
- [ ] Module environment heavy
- [ ] No sudo / user-space only (true for you?)
  - [x] Yes, no sudo
  - [ ] Sometimes sudo
  - [ ] `#unsure`

### F3. Filesystems & quirks
- [x] Home quota tight
- [x] Scratch / project spaces
- [x] Parallel FS (Lustre / GPFS / …)
- [x] Slow metadata / many small files hurt
- [x] Must avoid filling shared areas
- [ ] Other → …

### F4. Display / GUI needs
- [x] Need IDE GUI on remote
- [x] Terminal-only is fine most days
- [ ] Obsidian on laptop, agents on HPC
- [ ] Everything local when possible
- [x] Other → …mostly on remote hpc

### F5. Sync between machines
- [x] git only
- [x] rsync / scp habits
- [x] Shared filesystem
- [ ] Obsidian sync / git vault
- [ ] Pain point → …networks does not see other networks, but can bee seen by other networks behind vpn

---

## G — Repos & code layout

### G1. How many active repos/projects typically?
- [ ] 1–2
- [ ] 3–5
- [x] 6–15
- [ ] Many tiny scripts + few big systems

### G2. Hosting
- [x] GitHub.com
- [ ] GitHub Enterprise / GHES
- [x] GitLab (on-prem)
- [ ] Bitbucket / other
- [ ] Mixed
- [x] Some code not in git yet
- → URLs or org names if shareable: …

### G3. Monorepo vs many repos
- [ ] Mostly monorepo
- [x] Many small repos
- [x] Hybrid
- [ ] “Repo” is less true than shared project trees on disk

### G4. Paths the agent should know (fill what you can)
- Home projects → …$>HOME
- CMC / shared trees → /space (gpfs) ords but i dont know the path…, code lives on sitestore because of pixi envs
- Scratch → …dont know the path, small tmp
- Vault → `~/KnowledgeBase/CodeVault` (edit if wrong) …
- agy-stack → `~/src/agy-stack-box` (edit if wrong) …

### G5. Branching / release
- [x] trunk-based
- [x] git-flow-ish
- [ ] release branches for ops
- [x] tags / versions matter a lot
- [ ] Other → …

---

## H — Agent surfaces & UX

### H1. Daily driver preference (pick primary + backups)
- [x] Antigravity IDE
- [x] `agy` CLI (TUI)
- [x] Antigravity App 2.0 (multi-agent desktop) doest this still exist?
- [ ] Cursor (keep for some things)
- [x] VS Code + extension
- [x] OpenCode / Aider / Cline / other → pi…
- [ ] Mix depending on task

### H2. Interaction style
- [ ] Pair-programmer: small steps, ask me a lot
- [x] Autonomous: `/goal` until done, then review
- [x] Plan first (`/grill-me`), then implement
- [x] Research mode: explore, summarize, don’t edit
- [x] Ops mode: diagnose, propose fix, wait for OK
- [ ] Other → …

### H3. Diff / approval comfort
- [x] Approve every file edit
- [x] Approve batches
- [ ] Auto-edit OK in git worktrees only
- [x] Auto-edit OK on feature branches
- [ ] Never auto-run destructive shell
- [ ] Other → …

### H4. Communication tone for the agent
- [x] Ultra terse (caveman / ponytail ultra)
- [ ] Normal concise engineer
- [x] Teaching / explanatory
- [ ] Bilingual notes when useful
- [ ] Switch by mode (want custom modes) → …

### H5. Notifications / handoff
- [x] Want task-complete pings
- [x] Want Obsidian log of each session
- [x] Want PR-ready commit messages
- [x] Quiet unless blocked
- [ ] Other → …

### H6. Parallel agents
- [ ] One agent at a time
- [x] Like multi-agent / subagents
- [x] Separate agents per repo
- [x] Overnight scheduled jobs appealing
- [ ] Other → …

---

## I — Models & routing

### I1. Providers you can / will use
- [x] OpenRouter
- [ ] Google / Gemini (Antigravity native)
- [ ] Anthropic direct
- [ ] OpenAI direct
- [x] Local / HPC-hosted (vLLM, Ollama, …)
- [ ] Azure / GCCcloud / other approved cloud
- [ ] Other → …

### I2. Local / HPC models
- [x] Have or will run Qwen (or similar) on HPC
- [ ] GPU access reliable
- [ ] CPU-only acceptable for small models
- [ ] Not available — cloud BYOK only
- → Model names / sizes if known: …qwen3.8 27b north mini somrthing

### I3. Default routing dream (fill blanks)
- Planning / hard reasoning → …planning legacy software overhauls, auto routing
- Bulk coding / refactors → …idk
- Quick ask / trivia → …idk
- Embeddings / search (if any) → … there is 1 embedding model on our local provider
- Fallback when primary fails → …

### I4. Cost / quota
- [ ] Cost almost irrelevant
- [ ] Keep it reasonable
- [x] Strict personal budget → $20 to 100… / month
- [x] Prefer local whenever quality is “good enough”
- [ ] Other → …

### I5. Tool-calling reliability priority
- [x] Must be excellent (ops scripts)
- [ ] Good enough for coding
- [ ] OK to babysit weaker local models
- [ ] Other → …

---

## J — Memory (Obsidian / docs)

### J1. Vault role for agents (check all you want)
- [x] Personal second brain
- [x] Runbooks / how-tos
- [x] Experiment logs
- [x] Architecture Decision Records
- [x] “Lessons learned” from agent failures
- [ ] Meeting notes
- [x] Glossaries / acronym dictionary
- [x] Generated reports / artifacts
- [ ] Do **not** write to vault unless asked
- [ ] Other → …

### J2. Current vault path OK?
- [x] Yes: `KnowledgeBase/CodeVault`
- [ ] No → correct path: …

### J3. Structure preferences
- [x] Agent may create folders/notes
- [ ] Only append to specific inbox note
- [ ] Use daily notes
- [ ] Tag conventions matter → …
- [ ] Other → …

### J4. External docs the agent should prefer
- [x] In-repo README / Sphinx / MkDocs
- [x] Confluence / SharePoint / Wiki
- [x] PDF manuals / scientific notes
- [x] Public MSC docs
- [ ] Other → …
- → Key entry URLs or paths: …

### J5. Glossaries to seed (list freely)
→ …

---

## K — Safety, secrets, compliance

### K1. Secret handling
- [x] Secrets only in `state/secrets.env` / password manager
- [x] Never paste secrets into chats
- [x] Agent may read env for local tools
- [x] Agent must ask before reading secret files
- [ ] Other → …

### K2. Shell / HPC guardrails (check what you want enforced)
- [x] No `rm -rf` without explicit confirm
- [ ] No writes outside project / scratch
- [ ] No git push unless asked
- [x] No force-push ever
- [x] No touching production paths
- [x] No mass job submission without confirm
- [ ] Prefer dry-run flags first
- [ ] Other → …

### K3. Production / ops boundaries
→ Paths, queues, or systems that are **read-only** for agents: …

### K4. Audit needs
- [x] Keep local logs of agent actions
- [x] Summaries into Obsidian
- [ ] Not important
- [ ] Other → …

---

## L — Pain points & success criteria

### L1. Current top frustrations (check up to 7)
- [x] Context bloat / agent forgets constraints
- [ ] Bad shell commands on HPC
- [ ] Wrong files edited
- [x] Weak planning before coding
- [ ] Slow / expensive models
- [ ] Tool calling failures
- [ ] Legacy code misunderstood
- [ ] GRIB/NetCDF/FST mishandled
- [x] French/English mix confusion
- [ ] Switching machines loses setup
- [x] Cursor / IDE lock-in or cost
- [x] Docs scattered / unsearchable
- [ ] Tests hard to run
- [ ] Other → …

### L2. Rate severity of each (optional 1–5)
| Pain                  | 1–5 |
| --------------------- | --- |
| Wrong edits           | →2  |
| HPC / modules / paths | →2  |
| Model quality         | →4  |
| Setup fragility       | →2  |
| Knowledge/memory      | →5  |
| Compliance anxiety    | →3  |

### L3. “Awesome” in 90 days looks like…
→ …

### L4. Must-win workflows (pick ≤5)
- [x] Explain legacy module and propose safe change
- [x] Add tests + CI for a library
- [ ] Debug failed batch job from logs
- [ ] Build/repair Singularity/Apptainer flow
- [x] Write dissemination / open-data endpoint
- [x] Convert / validate GRIB–NetCDF–FST pipelines
- [ ] Draft bilingual technical note
- [x] Refactor without changing scientific results
- [ ] Keep laptop + HPC agent configs in sync
- [ ] Other → …

### L5. Anti-goals (what the setup must NOT become)
→ …

---

## M — Harness wishlist

### M1. Always-on behaviour
- [x] Keep ponytail ultra
- [x] Keep caveman ultracave
- [x] Soften tone for docs / science writing
- [x] Want named modes (Architect / Ops / Science / Docs)
- [ ] Other → …

### M2. Skills you want created (check / add)
- [x] HPC job script helper (Slurm/…)
- [x] Module / env bootstrap checker
- [x] GRIB/NetCDF inspect & summarize
- [x] FST / RPN helpers
- [ ] Scientific bit-repro checklist
- [ ] Dissemination pipeline patterns
- [x] Open data / OGC checklist
- [ ] Singularity build-on-laptop / run-on-HPC
- [ ] Incident debug from logs
- [ ] ADR / runbook writer into Obsidian
- [x] Bilingual commit / PR templates
- [ ] Other → …cmc-io, cmc-postproc, cmc-stats, cmc-weather, rerun-geo, aether, cmc-colormaps, cmc-viz

### M3. Hooks automation
- [x] Lint / format after edits
- [x] Run unit tests on touch
- [x] Block forbidden paths
- [x] Auto-log session summary to vault
- [x] Spell/acronym check for MSC terms
- [ ] Other → …

### M4. Harness²-style self-improvement
- [ ] Interested: overnight OpenCode “gym” OK
- [x] Only inside Antigravity
- [ ] Manual: I edit skills, agent proposes diffs
- [ ] Not now
- [ ] Other → …

### M5. MCP / tools beyond Obsidian
- [ ] Obsidian only is enough for now
- [x] Want browser MCP
- [x] Want DB / Datamart query tools
- [x] Want internal wiki search
- [x] Want weather/data plot helpers
- [ ] Other → …

### M6. Packaging preference for the tailored setup
- [ ] Everything in `agy-stack-box` state/
- [x] Per-repo `.agents/` checked into git where allowed
- [x] Global `~/.gemini` personal layer + project overlays
- [x] Separate “CMC profile” vs “personal/open-source profile”
- [ ] Other → …we use ssm packaging forr many things, we have a cmds-agent-mcp with skills on it for docs,  ssm, hcron, explainers etc, once on hpc you will be able to inspect

---

## N — Free dump

Anything that didn’t fit — systems names, pet peeves, “agent always does X wrong”, links, screenshots descriptions, dream demos:

→

…

→

…

→

…

---

## Done checklist

- [x] I filled at least sections **A, B, C, H, I, L, M**
- [ ] I marked `#unsure` instead of guessing where needed
- [ ] Frontmatter `status` set to `filled` (or `partial`)
- [x] Ready for agent to turn this into a concrete harness plan

**When finished:** tell the agent “questionnaire filled” (or `@` this note). Prefer **partial + honest** over blank perfection.
