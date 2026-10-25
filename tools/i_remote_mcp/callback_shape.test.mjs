import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { callbackShape, createRequestDiagnostics } from './diagnostics.mjs';
import { createApp } from './server.mjs';
import { FRONTEND_CALLBACKS } from './oauth.mjs';
import { createFakeReadModel, PUBLIC_URL } from './fixtures.mjs';
import { listenForFetch } from './fetch_test_listener.mjs';

test('callback shapes preserve fixed segments, canonical hosts, ports and empty segments', () => {
  const cases = [
    ['https://app.example.com/oauth/callback', 'https://app.example.com/oauth/callback'],
    ['https://App.Example.com:8443/oauth/callback/', 'https://app.example.com:8443/oauth/callback/'],
    ['https://x.example.com:443/cb', 'https://x.example.com/cb'],
    ['http://x.example.com:80/cb', 'http://x.example.com/cb'],
    ['http://127.0.0.1:9000/callback', 'http://127.0.0.1:9000/callback'],
    ['https://x.example.com/r/user_bound_custom-mcp-AbC123', 'https://x.example.com/r/{28}'],
    ['https://x.example.com/cb/550e8400-e29b-41d4-a716-446655440000', 'https://x.example.com/cb/{36}'],
    ['https://x.example.com/cb?state=secret#frag', 'https://x.example.com/cb?{q}#{f}'],
    ['https://x.example.com/cb?', 'https://x.example.com/cb'],
    ['https://x.example.com/cb#', 'https://x.example.com/cb'],
    ['https://x.example.com//cb/', 'https://x.example.com//cb/'],
    ['https://x.example.com', 'https://x.example.com/'],
    [`https://x.example.com/${'a'.repeat(32)}/${'a'.repeat(33)}/A/abc_-/123`,
      `https://x.example.com/${'a'.repeat(32)}/{33}/{1}/abc_-/{3}`],
  ];
  for (const [value, expected] of cases) assert.equal(callbackShape(value), expected, value);
  assert.doesNotMatch(callbackShape('https://x.example.com/cb?state=secret#frag'), /secret|frag/);
});

test('callback shapes reject invalid input, credentials, long hosts and more than 20 path segments', () => {
  const longHost = Array(5).fill('a'.repeat(60)).join('.');
  for (const value of ['https://user:pw@x.example.com/cb', 'https://user@x.example.com/cb',
    'ftp://x.example.com/cb', 'not a url', '', `https://${longHost}/cb`,
    null, undefined, 42, {}, []]) {
    assert.equal(callbackShape(value), null, String(value));
  }
  const twenty = 'https://x.example.com/' + Array(20).fill('cb').join('/');
  assert.equal(callbackShape(twenty), twenty);
  assert.equal(callbackShape(twenty + '/cb'), null);
  const twentyWithEmpty = 'https://x.example.com/' + Array(19).fill('cb').join('/') + '/';
  assert.equal(callbackShape(twentyWithEmpty), twentyWithEmpty);
  assert.equal(callbackShape(twentyWithEmpty + '/'), null);
  const maxHost = [...Array(3).fill('a'.repeat(63)), 'b'.repeat(61)].join('.');
  assert.equal(maxHost.length, 253);
  assert.equal(callbackShape(`https://${maxHost}/cb`), `https://${maxHost}/cb`);
  assert.equal(callbackShape(`https://${maxHost}b/cb`), null);
});

function registrationRecord(values, kept = []) {
  const records = [];
  const diagnostic = createRequestDiagnostics({ method: 'POST', url: '/register', headers: {} },
    { issuer: PUBLIC_URL, resource: PUBLIC_URL + '/mcp', diagnostic: record => records.push(record) });
  diagnostic.registration(values, kept);
  diagnostic.finish(400);
  return records[0];
}

test('registration shapes drop nulls, deduplicate in order and cap at eight without changing counts', () => {
  const callbacks = Array.from({ length: 10 }, (_, index) => `https://probe-${index}.example/cb`);
  const values = ['not a url', callbacks[0], callbacks[0], ...callbacks.slice(1),
    'https://x.example.com/r/user_bound_custom-mcp-AbC123'];
  const record = registrationRecord(values);
  assert.equal(record.callback_class, 'other');
  assert.equal(record.callback_count, values.length);
  assert.equal(record.gemini_kept_count, 0);
  assert.deepEqual(record.callback_shapes, callbacks.slice(0, 8));
  assert.deepEqual(registrationRecord(['not a url']).callback_shapes, []);
  const gemini = 'https://oauth-redirect.googleusercontent.com/r/user_bound_custom-mcp-synthetic';
  const mixed = registrationRecord([callbacks[0], gemini], [gemini]);
  assert.equal(mixed.callback_class, 'gemini_pattern');
  assert.equal(mixed.callback_count, 2);
  assert.equal(mixed.gemini_kept_count, 1);
  assert.equal(Object.hasOwn(mixed, 'callback_shapes'), false);
});

test('HTTP registration still rejects unknown callbacks and emits only shapes for other classifications', async t => {
  const stateDir = mkdtempSync(join(tmpdir(), 'synthetic-callback-shape-'));
  const records = [];
  const { server } = createApp({ stateDir, publicUrl: PUBLIC_URL,
    getReadModel: async () => createFakeReadModel(), identityLoader: () => ({}),
    chatgptEnabled: true, geminiEnabled: true, antigravityEnabled: true,
    diagnostic: record => records.push(record) });
  t.after(async () => {
    if (server.listening) await new Promise(resolve => server.close(resolve));
    rmSync(stateDir, { recursive: true, force: true });
  });
  await listenForFetch(server);
  const base = `http://127.0.0.1:${server.address().port}`;
  async function register(uri) {
    const response = await fetch(base + '/register', { method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ redirect_uris: [uri], token_endpoint_auth_method: 'none' }) });
    return { status: response.status, body: await response.json(), record: records.at(-1) };
  }
  const uri = 'https://sesame-test.example/oauth/callback/abcdef0123456789';
  const rejected = await register(uri);
  assert.equal(rejected.status, 400);
  assert.equal(rejected.body.error, 'invalid_redirect_uri');
  assert.equal(rejected.record.path, '/register');
  assert.equal(rejected.record.status, 400);
  assert.equal(rejected.record.callback_class, 'other');
  assert.equal(rejected.record.callback_count, 1);
  assert.equal(rejected.record.gemini_kept_count, 0);
  assert.deepEqual(rejected.record.callback_shapes, ['https://sesame-test.example/oauth/callback/{16}']);
  assert.doesNotMatch(JSON.stringify(rejected.record), /abcdef0123456789/);
  const classes = { claude_web: 'claude', chatgpt_web: 'chatgpt', antigravity: 'antigravity' };
  const known = Object.entries(FRONTEND_CALLBACKS).flatMap(([frontend, callbacks]) =>
    callbacks.map(callback => [callback, classes[frontend]]));
  known.push(['https://oauth-redirect.googleusercontent.com/r/user_bound_custom-mcp-synthetic', 'gemini_pattern']);
  for (const [callback, expected] of known) {
    const result = await register(callback);
    assert.equal(result.status, 201, callback);
    assert.equal(result.record.callback_class, expected);
    assert.equal(Object.hasOwn(result.record, 'callback_shapes'), false);
  }
  const response = await fetch(base + '/authorize?redirect_uri=' + encodeURIComponent(uri));
  await response.text();
  assert.equal(records.at(-1).callback, '[redacted]');
  assert.equal(Object.hasOwn(records.at(-1), 'callback_shapes'), false);
  assert.doesNotMatch(JSON.stringify(records), /abcdef0123456789|user_bound_custom-mcp/);
});
