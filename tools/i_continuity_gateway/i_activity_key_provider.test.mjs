import test from 'node:test';
import assert from 'node:assert/strict';
import {
  existsSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { createIActivityKeyProvider } from './i_activity_key_provider.mjs';

function temporaryIHome(t, prefix) {
  const root = mkdtempSync(join(tmpdir(), prefix));
  const iHome = join(root, 'isolated-i-home');
  t.after(() => rmSync(root, { recursive: true, force: true }));
  return iHome;
}

test('Windows DPAPI persists a wrapped key that a fresh provider can reload', {
  skip: process.platform !== 'win32',
}, (t) => {
  const iHome = temporaryIHome(t, 'i-activity-key-dpapi-');
  const creatingProvider = createIActivityKeyProvider({ iHome });
  assert.equal(
    creatingProvider.isSupported,
    true,
    'the Windows integration test requires the system Windows PowerShell DPAPI provider',
  );

  const created = creatingProvider.loadOrCreateKey();
  assert.equal(created.key.length, 32);
  assert.match(created.keyId, /^activity-dek-[a-f0-9]{20}$/);
  assert.equal(existsSync(creatingProvider.keyPath), true);

  const serializedRecord = readFileSync(creatingProvider.keyPath, 'utf8');
  const record = JSON.parse(serializedRecord);
  assert.equal(record.provider, 'windows-dpapi');
  assert.equal(record.scope, 'CurrentUser');
  assert.equal('key' in record, false);
  assert.equal('dek' in record, false);
  assert.notEqual(record.wrapped_dek, created.key.toString('base64'));
  assert.equal(serializedRecord.includes(created.key.toString('base64')), false);
  assert.equal(serializedRecord.includes(created.key.toString('hex')), false);

  // A new provider has a separate in-memory cache, matching a new process's
  // load path while still exercising the real CurrentUser DPAPI boundary.
  const reloadingProvider = createIActivityKeyProvider({ iHome });
  const reloaded = reloadingProvider.loadKey();
  assert.equal(reloaded.keyId, created.keyId);
  assert.deepEqual(reloaded.key, created.key);

  const tamperedRecord = {
    ...record,
    key_check_sha256: record.key_check_sha256 === '0'.repeat(64)
      ? '1'.repeat(64)
      : '0'.repeat(64),
  };
  writeFileSync(
    creatingProvider.keyPath,
    `${JSON.stringify(tamperedRecord, null, 2)}\n`,
    'utf8',
  );
  const tamperedBytes = readFileSync(creatingProvider.keyPath, 'utf8');

  const failClosedProvider = createIActivityKeyProvider({ iHome });
  assert.throws(
    () => failClosedProvider.loadOrCreateKey(),
    /activity encryption key could not be verified/,
  );
  assert.equal(
    readFileSync(creatingProvider.keyPath, 'utf8'),
    tamperedBytes,
    'a tampered record must not be replaced with a newly generated key',
  );
});

test('unsupported platforms fail closed without a plaintext key fallback', (t) => {
  const iHome = temporaryIHome(t, 'i-activity-key-linux-');
  let randomCalls = 0;
  let spawnCalls = 0;
  const provider = createIActivityKeyProvider({
    iHome,
    platform: 'linux',
    powershellPath: process.execPath,
    randomBytesProvider: () => {
      randomCalls += 1;
      return Buffer.alloc(32, 0x42);
    },
    spawnProvider: () => {
      spawnCalls += 1;
      throw new Error('DPAPI must not be invoked on an unsupported platform');
    },
  });

  assert.equal(provider.isSupported, false);
  assert.equal(provider.hasKey(), false);
  assert.throws(
    () => provider.loadOrCreateKey(),
    /encrypted activity is unavailable on this platform; no plaintext fallback is allowed/,
  );
  assert.equal(randomCalls, 0);
  assert.equal(spawnCalls, 0);
  assert.equal(existsSync(provider.keyPath), false);
  assert.equal(existsSync(iHome), false);
});
