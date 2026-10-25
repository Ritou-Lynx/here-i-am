import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { FRONTEND_CALLBACKS, FRONTEND_CALLBACK_PATTERNS, CLAUDE_AI_CALLBACKS, CHATGPT_CALLBACK_URI, ANTIGRAVITY_CALLBACKS, SESAME_CALLBACKS, frontendForRedirectUri } from './oauth.mjs';
import { FRONTENDS } from './writeback.mjs';
import { mcpPost, startTestServer } from './fixtures.mjs';

test('registry is frozen, exact and assigns every callback to one frontend', () => {
  assert.ok(Object.isFrozen(FRONTEND_CALLBACKS));
  assert.deepEqual(FRONTEND_CALLBACKS, { claude_web: CLAUDE_AI_CALLBACKS, chatgpt_web: [CHATGPT_CALLBACK_URI], antigravity: ANTIGRAVITY_CALLBACKS, sesame: SESAME_CALLBACKS });
  assert.ok(Object.isFrozen(FRONTEND_CALLBACK_PATTERNS));
  assert.deepEqual(Object.keys(FRONTEND_CALLBACK_PATTERNS), ['gemini_web']);
  const callbacks = Object.values(FRONTEND_CALLBACKS).flat();
  assert.equal(new Set(callbacks).size, callbacks.length);
  for (const [frontend, uris] of Object.entries(FRONTEND_CALLBACKS)) {
    assert.ok(Object.isFrozen(uris));
    for (const uri of uris) assert.equal(frontendForRedirectUri(uri), frontend);
  }
  for (const uri of [null, undefined, '', 'https://unknown.example/callback', CHATGPT_CALLBACK_URI + '?x=1']) {
    assert.equal(frontendForRedirectUri(uri), null);
  }
});

test('registry names equal writeback definitions and App known source keys', () => {
  const names = [...Object.keys(FRONTEND_CALLBACKS), ...Object.keys(FRONTEND_CALLBACK_PATTERNS)].sort();
  assert.deepEqual(Object.keys(FRONTENDS).sort(), names);
  const dart = readFileSync(new URL('../../lib/ui/character/widgets/chat_message_source_label.dart', import.meta.url), 'utf8');
  const map = /\b_knownChatSources\s*=\s*\{([^}]+)\}/s.exec(dart);
  assert.ok(map, 'App known source map must be found');
  const keys = [...map[1].matchAll(/'([^']+)'\s*:/g)].map(match => match[1]).sort();
  assert.deepEqual(keys, names.map(name => `frontend:${name}`).sort());
});

test('server independently rejects unknown verified frontend before parsing or RPC', async () => {
  const ctx = await startTestServer({ chatgptEnabled: true });
  try {
    // Isolate the routing guard from OAuth validation, which also rejects these values.
    for (const frontend of ['unknown_frontend', '', 'Claude_web', null, undefined, 'constructor', '__proto__']) {
      ctx.oauth.verifyAccessToken = () => ({ ok: true, frontend, familyId: 'synthetic', scopes: ['i.read', 'i.write'] });
      for (const message of [{ jsonrpc: '2.0', id: 1, method: 'initialize' }, { jsonrpc: '2.0', id: 2, method: 'tools/call', params: { name: 'i_context', arguments: {} } }]) {
        const result = await mcpPost(ctx.base, 'synthetic', message);
        assert.equal(result.status, 401);
        assert.equal(result.body.error, 'invalid_token');
        assert.match(result.headers.get('www-authenticate'), /error="invalid_token"/);
        assert.equal(result.headers.get('mcp-session-id'), null);
      }
    }
    assert.deepEqual(ctx.readModel.calls, []);
  } finally { await ctx.close(); }
});
