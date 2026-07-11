import {
  createCipheriv,
  createDecipheriv,
  createHash,
  randomBytes,
} from 'node:crypto';

const ALGORITHM = 'aes-256-gcm';
const FORMAT_VERSION = 1;
// Large enough for the bounded 2,000-entry derived Activity Index while still
// rejecting unbounded or obviously malformed encrypted payloads.
const MAX_CIPHERTEXT_BYTES = 4 * 1024 * 1024;

function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

function encode(value) {
  return Buffer.from(value).toString('base64url');
}

function decode(value, name, maxBytes) {
  const text = String(value || '');
  if (!text || !/^[A-Za-z0-9_-]+$/.test(text)) {
    throw new Error(`encrypted activity ${name} is invalid`);
  }
  const decoded = Buffer.from(text, 'base64url');
  if (decoded.length === 0 || decoded.length > maxBytes || encode(decoded) !== text) {
    throw new Error(`encrypted activity ${name} is invalid`);
  }
  return decoded;
}

function normalizedKeyMaterial(material) {
  const key = Buffer.from(material?.key || []);
  if (key.length !== 32) throw new Error('activity encryption key must be 32 bytes');
  const keyId = String(material?.keyId || '').trim();
  if (!/^[a-zA-Z0-9._-]{8,96}$/.test(keyId)) throw new Error('activity encryption key id is invalid');
  return { key, keyId };
}

export function createIActivityCrypto(material, { randomBytesProvider = randomBytes } = {}) {
  const { key, keyId } = normalizedKeyMaterial(material);

  function seal(value, scope) {
    const normalizedScope = String(scope || '').trim();
    if (!/^[a-z0-9:._-]{3,160}$/i.test(normalizedScope)) {
      throw new Error('activity encryption scope is invalid');
    }
    const protectedHeader = encode(JSON.stringify({
      typ: 'i.activity.encrypted',
      alg: 'A256GCM',
      kid: keyId,
      scope: normalizedScope,
      format: FORMAT_VERSION,
    }));
    const iv = Buffer.from(randomBytesProvider(12));
    if (iv.length !== 12) throw new Error('activity encryption nonce must be 12 bytes');
    const plaintext = Buffer.from(JSON.stringify(value), 'utf8');
    if (plaintext.length > MAX_CIPHERTEXT_BYTES) throw new Error('activity event is too large to encrypt');
    const cipher = createCipheriv(ALGORITHM, key, iv, { authTagLength: 16 });
    cipher.setAAD(Buffer.from(protectedHeader, 'utf8'));
    const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);
    const tag = cipher.getAuthTag();
    return {
      v: FORMAT_VERSION,
      protected: protectedHeader,
      iv: encode(iv),
      ciphertext: encode(ciphertext),
      tag: encode(tag),
    };
  }

  function open(envelope, expectedScope) {
    if (!envelope || typeof envelope !== 'object' || Array.isArray(envelope) || envelope.v !== FORMAT_VERSION) {
      throw new Error('encrypted activity envelope is invalid');
    }
    const protectedBytes = decode(envelope.protected, 'protected header', 2048);
    let header;
    try {
      header = JSON.parse(protectedBytes.toString('utf8'));
    } catch {
      throw new Error('encrypted activity protected header is invalid');
    }
    if (header?.typ !== 'i.activity.encrypted' || header.alg !== 'A256GCM' ||
        header.format !== FORMAT_VERSION || header.kid !== keyId || header.scope !== expectedScope) {
      throw new Error('encrypted activity protected header does not match this ledger');
    }
    const iv = decode(envelope.iv, 'nonce', 12);
    const ciphertext = decode(envelope.ciphertext, 'ciphertext', MAX_CIPHERTEXT_BYTES);
    const tag = decode(envelope.tag, 'authentication tag', 16);
    if (iv.length !== 12 || tag.length !== 16) throw new Error('encrypted activity envelope has invalid cryptographic lengths');
    try {
      const decipher = createDecipheriv(ALGORITHM, key, iv, { authTagLength: 16 });
      decipher.setAAD(Buffer.from(String(envelope.protected), 'utf8'));
      decipher.setAuthTag(tag);
      const plaintext = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
      const value = JSON.parse(plaintext.toString('utf8'));
      if (!value || typeof value !== 'object' || Array.isArray(value)) {
        throw new Error('decrypted activity value is not an object');
      }
      return value;
    } catch {
      throw new Error('encrypted activity integrity check failed');
    }
  }

  return {
    keyId,
    keyCheck: sha256(key),
    seal,
    open,
  };
}
