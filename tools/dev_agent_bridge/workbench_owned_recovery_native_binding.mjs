// Candidate-only same-Node Windows witness channel. Constants belong to the
// externally pinned ESM closure; discovery environment never supplies trust.
import { createRequire } from 'node:module';
import { createHash } from 'node:crypto';
import { readFileSync, lstatSync, realpathSync } from 'node:fs';
import path from 'node:path';
import { createOwnedRecoveryWitness, witnessFailure } from './workbench_owned_recovery_witness.mjs';

export const OWNED_RECOVERY_ADDON_PATH = 'D:\\memex\\tmp\\p6-r7-review\\owned-recovery-node-addon-02\\witness_addon.node';
export const OWNED_RECOVERY_ADDON_SHA256 = '7a80151fa467f296237c03f0cfacdfbda5a5447712041799053174666f8756fc';
export const OWNED_RECOVERY_WITNESS_PATH = 'D:\\memex\\tmp\\p6-r7-review\\owned-recovery-witness-04\\OwnedRecoveryWitness.exe';
export const OWNED_RECOVERY_WITNESS_SHA256 = '7381f83666994d5835c1580c37afbf80a7556c5a1d516596e6f4b794c4af823e';
export const OWNED_RECOVERY_NODE_PATH = 'D:\\Nodejs\\node.exe';
export const OWNED_RECOVERY_NODE_SHA256 = '58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f';
export const OWNED_RECOVERY_CONTROL_TIMEOUT_MS = 10000;
const fail = () => { throw new Error('owned_recovery_native_binding_rejected'); };
const check = value => { if (!value) fail(); };
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const samePath = (a, b) => typeof a === 'string' && a.toLowerCase() === b.toLowerCase();
function pinnedFile(filename, digest) {
  for (let p = filename; ; p = path.dirname(p)) {
    const s = lstatSync(p);
    check(!s.isSymbolicLink() && samePath(realpathSync(p), p)
      && (p === filename ? s.isFile() && s.nlink === 1 : s.isDirectory()));
    if (p === path.dirname(p)) break;
  }
  check(hash(readFileSync(filename)) === digest);
}
function decimal(value) { check(typeof value === 'string' && /^[1-9][0-9]{0,19}$/.test(value) && BigInt(value) <= 0xffffffffffffffffn); return value; }
function pid(value) { decimal(value); const n = Number(value); check(Number.isSafeInteger(n) && n <= 0xffffffff); return n; }

export async function connectOwnedRecoveryNative({ sourceClosureSha256, nativeSha256, onStage = () => {} }, env = process.env) {
  onStage('witness_discovery');
  check(process.platform === 'win32' && samePath(process.execPath, OWNED_RECOVERY_NODE_PATH));
  check(env.P6_R7_WITNESS_ROLE === 'node' && /^[a-f0-9]{64}$/.test(env.P6_R7_WITNESS_EPOCH)
    && env.P6_R7_WITNESS_PIPE === `p6-r7-recovery-${env.P6_R7_WITNESS_EPOCH}-node`
    && samePath(env.P6_R7_WITNESS_IMAGE, OWNED_RECOVERY_WITNESS_PATH)
    && env.P6_R7_WITNESS_SHA256 === OWNED_RECOVERY_WITNESS_SHA256);
  onStage('witness_addon_load');
  pinnedFile(OWNED_RECOVERY_ADDON_PATH, OWNED_RECOVERY_ADDON_SHA256);
  const addon = createRequire(import.meta.url)(OWNED_RECOVERY_ADDON_PATH);
  // The bootstrap must hold/protect addon and script closure from before load;
  // repeat the byte pin here so a changed disk image cannot be treated as live.
  pinnedFile(OWNED_RECOVERY_ADDON_PATH, OWNED_RECOVERY_ADDON_SHA256);
  let self, channel, closed = false;
  const nativeHandles = new Set();
  async function close() {
    if (closed) return;
    const outcomes = await Promise.allSettled([...nativeHandles].map(async handle => {
      await addon.close(handle); nativeHandles.delete(handle);
    }));
    if (channel) await addon.close(channel.handle);
    if (self) await addon.close(self.handle);
    check(outcomes.every(x => x.status === 'fulfilled')); closed = true;
  }
  try {
    onStage('node_self_capture');
    self = await addon.captureSelf({ imagePath: OWNED_RECOVERY_NODE_PATH,
      imageSha256: OWNED_RECOVERY_NODE_SHA256, parentPid: process.ppid }, 3000);
    onStage('witness_connect');
    channel = await addon.connect({ pipeName: env.P6_R7_WITNESS_PIPE,
      pid: pid(env.P6_R7_WITNESS_PID), creation: decimal(env.P6_R7_WITNESS_CREATION),
      parentPid: pid(env.P6_R7_WITNESS_PARENT_PID), imagePath: OWNED_RECOVERY_WITNESS_PATH,
      imageSha256: OWNED_RECOVERY_WITNESS_SHA256 }, 3000);
    const protocol = createOwnedRecoveryWitness({ adapter: { authenticated: true,
      exchange: text => addon.exchange(channel.handle, text, OWNED_RECOVERY_CONTROL_TIMEOUT_MS),
      exchangeFinal: text => addon.exchangeFinal(channel.handle, text, OWNED_RECOVERY_CONTROL_TIMEOUT_MS) },
    epoch: env.P6_R7_WITNESS_EPOCH, sourceClosureSha256, nativeSha256 });
    const protocolMethods = Object.fromEntries(Object.entries(Object.getOwnPropertyDescriptors(protocol))
      .filter(([, descriptor]) => typeof descriptor.value === 'function')
      .map(([key, descriptor]) => [key, descriptor.value]));
    return Object.freeze({ ...protocolMethods,
      get failed() { return protocol.failed; },
      get ownerCount() { return protocol.ownerCount; },
      get serverQuarantined() { return protocol.serverQuarantined; },
      get eofReported() { return protocol.eofReported; },
      async captureNative({ pid: nativePid, imagePath, imageSha256 }) {
        check(!closed && imageSha256 === nativeSha256);
        const result = await addon.captureNative({ pid: nativePid, parentPid: process.pid, imagePath, imageSha256 }, 3000);
        nativeHandles.add(result.handle); return result;
      },
      async observeNative(handle) { check(nativeHandles.has(handle)); return addon.observe(handle, 3000); },
      async closeNative(handle) { check(nativeHandles.has(handle)); await addon.close(handle); nativeHandles.delete(handle); },
      close,
    });
  } catch (error) { await close().catch(() => {}); throw witnessFailure(error); }
}
