import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, mkdirSync, realpathSync, rmSync, symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { prepareDedicatedHome, loginChallenge } from './workbench_text_gate_login.mjs';
function fixture(t) {
  const root = mkdtempSync(path.join(tmpdir(), 'hereiam-text-gate-path-test-'));
  for (const name of ['appdata', 'repository', 'original']) mkdirSync(path.join(root, name));
  t.after(() => {
    const resolved = realpathSync(root);
    if (path.dirname(resolved) !== realpathSync(tmpdir()) || !path.basename(resolved).startsWith('hereiam-text-gate-path-test-')) throw new Error('Unexpected test cleanup target.');
    rmSync(resolved, { recursive: true });
  });
  return { root, localAppData: path.join(root, 'appdata'), repository: path.join(root, 'repository'), originalHomes: [path.join(root, 'original')] };
}
test('dedicated login directory stays outside repository and original home on repeated setup', t => {
  const f = fixture(t);
  const first = prepareDedicatedHome(f);
  assert.equal(first.home, path.join(realpathSync(f.localAppData), 'HereIAm', 'Runtime', 'p6-text-only-codex'));
  assert.ok(existsSync(first.cwd));
  assert.deepEqual(prepareDedicatedHome(f), first);
});
for (const target of ['repository', 'original']) test(`rejects a junction to ${target} before creating descendants`, t => {
  const f = fixture(t);
  const destination = path.join(f.root, target);
  symlinkSync(destination, path.join(f.localAppData, 'HereIAm'), process.platform === 'win32' ? 'junction' : 'dir');
  assert.throws(() => prepareDedicatedHome(f), /redirected/);
  assert.equal(existsSync(path.join(destination, 'Runtime')), false);
});
test('rejects protected canonical roots even when application-data root is redirected', t => {
  const f = fixture(t);
  const link = path.join(f.root, 'redirected-appdata');
  symlinkSync(f.repository, link, process.platform === 'win32' ? 'junction' : 'dir');
  assert.throws(() => prepareDedicatedHome({ ...f, localAppData: link }), /protected directory/);
  assert.equal(existsSync(path.join(f.repository, 'HereIAm')), false);
});

test('normal and device challenges retain only the explicit user login fields', () => {
  assert.deepEqual(loginChallenge({ type: 'chatgpt', loginId: 'synthetic', authUrl: 'https://auth.openai.com/oauth/authorize?state=synthetic', extra: 'not retained' }, 'login'), { auth_url: 'https://auth.openai.com/oauth/authorize?state=synthetic' });
  assert.deepEqual(loginChallenge({ type: 'chatgptDeviceCode', loginId: 'synthetic', verificationUrl: 'https://auth.openai.com/codex/device', userCode: 'ABCD-1234', extra: 'not retained' }, 'device-login'), { verification_url: 'https://auth.openai.com/codex/device', user_code: 'ABCD-1234' });
});

test('device challenge rejects other origins, paths, embedded data and malformed codes', () => {
  const valid = { type: 'chatgptDeviceCode', loginId: 'synthetic', verificationUrl: 'https://auth.openai.com/codex/device', userCode: 'ABCD-1234' };
  for (const verificationUrl of ['http://auth.openai.com/codex/device', 'https://example.com/codex/device', 'https://auth.openai.com/codex/device?token=synthetic', 'https://auth.openai.com/other']) assert.throws(() => loginChallenge({ ...valid, verificationUrl }, 'device-login'));
  for (const userCode of ['', 'ABCD-1234\n', 'https://example.com', null]) assert.throws(() => loginChallenge({ ...valid, userCode }, 'device-login'));
});

test('challenges reject mismatched login modes and missing login identities', () => {
  const valid = { type: 'chatgpt', loginId: 'synthetic', authUrl: 'https://auth.openai.com/oauth/authorize' };
  for (const mode of ['device-login', 'status', 'apiKey']) assert.throws(() => loginChallenge(valid, mode));
  assert.throws(() => loginChallenge({ ...valid, loginId: '' }, 'login'));
  assert.throws(() => loginChallenge({ ...valid, authUrl: 'https://user@auth.openai.com/oauth/authorize' }, 'login'));
});
