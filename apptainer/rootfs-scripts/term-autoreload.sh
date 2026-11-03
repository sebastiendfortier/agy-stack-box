#!/usr/bin/env bash
# Watch the Antigravity App for the "terminal pane never mounted" bug and fix it.
#
# On a cold app start, clicking Terminal spawns the shell (a /bin/bash -l child
# of the language server) but the pane never mounts — no xterm, nothing visible.
# Reloading the renderer mounts the pane with the already-running shell.
# Reproduced twice on 2026-11-03; the app is closed-source, so this is a
# workaround. Manual version: scripts/agy-term-fix.
#
# Runs detached inside the instance (spawned by scripts/agy-app). Exits after
# WATCH_SECONDS without seeing the broken state, so a healthy app costs nothing.
set -euo pipefail

LS_LOG="${HOME}/.config/Antigravity/logs/language_server.log"
WATCH_SECONDS="${AGY_TERM_WATCH_SECONDS:-180}"
POLL_SECONDS=3
STRIKES_NEEDED=2   # consecutive broken polls before reloading

NODE_BIN="/apps/node/bin/node"
[[ -x "$NODE_BIN" ]] || NODE_BIN="$(command -v node)"

echo "[$(date +%T)] watching for unmounted terminal pane (max ${WATCH_SECONDS}s)"

LS_LOG="$LS_LOG" WATCH_SECONDS="$WATCH_SECONDS" POLL_SECONDS="$POLL_SECONDS" \
STRIKES_NEEDED="$STRIKES_NEEDED" NODE_BIN="$NODE_BIN" \
"$NODE_BIN" --input-type=module - <<'NODE'

import { readFileSync } from 'node:fs';
import { execSync } from 'node:child_process';

const lsLog = process.env.LS_LOG;
const watchMs = Number(process.env.WATCH_SECONDS) * 1000;
const pollMs = Number(process.env.POLL_SECONDS) * 1000;
const strikesNeeded = Number(process.env.STRIKES_NEEDED);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const log = (s) => console.log(`[${new Date().toISOString().slice(11, 19)}] ${s}`);

// The language server logs the Electron debug endpoint it discovered; the port
// changes on every app start.
function cdpPort() {
  try {
    const hits = readFileSync(lsLog, 'utf8')
      .match(/ws:\/\/127\.0\.0\.1:(\d+)\/devtools\/browser\//g);
    return hits ? Number(hits[hits.length - 1].match(/:(\d+)\//)[1]) : null;
  } catch { return null; }
}

// Terminals the app spawned: /bin/bash -l children of the language server.
function shellCount() {
  try {
    const lsPid = execSync("pgrep -f 'language_server --standalone' | head -1").toString().trim();
    if (!lsPid) return 0;
    return Number(execSync(`pgrep -P ${lsPid} -f '^/bin/bash -l$' | wc -l`).toString().trim());
  } catch { return 0; }
}

async function withPage(fn) {
  const port = cdpPort();
  if (!port) throw new Error('no CDP endpoint yet');
  const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
  const page = targets.find((t) => t.type === 'page');
  if (!page) throw new Error('no page target');
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  let id = 0;
  const pending = new Map();
  const send = (method, params) => new Promise((resolve) => {
    const myId = ++id;
    pending.set(myId, resolve);
    ws.send(JSON.stringify({ id: myId, method, params: params || {} }));
  });
  ws.onmessage = (ev) => {
    const m = JSON.parse(ev.data);
    if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
  };
  await new Promise((r) => (ws.onopen = r));
  try { return await fn(send); } finally { ws.close(); }
}

const xtermCount = () => withPage((send) =>
  send('Runtime.evaluate', { expression: `document.querySelectorAll('.xterm').length`, returnByValue: true })
    .then((r) => r.result?.result?.value ?? 0));

let strikes = 0;
const deadline = Date.now() + watchMs;

while (Date.now() < deadline) {
  await sleep(pollMs);
  const shells = shellCount();
  if (shells === 0) { strikes = 0; continue; }   // no terminal opened yet

  let xterms;
  try { xterms = await xtermCount(); } catch { continue; }  // renderer not ready

  log(`poll: shells=${shells} xterms=${xterms}`);
  if (xterms > 0) { strikes = 0; continue; }     // pane mounted, all good

  if (++strikes < strikesNeeded) continue;
  log('shell without pane — reloading renderer');
  await withPage((send) => send('Page.reload'));
  for (let i = 0; i < 10; i++) {
    await sleep(2000);
    try {
      if ((await xtermCount()) > 0) { log('terminal pane mounted'); process.exit(0); }
    } catch { /* renderer restarting */ }
  }
  log('pane still not mounted after reload');
  process.exit(1);
}

log('nothing to do — exiting');
NODE
