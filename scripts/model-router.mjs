#!/usr/bin/env node
// model-router.mjs — OpenAI-compatible capability-escalation router.
//
// Sits between AGY's local proxy (desktop-service) and the real providers.
// A custom_models.json entry points at this router; the router walks a ladder
// of tiers, starting at the cheapest internal model and escalating to
// openrouter/auto only when the cheap model proves inadequate.
//
// Two kinds of escalation:
//   breadth  — decide before calling (prompt size, images, tool load, sticky)
//   depth    — decide after calling, but only before bytes reach the client
//
// Zero dependencies: Node >= 18 globals only (fetch, crypto, http).
//
// Usage: node model-router.mjs --config /agy-state/router/config.json

import fs from 'node:fs';
import http from 'node:http';
import crypto from 'node:crypto';

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
    maxToolsForSmall: 12,
    repetitionMinRepeats: 3,
    refusalPatterns: [
      "\\bI can'(?:t| not)\\b",
      '\\bI cannot\\b',
      '\\bI am unable\\b',
      "\\bI'm unable\\b",
      "\\bI do(?:n't| not) have (?:access|the ability)\\b",
      '\\bas an AI\\b',
    ],
    actionIntentPatterns: [
      '\\b(edit|write|create|delete|remove|rename|move|fix|patch|update|implement|add|refactor)\\b',
      '\\b(run|execute|install|build|compile|test|lint|deploy)\\b',
      '\\b(read|open|inspect|search|grep|find|list)\\b',
    ],
    ...(raw.policy || {}),
  };
  return { ...raw, policy };
}

const config = readConfig(CONFIG_PATH);
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
  if (Date.now() > until) {
    sticky.delete(key);
    return false;
  }
  return true;
}
function markSticky(key, reason) {
  sticky.set(key, Date.now() + config.policy.escalationTtlMs);
  log(`sticky ${key} (${reason}) for ${Math.round(config.policy.escalationTtlMs / 1000)}s`);
}

const stats = {
  startedAt: Date.now(),
  requests: 0,
  byTier: {},
  escalations: 0,
  escalationReasons: {},
  failures: 0,
  judge: { calls: 0, hard: 0, easy: 0, failed: 0 },
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
  if (needsTools && tools > config.policy.maxToolsForSmall) {
    start = Math.max(start, 1 < tiers.length ? 1 : 0);
    notes.push(`tools=${tools}`);
  }
  // Skip tiers whose context window can't hold the prompt, or that we know
  // can't do tool calls when a tool call is required.
  while (start < tiers.length - 1) {
    const t = tiers[start];
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
  return { start, key, notes, needsTools, tokens };
}

// ---------------------------------------------------------------------------
// difficulty judge: ask the free tier to rate the task before we trust its answer
// ---------------------------------------------------------------------------
//
// Runs concurrently with the real attempt, so it adds no latency. Its verdict
// only matters while the answer is still in the hold buffer — if the judge says
// "hard", we drop the cheap answer before a single byte reaches the client.

const JUDGE_MARKER = 'ROUTING_JUDGE';

const JUDGE_SYSTEM = [
  'ROUTING_JUDGE',
  'You classify how hard a request is for a small 27B coding model.',
  'Answer with STRICT JSON only, no prose:',
  '{"difficulty":"easy"|"hard","confidence":0.0-1.0,"why":"<10 words>"}',
  '',
  'Call it "hard" when the request needs ANY of:',
  '- reasoning about behaviour across several files or an unknown codebase',
  '- debugging where the cause is not given',
  '- design/architecture trade-offs or a plan',
  '- writing non-trivial code, or a refactor with judgement calls',
  '- ambiguity: the request does not say what/where concretely',
  '- long context, several constraints to satisfy at once',
  '',
  'Call it "easy" when the request is:',
  '- a single concrete mechanical action (read/open/list/grep a named thing)',
  '- run one command and report',
  '- a small edit with the target and intent stated',
  '- a definition or short factual explanation',
  '- a follow-up to something already established',
  '',
  'When genuinely unsure, answer "hard".',
].join('\n');

function judgeConfigActive() {
  const j = config.judge;
  return Boolean(j && j.enabled);
}

function parseVerdict(text) {
  if (!text) return null;
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start === -1 || end <= start) return null;
  try {
    const obj = JSON.parse(text.slice(start, end + 1));
    const difficulty = String(obj.difficulty || '').toLowerCase();
    if (difficulty !== 'easy' && difficulty !== 'hard') return null;
    const confidence = Number.isFinite(Number(obj.confidence)) ? Number(obj.confidence) : 0.5;
    return { difficulty, confidence, why: String(obj.why || '').slice(0, 80) };
  } catch {
    return null;
  }
}

function judgeTier() {
  const j = config.judge || {};
  if (j.tier) {
    const found = tiers.find((t) => t.name === j.tier);
    if (found) return found;
  }
  return tiers[0];
}

async function askJudge(body) {
  const j = config.judge || {};
  const tier = judgeTier();
  const threshold = Number.isFinite(Number(j.threshold)) ? Number(j.threshold) : 0.6;
  const lastUser = lastUserText(body.messages).slice(0, 4000);
  if (!lastUser.trim()) return null;

  const toolNames = allowedToolNames(body);
  const contextLine = [
    `turn_number=${(body.messages || []).filter((m) => m?.role === 'user').length}`,
    `prompt_chars=${estimateTokens(body.messages) * 4}`,
    `tools_available=${toolNames ? toolNames.size : 0}`,
  ].join(' ');

  stats.judge.calls++;
  try {
    const res = await postUpstream(tier, {
      model: tier.model,
      messages: [
        { role: 'system', content: JUDGE_SYSTEM },
        { role: 'user', content: `${contextLine}\n\nREQUEST:\n${lastUser}` },
      ],
      max_tokens: Number.isFinite(Number(j.maxTokens)) ? Number(j.maxTokens) : 2048,
      temperature: 0,
    });
    if (!res.ok) {
      stats.judge.failed++;
      return null;
    }
    const json = await res.json();
    const text = json?.choices?.[0]?.message?.content || '';
    const verdict = parseVerdict(text);
    if (!verdict) {
      stats.judge.failed++;
      return null;
    }
    const hard = verdict.difficulty === 'hard' && verdict.confidence >= threshold;
    if (hard) stats.judge.hard++;
    else stats.judge.easy++;
    log(`judge ${tier.name}: ${verdict.difficulty} conf=${verdict.confidence} -> ${hard ? 'escalate' : 'keep'} (${verdict.why})`);
    return { ...verdict, hard };
  } catch (err) {
    stats.judge.failed++;
    log(`judge failed (${err?.message || err}) — staying on the cheap tier`);
    return null;
  }
}


// ---------------------------------------------------------------------------
// post-flight: is this answer good enough?
// ---------------------------------------------------------------------------

function evaluateDepth(state) {
  const p = config.policy;
  const hard = [];
  const soft = [];

  if (state.httpError) hard.push(`http:${state.httpError}`);
  if (state.emptied) hard.push('empty');
  if (state.truncated) hard.push('truncated');
  if (state.badToolCall) hard.push(`bad-tool:${state.badToolCall}`);
  if (state.toolNotAllowed) hard.push(`tool-not-allowed:${state.toolNotAllowed}`);

  // A refusal or a degenerate loop is decisive on its own: the model has
  // declared it won't, or has visibly broken. No second signal needed.
  if (state.refusal) hard.push('refusal');
  if (state.repetition) hard.push('repetition');
  if (state.missingToolCall) hard.push('no-tool-call');
  if (state.judgeHard) hard.push('judge:hard');
  if (state.shortAnswer) soft.push('very-short');

  return { escalate: hard.length > 0 || soft.length >= 2, hard, soft };
}

const REFUSAL_RE = () => config.policy.refusalPatterns;
const INTENT_RE = () => config.policy.actionIntentPatterns;

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
    return { state: { httpError: `network:${err?.message || err}` }, json: null, res: null };
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

  const choice = json?.choices?.[0] || {};
  const msg = choice.message || {};
  const content = typeof msg.content === 'string' ? msg.content : '';
  const toolCalls = Array.isArray(msg.tool_calls) ? msg.tool_calls : [];
  const allowed = allowedToolNames(body);

  const state = {};
  if (!content.trim() && toolCalls.length === 0) state.emptied = true;
  if (choice.finish_reason === 'length') state.truncated = true;
  if (matchesAny(content, REFUSAL_RE())) state.refusal = true;
  if (detectRepetition(content)) state.repetition = true;
  if (ctx.needsTools && toolCalls.length === 0 && matchesAny(lastUserText(body.messages), INTENT_RE())) {
    state.missingToolCall = true;
  }
  if (content.trim() && content.trim().length < 12 && toolCalls.length === 0) state.shortAnswer = true;

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
    return { state: { httpError: `network:${err?.message || err}` } };
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
  let committed = false;
  const startedAt = Date.now();

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

  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      buf += dec.decode(value, { stream: true });
      const [frames, rest] = sseFrames(buf);
      buf = rest;

      for (const frame of frames) {
        // The judge may finish while we are still holding: drop the cheap
        // answer and let the caller escalate, before anything is committed.
        if (!committed && ctx.judgeState?.verdict?.hard) {
          try { await reader.cancel(); } catch {}
          return { state: { judgeHard: true }, committed: false };
        }
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
            const delta = choice?.delta || {};
            if (typeof delta.content === 'string' && delta.content) heldText += delta.content;
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
              const timedOut = Date.now() - startedAt > p.maxHoldMs && (heldText.length > 0 || toolAcc.size > 0);
              if (toolsComplete || enoughText || timedOut) commit();
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
    if (!committed) return { state: { httpError: `stream:${err?.message || err}` } };
    log('stream error after commit (unrecoverable):', err?.message || err);
    return { state: {}, committed: true };
  }

  // ---- end of stream: evaluate ----
  if (!committed) {
    if (ctx.judgeState?.verdict?.hard) state.judgeHard = true;
    if (!heldText.trim() && toolAcc.size === 0) state.emptied = true;
    if (finishReason === 'length') state.truncated = true;
    if (matchesAny(heldText, REFUSAL_RE())) state.refusal = true;
    if (detectRepetition(heldText)) state.repetition = true;
    if (ctx.needsTools && toolAcc.size === 0 && matchesAny(lastUserText(body.messages), INTENT_RE())) {
      state.missingToolCall = true;
    }
    if (heldText.trim() && heldText.trim().length < 12 && toolAcc.size === 0) state.shortAnswer = true;
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

async function route(body, res) {
  stats.requests++;
  const { start, key, notes, needsTools } = chooseStart(body.messages, body);
  const stream = body.stream === true;
  const clientModel = body.model || 'auto';
  const tried = [];

  // Difficulty judge: one extra request to the free tier, fired in parallel
  // with the first (cheapest) attempt so it costs no wall-clock latency.
  let judgeP = null;
  const judgeState = { verdict: null };
  if (judgeConfigActive() && start < tiers.length - 1) {
    judgeP = askJudge(body)
      .then((v) => {
        judgeState.verdict = v;
        return v;
      })
      .catch(() => null);
  }

  for (let i = start; i < tiers.length; i++) {
    const tier = tiers[i];
    bump(stats.byTier, tier.name);
    const ctx = { needsTools, key, notes, judgeState };

    if (stream) {
      let began = false;
      const begin = () => {
        if (began) return;
        began = true;
        res.writeHead(200, {
          'content-type': 'text/event-stream; charset=utf-8',
          'cache-control': 'no-cache',
          connection: 'keep-alive',
          'x-router-tier': tier.name,
          ...(tried.length ? { 'x-router-escalated-from': tried.join(' ') } : {}),
        });
      };

      const out = await attemptStream(tier, body, ctx, res, clientModel, begin);
      if (out.committed) {
        res.write('data: [DONE]\n\n');
        res.end();
        return;
      }
      // Judge may still be in flight for a fast model — settle it before deciding.
      if (judgeP) await judgeP;
      if (judgeState.verdict?.hard) out.state.judgeHard = true;
      const verdict = evaluateDepth(out.state);
      if (verdict.escalate && i < tiers.length - 1) {
        tried.push(`${tier.name}:${[...verdict.hard, ...verdict.soft].join(',')}`);
        stats.escalations++;
        for (const r of [...verdict.hard, ...verdict.soft]) bump(stats.escalationReasons, r);
        log(`escalate ${tier.name} -> ${tiers[i + 1].name} [${[...verdict.hard, ...verdict.soft].join(',')}]`);
        markSticky(key, verdict.hard[0] || verdict.soft[0]);
        continue;
      }
      // Accept this tier's output: nothing was flushed yet, so replay it now.
      begin();
      if (out.held && out.held.length) {
        for (const f of out.held) res.write(rewriteModel(f, clientModel));
      } else if (out.state.httpError || out.state.emptied) {
        stats.failures++;
        res.write(`data: ${JSON.stringify({ choices: [{ delta: { role: 'assistant', content: '' }, index: 0, finish_reason: 'stop' }] })}\n\n`);
      }
      res.write('data: [DONE]\n\n');
      res.end();
      return;
    }

    const out = await attemptNonStream(tier, body, ctx);
    if (judgeP) await judgeP;
    if (judgeState.verdict?.hard) out.state.judgeHard = true;
    const verdict = evaluateDepth(out.state);
    if (verdict.escalate && i < tiers.length - 1) {
      tried.push(`${tier.name}:${[...verdict.hard, ...verdict.soft].join(',')}`);
      stats.escalations++;
      for (const r of [...verdict.hard, ...verdict.soft]) bump(stats.escalationReasons, r);
      log(`escalate ${tier.name} -> ${tiers[i + 1].name} [${[...verdict.hard, ...verdict.soft].join(',')}]`);
      markSticky(key, verdict.hard[0] || verdict.soft[0]);
      continue;
    }
    if (out.json) {
      out.json.model = clientModel;
      res.setHeader('x-router-tier', tier.name);
      if (tried.length) res.setHeader('x-router-escalated-from', tried.join(' '));
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify(out.json));
      return;
    }
    // Exhausted ladder.
    stats.failures++;
    const detail = out.detail || JSON.stringify(out.state);
    log('all tiers failed:', detail);
    res.setHeader('x-router-tier', tier.name);
    res.writeHead(502, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ error: { message: `model-router: all tiers failed (${detail})`, type: 'upstream_error' } }));
    return;
  }
  res.writeHead(502, { 'content-type': 'application/json' });
  res.end(JSON.stringify({ error: { message: 'model-router: no tier succeeded', type: 'upstream_error' } }));
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
      judge: {
        enabled: judgeConfigActive(),
        tier: judgeTier().name,
        threshold: Number(config.judge?.threshold ?? 0.6),
      },
      uptime: Math.round((Date.now() - stats.startedAt) / 1000),
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

const [host, portStr] = String(config.listen || '127.0.0.1:49700').split(':');
const port = Number(portStr || 49700);
server.listen(port, host, () => {
  log(`listening on http://${host}:${port}`);
  log(`ladder: ${tiers.map((t) => `${t.name}(${t.model})`).join(' -> ')}`);
  for (const t of tiers) {
    if (!keyFor(t)) log(`warning: tier "${t.name}" has no api key (env ${t.apiKeyEnv})`);
  }
});
