# 2026-11-02 — Router Phase 2 and public-repo hygiene
Mode: Code
Repo/path: `agy-stack-box`
Goal: Implement the deterministic router rewrite, complete approved hygiene edits, preserve/commit carryover changes, and capture the latest CLI diagnosis.

## Done
- Replaced judge and heuristic breadth/depth routing with a deterministic hard-signal rules table. Kept capability/context skips, sticky/image/large-prompt routing, repetition detection, and the existing fallback-down behavior.
- Added reasoning-aware empty-response handling, stable malformed/network/timeout signals, terminal provider-auth handling for 401/403, safe degraded headers, a testable import surface, and an injectable clock.
- Added Node tests for escalation, auth failures, timeout/network, malformed/truncated/refusal/empty responses, reasoning-only output, fallback/degraded headers, sticky expiry, streaming, and `/v1/models` 404.
- Removed embedded remote MCP endpoint strings. Added optional URL rendering and env placeholders; local Obsidian MCP remains configured from local secrets/port.
- Removed the hard-coded site proxy default while retaining caller-provided proxy variables. Added an ignore rule for generated `.ssm` bundles.
- CLI “models unavailable” diagnosis from the latest chat: Antigravity OAuth was not logged in. User action: run `./scripts/agy-cli` and complete the browser login.
- Reviewed existing pre-Phase-2 edits and retained them; no push/publish.

## Checks
- `npm test`: 24 passing tests.
- `node --check scripts/model-router.mjs`: passed.
- `bash -n scripts/setup-config.sh scripts/common.sh ssm/validate_ssm_package.sh`: passed.
- Router config template parsed as JSON after placeholder substitution.
- Public-source diff scan: no site hostname or specific site filesystem path added by tracked edits. Generic `/home` runtime paths and build safety checks remain.

## Blocked / follow-up
- SSM first-load currently seeds `secrets.env`; it does not run `setup-config.sh` or include the MCP renderer. Optional remote MCP URL rendering therefore applies to the `setup-config.sh` path; integrating it into SSM would expand the explicitly out-of-scope SSM changes.
- Did not run `ssm/validate_ssm_package.sh`: it rebuilds/removes generated package staging output, and the existing ignored `.ssm` bundle is very large. Syntax checks and unit tests were run instead.
- Left untracked planning/handoff files untouched because they contain site-specific fingerprints. Left generated bundle on disk and ignored it; did not stage it.

## Lessons
- Keep auth failures distinct from retryable provider failures; never relay provider response bodies into user-facing errors or headers.
- Inject time and isolate sticky state in tests so routing tests remain deterministic.
- Optional endpoint templates must omit unset remote servers rather than emit unresolved template strings.
