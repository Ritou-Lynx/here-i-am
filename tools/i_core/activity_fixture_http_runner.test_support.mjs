// Test-only setup. No database reads, mutation APIs, or assertion oracle.
// Public HTTP deliberately has no authority takeover endpoint. Model a stale
// runtime's cached epoch while its listener is stopped; the durable authority
// and all integrity commitments remain intact.
export function installStaleRuntimeEpoch(core, pairedEpoch, delta) {
  if (core.server.listening || !Number.isSafeInteger(pairedEpoch)
    || !Number.isSafeInteger(delta) || delta !== 1) {
    throw new Error('invalid_stopped_epoch_setup');
  }
  core.store.activity.authorityEpoch = pairedEpoch - delta;
}
