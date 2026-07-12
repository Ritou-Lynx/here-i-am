import { createCipheriv, createDecipheriv, createHash, pbkdf2Sync, randomBytes, randomUUID } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, readdirSync, renameSync, writeFileSync } from 'node:fs';
import { hostname } from 'node:os';
import { basename, join, resolve } from 'node:path';

import { createIActivityStore } from './i_activity_store.mjs';
import { loadProjectRegistry, resolveIHome } from './i_project_registry.mjs';

const ITERATIONS = 600_000;
const MAX_PACKAGE_BYTES = 16 * 1024 * 1024;

function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

function requirePassphrase(environment = process.env) {
  const value = String(environment.I_SYNC_PASSPHRASE || '');
  if (value.length < 16) throw new Error('I_SYNC_PASSPHRASE must contain at least 16 characters');
  return value;
}

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

function open(envelope, passphrase) {
  if (envelope?.schema_version !== 1 || envelope.type !== 'i.device-sync.encrypted' ||
      envelope.kdf?.name !== 'pbkdf2-sha256' || envelope.kdf.iterations !== ITERATIONS ||
      envelope.cipher?.name !== 'aes-256-gcm') throw new Error('sync package format is invalid');
  const salt = Buffer.from(envelope.kdf.salt, 'base64url');
  const iv = Buffer.from(envelope.cipher.iv, 'base64url');
  const tag = Buffer.from(envelope.cipher.tag, 'base64url');
  const ciphertext = Buffer.from(envelope.ciphertext, 'base64url');
  if (salt.length !== 16 || iv.length !== 12 || tag.length !== 16 || ciphertext.length > MAX_PACKAGE_BYTES) {
    throw new Error('sync package cryptographic fields are invalid');
  }
  const key = pbkdf2Sync(passphrase, salt, ITERATIONS, 32, 'sha256');
  const decipher = createDecipheriv('aes-256-gcm', key, iv);
  decipher.setAuthTag(tag);
  return JSON.parse(Buffer.concat([decipher.update(ciphertext), decipher.final()]).toString('utf8'));
}

function loadIdentity(iHome) {
  const parsed = JSON.parse(readFileSync(join(iHome, 'identity.json'), 'utf8').replace(/^\uFEFF/, ''));
  if (![1, 2].includes(parsed?.schema_version) || parsed.identity?.name !== '林埃' ||
      parsed.identity?.english_name !== 'i') throw new Error('identity projection is invalid');
  return parsed;
}

function assertSameIdentity(local, incoming) {
  const fields = [
    ['identity.name', local?.identity?.name, incoming?.identity?.name],
    ['identity.english_name', local?.identity?.english_name, incoming?.identity?.english_name],
    ['relationship.user_preferred_name', local?.relationship?.user_preferred_name,
      incoming?.relationship?.user_preferred_name],
  ];
  for (const [name, expected, actual] of fields) {
    if (String(expected || '') !== String(actual || '')) {
      throw new Error(`sync identity mismatch at ${name}; no package data was imported`);
    }
  }
}

function deviceId(iHome) {
  const path = join(iHome, 'device.json');
  if (existsSync(path)) {
    const parsed = JSON.parse(readFileSync(path, 'utf8'));
    if (/^[a-f0-9-]{36}$/.test(String(parsed.device_id || ''))) return parsed.device_id;
    throw new Error('device identity is invalid');
  }
  const value = { schema_version: 1, device_id: randomUUID(), label: hostname(), created_at: new Date().toISOString() };
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`, { encoding: 'utf8', mode: 0o600, flag: 'wx' });
  return value.device_id;
}

export function exportSyncPackage({ iHome = resolveIHome(), syncRoot, environment = process.env } = {}) {
  const home = resolve(iHome);
  const root = resolve(syncRoot);
  const registry = loadProjectRegistry({ iHome: home });
  const store = createIActivityStore({ iHome: home, registryProjectsProvider: () => registry.projects });
  const device = deviceId(home);
  const payload = {
    schema_version: 1,
    package_id: randomUUID(),
    device_id: device,
    created_at: new Date().toISOString(),
    identity: loadIdentity(home),
    closeouts: store.exportSyncCloseouts({ projects: registry.projects }),
  };
  const directory = join(root, 'packages', device);
  mkdirSync(directory, { recursive: true });
  const filename = `${payload.created_at.replace(/[:.]/g, '-')}-${payload.package_id}.json.enc`;
  const path = join(directory, filename);
  const temp = `${path}.${process.pid}.tmp`;
  writeFileSync(temp, `${JSON.stringify(seal(payload, requirePassphrase(environment)))}\n`, { encoding: 'utf8', mode: 0o600, flag: 'wx' });
  renameSync(temp, path);
  return { schema_version: 1, exported: true, path, package_id: payload.package_id, closeout_count: payload.closeouts.length };
}

export function importSyncPackages({ iHome = resolveIHome(), syncRoot, environment = process.env } = {}) {
  const home = resolve(iHome);
  const root = resolve(syncRoot);
  const registry = loadProjectRegistry({ iHome: home });
  const localIdentity = loadIdentity(home);
  const store = createIActivityStore({ iHome: home, registryProjectsProvider: () => registry.projects });
  const localDevice = deviceId(home);
  const statePath = join(home, 'sync-import-state.json');
  const state = existsSync(statePath) ? JSON.parse(readFileSync(statePath, 'utf8')) : { schema_version: 2, packages: {} };
  const completed = new Map(Object.entries(state.schema_version === 2 && state.packages &&
    typeof state.packages === 'object' ? state.packages : {}));
  const files = existsSync(join(root, 'packages'))
    ? readdirSync(join(root, 'packages'), { recursive: true, withFileTypes: true })
      .filter((entry) => entry.isFile() && entry.name.endsWith('.json.enc'))
      .map((entry) => join(entry.parentPath || entry.path, entry.name))
    : [];
  const totals = { imported: 0, duplicates: 0, skipped_unknown_project: 0, packages: 0 };
  for (const path of files.sort()) {
    const raw = readFileSync(path);
    if (raw.length > MAX_PACKAGE_BYTES) throw new Error(`sync package is too large: ${basename(path)}`);
    const payload = open(JSON.parse(raw.toString('utf8')), requirePassphrase(environment));
    if (payload?.schema_version !== 1 || !payload.package_id || !Array.isArray(payload.closeouts)) {
      throw new Error(`sync payload is invalid: ${basename(path)}`);
    }
    if (payload.device_id === localDevice) continue;
    assertSameIdentity(localIdentity, payload.identity);
    const completedKeys = new Set(Array.isArray(completed.get(payload.package_id))
      ? completed.get(payload.package_id) : []);
    const pending = payload.closeouts.filter((item) => !completedKeys.has(String(item.project_key || '')));
    if (pending.length === 0) continue;
    const result = store.importSyncCloseouts({ projects: registry.projects, closeouts: pending });
    totals.imported += result.imported;
    totals.duplicates += result.duplicates;
    totals.skipped_unknown_project += result.skipped_unknown_project;
    totals.packages += 1;
    const registeredKeys = new Set(registry.projects.map((project) => project.project_key));
    for (const item of pending) {
      const key = String(item.project_key || '');
      if (registeredKeys.has(key)) completedKeys.add(key);
    }
    completed.set(payload.package_id, [...completedKeys].sort());
  }
  const recentPackages = [...completed.entries()].slice(-5000);
  const next = { schema_version: 2, packages: Object.fromEntries(recentPackages), updated_at: new Date().toISOString() };
  const temp = `${statePath}.${process.pid}.tmp`;
  writeFileSync(temp, `${JSON.stringify(next, null, 2)}\n`, { encoding: 'utf8', mode: 0o600 });
  renameSync(temp, statePath);
  return { schema_version: 1, ...totals, state_hash: sha256(JSON.stringify(next.packages)) };
}
