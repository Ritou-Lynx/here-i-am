#!/usr/bin/env node
// Watches the scoped i_core captures feed and wakes one Codex planner run.
// It never stores capture text and is inert until an explicit enabled config is supplied.
import { spawn } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import { readFileSync, renameSync, writeFileSync } from 'node:fs';
import { appendFile, mkdir, open, readFile, rename, unlink, writeFile } from 'node:fs/promises';
import { dirname, isAbsolute, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const DEFAULTS = Object.freeze({
  poll_ms: 60_000,
  batch_ms: 180_000,
  min_interval_ms: 600_000,
  quiet_start: '23:30',
  quiet_end: '07:00',
  codex_timeout_ms: 900_000,
  codex_kill_grace_ms: 5_000,
  request_timeout_ms: 15_000,
  retry_base_ms: 2_000,
  retry_cap_ms: 300_000,
});

class CoreError extends Error {
  constructor(code, status = 0, payload = null) {
    super(code);
    this.code = code;
    this.status = status;
    this.payload = payload;
  }
}

export const PLANNER_TIME_ZONE = 'Asia/Shanghai';
const sleep = (ms, signal) => new Promise(resolveSleep => {
  if (signal?.aborted) return resolveSleep();
  const timer = setTimeout(done, ms);
  function done() { clearTimeout(timer); signal?.removeEventListener('abort', done); resolveSleep(); }
  signal?.addEventListener('abort', done, {once: true});
});
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const plain = value => object(value) && Object.getPrototypeOf(value) === Object.prototype;
const canonicalJSON = value => JSON.stringify(sort(value));
const sort = value => Array.isArray(value) ? value.map(sort) : plain(value) ?
  Object.fromEntries(Object.keys(value).sort().map(key => [key, sort(value[key])])) : value;
const digest = value => createHash('sha256').update(canonicalJSON(value)).digest('hex');
const hexDigest = value => typeof value === 'string' && /^[0-9a-f]{64}$/i.test(value);
const validTime = value => typeof value === 'string' && Number.isFinite(Date.parse(value));
const clockMinutes = value => {
  if (typeof value !== 'string' || !/^\d{2}:\d{2}$/.test(value)) throw new Error('invalid_quiet_time');
  const [hour, minute] = value.split(':').map(Number);
  if (hour > 23 || minute > 59) throw new Error('invalid_quiet_time');
  return hour * 60 + minute;
};
const inside = (root, child) => {
  const path = relative(root, child);
  return path === '' || (!path.startsWith('..') && !isAbsolute(path));
};
const id = value => typeof value === 'string' && /^[a-zA-Z0-9][a-zA-Z0-9_.:-]{0,199}$/.test(value);

export function isQuietTime(date, start = DEFAULTS.quiet_start, end = DEFAULTS.quiet_end) {
  const parts = Object.fromEntries(new Intl.DateTimeFormat('en-GB', {
    timeZone: PLANNER_TIME_ZONE, hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
  }).formatToParts(date).filter(part => part.type === 'hour' || part.type === 'minute').map(part => [part.type, Number(part.value)]));
  const current = parts.hour * 60 + parts.minute;
  const from = clockMinutes(start), until = clockMinutes(end);
  if (from === until) return true;
  return from < until ? current >= from && current < until : current >= from || current < until;
}

function normalizeConfig(raw, env = process.env) {
  if (!object(raw)) throw new Error('invalid_config');
  const coreUrl = new URL(raw.core_url);
  if (!['http:', 'https:'].includes(coreUrl.protocol) || coreUrl.username || coreUrl.password ||
      coreUrl.pathname !== '/' || coreUrl.search || coreUrl.hash ||
      !['127.0.0.1', 'localhost', '[::1]'].includes(coreUrl.hostname)) throw new Error('invalid_core_url');
  if (typeof raw.core_instance_id !== 'string' || !raw.core_instance_id) throw new Error('invalid_core_instance_id');
  if (typeof raw.token_env !== 'string' || !/^[A-Z_][A-Z0-9_]*$/.test(raw.token_env)) throw new Error('invalid_token_env');
  const token = env[raw.token_env];
  if (typeof token !== 'string' || !token || /\s/.test(token)) throw new Error('missing_capture_token');
  if (typeof raw.plan_dir !== 'string' || !isAbsolute(raw.plan_dir)) throw new Error('invalid_plan_dir');
  const planDir = resolve(raw.plan_dir);
  const statePath = resolve(planDir, raw.state_file ?? '.capture-sync-state.json');
  const logPath = resolve(planDir, raw.log_file ?? 'logs/capture-sync.jsonl');
  const lockPath = resolve(planDir, raw.lock_file ?? '.capture-sync.lock');
  if (!inside(planDir, statePath) || !inside(planDir, logPath) || !inside(planDir, lockPath)) throw new Error('path_outside_plan_dir');
  const config = {...DEFAULTS, ...raw, core_url: coreUrl.href, plan_dir: planDir, state_path: statePath, log_path: logPath, lock_path: lockPath, token};
  for (const key of ['poll_ms', 'batch_ms', 'min_interval_ms', 'codex_timeout_ms', 'codex_kill_grace_ms', 'request_timeout_ms', 'retry_base_ms', 'retry_cap_ms']) {
    if (!Number.isSafeInteger(config[key]) || config[key] < 1) throw new Error(`invalid_${key}`);
  }
  clockMinutes(config.quiet_start); clockMinutes(config.quiet_end);
  if (!object(config.codex) || typeof config.codex.executable !== 'string' || !isAbsolute(config.codex.executable) ||
      (process.platform === 'win32' && /\.(?:cmd|bat)$/i.test(config.codex.executable)) ||
      !Array.isArray(config.codex.args) || config.codex.args.some(value => typeof value !== 'string') ||
      typeof config.codex.model !== 'string' || !/^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,79}$/.test(config.codex.model)) {
    throw new Error('invalid_codex_command');
  }
  const configuredModels = [];
  for (let index = 0; index < config.codex.args.length; index++) {
    const value = config.codex.args[index];
    if (value === '--') break;
    if (value === '--model' || value === '-m') {
      configuredModels.push(config.codex.args[index + 1]);
      index++;
    } else if (value.startsWith('--model=')) configuredModels.push(value.slice('--model='.length));
    else if (/^-m.+/.test(value)) configuredModels.push(null);
  }
  if (configuredModels.length !== 1 || configuredModels[0] !== config.codex.model) {
    throw new Error('codex_model_not_explicit');
  }
  return config;
}

export async function loadConfig(path, env = process.env) {
  const raw = JSON.parse(await readFile(path, 'utf8'));
  if (raw.enabled !== true) throw new Error('capture_sync_disabled');
  return normalizeConfig(raw, env);
}

function initialState(coreInstanceId) {
  return {
    version: 1,
    core_instance_id: coreInstanceId,
    committed_cursor: null,
    seen_cursor: null,
    seen_snapshot_id: null,
    policy_version: null,
    authority_binding: null,
    pending_ids: [],
    first_pending_at: null,
    last_success_at: null,
    processed: false,
    blocked_reason: null,
    retry: {attempt: 0, next_at: null, phase: null},
  };
}

function validState(value, coreInstanceId) {
  const valid = object(value) && value.version === 1 && value.core_instance_id === coreInstanceId &&
    [value.committed_cursor, value.seen_cursor, value.seen_snapshot_id, value.policy_version, value.first_pending_at, value.last_success_at]
      .every(item => item === null || typeof item === 'string') &&
    (value.authority_binding === null || exactAuthorityBinding(value.authority_binding)) &&
    Array.isArray(value.pending_ids) && value.pending_ids.every(id) && typeof value.processed === 'boolean' &&
    [null, 'capture_binding_changed', 'codex_tree_reap_unverified'].includes(value.blocked_reason) &&
    object(value.retry) && Number.isSafeInteger(value.retry.attempt) && value.retry.attempt >= 0 &&
    (value.retry.next_at === null || typeof value.retry.next_at === 'string') &&
    (value.retry.phase === null || typeof value.retry.phase === 'string');
  return valid && (value.pending_ids.length === 0 ? value.first_pending_at === null : Number.isFinite(Date.parse(value.first_pending_at))) &&
    (value.seen_cursor === null ? value.policy_version === null : typeof value.policy_version === 'string' && value.policy_version.length > 0) &&
    (value.last_success_at === null || Number.isFinite(Date.parse(value.last_success_at))) &&
    (value.retry.next_at === null || Number.isFinite(Date.parse(value.retry.next_at)));
}

async function atomicJson(path, value) {
  await mkdir(dirname(path), {recursive: true});
  const temporary = `${path}.${process.pid}.${Date.now()}.tmp`;
  await writeFile(temporary, `${JSON.stringify(value, null, 2)}\n`, {encoding: 'utf8', flag: 'wx'});
  await rename(temporary, path);
}

const codedError = code => Object.assign(new Error(code), {code});
const LOG_CODES = new Set([
  'ack_failed', 'capture_binding_changed', 'changes_page_limit', 'codex_failed', 'codex_start_failed', 'codex_timeout',
  'codex_tree_reap_unverified',
  'core_error', 'core_failed', 'core_unavailable', 'cursor_expired', 'deleted_target', 'duplicate_snapshot_record',
  'invalid_capture_record', 'invalid_capture_tombstone', 'invalid_changes_page', 'invalid_core_response', 'invalid_record_response',
  'invalid_snapshot_binding', 'invalid_snapshot_page', 'not_found', 'planner_incomplete', 'resync_required', 'scope_forbidden',
  'snapshot_binding_changed', 'snapshot_collection_digest_mismatch', 'snapshot_page_digest_mismatch', 'snapshot_page_limit',
  'unauthenticated', 'verify_failed',
]);

function pidAlive(pid) {
  try { process.kill(pid, 0); return true; }
  catch (error) { return error?.code !== 'ESRCH'; }
}

export async function acquireInstanceLock(config) {
  const path = config.lock_path;
  const recoveryPath = `${path}.recovery`;
  const nonce = randomUUID();
  await mkdir(dirname(path), {recursive: true});
  for (let attempt = 0; attempt < 4; attempt++) {
    try {
      const handle = await open(path, 'wx', 0o600);
      try { await handle.writeFile(`${JSON.stringify({version: 1, pid: process.pid, child_pid: null, reap_unverified: false, nonce, started_at: new Date().toISOString()})}\n`, 'utf8'); }
      finally { await handle.close(); }
      return {
        path,
        setChildPid(childPid) {
          const current = JSON.parse(readFileSync(path, 'utf8'));
          if (!object(current) || current.nonce !== nonce || current.pid !== process.pid) throw codedError('capture_sync_lock_lost');
          if (current.reap_unverified === true) throw codedError('codex_tree_reap_unverified');
          if (!(childPid === null || Number.isSafeInteger(childPid) && childPid > 0)) throw codedError('capture_sync_child_pid_invalid');
          const temporary = `${path}.${process.pid}.${Date.now()}.locktmp`;
          writeFileSync(temporary, `${JSON.stringify({...current, child_pid: childPid})}\n`, {encoding:'utf8',flag:'wx',mode:0o600});
          renameSync(temporary, path);
        },
        markReapUnverified() {
          const current = JSON.parse(readFileSync(path, 'utf8'));
          if (!object(current) || current.nonce !== nonce || current.pid !== process.pid) throw codedError('capture_sync_lock_lost');
          const temporary = `${path}.${process.pid}.${Date.now()}.locktmp`;
          writeFileSync(temporary, `${JSON.stringify({...current, reap_unverified: true})}\n`, {encoding:'utf8',flag:'wx',mode:0o600});
          renameSync(temporary, path);
        },
        async release() {
          let current;
          try { current = JSON.parse(await readFile(path, 'utf8')); }
          catch (error) { return error?.code === 'ENOENT'; }
          if (!object(current) || current.nonce !== nonce || current.pid !== process.pid) return false;
          if (current.reap_unverified === true || current.child_pid !== null) return false;
          try { await unlink(path); return true; }
          catch (error) { return error?.code === 'ENOENT'; }
        },
      };
    } catch (error) {
      if (error?.code !== 'EEXIST') throw error;
      let recoveryHandle;
      try {
        recoveryHandle = await open(recoveryPath, 'wx', 0o600);
        await recoveryHandle.writeFile(`${JSON.stringify({version:1,pid:process.pid,nonce,started_at:new Date().toISOString()})}\n`, 'utf8');
      } catch (guardError) {
        try { await recoveryHandle?.close(); } catch {}
        if (guardError?.code === 'EEXIST') throw codedError('capture_sync_lock_recovery_busy');
        throw codedError('capture_sync_lock_recovery_failed');
      }
      try {
        await recoveryHandle.close();
        let existing;
        try { existing = JSON.parse(await readFile(path, 'utf8')); }
        catch (readError) {
          if (readError?.code === 'ENOENT') continue;
          throw codedError('capture_sync_lock_unreadable');
        }
        if (!object(existing) || existing.version !== 1 || !Number.isSafeInteger(existing.pid) || existing.pid < 1 ||
            !(existing.child_pid === null || Number.isSafeInteger(existing.child_pid) && existing.child_pid > 0) ||
            ![undefined, false, true].includes(existing.reap_unverified) ||
            typeof existing.nonce !== 'string' || !validTime(existing.started_at)) throw codedError('capture_sync_lock_invalid');
        if (existing.reap_unverified === true) throw codedError('codex_tree_reap_unverified');
        if (pidAlive(existing.pid)) throw codedError('capture_sync_already_running');
        if (existing.child_pid !== null && pidAlive(existing.child_pid)) throw codedError('capture_sync_orphan_child_running');
        // A dead direct child does not prove its descendants exited. Only the
        // original runner can clear this registration after confirmed cleanup.
        if (existing.child_pid !== null) throw codedError('codex_tree_reap_unverified');
        const stale = `${path}.stale-${Date.now()}-${randomUUID()}`;
        try { await rename(path, stale); }
        catch (renameError) { if (renameError?.code === 'ENOENT') continue; throw codedError('capture_sync_lock_recovery_failed'); }
      } finally {
        try { await unlink(recoveryPath); } catch (cleanupError) { if (cleanupError?.code !== 'ENOENT') throw codedError('capture_sync_lock_recovery_failed'); }
      }
    }
  }
  throw codedError('capture_sync_lock_contended');
}

function killDirect(child) {
  try { child.kill('SIGKILL'); } catch {}
}

export function terminateWindowsTree(child, graceMs, spawnImpl = spawn) {
  if (!child.pid) return Promise.resolve(false);
  return new Promise(resolveKill => {
    let killer;
    try { killer = spawnImpl('taskkill.exe', ['/pid', String(child.pid), '/t', '/f'], {shell:false,windowsHide:true,stdio:'ignore'}); }
    catch { killDirect(child); resolveKill(false); return; }
    let done = false;
    const finish = verified => { if (done) return; done = true; clearTimeout(timer); resolveKill(verified); };
    const timer = setTimeout(() => { try { killer.kill(); } catch {} killDirect(child); finish(false); }, graceMs);
    killer.once('error', () => { killDirect(child); finish(false); });
    killer.once('exit', code => { if (code !== 0) killDirect(child); finish(code === 0); });
  });
}

export async function defaultCodexRunner(command, {timeoutMs, killGraceMs, signal, onSpawn, onExit,
  terminateTree = process.platform === 'win32' ? terminateWindowsTree : null} = {}) {
  return new Promise((resolveRun, rejectRun) => {
    const child = spawn(command.executable, command.args, {shell: false, windowsHide: true, stdio: 'ignore'});
    let timeout, forceTimer, timedOut = false, aborted = false, settled = false, finishing = false, registered = false;
    let fatalError = null, termination = null;
    const clear = () => {
      clearTimeout(timeout); clearTimeout(forceTimer);
      signal?.removeEventListener('abort', abort);
    };
    const stop = () => {
      if (settled || finishing || child.exitCode !== null || termination) return;
      if (terminateTree) termination = terminateTree(child, killGraceMs);
      else {
        try { child.kill('SIGTERM'); } catch {}
        termination = Promise.resolve(true);
      }
      forceTimer = setTimeout(() => killDirect(child), killGraceMs);
    };
    const abort = () => { aborted = true; stop(); };
    timeout = setTimeout(() => { timedOut = true; stop(); }, timeoutMs);
    signal?.addEventListener('abort', abort, {once: true});
    if (signal?.aborted) abort();
    const finish = async ({code = null, childSignal = null, spawnError = null} = {}) => {
      if (settled || finishing) return;
      finishing = true;
      const reapVerified = termination ? await termination : true;
      settled = true; clear();
      if (!reapVerified) { rejectRun(codedError('codex_tree_reap_unverified')); return; }
      if (registered) {
        try { onExit?.(); }
        catch { rejectRun(codedError('capture_sync_lock_lost')); return; }
      }
      if (fatalError) rejectRun(fatalError);
      else if (spawnError) rejectRun(codedError(spawnError?.code ?? 'codex_start_failed'));
      else resolveRun({code, signal: childSignal, timed_out: timedOut, aborted});
    };
    child.once('error', error => { void finish({spawnError:error}); });
    child.once('exit', (code, childSignal) => { void finish({code,childSignal}); });
    if (Number.isSafeInteger(child.pid) && child.pid > 0) {
      try { onSpawn?.(child.pid); registered = true; }
      catch (error) { fatalError = codedError(error?.code ?? 'capture_sync_lock_lost'); stop(); }
    }
  });
}

function validateDisposition(value) {
  return plain(value) && ['pending', 'done', 'skipped'].includes(value.status) &&
    Array.isArray(value.outputs) && value.outputs.every(id) && Number.isSafeInteger(value.input_revision) && value.input_revision >= 1 &&
    typeof value.note === 'string';
}

function validateCaptureRecord(record) {
  if (!plain(record) || !id(record.id) || !Number.isSafeInteger(record.revision) || record.revision < 1 ||
      !Object.hasOwn(record, 'deleted_at')) throw new CoreError('invalid_capture_record');
  if (record.deleted_at !== null) {
    if (!validTime(record.deleted_at)) throw new CoreError('invalid_capture_tombstone');
    return record;
  }
  const textRevision = record.field_meta?.text?.rev;
  if (!plain(record.data) || typeof record.data.text !== 'string' || !plain(record.provenance) ||
      typeof record.provenance.source !== 'string' || !Number.isSafeInteger(textRevision) || textRevision < 1 || textRevision > record.revision ||
      (Object.hasOwn(record.data, 'planner') && !validateDisposition(record.data.planner))) throw new CoreError('invalid_capture_record');
  return record;
}

function validateTombstone(tombstone, expectedId) {
  if (!plain(tombstone) || tombstone.domain !== 'captures' || tombstone.id !== expectedId ||
      !Number.isSafeInteger(tombstone.revision) || tombstone.revision < 1 || !validTime(tombstone.deleted_at) ||
      !['recoverable', 'purged'].includes(tombstone.body_state)) throw new CoreError('invalid_capture_tombstone');
}

function plannerPending(raw) {
  const record = validateCaptureRecord(raw);
  if (record.deleted_at !== null || record.provenance?.source === 'i_remember') return false;
  const revision = record.field_meta?.text?.rev ?? record.revision;
  const disposition = record.data?.planner;
  return !object(disposition) || disposition.input_revision !== revision || disposition.status === 'pending';
}

function plannerTerminal(raw) {
  const record = validateCaptureRecord(raw);
  if (record.deleted_at !== null) return false;
  const revision = record.field_meta.text.rev;
  const disposition = record.data.planner;
  return validateDisposition(disposition) && disposition.input_revision === revision && ['done', 'skipped'].includes(disposition.status);
}

const exactKeys = (value, keys) => plain(value) && Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));
const snapshotKeys = ['snapshot_id', 'snapshot_token', 'records', 'page_digest', 'next_page_token', 'has_more', 'manifest'];
const manifestKeys = ['core_instance_id', 'domain', 'principal_id', 'credential_generation', 'installation_id', 'view_policy_version', 'namespace',
  'snapshot_id', 'schema_version', 'policy_version', 'created_at', 'expires_at', 'cut_sequence', 'collection_digest', 'base_watermark', 'base_cursor', 'manifest_auth'];
const bindingKeys = manifestKeys.filter(key => !['base_cursor', 'manifest_auth'].includes(key));
const authorityBindingKeys = ['core_instance_id', 'domain', 'principal_id', 'credential_generation', 'installation_id',
  'view_policy_version', 'namespace', 'schema_version'];
const exactAuthorityBinding = value => exactKeys(value, authorityBindingKeys) &&
  value.core_instance_id && value.domain === 'captures' && value.principal_id &&
  Number.isSafeInteger(value.credential_generation) && value.credential_generation > 0 && value.installation_id &&
  value.view_policy_version && value.namespace === 'production' && value.schema_version === 1;

function validateSnapshotPage(result, config, expected = null) {
  if (!exactKeys(result, snapshotKeys) || typeof result.snapshot_id !== 'string' || !result.snapshot_id ||
      typeof result.snapshot_token !== 'string' || !result.snapshot_token || !Array.isArray(result.records) ||
      !hexDigest(result.page_digest) || typeof result.has_more !== 'boolean' || !exactKeys(result.manifest, manifestKeys)) {
    throw new CoreError('invalid_snapshot_page');
  }
  for (const record of result.records) validateCaptureRecord(record);
  if (digest(result.records) !== result.page_digest) throw new CoreError('snapshot_page_digest_mismatch');
  const manifest = result.manifest;
  if (manifest.core_instance_id !== config.core_instance_id || manifest.domain !== 'captures' || manifest.namespace !== 'production' ||
      manifest.snapshot_id !== result.snapshot_id || manifest.schema_version !== 1 || manifest.policy_version !== manifest.view_policy_version ||
      typeof manifest.principal_id !== 'string' || !manifest.principal_id || !Number.isSafeInteger(manifest.credential_generation) || manifest.credential_generation < 1 ||
      typeof manifest.installation_id !== 'string' || !manifest.installation_id || typeof manifest.policy_version !== 'string' || !manifest.policy_version ||
      !validTime(manifest.created_at) || !validTime(manifest.expires_at) || Date.parse(manifest.expires_at) <= Date.parse(manifest.created_at) ||
      !Number.isSafeInteger(manifest.cut_sequence) || manifest.cut_sequence < 0 || !Number.isSafeInteger(manifest.base_watermark) ||
      manifest.base_watermark < 0 || manifest.base_watermark > manifest.cut_sequence || !hexDigest(manifest.collection_digest) || !hexDigest(manifest.manifest_auth) ||
      (result.has_more ? result.next_page_token === null || manifest.base_cursor !== null : result.next_page_token !== null || typeof manifest.base_cursor !== 'string' || !manifest.base_cursor)) {
    throw new CoreError('invalid_snapshot_binding');
  }
  const binding = Object.fromEntries(bindingKeys.map(key => [key, manifest[key]]));
  if (expected && (result.snapshot_id !== expected.snapshot_id || result.snapshot_token !== expected.snapshot_token ||
      canonicalJSON(binding) !== canonicalJSON(expected.binding))) throw new CoreError('snapshot_binding_changed');
  return {snapshot_id: result.snapshot_id, snapshot_token: result.snapshot_token, binding};
}

function validateChangesPage(result) {
  const keys = ['records', 'next_cursor', 'has_more', 'retained_watermark', 'policy_version'];
  if (!exactKeys(result, keys) || !Array.isArray(result.records) || typeof result.next_cursor !== 'string' || !result.next_cursor ||
      typeof result.has_more !== 'boolean' || !Number.isSafeInteger(result.retained_watermark) || result.retained_watermark < 0 ||
      typeof result.policy_version !== 'string' || !result.policy_version) throw new CoreError('invalid_changes_page');
  for (const record of result.records) validateCaptureRecord(record);
}

export class CaptureMonitor {
  constructor(config, {fetchImpl = fetch, runCodex = defaultCodexRunner, random = Math.random, instanceLock = null} = {}) {
    this.config = normalizeConfig(config, {[config.token_env]: config.token});
    this.fetch = fetchImpl;
    this.runCodex = runCodex;
    this.random = random;
    this.instanceLock = instanceLock;
    this.state = null;
    this.stopController = new AbortController();
    this.tickTail = Promise.resolve();
  }

  stop() { this.stopController.abort(); }

  async load() {
    if (this.state) return this.state;
    try {
      const value = JSON.parse(await readFile(this.config.state_path, 'utf8'));
      if (!validState(value, this.config.core_instance_id)) throw new Error('invalid_state');
      this.state = value;
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
      this.state = initialState(this.config.core_instance_id);
      await this.save();
    }
    return this.state;
  }

  async save() { await atomicJson(this.config.state_path, this.state); }

  async log(event, fields = {}) {
    await mkdir(dirname(this.config.log_path), {recursive: true});
    const safe = {};
    for (const key of ['count', 'attempt', 'delay_ms', 'exit_code']) if (fields[key] !== undefined) safe[key] = fields[key];
    if (typeof fields.code === 'string') safe.code = LOG_CODES.has(fields.code) ? fields.code : 'unspecified_error';
    await appendFile(this.config.log_path, `${JSON.stringify({at: new Date().toISOString(), event, ...safe})}\n`, 'utf8');
  }

  async core(resource, {method = 'GET', query = {}, body} = {}) {
    const url = new URL(`/v1/core/domains/captures/${resource}`, this.config.core_url);
    if (method === 'GET') {
      url.searchParams.set('core_instance_id', this.config.core_instance_id);
      for (const [key, value] of Object.entries(query)) if (value !== undefined && value !== null) url.searchParams.set(key, String(value));
    }
    let response, payload;
    try {
      response = await this.fetch(url, {
        method,
        redirect: 'error',
        signal: AbortSignal.timeout(this.config.request_timeout_ms),
        headers: {
          authorization: `Bearer ${this.config.token}`,
          ...(method === 'GET' ? {'x-i-core-domain-protocol': '1'} : {'content-type': 'application/json'}),
        },
        ...(body ? {body: JSON.stringify(body)} : {}),
      });
      payload = await response.json();
    } catch {
      throw new CoreError('core_unavailable');
    }
    if (!response.ok) throw new CoreError(payload?.error?.code ?? 'core_error', response.status, payload);
    if (!object(payload)) throw new CoreError('invalid_core_response', response.status);
    return payload;
  }

  async bootstrap(now, {preservePending = [], expectedAuthorityBinding = null} = {}) {
    const preservedFirstPendingAt = this.state.first_pending_at;
    let snapshotToken, pageToken, cursor = null, snapshotId = null;
    let expected = null, finalManifest = null;
    const pending = new Set(preservePending), preserved = new Set(preservePending), allRecords = [], recordIds = new Set();
    for (let page = 0; page < 10_000; page++) {
      const result = await this.core('snapshot', {query: {limit: 500, snapshot_token: snapshotToken, page_token: pageToken}});
      const current = validateSnapshotPage(result, this.config, expected);
      expected ??= current;
      snapshotId = result.snapshot_id;
      for (const record of result.records) {
        if (recordIds.has(record.id)) throw new CoreError('duplicate_snapshot_record');
        recordIds.add(record.id); allRecords.push(record);
        if (preserved.has(record.id)) {
          if (plannerTerminal(record)) pending.delete(record.id);
        } else if (plannerPending(record)) pending.add(record.id);
      }
      if (!result.has_more) {
        cursor = result.manifest?.base_cursor;
        finalManifest = result.manifest;
        break;
      }
      snapshotToken = result.snapshot_token;
      pageToken = result.next_page_token;
    }
    if (!cursor) throw new CoreError('snapshot_page_limit');
    if (digest(allRecords) !== finalManifest.collection_digest) throw new CoreError('snapshot_collection_digest_mismatch');
    const authorityBinding = Object.fromEntries(authorityBindingKeys.map(key => [key, finalManifest[key]]));
    if (expectedAuthorityBinding && canonicalJSON(authorityBinding) !== canonicalJSON(expectedAuthorityBinding)) {
      throw new CoreError('capture_binding_changed');
    }
    this.state.committed_cursor = null;
    this.state.seen_cursor = cursor;
    this.state.seen_snapshot_id = snapshotId;
    this.state.policy_version = finalManifest.policy_version;
    this.state.authority_binding = authorityBinding;
    this.state.pending_ids = [...pending];
    this.state.first_pending_at = pending.size ? (preservePending.length && preservedFirstPendingAt || new Date(now).toISOString()) : null;
    this.state.processed = false;
    this.state.blocked_reason = null;
    this.clearRetry();
    await this.save();
    await this.log('snapshot_ready', {count: pending.size});
  }

  async pollChanges(now) {
    const pending = new Set(this.state.pending_ids);
    let cursor = this.state.seen_cursor;
    let complete = false;
    for (let page = 0; page < 10_000; page++) {
      const result = await this.core('changes', {query: {cursor, limit: 500}});
      validateChangesPage(result);
      if (result.policy_version !== this.state.policy_version) throw new CoreError('resync_required', 409);
      for (const record of result.records) {
        if (plannerPending(record)) pending.add(record.id);
        else pending.delete(record.id);
      }
      cursor = result.next_cursor;
      if (!result.has_more) { complete = true; break; }
    }
    if (!complete) throw new CoreError('changes_page_limit');
    this.state.seen_cursor = cursor;
    this.state.seen_snapshot_id = null;
    if (!this.state.pending_ids.length && pending.size) this.state.first_pending_at = new Date(now).toISOString();
    this.state.pending_ids = [...pending];
    await this.save();
  }

  clearRetry() { this.state.retry = {attempt: 0, next_at: null, phase: null}; }

  async fail(phase, code, now) {
    const attempt = this.state.retry.phase === phase ? this.state.retry.attempt + 1 : 1;
    const base = Math.min(this.config.retry_cap_ms, this.config.retry_base_ms * 2 ** Math.min(attempt - 1, 30));
    const delay = Math.max(1, Math.round(base * (0.8 + this.random() * 0.4)));
    this.state.retry = {attempt, next_at: new Date(now + delay).toISOString(), phase};
    await this.save();
    await this.log('retry_scheduled', {attempt, delay_ms: delay, code});
    return {status: 'retry', phase, delay_ms: delay};
  }

  retryDue(now) {
    return this.state.retry.next_at === null || Date.parse(this.state.retry.next_at) <= now;
  }

  async verifyProcessed() {
    for (const captureId of this.state.pending_ids) {
      try {
        const result = await this.core(`records/${encodeURIComponent(captureId)}`);
        if (!exactKeys(result, ['record', 'policy_version']) || result.policy_version !== this.state.policy_version ||
            !plain(result.record) || result.record.id !== captureId) throw new CoreError('invalid_record_response');
        if (!plannerTerminal(result.record)) return false;
      } catch (error) {
        if (error instanceof CoreError && error.status === 410 && error.code === 'deleted_target') {
          validateTombstone(error.payload?.tombstone, captureId);
          continue;
        }
        throw error;
      }
    }
    return true;
  }

  async acknowledge() {
    const body = {
      domain_protocol_version: 1,
      core_instance_id: this.config.core_instance_id,
      cursor: this.state.seen_cursor,
      ...(this.state.seen_snapshot_id ? {snapshot_id: this.state.seen_snapshot_id} : {}),
    };
    await this.core('ack', {method: 'POST', body});
    this.state.committed_cursor = this.state.seen_cursor;
    this.state.seen_snapshot_id = null;
    this.state.pending_ids = [];
    this.state.first_pending_at = null;
    this.state.processed = false;
    this.clearRetry();
    await this.save();
  }

  tick(now = Date.now()) {
    const invoke = () => this._tick(now);
    const result = this.tickTail.then(invoke, invoke);
    this.tickTail = result.catch(() => {});
    return result;
  }

  async _tick(now) {
    if (this.stopController.signal.aborted) return {status: 'stopped'};
    await this.load();
    if (this.state.blocked_reason === 'capture_binding_changed') return {status: 'rebind_required'};
    if (this.state.blocked_reason === 'codex_tree_reap_unverified') return {status: 'reap_required'};
    if (!this.retryDue(now)) return {status: 'backoff'};
    try {
      if (!this.state.seen_cursor) await this.bootstrap(now);
      else if (!this.state.processed) await this.pollChanges(now);
    } catch (error) {
      if (error instanceof CoreError && error.code === 'resync_required') {
        try {
          await this.bootstrap(now, {preservePending:this.state.pending_ids, expectedAuthorityBinding:this.state.authority_binding});
        } catch (bootstrapError) {
          if (bootstrapError instanceof CoreError && bootstrapError.code === 'capture_binding_changed') {
            this.state.blocked_reason = 'capture_binding_changed';
            await this.save();
            await this.log('rebind_required', {code:'capture_binding_changed'});
            return {status:'rebind_required'};
          }
          return this.fail('core', bootstrapError.code ?? 'core_failed', now);
        }
      } else return this.fail('core', error.code ?? 'core_failed', now);
    }

    if (!this.state.pending_ids.length) {
      try {
        await this.acknowledge();
        return {status: 'idle'};
      } catch (error) { return this.fail('ack', error.code ?? 'ack_failed', now); }
    }

    if (this.state.processed) {
      let complete;
      try { complete = await this.verifyProcessed(); }
      catch (error) { return this.fail('verify', error.code ?? 'verify_failed', now); }
      if (!complete) {
        this.state.processed = false;
        return this.fail('codex', 'planner_incomplete', now);
      }
      try {
        const count = this.state.pending_ids.length;
        await this.acknowledge();
        await this.log('batch_committed', {count});
        return {status: 'committed', count};
      } catch (error) { return this.fail('ack', error.code ?? 'ack_failed', now); }
    }

    const first = Date.parse(this.state.first_pending_at);
    if (now < first + this.config.batch_ms) return {status: 'batching', count: this.state.pending_ids.length};
    const last = this.state.last_success_at === null ? 0 : Date.parse(this.state.last_success_at);
    if (now < last + this.config.min_interval_ms) return {status: 'rate_limited', count: this.state.pending_ids.length};
    if (isQuietTime(new Date(now), this.config.quiet_start, this.config.quiet_end)) return {status: 'quiet', count: this.state.pending_ids.length};

    let result;
    try {
      result = await this.runCodex(this.config.codex, {
        timeoutMs: this.config.codex_timeout_ms,
        killGraceMs: this.config.codex_kill_grace_ms,
        signal: this.stopController.signal,
        onSpawn: childPid => this.instanceLock?.setChildPid(childPid),
        onExit: () => this.instanceLock?.setChildPid(null),
      });
    }
    catch (error) {
      if (error?.code === 'codex_tree_reap_unverified') {
        try { this.instanceLock?.markReapUnverified(); } catch {}
        this.state.blocked_reason = 'codex_tree_reap_unverified';
        await this.save();
        await this.log('reap_required', {code:'codex_tree_reap_unverified'});
        return {status:'reap_required'};
      }
      return this.fail('codex', error.code ?? 'codex_start_failed', now);
    }
    if (result?.aborted && this.stopController.signal.aborted) return {status: 'stopped'};
    if (result?.timed_out) return this.fail('codex', 'codex_timeout', now);
    if (result?.code !== 0) return this.fail('codex', 'codex_failed', now);
    this.state.processed = true;
    this.state.last_success_at = new Date(now).toISOString();
    this.clearRetry();
    await this.save();
    await this.log('codex_finished', {count: this.state.pending_ids.length, exit_code: 0});
    return this._tick(now);
  }

  async run() {
    while (!this.stopController.signal.aborted) {
      await this.tick();
      await sleep(this.config.poll_ms, this.stopController.signal);
    }
    return {status: 'stopped'};
  }
}

async function main() {
  const args = process.argv.slice(2);
  const configIndex = args.indexOf('--config');
  if (configIndex < 0 || !args[configIndex + 1]) throw new Error('config_required');
  const config = await loadConfig(resolve(args[configIndex + 1]));
  const lock = await acquireInstanceLock(config);
  const monitor = new CaptureMonitor(config, {instanceLock: lock});
  const stop = () => monitor.stop();
  process.once('SIGINT', stop); process.once('SIGTERM', stop);
  try {
    if (args.includes('--once')) {
      const result = await monitor.tick();
      if (['retry', 'backoff', 'rebind_required', 'reap_required'].includes(result.status)) process.exitCode = 2;
    } else await monitor.run();
  } finally {
    process.removeListener('SIGINT', stop); process.removeListener('SIGTERM', stop);
    await lock.release();
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(() => {
    process.stderr.write('capture_sync failed.\n');
    process.exitCode = 1;
  });
}
