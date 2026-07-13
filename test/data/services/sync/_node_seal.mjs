// Standalone re-implementation of i_device_sync.mjs seal(), used only to
// produce a cross-language interop fixture for the Dart crypto test.
import { createCipheriv, pbkdf2Sync, randomBytes } from 'node:crypto';

const ITERATIONS = 600_000;

function seal(value, passphrase) {
  const salt = randomBytes(16);
  const iv = randomBytes(12);
  const key = pbkdf2Sync(passphrase, salt, ITERATIONS, 32, 'sha256');
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  const plaintext = Buffer.from(JSON.stringify(value), 'utf8');
  const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  return {
    schema_version: 1,
    type: 'i.device-sync.encrypted',
    kdf: { name: 'pbkdf2-sha256', iterations: ITERATIONS, salt: salt.toString('base64url') },
    cipher: { name: 'aes-256-gcm', iv: iv.toString('base64url'), tag: cipher.getAuthTag().toString('base64url') },
    ciphertext: ciphertext.toString('base64url'),
  };
}

const passphrase = process.argv[2];
const payload = process.argv[3];
process.stdout.write(JSON.stringify(seal(JSON.parse(payload), passphrase)));
