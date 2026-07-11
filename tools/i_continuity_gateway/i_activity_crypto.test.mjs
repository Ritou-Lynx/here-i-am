import test from 'node:test';
import assert from 'node:assert/strict';

import { createIActivityCrypto } from './i_activity_crypto.mjs';

const KEY_ID = 'activity-dek-test-0001';
const SCOPE = 'project:here-i-am';

function material(byte = 0x11) {
  return {
    key: Buffer.alloc(32, byte),
    keyId: KEY_ID,
  };
}

function cryptoFor(byte = 0x11, options) {
  return createIActivityCrypto(material(byte), options);
}

function encode(value) {
  return Buffer.from(value).toString('base64url');
}

function mutateEncoded(value) {
  const bytes = Buffer.from(value, 'base64url');
  bytes[0] ^= 0x01;
  return bytes.toString('base64url');
}

function replace(envelope, field, value) {
  return { ...envelope, [field]: value };
}

test('round-trips a structured activity containing Chinese text and emoji', () => {
  const crypto = cryptoFor();
  const activity = {
    summary: '林埃记住了跨工具的进展 🧠✨',
    decisions: ['使用本地加密账本', '英文名统一为 i'],
    open_loops: ['下一步接入 Memory V3 🚀'],
    nested: {
      note: '中文、emoji 与换行都应原样返回\n第二行',
      completed: false,
      count: 3,
    },
  };

  const envelope = crypto.seal(activity, SCOPE);

  assert.deepEqual(crypto.open(envelope, SCOPE), activity);
  assert.equal(envelope.v, 1);
  assert.match(envelope.protected, /^[A-Za-z0-9_-]+$/);
  assert.match(envelope.iv, /^[A-Za-z0-9_-]+$/);
  assert.match(envelope.ciphertext, /^[A-Za-z0-9_-]+$/);
  assert.match(envelope.tag, /^[A-Za-z0-9_-]+$/);
});

test('the same plaintext receives a fresh nonce and different ciphertext', () => {
  let nonceSequence = 0;
  const crypto = cryptoFor(0x22, {
    randomBytesProvider: (length) => {
      assert.equal(length, 12);
      nonceSequence += 1;
      return Buffer.alloc(length, nonceSequence);
    },
  });
  const activity = { summary: 'Identical plaintext.' };

  const first = crypto.seal(activity, SCOPE);
  const second = crypto.seal(activity, SCOPE);

  assert.notEqual(first.iv, second.iv);
  assert.notEqual(first.ciphertext, second.ciphertext);
  assert.deepEqual(crypto.open(first, SCOPE), activity);
  assert.deepEqual(crypto.open(second, SCOPE), activity);
});

test('a different key with the same key id cannot decrypt an envelope', () => {
  const writer = cryptoFor(0x33);
  const wrongKeyReader = cryptoFor(0x44);
  const envelope = writer.seal({ summary: 'Key-bound content.' }, SCOPE);

  assert.throws(
    () => wrongKeyReader.open(envelope, SCOPE),
    /encrypted activity integrity check failed/,
  );
});

test('authentication tag tampering is rejected', () => {
  const crypto = cryptoFor();
  const envelope = crypto.seal({ summary: 'Authenticated content.' }, SCOPE);
  const tampered = replace(envelope, 'tag', mutateEncoded(envelope.tag));

  assert.throws(
    () => crypto.open(tampered, SCOPE),
    /encrypted activity integrity check failed/,
  );
});

test('the protected header is authenticated as AAD', () => {
  const crypto = cryptoFor();
  const envelope = crypto.seal({ summary: 'Header-bound content.' }, SCOPE);
  const header = JSON.parse(Buffer.from(envelope.protected, 'base64url').toString('utf8'));
  const tamperedScope = 'project:another-project';
  const tampered = replace(
    envelope,
    'protected',
    encode(JSON.stringify({ ...header, scope: tamperedScope })),
  );

  // Supplying the tampered scope gets past semantic header validation. GCM must
  // still reject it because the protected bytes no longer match the sealed AAD.
  assert.throws(
    () => crypto.open(tampered, tamperedScope),
    /encrypted activity integrity check failed/,
  );
});

test('an envelope cannot be opened under a different ledger scope', () => {
  const crypto = cryptoFor();
  const envelope = crypto.seal({ summary: 'Project-isolated content.' }, SCOPE);

  assert.throws(
    () => crypto.open(envelope, 'project:another-project'),
    /protected header does not match this ledger/,
  );
});

test('malformed envelope shapes and versions are rejected', async (t) => {
  const crypto = cryptoFor();
  const envelope = crypto.seal({ summary: 'Valid activity.' }, SCOPE);

  for (const [label, malformed] of [
    ['null envelope', null],
    ['array envelope', []],
    ['missing version', { ...envelope, v: undefined }],
    ['wrong version', { ...envelope, v: 2 }],
    ['string envelope', 'encrypted'],
  ]) {
    await t.test(label, () => {
      assert.throws(
        () => crypto.open(malformed, SCOPE),
        /encrypted activity envelope is invalid/,
      );
    });
  }
});

test('invalid or non-canonical base64url fields are rejected', async (t) => {
  const crypto = cryptoFor();
  const envelope = crypto.seal({ summary: 'Valid activity.' }, SCOPE);

  for (const [label, field, value, error] of [
    ['protected header characters', 'protected', '***', /protected header is invalid/],
    ['protected header padding', 'protected', `${envelope.protected}=`, /protected header is invalid/],
    ['missing nonce', 'iv', undefined, /nonce is invalid/],
    ['nonce characters', 'iv', 'not+base64', /nonce is invalid/],
    ['empty ciphertext', 'ciphertext', '', /ciphertext is invalid/],
    ['ciphertext characters', 'ciphertext', 'bad/value', /ciphertext is invalid/],
    ['missing authentication tag', 'tag', undefined, /authentication tag is invalid/],
    ['authentication tag characters', 'tag', 'bad=value', /authentication tag is invalid/],
  ]) {
    await t.test(label, () => {
      assert.throws(
        () => crypto.open(replace(envelope, field, value), SCOPE),
        error,
      );
    });
  }
});

test('malformed protected header JSON and required fields are rejected', async (t) => {
  const crypto = cryptoFor();
  const envelope = crypto.seal({ summary: 'Valid activity.' }, SCOPE);
  const validHeader = JSON.parse(Buffer.from(envelope.protected, 'base64url').toString('utf8'));

  await t.test('invalid JSON', () => {
    assert.throws(
      () => crypto.open(replace(envelope, 'protected', encode('{not-json')), SCOPE),
      /encrypted activity protected header is invalid/,
    );
  });

  for (const [label, changedHeader] of [
    ['wrong type', { ...validHeader, typ: 'other' }],
    ['wrong algorithm', { ...validHeader, alg: 'A128GCM' }],
    ['wrong key id', { ...validHeader, kid: 'activity-dek-other' }],
    ['wrong format', { ...validHeader, format: 2 }],
    ['missing scope', { ...validHeader, scope: undefined }],
  ]) {
    await t.test(label, () => {
      assert.throws(
        () => crypto.open(
          replace(envelope, 'protected', encode(JSON.stringify(changedHeader))),
          SCOPE,
        ),
        /protected header does not match this ledger/,
      );
    });
  }
});

test('invalid nonce, tag, and ciphertext lengths are rejected', async (t) => {
  const crypto = cryptoFor();
  const envelope = crypto.seal({ summary: 'Valid activity.' }, SCOPE);

  for (const [label, field, bytes, error] of [
    ['short nonce', 'iv', Buffer.alloc(11, 1), /invalid cryptographic lengths/],
    ['long nonce', 'iv', Buffer.alloc(13, 1), /nonce is invalid/],
    ['short tag', 'tag', Buffer.alloc(15, 1), /invalid cryptographic lengths/],
    ['long tag', 'tag', Buffer.alloc(17, 1), /authentication tag is invalid/],
    [
      'oversized ciphertext',
      'ciphertext',
      Buffer.alloc((4 * 1024 * 1024) + 1, 1),
      /ciphertext is invalid/,
    ],
  ]) {
    await t.test(label, () => {
      assert.throws(
        () => crypto.open(replace(envelope, field, encode(bytes)), SCOPE),
        error,
      );
    });
  }
});

test('invalid key material, scope, and nonce providers fail closed', async (t) => {
  await t.test('short encryption key', () => {
    assert.throws(
      () => createIActivityCrypto({ key: Buffer.alloc(31), keyId: KEY_ID }),
      /activity encryption key must be 32 bytes/,
    );
  });

  await t.test('invalid key id', () => {
    assert.throws(
      () => createIActivityCrypto({ key: Buffer.alloc(32), keyId: 'short' }),
      /activity encryption key id is invalid/,
    );
  });

  await t.test('invalid ledger scope', () => {
    assert.throws(
      () => cryptoFor().seal({ summary: 'No scope.' }, '../outside'),
      /activity encryption scope is invalid/,
    );
  });

  await t.test('wrong nonce provider length', () => {
    const crypto = cryptoFor(0x55, {
      randomBytesProvider: () => Buffer.alloc(11),
    });
    assert.throws(
      () => crypto.seal({ summary: 'Bad nonce.' }, SCOPE),
      /activity encryption nonce must be 12 bytes/,
    );
  });
});

test('the bounded 2,000-entry Activity Index fits inside the encrypted payload limit', () => {
  const crypto = createIActivityCrypto(material());
  const index = {
    schema_version: 2,
    generated_at: '2026-07-10T08:00:00.000Z',
    event_count: 2000,
    entries: Array.from({ length: 2000 }, (_, indexValue) => ({
      event_id: `event-${String(indexValue).padStart(8, '0')}`,
      project_id: `project-${String(indexValue % 20).padStart(4, '0')}`,
      event_type: 'session_closeout',
      occurred_at: '2026-07-10T08:00:00.000Z',
      decision_count: 16,
      open_loop_count: 16,
      redaction: 'policy_summary',
      summary: '记'.repeat(280),
    })),
  };
  const envelope = crypto.seal(index, 'activity-index:v2');
  assert.equal(crypto.open(envelope, 'activity-index:v2').event_count, 2000);
});
