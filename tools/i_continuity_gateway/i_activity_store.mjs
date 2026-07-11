import { createHash, randomUUID } from 'node:crypto';
import {
  closeSync,
  existsSync,
  fsyncSync,
  mkdirSync,
  openSync,
  readFileSync,
  readdirSync,
  renameSync,
  statSync,
  unlinkSync,
  writeSync,
} from 'node:fs';
import { hostname } from 'node:os';
import { basename, isAbsolute, join, resolve } from 'node:path';

import { createIActivityCrypto } from './i_activity_crypto.mjs';
import { createIActivityKeyProvider } from './i_activity_key_provider.mjs';

const MAX_SUMMARY_CHARS = 2000;
const MAX_LIST_ITEMS = 16;
const MAX_LIST_ITEM_CHARS = 600;
const MAX_ARTIFACTS = 24;
const MAX_INDEX_ENTRIES = 2000;
const LOCK_TIMEOUT_MS = 3000;
const STALE_LOCK_MS = 30000;
const SLEEP_BUFFER = new Int32Array(new SharedArrayBuffer(4));

function sha256(value) {
  return createHash('sha256').update(value, 'utf8').digest('hex');
}

function readUtf8(path) {
  if (!existsSync(path)) return '';
  return readFileSync(path, 'utf8').replace(/^\uFEFF/, '').replace(/\r\n/g, '\n');
}

function clipText(value, maxChars) {
  const text = String(value || '').replace(/\s+/g, ' ').trim();
  if (text.length <= maxChars) return text;
  return `${text.slice(0, Math.max(0, maxChars - 1)).trimEnd()}…`;
}

function requiredText(value, name, maxChars) {
  const text = String(value || '').trim();
  if (!text) throw new Error(`${name} is required`);
  if (text.length > maxChars) throw new Error(`${name} exceeds ${maxChars} characters`);
  return text;
}

function normalizedList(value, name, maxItems = MAX_LIST_ITEMS) {
  if (value == null) return [];
  if (!Array.isArray(value)) throw new Error(`${name} must be an array`);
  if (value.length > maxItems) throw new Error(`${name} exceeds ${maxItems} items`);
  return value.map((item, index) => requiredText(item, `${name}[${index}]`, MAX_LIST_ITEM_CHARS));
}

function normalizedId(value, name) {
  const text = requiredText(value, name, 220);
  if (!/^[a-zA-Z0-9][a-zA-Z0-9._:/-]{5,219}$/.test(text)) {
    throw new Error(`${name} contains unsupported characters or is too short`);
  }
  return text;
}

function normalizedClientId(value) {
  const text = String(value || 'unknown').trim().toLocaleLowerCase('en-US') || 'unknown';
  return text.replace(/[^a-z0-9._-]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 80) || 'unknown';
}

function normalizedOccurredAt(value, now) {
  if (value == null || value === '') return now.toISOString();
  const parsed = new Date(String(value));
  if (Number.isNaN(parsed.getTime())) throw new Error('occurred_at must be an ISO date-time');
  const earliest = Date.UTC(2000, 0, 1);
  const latest = now.getTime() + (24 * 60 * 60 * 1000);
  if (parsed.getTime() < earliest || parsed.getTime() > latest) {
    throw new Error('occurred_at is outside the accepted range');
  }
  return parsed.toISOString();
}

function normalizedArtifacts(value) {
  const artifacts = normalizedList(value, 'artifact_refs', MAX_ARTIFACTS);
  return artifacts.map((artifact) => {
    const normalized = artifact.replace(/\\/g, '/');
    if (isAbsolute(artifact) || /^[a-zA-Z]:/.test(artifact) || normalized.startsWith('~/') ||
        normalized.split('/').includes('..')) {
      throw new Error('artifact_refs must use project-relative paths or opaque commit/test references');
    }
    if (/^[a-z][a-z0-9+.-]*:/i.test(normalized) &&
        !/^(?:commit|test):[a-z0-9][a-z0-9._/-]{0,199}$/i.test(normalized)) {
      throw new Error('artifact_refs must only use project-relative paths, commit:<hash> or test:<id>');
    }
    return normalized;
  });
}

function containsLikelySecret(value) {
  const text = String(value || '');
  const patterns = [
    /-----BEGIN [A-Z ]*PRIVATE KEY-----/i,
    /\b(?:api[_-]?key|access[_-]?token|secret|password|passwd)\s*[:=]\s*["']?[a-z0-9_./+=-]{8,}/i,
    /\b(?:api[_-]?key|access[_-]?token|secret|password|passwd|accountkey)\s*[:=]\s*[^\s,"']{8,}/i,
    /(?:密码|密钥|令牌)\s*[:：=]\s*\S{6,}/,
    /\bBearer\s+[a-z0-9._~+/-]{12,}=*/i,
    /\bsk-[a-z0-9_-]{16,}\b/i,
    /\bgh[pousr]_[a-z0-9]{20,}\b/i,
    /\bglpat-[a-z0-9_-]{16,}\b/i,
    /\bxox[baprs]-[a-z0-9-]{16,}\b/i,
    /\bnpm_[a-z0-9]{20,}\b/i,
    /\bAIza[0-9A-Za-z_-]{20,}\b/,
    /\bAKIA[0-9A-Z]{16}\b/,
    /\beyJ[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}\b/,
    /\b(?:postgres(?:ql)?|mysql|mongodb(?:\+srv)?):\/\/[^\s/@:]+:[^\s/@]+@/i,
  ];
  return patterns.some((pattern) => pattern.test(text));
}

function assertNoLikelySecrets(parts) {
  const combined = parts.flat(Infinity).join('\n');
  if (containsLikelySecret(combined)) {
    throw new Error('closeout appears to contain a credential or secret; remove it before saving');
  }
}

function readJsonLines(path, decode = (value) => value) {
  const content = readUtf8(path);
  if (!content.trim()) return [];
  const lines = content.split('\n');
  const events = [];
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    if (!line) continue;
    try {
      events.push(decode(JSON.parse(line)));
    } catch {
      throw new Error(`encrypted activity ledger failed integrity validation at ${basename(path)}:${index + 1}`);
    }
  }
  return events;
}

function sleepSync(milliseconds) {
  Atomics.wait(SLEEP_BUFFER, 0, 0, milliseconds);
}

function processIsAlive(pid) {
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return error?.code !== 'ESRCH';
  }
}

function tryRecoverAbandonedLock(lockPath) {
  try {
    const raw = readUtf8(lockPath);
    const metadata = JSON.parse(raw);
    if (processIsAlive(Number(metadata.owner_pid))) return false;
    unlinkSync(lockPath);
    return true;
  } catch (error) {
    if (error?.code === 'ENOENT') return true;
    try {
      if (Date.now() - statSync(lockPath).mtimeMs > STALE_LOCK_MS) {
        unlinkSync(lockPath);
        return true;
      }
    } catch (statError) {
      if (statError?.code === 'ENOENT') return true;
    }
    return false;
  }
}

function withWriteLock(activityRoot, callback) {
  mkdirSync(activityRoot, { recursive: true });
  const lockPath = join(activityRoot, '.write-lock');
  const ownerToken = `${process.pid}-${randomUUID()}`;
  const deadline = Date.now() + LOCK_TIMEOUT_MS;
  while (true) {
    let lockHandle;
    try {
      lockHandle = openSync(lockPath, 'wx', 0o600);
      writeSync(lockHandle, JSON.stringify({
        schema_version: 1,
        owner_pid: process.pid,
        owner_token: ownerToken,
        acquired_at: new Date().toISOString(),
      }));
      fsyncSync(lockHandle);
      closeSync(lockHandle);
      break;
    } catch (error) {
      if (lockHandle !== undefined) {
        try { closeSync(lockHandle); } catch { /* Best-effort cleanup after failed acquisition. */ }
        try { unlinkSync(lockPath); } catch { /* The next stale-lock check remains fail-closed. */ }
      }
      if (error?.code !== 'EEXIST') throw error;
      tryRecoverAbandonedLock(lockPath);
      if (Date.now() >= deadline) throw new Error('activity ledger is busy; retry the same idempotency key');
      sleepSync(25);
    }
  }
  try {
    return callback();
  } finally {
    try {
      const metadata = JSON.parse(readUtf8(lockPath));
      if (metadata.owner_token !== ownerToken) {
        throw new Error('activity ledger lock ownership changed unexpectedly');
      }
      unlinkSync(lockPath);
    } catch (error) {
      if (error?.code !== 'ENOENT') throw error;
    }
  }
}

function appendDurableLine(path, line) {
  const handle = openSync(path, 'a', 0o600);
  try {
    writeSync(handle, line);
    fsyncSync(handle);
  } finally {
    closeSync(handle);
  }
}

function writeDurableFile(path, content) {
  const handle = openSync(path, 'wx', 0o600);
  try {
    writeSync(handle, content);
    fsyncSync(handle);
  } finally {
    closeSync(handle);
  }
}

function eventFileName(projectId) {
  return `${sha256(String(projectId)).slice(0, 24)}.jsonl.enc`;
}

function eventContentHash(payload) {
  return sha256(JSON.stringify({
    source_session_id: payload.source_session_id,
    presence_mode: payload.presence_mode,
    sensitivity: payload.sensitivity,
    summary: payload.summary,
    decisions: payload.decisions,
    open_loops: payload.open_loops,
    artifact_refs: payload.artifact_refs,
    occurred_at: payload.occurred_at,
  }));
}

function activityIndexEntry(event, currentProject, requireCurrentProject) {
  const policy = event.policy_snapshot;
  const visibility = policy.cross_project_visibility;
  if (requireCurrentProject && !currentProject) return null;
  if (currentProject && (
    currentProject.policy.id === 'confidential_local' ||
    currentProject.policy.id === 'ephemeral' ||
    currentProject.policy.cross_project_visibility === 'hidden'
  )) return null;
  if (event.sensitivity === 'local_only' || visibility === 'hidden' ||
      policy.id === 'confidential_local' || policy.id === 'ephemeral') {
    return null;
  }
  const currentPolicy = currentProject?.policy;
  const effectiveNameOnly = visibility === 'name_only' ||
    currentPolicy?.cross_project_visibility === 'name_only';
  if (effectiveNameOnly) {
    return {
      project_id: event.project_id,
      visibility: 'name_only',
      occurred_at: event.occurred_at,
    };
  }
  const base = {
    event_id: event.event_id,
    project_id: event.project_id,
    source_tool: event.source_tool,
    event_type: event.event_type,
    occurred_at: event.occurred_at,
    decision_count: event.decisions.length,
    open_loop_count: event.open_loops.length,
  };
  if (policy.id === 'work_redacted' || currentPolicy?.id === 'work_redacted') {
    return {
      ...base,
      redaction: 'work_redacted',
      summary: `${event.source_tool} 完成了一次工作会话`,
    };
  }
  return {
    ...base,
    redaction: 'policy_summary',
    summary: clipText(event.summary, 280),
  };
}

function publicCloseout(event, { includeDetails = true } = {}) {
  const base = {
    event_id: event.event_id,
    event_type: event.event_type,
    project_id: event.project_id,
    project_key: event.project_key,
    source_tool: event.source_tool,
    source_session_id: event.source_session_id,
    presence_mode: event.presence_mode,
    sensitivity: event.sensitivity || event.policy_snapshot?.classification || 'unclassified',
    summary: event.summary,
    occurred_at: event.occurred_at,
    received_at: event.received_at,
    authority: event.authority,
    trust_level: event.trust_level,
    source: `i://project-activity/${event.event_id}`,
  };
  if (!includeDetails) return base;
  return {
    ...base,
    decisions: event.decisions,
    open_loops: event.open_loops,
    artifact_refs: event.artifact_refs,
  };
}

function scoreActivity(event, query) {
  const normalized = String(query || '').toLocaleLowerCase('zh-CN').trim();
  if (!normalized) return 0;
  const haystack = [event.summary, ...event.decisions, ...event.open_loops, ...event.artifact_refs]
    .join(' ').toLocaleLowerCase('zh-CN');
  if (haystack.includes(normalized)) return 30;
  const tokens = normalized.match(/[a-z0-9_./-]{2,}|[\p{Script=Han}]{2,}/gu) || [];
  let score = 0;
  for (const token of tokens) {
    if (haystack.includes(token)) score += Math.min(10, token.length * 2);
    if (/^[\p{Script=Han}]+$/u.test(token) && token.length > 2) {
      for (let index = 0; index < token.length - 1; index += 1) {
        if (haystack.includes(token.slice(index, index + 2))) score += 2;
      }
    }
  }
  return score;
}

export function createIActivityStore({
  iHome,
  clock = () => new Date(),
  uuid = randomUUID,
  keyProvider,
  registryProjectsProvider,
} = {}) {
  if (!iHome) throw new Error('iHome is required');
  const home = resolve(iHome);
  const activityBaseRoot = join(home, 'activity');
  const activityRoot = join(activityBaseRoot, 'v2');
  const eventsRoot = join(activityRoot, 'events');
  const indexPath = join(activityRoot, 'activity-index.enc.json');
  const indexDirtyPath = join(activityRoot, 'activity-index.dirty');
  const indexPolicyPath = join(activityRoot, 'activity-index.policy');
  const legacyEventsRoot = join(activityBaseRoot, 'events');
  const legacyIndexPath = join(activityBaseRoot, 'activity-index.json');
  const activityKeyProvider = keyProvider || createIActivityKeyProvider({ iHome: home });
  let activityCrypto = null;

  function currentRegistryPolicy() {
    if (typeof registryProjectsProvider !== 'function') {
      return { projects: null, policyHash: null };
    }
    const projects = registryProjectsProvider();
    const normalized = (Array.isArray(projects) ? projects : [])
      .map((project) => ({
        project_id: String(project.project_id || ''),
        policy_id: String(project.policy?.id || 'ephemeral'),
        visibility: String(project.policy?.cross_project_visibility || 'hidden'),
      }))
      .filter((project) => project.project_id)
      .sort((a, b) => a.project_id.localeCompare(b.project_id));
    return {
      projects: new Map((Array.isArray(projects) ? projects : []).map((project) => [
        project.project_id,
        project,
      ])),
      policyHash: sha256(JSON.stringify(normalized)),
    };
  }

  function hasLegacyActivity() {
    return existsSync(legacyEventsRoot) || existsSync(legacyIndexPath);
  }

  function assertNoLegacyActivity() {
    if (hasLegacyActivity()) {
      throw new Error('legacy plaintext activity data requires explicit migration before Phase 2 can continue');
    }
  }

  function hasEncryptedData() {
    return existsSync(indexPath) || (
      existsSync(eventsRoot) && readdirSync(eventsRoot).some((entry) => entry.endsWith('.jsonl.enc'))
    );
  }

  function cryptoForRead() {
    if (activityCrypto) return activityCrypto;
    const material = activityKeyProvider.loadKey();
    if (!material) throw new Error('activity encryption key is missing; encrypted data was not read');
    activityCrypto = createIActivityCrypto(material);
    return activityCrypto;
  }

  function cryptoForWrite() {
    if (activityCrypto) return activityCrypto;
    let material = activityKeyProvider.loadKey();
    if (!material && hasEncryptedData()) {
      throw new Error('activity encryption key is missing; refusing to create a replacement for existing data');
    }
    material ||= activityKeyProvider.loadOrCreateKey();
    activityCrypto = createIActivityCrypto(material);
    return activityCrypto;
  }

  function projectLedgerPath(projectId) {
    return join(eventsRoot, eventFileName(projectId));
  }

  function projectLedgerScope(projectId) {
    return `ledger:${eventFileName(projectId)}`;
  }

  function readProjectEvents(projectId) {
    const path = projectLedgerPath(projectId);
    if (!existsSync(path)) return [];
    assertNoLegacyActivity();
    const crypto = cryptoForRead();
    return readJsonLines(path, (envelope) => crypto.open(envelope, projectLedgerScope(projectId)))
      .filter((event) => event.project_id === projectId)
      .sort((a, b) => b.occurred_at.localeCompare(a.occurred_at) ||
        b.received_at.localeCompare(a.received_at));
  }

  function allEvents() {
    if (!existsSync(eventsRoot)) return [];
    assertNoLegacyActivity();
    const crypto = cryptoForRead();
    return readdirSync(eventsRoot, { withFileTypes: true })
      .filter((entry) => entry.isFile() && entry.name.endsWith('.jsonl.enc'))
      .flatMap((entry) => readJsonLines(
        join(eventsRoot, entry.name),
        (envelope) => crypto.open(envelope, `ledger:${entry.name}`),
      ));
  }

  function eventsEligibleForIndex(currentPolicy) {
    if (currentPolicy.projects === null) return allEvents();
    return [...currentPolicy.projects.values()]
      .filter((project) => (
        project.policy.id !== 'confidential_local' &&
        project.policy.id !== 'ephemeral' &&
        project.policy.cross_project_visibility !== 'hidden'
      ))
      .flatMap((project) => readProjectEvents(project.project_id));
  }

  function rebuildIndexLocked(now) {
    const currentPolicy = currentRegistryPolicy();
    const entries = eventsEligibleForIndex(currentPolicy)
      .map((event) => activityIndexEntry(
        event,
        currentPolicy.projects?.get(event.project_id),
        currentPolicy.projects !== null,
      ))
      .filter(Boolean)
      .sort((a, b) => b.occurred_at.localeCompare(a.occurred_at))
      .slice(0, MAX_INDEX_ENTRIES);
    const index = {
      schema_version: 3,
      generated_at: now.toISOString(),
      registry_policy_hash: currentPolicy.policyHash,
      event_count: entries.length,
      entries,
    };
    mkdirSync(activityRoot, { recursive: true });
    const tempPath = `${indexPath}.${process.pid}.${Date.now()}.tmp`;
    const policyMarker = currentPolicy.policyHash || 'snapshot';
    const policyTempPath = `${indexPolicyPath}.${process.pid}.${Date.now()}.tmp`;
    try {
      const envelope = cryptoForRead().seal(index, 'activity-index:v2');
      writeDurableFile(tempPath, `${JSON.stringify(envelope, null, 2)}\n`);
      writeDurableFile(policyTempPath, `${policyMarker}\n`);
      renameSync(tempPath, indexPath);
      renameSync(policyTempPath, indexPolicyPath);
      if (existsSync(indexDirtyPath)) unlinkSync(indexDirtyPath);
    } finally {
      if (existsSync(tempPath)) {
        try { unlinkSync(tempPath); } catch { /* A later rebuild can clean stale temp files. */ }
      }
      if (existsSync(policyTempPath)) {
        try { unlinkSync(policyTempPath); } catch { /* A later rebuild can clean stale temp files. */ }
      }
    }
    return index;
  }

  function markIndexDirty() {
    if (existsSync(indexDirtyPath)) return;
    writeDurableFile(indexDirtyPath, `${new Date().toISOString()}\n`);
  }

  function closeSession({ project, clientId, input = {} }) {
    if (!project?.registered) {
      return {
        schema_version: 1,
        accepted: false,
        persisted: false,
        reason: 'project_registration_required',
        project_key: project?.project_key || null,
      };
    }
    if (project.access_status !== 'allowed') throw new Error('this client is not allowed to write the active project');
    const presenceMode = String(input.presence_mode || 'delegated_tool').trim();
    if (!['delegated_tool', 'lin_ai', 'private'].includes(presenceMode)) {
      throw new Error('presence_mode must be delegated_tool, lin_ai or private');
    }
    const sensitivity = String(input.sensitivity || 'project_default').trim();
    if (!['project_default', 'local_only', 'private'].includes(sensitivity)) {
      throw new Error('sensitivity must be project_default, local_only or private');
    }
    if (presenceMode === 'private' || sensitivity === 'private' || project.policy.id === 'ephemeral') {
      return {
        schema_version: 1,
        accepted: false,
        persisted: false,
        reason: presenceMode === 'private'
          ? 'private_presence_mode'
          : (sensitivity === 'private' ? 'private_sensitivity' : 'ephemeral_project'),
        project_key: project.project_key,
      };
    }

    const now = clock();
    const sourceTool = normalizedClientId(clientId);
    const requestedOccurredAt = input.occurred_at == null || input.occurred_at === ''
      ? null
      : normalizedOccurredAt(input.occurred_at, now);
    const normalized = {
      source_session_id: normalizedId(input.session_id, 'session_id'),
      idempotency_key: normalizedId(input.idempotency_key, 'idempotency_key'),
      presence_mode: presenceMode,
      sensitivity,
      summary: requiredText(input.summary, 'summary', MAX_SUMMARY_CHARS),
      decisions: normalizedList(input.decisions, 'decisions'),
      open_loops: normalizedList(input.open_loops, 'open_loops'),
      artifact_refs: normalizedArtifacts(input.artifact_refs),
      occurred_at: requestedOccurredAt || now.toISOString(),
    };
    assertNoLikelySecrets([
      normalized.summary,
      normalized.decisions,
      normalized.open_loops,
      normalized.artifact_refs,
    ]);
    const contentHash = eventContentHash({
      ...normalized,
      // A retry without an explicit timestamp must remain idempotent even when it arrives later.
      occurred_at: requestedOccurredAt,
    });
    const idempotencyScope = `${project.project_id}:${sourceTool}:${normalized.idempotency_key}`;

    assertNoLegacyActivity();
    return withWriteLock(activityBaseRoot, () => {
      mkdirSync(eventsRoot, { recursive: true });
      const ledgerPath = projectLedgerPath(project.project_id);
      const existing = readProjectEvents(project.project_id).find((event) => (
        event.idempotency_scope === idempotencyScope
      ));
      if (existing) {
        if (existing.content_hash !== contentHash) {
          throw new Error('idempotency key already exists with different closeout content');
        }
        let indexStatus = existsSync(indexDirtyPath) ? 'stale_rebuild_required' : 'ready';
        if (indexStatus !== 'ready' || !existsSync(indexPath)) {
          try {
            rebuildIndexLocked(now);
            indexStatus = 'ready';
          } catch {
            indexStatus = 'stale_rebuild_required';
          }
        }
        return {
          schema_version: 1,
          accepted: true,
          persisted: true,
          duplicate: true,
          event: publicCloseout(existing),
          index_status: indexStatus,
        };
      }

      const event = {
        schema_version: 2,
        event_id: uuid(),
        event_type: 'session_closeout',
        project_id: project.project_id,
        project_key: project.project_key,
        project_name: project.display_name,
        policy_snapshot: {
          id: project.policy.id,
          version: 1,
          classification: project.policy.classification,
          cross_project_visibility: project.policy.cross_project_visibility,
          memory_v3: project.policy.memory_v3,
        },
        source_tool: sourceTool,
        source_instance: `local-${sha256(hostname()).slice(0, 12)}`,
        source_session_id: normalized.source_session_id,
        presence_mode: normalized.presence_mode,
        sensitivity: normalized.sensitivity === 'local_only'
          ? 'local_only'
          : project.policy.classification,
        summary: normalized.summary,
        decisions: normalized.decisions,
        open_loops: normalized.open_loops,
        artifact_refs: normalized.artifact_refs,
        authority: 'agent_inferred',
        trust_level: 'trusted_client_unverified_content',
        memory_lanes_allowed: ['project'],
        storage_mode: 'local_gateway_encrypted_ledger',
        redaction_state: normalized.sensitivity === 'local_only'
          ? 'activity_index_excluded'
          : (project.policy.id === 'work_redacted' ? 'activity_index_redacted' : 'policy_summary'),
        occurred_at: normalized.occurred_at,
        received_at: now.toISOString(),
        content_hash: contentHash,
        idempotency_key: normalized.idempotency_key,
        idempotency_scope: idempotencyScope,
      };
      const crypto = cryptoForWrite();
      markIndexDirty();
      appendDurableLine(
        ledgerPath,
        `${JSON.stringify(crypto.seal(event, projectLedgerScope(project.project_id)))}\n`,
      );
      let indexStatus = 'ready';
      try {
        rebuildIndexLocked(now);
      } catch {
        indexStatus = 'stale_rebuild_required';
      }
      return {
        schema_version: 1,
        accepted: true,
        persisted: true,
        duplicate: false,
        event: publicCloseout(event),
        index_status: indexStatus,
      };
    });
  }

  function getProjectHandoffs(project, { limit = 3 } = {}) {
    if (!project?.registered || project.access_status !== 'allowed' || project.policy.id === 'ephemeral') return [];
    const maxItems = Math.max(1, Math.min(20, Number.parseInt(String(limit), 10) || 3));
    if (!existsSync(projectLedgerPath(project.project_id))) return [];
    return withWriteLock(activityBaseRoot, () => (
      readProjectEvents(project.project_id).slice(0, maxItems).map((event) => publicCloseout(event))
    ));
  }

  function searchProjectActivity(project, query, { limit = 6 } = {}) {
    if (!project?.registered || project.access_status !== 'allowed' || project.policy.id === 'ephemeral') return [];
    const maxItems = Math.max(1, Math.min(20, Number.parseInt(String(limit), 10) || 6));
    if (!existsSync(projectLedgerPath(project.project_id))) return [];
    return withWriteLock(activityBaseRoot, () => (
      readProjectEvents(project.project_id)
        .map((event) => ({ event, score: scoreActivity(event, query) }))
        .filter((item) => item.score > 0)
        .sort((a, b) => b.score - a.score || b.event.occurred_at.localeCompare(a.event.occurred_at))
        .slice(0, maxItems)
        .map(({ event, score }) => ({ ...publicCloseout(event), score }))
    ));
  }

  function getRecentActivity({ visibleProjects, limit = 20 } = {}) {
    const maxItems = Math.max(1, Math.min(100, Number.parseInt(String(limit), 10) || 20));
    const visible = new Map((visibleProjects || []).map((project) => [project.project_id, project]));
    assertNoLegacyActivity();
    if (!hasEncryptedData()) {
      return {
        schema_version: 1,
        coverage: 'registered_project_closeouts',
        activity_count: 0,
        activities: [],
        index_status: 'missing',
        encryption: 'aes-256-gcm',
        as_of: clock().toISOString(),
      };
    }
    return withWriteLock(activityBaseRoot, () => {
      const currentPolicyHash = currentRegistryPolicy().policyHash;
      const expectedPolicyMarker = currentPolicyHash || 'snapshot';
      const storedPolicyMarker = readUtf8(indexPolicyPath).trim();
      let index;
      const policyRequiresRebuild = storedPolicyMarker !== expectedPolicyMarker ||
        existsSync(indexDirtyPath);
      if (!policyRequiresRebuild) {
        try {
          const envelope = JSON.parse(readUtf8(indexPath));
          index = cryptoForRead().open(envelope, 'activity-index:v2');
        } catch {
          index = null;
        }
      }
      if (!index || index.schema_version !== 3 || policyRequiresRebuild ||
          index.registry_policy_hash !== currentPolicyHash) {
        try {
          index = rebuildIndexLocked(clock());
        } catch {
          throw new Error('activity index is stale and could not be rebuilt safely; retry later');
        }
      }

      const nameOnlyProjects = new Set();
      const activities = [];
      for (const rawEntry of Array.isArray(index.entries) ? index.entries : []) {
        if (activities.length >= maxItems) break;
        if (!rawEntry || typeof rawEntry !== 'object') continue;
        const projectId = String(rawEntry.project_id || '');
        const current = visible.get(projectId);
        if (!current) continue;
        const nameOnly = current.policy.cross_project_visibility === 'name_only' ||
          rawEntry.visibility === 'name_only';
        if (nameOnly) {
          if (!nameOnlyProjects.has(projectId)) {
            nameOnlyProjects.add(projectId);
            activities.push({
              project_id: current.project_id,
              project_key: current.project_key,
              project_name: current.display_name,
              visibility: 'name_only',
            });
          }
          continue;
        }
        const eventId = String(rawEntry.event_id || '');
        const sourceTool = normalizedClientId(rawEntry.source_tool);
        const eventType = String(rawEntry.event_type || '');
        const occurredAt = String(rawEntry.occurred_at || '');
        if (!eventId || eventType !== 'session_closeout' || !occurredAt) continue;
        const base = {
          event_id: eventId,
          project_id: current.project_id,
          project_key: current.project_key,
          project_name: current.display_name,
          source_tool: sourceTool,
          event_type: eventType,
          occurred_at: occurredAt,
          visibility: 'summary',
          decision_count: Math.max(0, Math.min(MAX_LIST_ITEMS, Number(rawEntry.decision_count) || 0)),
          open_loop_count: Math.max(0, Math.min(MAX_LIST_ITEMS, Number(rawEntry.open_loop_count) || 0)),
        };
        if (current.policy.id === 'work_redacted' || rawEntry.redaction === 'work_redacted') {
          activities.push({
            ...base,
            redaction: 'work_redacted',
            summary: `${sourceTool} 完成了一次工作会话`,
          });
        } else if (rawEntry.redaction === 'policy_summary') {
          activities.push({
            ...base,
            redaction: 'policy_summary',
            summary: clipText(rawEntry.summary, 280),
          });
        }
      }
      return {
        schema_version: 1,
        coverage: 'registered_project_closeouts',
        activity_count: activities.length,
        activities,
        index_status: 'ready',
        encryption: 'aes-256-gcm',
        generated_at: index.generated_at,
        as_of: clock().toISOString(),
      };
    });
  }

  /// Trusted Here I am Bridge export. This is not an MCP cross-project query:
  /// it only emits the current Registry policies' Memory V3-safe projection.
  function getMemoryV3Projections({ projects, after, limit = 100 } = {}) {
    const maxItems = Math.max(1, Math.min(500, Number.parseInt(String(limit), 10) || 100));
    const afterIso = after ? new Date(after).toISOString() : null;
    const projected = [];
    for (const project of projects || []) {
      const policy = project?.policy || {};
      if (!project || project.registered === false ||
          (project.access_status && project.access_status !== 'allowed')) continue;
      if (!['project_summary', 'redacted_summary'].includes(policy.memory_v3)) continue;
      for (const event of readProjectEvents(project.project_id)) {
        if (projected.length >= maxItems) break;
        if (afterIso && event.received_at <= afterIso) continue;
        if (event.event_type !== 'session_closeout' ||
            event.sensitivity === 'local_only' || event.presence_mode === 'private') continue;
        const redacted = policy.memory_v3 === 'redacted_summary' || policy.id === 'work_redacted';
        projected.push({
          schema_version: 1,
          event_id: event.event_id,
          event_type: event.event_type,
          project_id: project.project_id,
          project_key: project.project_key,
          policy: {
            id: policy.id,
            version: 1,
            memory_v3: policy.memory_v3,
          },
          source_tool: event.source_tool,
          source_session_id: event.source_session_id,
          sensitivity: redacted ? 'redacted' : 'personal',
          redaction_state: redacted ? 'activity_index_redacted' : 'policy_summary',
          authority: event.authority,
          trust_level: event.trust_level,
          source: `i://project-activity/${event.event_id}`,
          memory_lanes_allowed: ['project'],
          summary: redacted ? `${event.source_tool} completed a work session.` : clipText(event.summary, 1000),
          decisions: redacted ? [] : event.decisions,
          open_loops: redacted ? [] : event.open_loops,
          artifact_refs: redacted ? [] : event.artifact_refs,
          occurred_at: event.occurred_at,
          received_at: event.received_at,
          content_hash: event.content_hash,
        });
      }
    }
    projected.sort((a, b) => b.received_at.localeCompare(a.received_at));
    return {
      schema_version: 1,
      projection_count: projected.length,
      projections: projected.slice(0, maxItems),
      as_of: clock().toISOString(),
    };
  }

  function rebuildActivityIndex() {
    assertNoLegacyActivity();
    if (!hasEncryptedData()) {
      return { schema_version: 3, event_count: 0, entries: [], status: 'no_activity' };
    }
    return withWriteLock(activityBaseRoot, () => rebuildIndexLocked(clock()));
  }

  function getStorageStatus() {
    if (hasLegacyActivity()) return 'migration_required';
    if (!activityKeyProvider.isSupported) return 'unsupported_platform';
    if (hasEncryptedData() && !activityKeyProvider.hasKey()) return 'key_missing';
    return activityKeyProvider.hasKey() ? 'encrypted_ready' : 'encrypted_uninitialized';
  }

  return {
    activityRoot,
    closeSession,
    getProjectHandoffs,
    searchProjectActivity,
    getRecentActivity,
    getMemoryV3Projections,
    rebuildActivityIndex,
    getStorageStatus,
  };
}
