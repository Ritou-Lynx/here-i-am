import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createWindowsDpapiPersonalDomainStateAdapter } from './personal_domain_private_state.mjs';

function directory(t, prefix) {
  const root = mkdtempSync(path.join(tmpdir(), prefix));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  return root;
}

function syntheticDpapi(_command, _args, options) {
  const entropy = Buffer.from(options.env.I_CORE_PERSONAL_STATE_ENTROPY, 'base64');
  const output = Buffer.alloc(options.input.length);
  for (let index = 0; index < options.input.length; index++) {
    output[index] = options.input[index] ^ entropy[index % entropy.length] ^ 0xa5;
  }
  return { status: 0, stdout: output, stderr: Buffer.alloc(0) };
}

test('private owner state writes bound ciphertext and its exclusive lock rejects then releases', t => {
  const root = directory(t, 'personal-domain-private-state-'), statePath = path.join(root, 'owner.dpapi.json');
  const make = coreInstanceId => createWindowsDpapiPersonalDomainStateAdapter({ statePath, coreInstanceId,
    platform: 'win32', powershellPath: process.execPath, spawnProvider: syntheticDpapi,
    clock: () => Date.parse('2026-10-07T08:00:00.000Z') });
  const first = { version: 1, phone_grants: [{ principal_id: 'phone', secret: 'PRIVATE-FIRST' }],
    adoption_manifests: [] };
  make('core-private').save(first);
  const encoded = readFileSync(statePath, 'utf8');
  assert.equal(encoded.includes('PRIVATE-FIRST'), false);
  assert.equal(JSON.parse(encoded).provider, 'windows-dpapi-current-user');
  assert.deepEqual(make('core-private').load(), first);
  const second = { ...first, phone_grants: [{ principal_id: 'phone', secret: 'PRIVATE-ROTATED' }] };
  make('core-private').save(second);
  assert.deepEqual(make('core-private').load(), second);
  assert.equal(readFileSync(statePath, 'utf8').includes('PRIVATE-ROTATED'), false);
  assert.throws(() => make('wrong-core').load(), { code: 'invalid_personal_domain_private_state' });
  const release = make('core-private').acquireExclusive();
  assert.throws(() => make('core-private').acquireExclusive(), { code: 'personal_domain_private_state_busy' });
  release();
  const releaseAgain = make('core-private').acquireExclusive();
  releaseAgain();
});

test('real Windows CurrentUser DPAPI round trips owner state without plaintext on disk', {
  skip: process.platform !== 'win32',
}, t => {
  const root = directory(t, 'personal-domain-real-dpapi-'), statePath = path.join(root, 'owner.dpapi.json');
  const adapter = createWindowsDpapiPersonalDomainStateAdapter({ statePath, coreInstanceId: 'core-dpapi-real' });
  const state = { version: 1, phone_grants: [{ principal_id: 'phone', secret: 'PRIVATE-REAL-DPAPI' }],
    adoption_manifests: [] };
  adapter.save(state);
  assert.deepEqual(createWindowsDpapiPersonalDomainStateAdapter({ statePath,
    coreInstanceId: 'core-dpapi-real' }).load(), state);
  assert.equal(readFileSync(statePath, 'utf8').includes('PRIVATE-REAL-DPAPI'), false);
});
