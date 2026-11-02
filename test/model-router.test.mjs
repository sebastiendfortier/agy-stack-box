import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'agy-router-test-'));
const configPath = path.join(tempDir, 'router.json');
fs.writeFileSync(configPath, JSON.stringify({
  listen: '127.0.0.1:0',
  policy: { escalationTtlMs: 1000, largePromptTokens: 100000 },
  tiers: [
    { name: 'free', baseUrl: 'http://free.test/v1', model: 'free-model', apiKeyEnv: 'TEST_FREE_KEY', contextWindow: 100000 },
    { name: 'paid', baseUrl: 'http://paid.test/v1', model: 'paid-model', apiKeyEnv: 'TEST_PAID_KEY', contextWindow: 100000 },
  ],
}));
process.env.MODEL_ROUTER_CONFIG = configPath;
process.env.TEST_FREE_KEY = 'test-free';
process.env.TEST_PAID_KEY = 'test-paid';
const { route, chooseStart, buildPlan, evaluateDepth, sticky, clock } = await import('../scripts/model-router.mjs');

function recorder() {
  return {
    status: null,
    headers: {},
    body: '',
    headersSent: false,
    setHeader(name, value) { this.headers[name.toLowerCase()] = value; },
    writeHead(status, headers = {}) {
      this.status = status;
      for (const [name, value] of Object.entries(headers)) this.headers[name.toLowerCase()] = value;
      this.headersSent = true;
    },
    write(chunk) { this.body += chunk; },
    end(chunk = '') { this.body += chunk; this.ended = true; },
  };
}

function completion(content = 'complete answer', extra = {}) {
  return new Response(JSON.stringify({
    choices: [{ message: { role: 'assistant', content, ...extra }, finish_reason: 'stop' }],
  }), { status: 200, headers: { 'content-type': 'application/json' } });
}

function sseResponse(frames) {
  const body = frames.map((frame) => `data: ${JSON.stringify(frame)}\n\n`).join('') + 'data: [DONE]\n\n';
  return new Response(body, { status: 200, headers: { 'content-type': 'text/event-stream' } });
}

const requestBody = (more = {}) => ({ model: 'auto', messages: [{ role: 'user', content: 'test task' }], ...more });
const originalFetch = globalThis.fetch;
test.beforeEach(() => sticky.clear());
test.after(() => {
  globalThis.fetch = originalFetch;
  fs.rmSync(tempDir, { recursive: true, force: true });
});

test('starts at free tier and escalates after an upstream 502', async () => {
  const called = [];
  globalThis.fetch = async (url) => {
    called.push(url);
    return url.startsWith('http://free') ? new Response('down', { status: 502 }) : completion();
  };
  const res = recorder();
  await route(requestBody(), res);
  assert.deepEqual(called.map((url) => url.startsWith('http://free') ? 'free' : 'paid'), ['free', 'paid']);
  assert.equal(res.status, 200);
  assert.equal(JSON.parse(res.body).choices[0].message.content, 'complete answer');
});

test('401 and 403 fail without escalating or exposing provider body', async (t) => {
  for (const status of [401, 403]) {
    await t.test(String(status), async () => {
      let calls = 0;
      globalThis.fetch = async () => { calls++; return new Response('secret provider response', { status }); };
      const res = recorder();
      await route(requestBody(), res);
      assert.equal(calls, 1);
      assert.equal(res.status, 502);
      assert.doesNotMatch(res.body, /secret provider response|test-paid|test-free/);
    });
  }
});

test('network failures escalate to paid tier', async () => {
  let calls = 0;
  globalThis.fetch = async (url) => {
    calls++;
    if (url.startsWith('http://free')) throw new TypeError('network down');
    return completion();
  };
  const res = recorder();
  await route(requestBody(), res);
  assert.equal(calls, 2);
  assert.equal(res.status, 200);
});


test('timeout failures escalate', async () => {
  let calls = 0;
  globalThis.fetch = async (url) => {
    calls++;
    if (url.startsWith('http://free')) throw new DOMException('aborted', 'AbortError');
    return completion();
  };
  const res = recorder();
  await route(requestBody(), res);
  assert.equal(calls, 2);
  assert.equal(res.status, 200);
});

test('truncated output escalates', async () => {
  let calls = 0;
  globalThis.fetch = async (url) => {
    calls++;
    return url.startsWith('http://free')
      ? new Response(JSON.stringify({ choices: [{ message: { content: 'partial' }, finish_reason: 'length' }] }), { status: 200 })
      : completion();
  };
  const res = recorder();
  await route(requestBody(), res);
  assert.equal(calls, 2);
  assert.equal(res.status, 200);
});

test('malformed JSON escalates with stable signal', async () => {
  let calls = 0;
  globalThis.fetch = async (url) => {
    calls++;
    return url.startsWith('http://free') ? new Response('{bad json', { status: 200 }) : completion();
  };
  const res = recorder();
  await route(requestBody(), res);
  assert.equal(calls, 2);
  assert.equal(res.status, 200);
});

test('refusal escalates', async () => {
  let calls = 0;
  globalThis.fetch = async (url) => {
    calls++;
    return url.startsWith('http://free') ? completion("I cannot help with that request.") : completion();
  };
  const res = recorder();
  await route(requestBody(), res);
  assert.equal(calls, 2);
});

test('reasoning-only completion is accepted as non-empty', async () => {
  let calls = 0;
  globalThis.fetch = async () => {
    calls++;
    return completion('', { reasoning_content: 'internal reasoning is present' });
  };
  const res = recorder();
  await route(requestBody(), res);
  assert.equal(calls, 1);
  assert.equal(res.status, 200);
});

test('empty completion escalates', async () => {
  let calls = 0;
  globalThis.fetch = async (url) => {
    calls++;
    return url.startsWith('http://free') ? completion('') : completion();
  };
  const res = recorder();
  await route(requestBody(), res);
  assert.equal(calls, 2);
});

test('top-tier failure falls back with a sanitized degraded header', async () => {
  const calls = [];
  globalThis.fetch = async (url) => {
    calls.push(url);
    if (url.startsWith('http://free')) return completion();
    return new Response('provider detail must stay private', { status: 500 });
  };
  const body = requestBody({ messages: [{ role: 'user', content: 'x'.repeat(400001) }] });
  const res = recorder();
  await route(body, res);
  assert.equal(res.status, 200);
  assert.deepEqual(calls.map((url) => url.startsWith('http://free') ? 'free' : 'paid'), ['paid', 'free']);
  assert.match(res.headers['x-router-degraded'], /^paid:http:500$/);
  assert.doesNotMatch(res.body, /provider detail must stay private/);
});


test('missing top-tier key falls back with a degraded header', async () => {
  const savedKey = process.env.TEST_PAID_KEY;
  delete process.env.TEST_PAID_KEY;
  let calls = 0;
  globalThis.fetch = async () => { calls++; return completion(); };
  const body = requestBody({ messages: [{ role: 'user', content: 'x'.repeat(400001) }] });
  const res = recorder();
  try {
    await route(body, res);
    assert.equal(calls, 1);
    assert.equal(res.status, 200);
    assert.equal(res.headers['x-router-tier'], 'free');
    assert.equal(res.headers['x-router-degraded'], 'paid:no-key');
  } finally {
    process.env.TEST_PAID_KEY = savedKey;
  }
});

test('sticky escalation expires using the injected clock', () => {
  let now = 10_000;
  clock.now = () => now;
  sticky.clear();
  const body = requestBody();
  const { key } = chooseStart(body.messages, body);
  sticky.set(key, now + 1000);
  assert.equal(chooseStart(body.messages, body).start, 1);
  now += 1001;
  assert.equal(chooseStart(body.messages, body).start, 0);
  clock.now = () => Date.now();
});

test('deterministic depth rules ignore short-answer and task-intent heuristics', () => {
  assert.deepEqual(evaluateDepth({ shortAnswer: true, missingToolCall: true }), { escalate: false, hard: [], soft: [] });
  assert.deepEqual(evaluateDepth({ truncated: true }), { escalate: true, hard: ['truncated'], soft: [] });
});

test('streamed empty first tier does not leak frames before paid tier wins', async () => {
  const called = [];
  globalThis.fetch = async (url) => {
    called.push(url);
    if (url.startsWith('http://free')) {
      return sseResponse([{ choices: [{ delta: { content: '' }, finish_reason: 'stop' }] }]);
    }
    return sseResponse([{ choices: [{ delta: { content: 'paid-only' }, finish_reason: 'stop' }] }]);
  };
  const res = recorder();
  await route(requestBody({ stream: true }), res);
  assert.equal(called.length, 2);
  assert.equal(res.status, 200);
  assert.match(res.body, /paid-only/);
  assert.doesNotMatch(res.body, /free/);
});


test('malformed JSON payload escalates with stable classification', async () => {
  let calls = 0;
  globalThis.fetch = async (url) => {
    calls++;
    return url.startsWith('http://free')
      ? new Response(JSON.stringify({ choices: [] }), { status: 200 })
      : completion();
  };
  const res = recorder();
  await route(requestBody(), res);
  assert.equal(calls, 2);
  assert.equal(res.status, 200);
});


test('malformed stream frame escalates with stable classification', async () => {
  let calls = 0;
  globalThis.fetch = async (url) => {
    calls++;
    if (url.startsWith('http://free')) {
      return new Response('data: {not-json}\n\ndata: [DONE]\n\n', { status: 200 });
    }
    return sseResponse([{ choices: [{ delta: { content: 'paid-only' }, finish_reason: 'stop' }] }]);
  };
  const res = recorder();
  await route(requestBody({ stream: true }), res);
  assert.equal(calls, 2);
  assert.equal(res.status, 200);
  assert.match(res.body, /paid-only/);
  assert.doesNotMatch(res.body, /not-json/);
});

test('tier-two failure followed by tier-one failure never returns provider bodies', async () => {
  globalThis.fetch = async (url) => new Response(
    url.startsWith('http://free') ? 'secret free detail' : 'secret paid detail',
    { status: 500 },
  );
  const body = requestBody({ messages: [{ role: 'user', content: 'x'.repeat(400001) }] });
  const res = recorder();
  await route(body, res);
  assert.equal(res.status, 502);
  assert.doesNotMatch(res.body, /secret free detail|secret paid detail|test-free|test-paid/);
});

test('streamed reasoning-only completion counts as non-empty', async () => {
  let calls = 0;
  globalThis.fetch = async () => {
    calls++;
    return sseResponse([{ choices: [{ delta: { reasoning_content: 'reasoning' }, finish_reason: 'stop' }] }]);
  };
  const res = recorder();
  await route(requestBody({ stream: true }), res);
  assert.equal(calls, 1);
  assert.equal(res.status, 200);
});

test('does not expose a /v1/models route', async () => {
  const { server } = await import('../scripts/model-router.mjs');
  const req = { url: '/v1/models', method: 'GET', headers: {} };
  const res = recorder();
  await new Promise((resolve) => server.emit('request', req, { ...res, end: function (body = '') { res.end(body); resolve(); }, writeHead: function (status, headers) { res.writeHead(status, headers); } }));
  assert.equal(res.status, 404);
});
