import { execFileSync } from 'node:child_process';
import { readFileSync, statSync } from 'node:fs';
import path from 'node:path';
import { createHash, timingSafeEqual } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { cleanEnvironment, plainPath } from './package.mjs';

export function protectedPath(target, root = false) {
  plainPath(target);
  const script = path.join(path.dirname(fileURLToPath(import.meta.url)), 'protected_paths.ps1');
  const quote = s => "'" + s.replaceAll("'", "''") + "'";
  execFileSync(path.join(process.env.SystemRoot, 'System32/WindowsPowerShell/v1.0/powershell.exe'),
    ['-NoProfile', '-NonInteractive', '-Command', `$ErrorActionPreference='Stop'; . ${quote(script)}; Assert-ProtectedPath ${quote(target)} ${root ? '-Root' : ''}`],
    { env: cleanEnvironment(), windowsHide: true, timeout: 10000, stdio: ['ignore', 'pipe', 'pipe'] });
}
function exact(value, keys) {
  if (!value || typeof value !== 'object' || Array.isArray(value) || Object.keys(value).some(k => !keys.includes(k))) throw new Error('config_fields_rejected');
}
export function readConfiguration(filename, binding) {
  if (!filename) return { pairingCode: null, activityAdminSecret: null, workerSecret: null, companionReplyJobsEnabled: false, relay: null };
  protectedPath(path.dirname(filename), true); protectedPath(filename);
  if (statSync(filename).size > 8192) throw new Error('config_size_rejected');
  let value;
  try { value = JSON.parse(readFileSync(filename, 'utf8')); } catch { throw new Error('config_json_rejected'); }
  exact(value, ['format', 'manifest_sha256', 'database_path', 'node_id', 'owner_sid', 'pairing', 'activity_owner', 'worker', 'jobs', 'relay']);
  if (value.format !== 'r3-config-v1' || value.manifest_sha256 !== binding.manifest_sha256 || value.database_path !== binding.database_path
      || value.node_id !== binding.node_id || value.owner_sid !== binding.owner_sid) throw new Error('config_binding_mismatch');
  const secrets = [];
  const secret = (name, relay = false) => {
    const item = value[name];
    if (item === undefined) return null;
    exact(item, relay ? ['enabled', 'secret', 'mode'] : ['enabled', 'secret']);
    if (typeof item.enabled !== 'boolean') throw new Error('config_enabled_required');
    if (!item.enabled) {
      if (Object.keys(item).length !== 1) throw new Error('disabled_config_fields_rejected');
      return null;
    }
    // Only high-entropy synthetic/current-user supplied credentials; no trim/coercion.
    if (typeof item.secret !== 'string' || !/^[a-f0-9]{64}$/.test(item.secret)) throw new Error('config_secret_format_rejected');
    if (relay && item.mode !== 'no-egress-test') throw new Error('relay_external_unsupported');
    secrets.push(item.secret); return item.secret;
  };
  const pairingCode = secret('pairing'), activityAdminSecret = secret('activity_owner'), workerSecret = secret('worker'), relayToken = secret('relay', true);
  if (new Set(secrets).size !== secrets.length) throw new Error('config_secret_overlap');
  const jobs = value.jobs ?? { enabled: false };
  exact(jobs, ['enabled']);
  if (typeof jobs.enabled !== 'boolean' || (jobs.enabled && !workerSecret)) throw new Error('jobs_worker_required');
  return { pairingCode, activityAdminSecret, workerSecret, companionReplyJobsEnabled: jobs.enabled, relay: relayToken };
}

// Deliberately contains no transport, subprocess, URL, mailbox or provider configuration.
export async function noEgressRelay(token) {
  const { ShortcutMailRelayError } = await import(new URL('./tools/i_core/shortcut_mail_relay.mjs', import.meta.url));
  const authorize = value => {
    if (typeof value !== 'string' || value.length !== token.length || !timingSafeEqual(Buffer.from(value), Buffer.from(token))) {
      throw new ShortcutMailRelayError('shortcut_mail_unauthorized', 'Scoped test token required.', { status: 401 });
    }
  };
  let closed = false;
  const receipts = new Map();
  const tokenHash = createHash('sha256').update(token).digest('hex');
  return {
    tokenHash,
    async send({ idempotency_key, token: supplied }) {
      authorize(supplied);
      if (closed) throw new Error('test_relay_closed');
      const receipt = { status: 'test_no_egress', idempotency_key, external_send_attempted: false };
      receipts.set(idempotency_key, receipt); return receipt;
    },
    async getReceipt({ idempotency_key, token: supplied }) { authorize(supplied); return receipts.get(idempotency_key) ?? null; },
    close() { closed = true; receipts.clear(); },
  };
}
