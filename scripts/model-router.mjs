#!/usr/bin/env node
// model-router.mjs — OpenAI-compatible capability-escalation router.
//
// Sits between AGY's local proxy (desktop-service) and the real providers.
// A custom_models.json entry points at this router; the router walks a ladder
// of tiers, starting at the cheapest internal model and escalating to
// openrouter/auto only when the cheap model proves inadequate.
//
// Two kinds of escalation:
//   breadth  — decide before calling (prompt size, images, sticky)
//   depth    — decide after calling, but only before bytes reach the client
//
// Zero dependencies: Node >= 18 globals only (fetch, crypto, http).
//
// Usage: node model-router.mjs --config /agy-state/router/config.json

import fs from 'node:fs';
import http from 'node:http';
import crypto from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const MAX_BODY_BYTES = 32 * 1024 * 1024;

// ---------------------------------------------------------------------------
// args / config
// ---------------------------------------------------------------------------

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith('--')) continue;
    const key = a.slice(2);
    const val = argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[++i] : 'true';
    out[key] = val;
  }
  return out;
}

const argv = parseArgs(process.argv.slice(2));
const CONFIG_PATH = argv.config || process.env.MODEL_ROUTER_CONFIG;
if (!CONFIG_PATH) {
  console.error('fatal: --config is required');
  process.exit(2);
}

function readConfig(path) {
  const raw = JSON.parse(fs.readFileSync(path, 'utf8'));
  const policy = {
    commitAfterChars: 240,
    maxHoldMs: 1500,
    escalationTtlMs: 5 * 60 * 1000,
    largePromptTokens: 60000,
    repetitionMinRepeats: 3,
    // When the top rung is unusable (no credits, no key, provider down), retry
    // the free rung instead of returning an empty answer. See buildPlan().
    fallbackDown: true,
    refusalPatterns: [
      "\\bI can'(?:t| not)\\b",
      '\\bI cannot\\b',
      '\\bI am unable\\b',
      "\\bI'm unable\\b",
      "\\bI do(?:n't| not) have (?:access|the ability)\\b",
      '\\bas an AI\\b',
    ],
    ...(raw.policy || {}),
  };
  return { ...raw, policy };
}

const config = readConfig(CONFIG_PATH);
const clock = { now: () => Date.now() };
const tiers = (config.tiers || []).map((t, i) => ({
  index: i,
  name: t.name || `tier${i}`,
  baseUrl: String(t.baseUrl || '').replace(/\/+$/, ''),
  model: t.model,
  apiKeyEnv: t.apiKeyEnv || null,
  apiKey: t.apiKey || null,
  contextWindow: t.contextWindow || 131072,
  supportsTools: t.supportsTools !== false,
  timeoutMs: t.timeoutMs || 300000,
}));

if (tiers.length === 0) {
  console.error('fatal: config.tiers is empty');
  process.exit(2);
}

function keyFor(tier) {
  if (tier.apiKey) return tier.apiKey;
  if (tier.apiKeyEnv && process.env[tier.apiKeyEnv]) return process.env[tier.apiKeyEnv];
  return '';
}

// A tier is usable only if the credential it declares is actually present.
// A tier with no apiKeyEnv expects no credential (e.g. a local endpoint), so it
// counts as configured. This is what stops a missing OPENROUTER_API_KEY from
// turning into a stream of 401s at request time.
function tierConfigured(tier) {
  if (tier.apiKey) return true;
  if (!tier.apiKeyEnv) return true;
  return Boolean(process.env[tier.apiKeyEnv]);
}

const NO_CREDENTIALS_MSG =
  'No model credentials configured: set IHUB_API_KEY and/or OPENROUTER_API_KEY ' +
  'in state/secrets.env, then re-run ./scripts/setup-config.sh.';

// Shown when every rung failed. The router cannot call Google's built-in
// models itself (they authenticate with the Antigravity account, not an API
// key), so the only useful thing left is to tell the user where to go.
const FALLBACK_HINT =
  'No model answered: the free iHub tier and the OpenRouter tier both failed. ' +
  'Switch to a Google model in the model picker — those run on your Antigravity ' +
  'account and need no OpenRouter credits.';

// ---------------------------------------------------------------------------
// logging
// ---------------------------------------------------------------------------

const log = (...parts) => {
  console.error(`[router ${new Date().toISOString()}]`, ...parts);
};

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

const r1 = (x) => Math.round(x * 10) / 10;

function estimateTokens(messages) {
  // Deliberately crude (chars/4) — it only gates a threshold, not billing.
  let chars = 0;
  for (const m of messages || []) {
    if (typeof m?.content === 'string') chars += m.content.length;
    else if (Array.isArray(m?.content)) {
      for (const p of m.content) {
        if (typeof p?.text === 'string') chars += p.text.length;
        if (p?.type === 'image_url' || p?.type === 'image') chars += 2000;
      }
    }
    for (const tc of m?.tool_calls || []) {
      chars += JSON.stringify(tc?.function?.arguments ?? '').length;
    }
  }
  if (messages?.[0]?.role === 'system') chars += 0;
  return Math.ceil(chars / 4);
}

function hasImage(messages) {
  return (messages || []).some(
    (m) => Array.isArray(m?.content) && m.content.some((p) => p?.type === 'image_url' || p?.type === 'image'),
  );
}

function lastUserText(messages) {
  for (let i = (messages || []).length - 1; i >= 0; i--) {
    const m = messages[i];
    if (m?.role !== 'user') continue;
    if (typeof m.content === 'string') return m.content;
    if (Array.isArray(m.content)) {
      return m.content.filter((p) => typeof p?.text === 'string').map((p) => p.text).join('\n');
    }
    return '';
  }
  return '';
}

function matchesAny(text, patterns) {
  if (!text) return false;
  for (const p of patterns) {
    try {
      if (new RegExp(p, 'i').test(text)) return true;
    } catch {
      /* ignore bad pattern */
    }
  }
  return false;
}

function conversationKey(messages) {
  // Stable-ish session fingerprint: system prompt + first user turn.
  const sys = (messages || []).find((m) => m?.role === 'system');
  const usr = (messages || []).find((m) => m?.role === 'user');
  const seed = `${typeof sys?.content === 'string' ? sys.content : ''}\u0000${
    typeof usr?.content === 'string' ? usr.content : JSON.stringify(usr?.content ?? '')
  }`;
  return crypto.createHash('sha256').update(seed).digest('hex').slice(0, 16);
}

// Sticky escalation: once a conversation escalates, keep starting escalated
// for a while so we don't ping-pong on every single turn.
const sticky = new Map(); // key -> expiry epoch ms
function isSticky(key) {
  const until = sticky.get(key);
  if (!until) return false;
  if (clock.now() > until) {
    sticky.delete(key);
    return false;
  }
  return true;
}
function markSticky(key, reason) {
  sticky.set(key, clock.now() + config.policy.escalationTtlMs);
  log(`sticky ${key} (${reason}) for ${Math.round(config.policy.escalationTtlMs / 1000)}s`);
}
// A fallback that succeeded proves the top rung is not worth starting on right
// now, so drop the sticky entry instead of paying for one failed call per turn.
function clearSticky(key, reason) {
  if (sticky.delete(key)) log(`cleared sticky ${key} (${reason})`);
}

const stats = {
  startedAt: Date.now(),
  requests: 0,
  byTier: {},
  escalations: 0,
  escalationReasons: {},
  fallbacks: 0,
  degraded: 0,
  failures: 0,
};
function bump(obj, k) {
  obj[k] = (obj[k] || 0) + 1;
}

// ---------------------------------------------------------------------------
// pre-flight: choose a starting tier
// ---------------------------------------------------------------------------

function chooseStart(messages, body) {
  const tokens = estimateTokens(messages);
  const tools = Array.isArray(body.tools) ? body.tools.length : 0;
  const toolChoiceNone = body.tool_choice === 'none';
  const needsTools = tools > 0 && !toolChoiceNone;
  const key = conversationKey(messages);
  const notes = [];

  let start = 0;
  if (isSticky(key)) {
    start = tiers.length - 1;
    notes.push('sticky');
  }
  if (hasImage(messages)) {
    start = tiers.length - 1;
    notes.push('image');
  }
  if (tokens > config.policy.largePromptTokens) {
    start = tiers.length - 1;
    notes.push(`prompt>${config.policy.largePromptTokens}tok`);
  }
  // Skip tiers whose context window can't hold the prompt, that we know can't
  // do tool calls when a tool call is required, or whose credential is absent.
  while (start < tiers.length - 1) {
    const t = tiers[start];
    if (!tierConfigured(t)) {
      notes.push(`${t.name}:no-key`);
      start++;
      continue;
    }
    if (tokens * 1.2 > t.contextWindow) {
      notes.push(`${t.name}:no-context`);
      start++;
      continue;
    }
    if (needsTools && !t.supportsTools) {
      notes.push(`${t.name}:no-tools`);
      start++;
      continue;
    }
    break;
  }
  // Sticky/image/large-prompt jumps land on the top rung. If that rung has no
  // credential, walk back down to the best usable one instead of failing.
  if (!tierConfigured(tiers[start])) {
    for (let i = start; i >= 0; i--) {
      if (tierConfigured(tiers[i])) {
        notes.push(`${tiers[start].name}:no-key->${tiers[i].name}`);
        start = i;
        break;
      }
    }
  }
  return { start, key, notes, needsTools, tokens };
}

// ---------------------------------------------------------------------------
// post-flight: is this answer good enough?
// ---------------------------------------------------------------------------

const DEPTH_RULES = [
  ['httpError', (value) => `http:${value}`],
  ['emptied', () => 'empty'],
  ['truncated', () => 'truncated'],
  ['badToolCall', (value) => `bad-tool:${value}`],
  ['toolNotAllowed', (value) => `tool-not-allowed:${value}`],
  ['refusal', () => 'refusal'],
  ['repetition', () => 'repetition'],
];

function evaluateDepth(state) {
  const hard = [];
  for (const [field, reason] of DEPTH_RULES) {
    if (state[field]) hard.push(reason(state[field]));
  }
  return { escalate: hard.length > 0, hard, soft: [] };
}

const REFUSAL_RE = () => config.policy.refusalPatterns;

function detectRepetition(text) {
  // Short answers can still be degenerate: three identical meaningful lines
  // is a loop even if the whole reply is only ~60 characters.
  if (!text || text.length < 24) return false;
  const lines = text.split('\n').map((l) => l.trim()).filter(Boolean);
  const counts = new Map();
  for (const l of lines) {
    if (l.length < 8) continue;
    counts.set(l, (counts.get(l) || 0) + 1);
    if (counts.get(l) >= config.policy.repetitionMinRepeats) return true;
  }
  // char-level loop: same 24-char window repeated
  for (let i = 0; i + 72 <= text.length; i += 12) {
    const w = text.slice(i, i + 24);
    if (text.slice(i + 24, i + 72) === w + w) return true;
  }
  return false;
}

function allowedToolNames(body) {
  if (!Array.isArray(body.tools)) return null;
  const names = new Set();
  for (const t of body.tools) {
    const n = t?.function?.name || t?.name;
    if (n) names.add(n);
  }
  return names;
}

// ---------------------------------------------------------------------------
// upstream call
// ---------------------------------------------------------------------------

function buildUpstreamRequest(tier, body) {
  const headers = { 'content-type': 'application/json' };
  const k = keyFor(tier);
  if (k) headers.authorization = `Bearer ${k}`;
  const payload = { ...body, model: tier.model };
  delete payload.user;
  return { url: `${tier.baseUrl}/chat/completions`, headers, payload };
}

async function postUpstream(tier, body, signal) {
  const { url, headers, payload } = buildUpstreamRequest(tier, body);
  const ac = new AbortController();
  const timer = setTimeout(() => ac.abort(new Error('timeout')), tier.timeoutMs);
  if (signal) signal.addEventListener('abort', () => ac.abort(new Error('client-abort')), { once: true });
  try {
    const res = await fetch(url, {
      method: 'POST',
      headers,
      body: JSON.stringify(payload),
      signal: ac.signal,
    });
    return res;
  } finally {
    clearTimeout(timer);
  }
}

// ---------------------------------------------------------------------------
// non-streaming attempt
// ---------------------------------------------------------------------------

async function attemptNonStream(tier, body, ctx) {
  let res;
  try {
    res = await postUpstream(tier, body);
  } catch (err) {
    return { state: { httpError: err?.name === 'AbortError' ? 'timeout' : 'network' }, json: null, res: null };
  }
  if (!res.ok) {
    let detail = '';
    try {
      detail = (await res.text()).slice(0, 400);
    } catch {}
    return { state: { httpError: `${res.status}` }, json: null, res, detail };
  }
  let json;
  try {
    json = await res.json();
  } catch {
    return { state: { httpError: 'bad-json' }, json: null, res };
  }

  const choice = json?.choices?.[0];
  if (!choice || typeof choice !== 'object' || !choice.message || typeof choice.message !== 'object') {
    return { state: { httpError: 'bad-payload' }, json: null, res };
  }
  const msg = choice.message;
  const content = typeof msg.content === 'string' ? msg.content : '';
  const toolCalls = Array.isArray(msg.tool_calls) ? msg.tool_calls : [];
  const allowed = allowedToolNames(body);

  const state = {};
  const reasoning = typeof msg.reasoning_content === 'string' ? msg.reasoning_content : '';
  if (!content.trim() && !reasoning.trim() && toolCalls.length === 0) state.emptied = true;
  if (choice.finish_reason === 'length') state.truncated = true;
  if (matchesAny(content, REFUSAL_RE())) state.refusal = true;
  if (detectRepetition(content)) state.repetition = true;

  for (const tc of toolCalls) {
    const name = tc?.function?.name;
    if (!name) state.badToolCall = 'no-name';
    else if (allowed && !allowed.has(name)) state.toolNotAllowed = name;
    const args = tc?.function?.arguments;
    if (typeof args === 'string' && args.trim()) {
      try {
        JSON.parse(args);
      } catch {
        state.badToolCall = 'bad-args';
      }
    }
  }
  return { state, json, res };
}

// ---------------------------------------------------------------------------
// streaming attempt
// ---------------------------------------------------------------------------

function sseFrames(buf) {
  // Returns [frames, rest]
  const frames = [];
  let idx;
  while ((idx = buf.indexOf('\n\n')) !== -1) {
    frames.push(buf.slice(0, idx + 2));
    buf = buf.slice(idx + 2);
  }
  return [frames, buf];
}

function rewriteModel(frameText, modelName) {
  const line = frameText.trim();
  if (!line.startsWith('data:')) return frameText;
  const data = line.slice(5).trim();
  if (!data || data === '[DONE]') return frameText;
  try {
    const obj = JSON.parse(data);
    if (obj && typeof obj === 'object') {
      obj.model = modelName;
      return `data: ${JSON.stringify(obj)}\n\n`;
    }
  } catch {}
  return frameText;
}

async function attemptStream(tier, body, ctx, res, clientModel, begin) {
  let upstream;
  try {
    upstream = await postUpstream(tier, body);
  } catch (err) {
    return { state: { httpError: err?.name === 'AbortError' ? 'timeout' : 'network' } };
  }
  if (!upstream.ok) {
    let detail = '';
    try {
      detail = (await upstream.text()).slice(0, 400);
    } catch {}
    return { state: { httpError: `${upstream.status}` }, detail };
  }

  const p = config.policy;
  const allowed = allowedToolNames(body);
  const state = {};
  const held = [];
  let heldText = '';
  let heldReasoning = '';
  let committed = false;
  const startedAt = clock.now();

  const toolAcc = new Map(); // index -> { name, args }
  let finishReason = null;

  const commit = () => {
    if (committed) return;
    committed = true;
    begin();
    for (const f of held) res.write(rewriteModel(f, clientModel));
    held.length = 0;
  };

  const reader = upstream.body.getReader();
  const dec = new TextDecoder();
  let buf = '';
  let sawDone = false;
  let sawChoice = false;

  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      buf += dec.decode(value, { stream: true });
      const [frames, rest] = sseFrames(buf);
      buf = rest;

      for (const frame of frames) {
        const trimmed = frame.trim();
        if (trimmed.startsWith('data:')) {
          const data = trimmed.slice(5).trim();
          if (data === '[DONE]') {
            // Do NOT commit here: a terminal marker with no bytes flushed yet
            // still leaves us free to escalate silently.
            sawDone = true;
            break;
          }
          try {
            const obj = JSON.parse(data);
            const choice = obj?.choices?.[0];
            if (!choice || typeof choice !== 'object' || (choice.delta && typeof choice.delta !== 'object')) {
              state.httpError = 'bad-payload';
              continue;
            }
            sawChoice = true;
            const delta = choice.delta || {};
            if (typeof delta.content === 'string' && delta.content) heldText += delta.content;
            if (typeof delta.reasoning_content === 'string' && delta.reasoning_content) heldReasoning += delta.reasoning_content;
            for (const tc of delta.tool_calls || []) {
              const slot = toolAcc.get(tc.index ?? 0) || { name: '', args: '' };
              if (tc.function?.name) slot.name = tc.function.name;
              if (typeof tc.function?.arguments === 'string') slot.args += tc.function.arguments;
              toolAcc.set(tc.index ?? 0, slot);
            }
            if (choice?.finish_reason) finishReason = choice.finish_reason;

            if (!committed) {
              const toolsComplete =
                toolAcc.size > 0 &&
                [...toolAcc.values()].every((s) => s.name && (!s.args || (() => {
                  try { JSON.parse(s.args); return true; } catch { return false; }
                })()));
              const enoughText = heldText.length >= p.commitAfterChars;
              const timedOut = clock.now() - startedAt > p.maxHoldMs && (heldText.length > 0 || toolAcc.size > 0);
              if (!state.httpError && (toolsComplete || enoughText || timedOut)) commit();
            }
          } catch {
            if (!committed) {
              // unparseable upstream frame — treat as a bad signal, keep holding
              state.httpError = 'bad-frame';
            }
          }
        }
        if (committed) res.write(rewriteModel(frame, clientModel));
        else held.push(frame);
      }
    }
  } catch (err) {
    if (!committed) return { state: { httpError: 'stream' } };
    log('stream error after commit (unrecoverable):', err?.message || err);
    return { state: {}, committed: true };
  }

  // ---- end of stream: evaluate ----
  if (!committed) {
    if (sawDone && !sawChoice) state.httpError = 'bad-payload';
    if (!heldText.trim() && !heldReasoning.trim() && toolAcc.size === 0) state.emptied = true;
    if (finishReason === 'length') state.truncated = true;
    if (matchesAny(heldText, REFUSAL_RE())) state.refusal = true;
    if (detectRepetition(heldText)) state.repetition = true;
    for (const s of toolAcc.values()) {
      if (!s.name) state.badToolCall = 'no-name';
      else if (allowed && !allowed.has(s.name)) state.toolNotAllowed = s.name;
      if (s.args) {
        try { JSON.parse(s.args); } catch { state.badToolCall = 'bad-args'; }
      }
    }
    // Nothing was flushed, so the caller may still escalate.
    return { state, committed: false, held };
  }

  return { state: {}, committed: true };
}

// ---------------------------------------------------------------------------
// main routing loop
// ---------------------------------------------------------------------------

// Attempt plan: start at the chosen rung, climb to the top, then — if the top
// rung turns out to be unusable — come back down to the free rung once. Without
// that last step a dead OpenRouter key turns every escalated turn into a blank
// answer. FALLBACK_HINT is what the user sees when even that fails.
function buildPlan(start) {
  const plan = [];
  for (let i = start; i < tiers.length; i++) {
    if (!tierConfigured(tiers[i])) continue;
    plan.push({ tier: i, kind: i === start ? 'start' : 'escalate' });
  }
  const lastTier = plan.length ? plan[plan.length - 1].tier : -1;
  const canFallBack =
    config.policy.fallbackDown !== false &&
    tiers.length > 1 &&
    lastTier !== 0 &&
    tierConfigured(tiers[0]);
  if (canFallBack) plan.push({ tier: 0, kind: 'fallback' });
  return plan;
}

// Did this attempt produce something we can hand to the client? An empty
// completion is a failure even though the HTTP call itself succeeded.
function isUsable(out, stream) {
  if (out.state.emptied || out.state.httpError) return false;
  if (stream) return Boolean(out.held && out.held.length);
  return Boolean(out.json);
}

function safeSignal(reason) {
  return String(reason || 'unusable').replace(/[^a-zA-Z0-9:_-]/g, '_').slice(0, 80);
}

function emitAuthFailure(res, tried) {
  res.writeHead(502, {
    'content-type': 'application/json',
    ...(tried.length ? { 'x-router-escalated-from': tried.join(' ') } : {}),
  });
  res.end(JSON.stringify({ error: { message: 'Model provider authentication failed.', type: 'upstream_error', code: 'provider_auth' } }));
}

// Every rung failed. Say so, and point at the one thing that still works.
function emitExhausted(res, failed, tried) {
  const detail =
    failed.map((f) => `${f.tier}:${f.reasons.join(',')}`).join(' | ') || 'no attempt';
  log(`all tiers failed: ${detail}`);
  stats.failures++;
  const message = FALLBACK_HINT;
  if (res.headersSent) {
    try {
      res.write(`data: ${JSON.stringify({ error: { message, type: 'upstream_error' } })}\n\n`);
      res.write('data: [DONE]\n\n');
      res.end();
    } catch {}
    return;
  }
  res.writeHead(502, {
    'content-type': 'application/json',
    ...(tried.length ? { 'x-router-escalated-from': tried.join(' ') } : {}),
  });
  res.end(JSON.stringify({ error: { message, type: 'upstream_error', code: 'all_tiers_failed' } }));
}

async function route(body, res) {
  stats.requests++;

  if (!tiers.some(tierConfigured)) {
    log('no model credentials configured — refusing to guess');
    res.writeHead(503, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ error: { message: NO_CREDENTIALS_MSG, type: 'configuration_error' } }));
    return;
  }

  const { start, key, notes, needsTools } = chooseStart(body.messages, body);
  // TODO(PLAN-SSM §4): upstream retry intent has no supported request marker;
  // do not infer a retry from identical messages.
  const stream = body.stream === true;
  const clientModel = body.model || 'auto';
  const plan = buildPlan(start);
  const missingKeyNote = notes.find((note) => note.endsWith(':no-key') || note.includes(':no-key->'));
  const preflightDegraded = missingKeyNote
    ? `${safeSignal(missingKeyNote.split(':')[0])}:no-key`
    : null;
  const tried = [];
  const failed = [];


  for (let p = 0; p < plan.length; p++) {
    const { tier: ti, kind } = plan[p];
    const tier = tiers[ti];
    const isLast = p === plan.length - 1;
    // Known before the attempt: we only reach a fallback because a rung failed.
    const degraded = kind === 'fallback' && failed.length
      ? `${failed[0].tier}:${safeSignal(failed[0].reasons[0])}`
      : p === 0 ? preflightDegraded : null;
    if (kind === 'fallback') {
      stats.fallbacks++;
      log(`fall back down to ${tier.name} (${degraded})`);
    }
    bump(stats.byTier, tier.name);
    const ctx = { needsTools, key, notes };

    if (stream) {
      let began = false;
      let headerDegraded = degraded;
      const begin = () => {
        if (began) return;
        began = true;
        res.writeHead(200, {
          'content-type': 'text/event-stream; charset=utf-8',
          'cache-control': 'no-cache',
          connection: 'keep-alive',
          'x-router-tier': tier.name,
          ...(tried.length ? { 'x-router-escalated-from': tried.join(' ') } : {}),
          ...(headerDegraded ? { 'x-router-degraded': headerDegraded } : {}),
        });
      };

      const out = await attemptStream(tier, body, ctx, res, clientModel, begin);
      if (out.committed) {
        res.write('data: [DONE]\n\n');
        res.end();
        return;
      }
      // Judge may still be in flight for a fast model — settle it before deciding.
      if (out.state.httpError === '401' || out.state.httpError === '403') {
        emitAuthFailure(res, tried);
        return;
      }
      const verdict = evaluateDepth(out.state);
      const reasons = [...verdict.hard];
      const usable = isUsable(out, stream);

      if (!usable || (verdict.escalate && !isLast)) {
        failed.push({ tier: tier.name, reasons: usable ? reasons : [...reasons, 'unusable'] });
        for (const r of reasons) bump(stats.escalationReasons, r);
        if (!isLast) {
          tried.push(`${tier.name}:${reasons.join(',')}`);
          stats.escalations++;
          log(`escalate ${tier.name} -> ${tiers[plan[p + 1].tier].name} [${reasons.join(',')}]`);
          continue;
        }
        log(`last attempt unusable on ${tier.name} [${reasons.join(',')}]`);
        continue;
      }

      // Accept: nothing was flushed yet, so replay the held frames now.
      if (verdict.escalate) headerDegraded = headerDegraded || safeSignal(reasons[0]);
      begin();
      if (headerDegraded) {
        stats.degraded++;
        log(`serving degraded answer from ${tier.name} (${headerDegraded})`);
      }
      for (const f of out.held) res.write(rewriteModel(f, clientModel));
      res.write('data: [DONE]\n\n');
      res.end();
      if (ti > 0) markSticky(key, failed[0]?.reasons[0] || 'escalated');
      else if (kind === 'fallback') clearSticky(key, 'fallback succeeded');
      return;
    }

    const out = await attemptNonStream(tier, body, ctx);
    if (out.state.httpError === '401' || out.state.httpError === '403') {
      emitAuthFailure(res, tried);
      return;
    }
    const verdict = evaluateDepth(out.state);
    const reasons = [...verdict.hard];
    const usable = isUsable(out, stream);

    if (!usable || (verdict.escalate && !isLast)) {
      failed.push({ tier: tier.name, reasons: usable ? reasons : [...reasons, 'unusable'] });
      for (const r of reasons) bump(stats.escalationReasons, r);
      if (!isLast) {
        tried.push(`${tier.name}:${reasons.join(',')}`);
        stats.escalations++;
        log(`escalate ${tier.name} -> ${tiers[plan[p + 1].tier].name} [${reasons.join(',')}]`);
        continue;
      }
      log(`last attempt unusable on ${tier.name} [${reasons.join(',')}]`);
      continue;
    }

    out.json.model = clientModel;
    res.setHeader('x-router-tier', tier.name);
    if (tried.length) res.setHeader('x-router-escalated-from', tried.join(' '));
    const warn = degraded || (verdict.escalate ? safeSignal(reasons[0]) : null);
    if (warn) {
      stats.degraded++;
      res.setHeader('x-router-degraded', warn);
      log(`serving degraded answer from ${tier.name} (${warn})`);
    }
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify(out.json));
    if (ti > 0) markSticky(key, failed[0]?.reasons[0] || 'escalated');
    else if (kind === 'fallback') clearSticky(key, 'fallback succeeded');
    return;
  }

  emitExhausted(res, failed, tried);
}

// ---------------------------------------------------------------------------
// http server
// ---------------------------------------------------------------------------

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', (c) => {
      size += c.length;
      if (size > MAX_BODY_BYTES) {
        reject(new Error('body too large'));
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

const authToken = config.authToken || process.env.MODEL_ROUTER_TOKEN || '';

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');

  if (url.pathname === '/healthz') {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({
      status: 'ok',
      service: 'model-router',
      pid: process.pid,
      tiers: tiers.map((t) => ({ name: t.name, model: t.model, supportsTools: t.supportsTools })),
      uptime: Math.round((clock.now() - stats.startedAt) / 1000),
    }));
    return;
  }

  if (url.pathname === '/stats') {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ ...stats, sticky: [...sticky.keys()] }, null, 2));
    return;
  }

  const isChat =
    url.pathname === '/v1/chat/completions' ||
    url.pathname === '/chat/completions' ||
    url.pathname === '/auto' ||
    url.pathname === '/v1/auto';

  if (!isChat || req.method !== 'POST') {
    res.writeHead(404, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ error: { message: 'not found' } }));
    return;
  }

  if (authToken) {
    const got = (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
    if (got !== authToken) {
      res.writeHead(401, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ error: { message: 'Authentication Error, No api key passed in.', type: 'auth_error', code: '401' } }));
      return;
    }
  }

  let body;
  try {
    body = JSON.parse(await readBody(req));
  } catch (err) {
    res.writeHead(400, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ error: { message: `bad request: ${err.message}` } }));
    return;
  }

  // Streaming headers are written by the router once the winning tier is known,
  // so x-router-tier can reflect who actually answered.

  try {
    await route(body, res);
  } catch (err) {
    log('route failed:', err?.stack || err);
    if (!res.headersSent) {
      res.writeHead(500, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ error: { message: `model-router: ${err.message}` } }));
    } else {
      try { res.end(); } catch {}
    }
  }
});

const isMain = process.argv[1] && path.resolve(fileURLToPath(import.meta.url)) === path.resolve(process.argv[1]);
if (isMain) {
  const [host, portStr] = String(config.listen || '127.0.0.1:49700').split(':');
  const port = Number(portStr || 49700);
  server.listen(port, host, () => {
    log(`listening on http://${host}:${port}`);
    log(`ladder: ${tiers.map((t) => `${t.name}(${t.model})`).join(' -> ')}`);
    for (const t of tiers) {
      if (!keyFor(t)) log(`warning: tier "${t.name}" has no api key (env ${t.apiKeyEnv})`);
    }
  });
}

export { route, chooseStart, buildPlan, evaluateDepth, sticky, clock, server };
