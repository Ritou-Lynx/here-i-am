// Test harness: boots a throwaway i core on a random loopback port and prints
// its base URL on stdout, keeping the process alive until killed.
// Usage: node _core_server_harness.mjs <pairingCode> [backupPairingCode]
// The backup code becomes active once the primary is consumed, so a single
// core instance can pair more than one device (real cores get a fresh code
// from the owner for each new device).
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createICoreServer } from '../../../../tools/i_core/i_core_server.mjs';

const pairingCode = process.argv[2] ?? '654321';
const backupPairingCode = process.argv[3] ?? null;
const directory = mkdtempSync(path.join(tmpdir(), 'i-core-dart-test-'));
const core = createICoreServer({
  databasePath: path.join(directory, 'core.sqlite'),
  pairingCode,
});

const address = await core.listen({ port: 0 });
console.log(`http://127.0.0.1:${address.port}`);

// The core exposes no consumption event, so poll the store for the consumed
// marker: when the primary code is gone from consumed_pairing_codes (i.e. the
// first device paired), arm the backup code for the second device.
if (backupPairingCode) {
  const check = setInterval(async () => {
    try {
      if (!core.store.isPairingCodeConsumed(pairingCode)) return;
      clearInterval(check);
      core.replacePairingCode(backupPairingCode);
    } catch (_) {
      // store not ready yet; retry
    }
  }, 50);
}

process.on('SIGTERM', async () => {
  await core.close();
  process.exit(0);
});
