import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const templatePath = path.join(root, 'config/templates/mcp_config.json.tmpl');

function render(environment = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'agy-mcp-test-'));
  const outputPath = path.join(dir, 'mcp.json');
  try {
    execFileSync('python3', [path.join(root, 'scripts/render-mcp-config.py'), templatePath, outputPath], {
      env: { ...process.env, OBSIDIAN_API_KEY: 'test-obsidian', OBSIDIAN_REST_PORT: '30001', CMDS_AGENT_MCP_URL: '', CMDS_AGENT_MCP_TOKEN: '', WIKI_MCP_URL: '', GITLAB_MCP_URL: '', ...environment },
    });
    return JSON.parse(fs.readFileSync(outputPath, 'utf8'));
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

test('template has no embedded site hostname and optional remote servers default off', () => {
  const template = fs.readFileSync(templatePath, 'utf8');
  assert.doesNotMatch(template, /science\.gc\.ca/);
  assert.deepEqual(Object.keys(render().mcpServers), ['obsidian']);
});

test('remote MCP URLs render from environment', () => {
  const rendered = render({
    CMDS_AGENT_MCP_URL: 'https://cmds.example/skills-mcp',
    WIKI_MCP_URL: 'https://wiki.example/mcp',
    GITLAB_MCP_URL: 'https://git.example/mcp',
  });
  assert.equal(rendered.mcpServers['cmds-agent'].serverUrl, 'https://cmds.example/skills-mcp');
  assert.equal(rendered.mcpServers.wiki.serverUrl, 'https://wiki.example/mcp');
  assert.equal(rendered.mcpServers.gitlab.serverUrl, 'https://git.example/mcp');
});

test('cmds-agent renders Authorization only when a token is set', () => {
  const withToken = render({
    CMDS_AGENT_MCP_URL: 'https://cmds.example/skills-mcp',
    CMDS_AGENT_MCP_TOKEN: 'tok-123',
  });
  assert.equal(
    withToken.mcpServers['cmds-agent'].headers.Authorization,
    'Bearer tok-123',
  );

  const noToken = render({
    CMDS_AGENT_MCP_URL: 'https://cmds.example/skills-mcp',
  });
  assert.equal(noToken.mcpServers['cmds-agent'].headers, undefined);

  // No URL at all: server omitted, token or not.
  const noUrl = render({ CMDS_AGENT_MCP_TOKEN: 'tok-123' });
  assert.equal(noUrl.mcpServers['cmds-agent'], undefined);
});

test('common runtime has no hard-coded site proxy default', () => {
  const common = fs.readFileSync(path.join(root, 'scripts/common.sh'), 'utf8');
  assert.doesNotMatch(common, /webproxy\.science\.gc\.ca/);
});

test('renderer rejects a remote MCP URL without http(s)', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'agy-mcp-test-'));
  const outputPath = path.join(dir, 'mcp.json');
  try {
    assert.throws(() => execFileSync('python3', [path.join(root, 'scripts/render-mcp-config.py'), templatePath, outputPath], {
      env: { ...process.env, OBSIDIAN_API_KEY: 'test', OBSIDIAN_REST_PORT: '30001', CMDS_AGENT_MCP_URL: 'file:///tmp/server', WIKI_MCP_URL: '', GITLAB_MCP_URL: '' },
      stdio: 'pipe',
    }));
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
