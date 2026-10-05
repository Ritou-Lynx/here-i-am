import { timingSafeEqual } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import http from 'node:http';
import https from 'node:https';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  CORE_PROTOCOL_VERSION,
  CoreStoreError,
  ICoreStore,
  preflightActivityCommitmentVersion,
  preflightAuthoritySecretSeparation,
  verifyActivityRecoveryCandidate,
  isExternalFrontendDevice,
} from './i_core_store.mjs';
import { ACTIVITY_MAX_REQUEST_BYTES } from './activity_control_plane.mjs';
import { createDomainRequestHandler } from './domain_http.mjs';
import {
  SHORTCUT_WORKFLOW,
  ShortcutMailRelayError,
  createConfiguredShortcutMailRelay,
} from './shortcut_mail_relay.mjs';

const modulePath = fileURLToPath(import.meta.url);
const moduleDir = path.dirname(modulePath);

function json(response, status, payload) {
  const body = JSON.stringify(payload);
  response.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(body),
    'cache-control': 'no-store',
  });
  response.end(body);
}

function errorBody(error) {
  return {
    error: {
      code: error.code ?? 'core_error',
      message: error.message ?? 'Core request failed.',
      retryable: error.retryable ?? false,
      details: error.details ?? {},
    },
  };
}

function equalSecret(left, right) {
  if (typeof left !== 'string' || typeof right !== 'string') return false;
  const a = Buffer.from(left);
  const b = Buffer.from(right);
  return a.length === b.length && timingSafeEqual(a, b);
}

async function readJson(request, maxBytes = 1024 * 1024) {
  const chunks = [];
  let bytes = 0;
  for await (const chunk of request) {
    bytes += chunk.length;
    if (bytes > maxBytes) {
      throw new CoreStoreError('request_too_large', 'JSON request body is too large.', { status: 413 });
    }
    chunks.push(chunk);
  }
  if (chunks.length === 0) return {};
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch (_) {
    throw new CoreStoreError('invalid_json', 'Request body must be valid JSON.');
  }
}

function bearerToken(request) {
  const header = request.headers.authorization;
  if (typeof header !== 'string' || !header.startsWith('Bearer ')) return null;
  return header.slice('Bearer '.length).trim();
}

function requireProtocol(request) {
  const version = request.headers['x-core-protocol'];
  if (version !== CORE_PROTOCOL_VERSION) {
    throw new CoreStoreError(
      'protocol_mismatch',
      `X-Core-Protocol must be ${CORE_PROTOCOL_VERSION}.`,
      { status: 426 },
    );
  }
}

function requireFeedReader(request, store) {
  const device = requireDevice(request, store);
  if (isExternalFrontendDevice(device)) {
    throw new CoreStoreError(
      'chat_read_forbidden',
      'External frontend credentials can only append turns.',
      { status: 403 },
    );
  }
  return device;
}

function requireDevice(request, store) {
  requireProtocol(request);
  const token = bearerToken(request);
  const device = store.authenticate(token);
  if (!device) {
    if (store.activity.isActiveCredentialToken(token)) {
      throw new CoreStoreError(
        'chat_read_forbidden',
        'Activity-scoped credentials cannot access the chat control plane.',
        { status: 403 },
      );
    }
    throw new CoreStoreError('unauthorized', 'A valid device token is required.', { status: 401 });
  }
  return device;
}

function requireActivityEnabled(activityAdminSecret) {
  if (!activityAdminSecret) {
    throw new CoreStoreError(
      'activity_disabled',
      'The activity control plane is disabled until an independent owner credential is configured.',
      { status: 503 },
    );
  }
}

function requireActivityOwner(request, store, activityAdminSecret) {
  requireProtocol(request);
  requireActivityEnabled(activityAdminSecret);
  const token = bearerToken(request);
  if (!equalSecret(token, activityAdminSecret)) {
    if (store.activity.isActiveCredentialToken(token)) {
      throw new CoreStoreError(
        'admin_escalation_forbidden',
        'Activity probe and summary credentials cannot act as the activity owner.',
        { status: 403 },
      );
    }
    throw new CoreStoreError(
      'activity_admin_unauthorized',
      'A valid independent activity owner credential is required.',
      { status: 401 },
    );
  }
  return { principal_id: 'activity-owner', scopes: ['activity.admin'] };
}

function requireActivityPrincipal(request, store, activityAdminSecret) {
  requireProtocol(request);
  requireActivityEnabled(activityAdminSecret);
  const principal = store.activity.authenticate(bearerToken(request));
  if (!principal) {
    throw new CoreStoreError(
      'activity_unauthorized',
      'A valid activity-scoped credential is required.',
      { status: 401 },
    );
  }
  return principal;
}

function pathIdentity(pathname, prefix) {
  if (!pathname.startsWith(prefix)) return null;
  const encoded = pathname.slice(prefix.length);
  if (!encoded || encoded.includes('/')) return null;
  try {
    const value = decodeURIComponent(encoded);
    return value.trim() ? value : null;
  } catch (_) {
    throw new CoreStoreError('invalid_request', 'Path identity is not valid URL encoding.');
  }
}

function requireWorker(request, workerSecret) {
  requireProtocol(request);
  if (!workerSecret || !equalSecret(bearerToken(request), workerSecret)) {
    throw new CoreStoreError(
      'worker_unauthorized',
      'A valid core worker credential is required.',
      { status: 401 },
    );
  }
}

function requireShortcutMailRelay(request, relay) {
  requireProtocol(request);
  if (!relay) {
    throw new CoreStoreError(
      'shortcut_mail_disabled',
      'The manual Shortcut mail test is not configured on this core.',
      { status: 503 },
    );
  }
  const token = bearerToken(request);
  if (!token) {
    throw new CoreStoreError(
      'shortcut_mail_unauthorized',
      'A scoped Shortcut mail test token is required.',
      { status: 401 },
    );
  }
  return token;
}

function shortcutMailTestBody(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    throw new CoreStoreError('invalid_request', 'Request body must be an object.');
  }
  const keys = Object.keys(body);
  if (keys.length !== 1 || keys[0] !== 'trigger') {
    throw new CoreStoreError(
      'fixed_template_only',
      'The manual Shortcut mail test accepts only the fixed trigger.',
    );
  }
  if (body.trigger !== SHORTCUT_WORKFLOW) {
    throw new CoreStoreError(
      'unsupported_workflow',
      `trigger must be ${SHORTCUT_WORKFLOW}.`,
      { status: 403 },
    );
  }
  return body.trigger;
}

function idempotencyKey(request) {
  const value = request.headers['idempotency-key'];
  if (typeof value !== 'string' || !value.trim()) {
    throw new CoreStoreError(
      'invalid_request',
      'Idempotency-Key is required for this manual test.',
    );
  }
  return value.trim();
}

export function createICoreServer({
  databasePath,
  pairingCode = null,
  certPath = null,
  keyPath = null,
  workerSecret = null,
  companionReplyJobsEnabled = false,
  shortcutMailRelay = null,
  ownsShortcutMailRelay = shortcutMailRelay !== null,
  activityAdminSecret = null,
  activityRecoveryFloor = null,
  requireActivityRecoveryFloor = false,
  activityRuntimeId = undefined,
  activityRuntimeLeaseMs = undefined,
  activityRetentionIntervalMs = 60_000,
  domainVerifyAuthorization = undefined,
  domainTestOnlyFault = undefined,
  domainDedupHooks = undefined,
  clock = Date.now,
} = {}) {
  if (!databasePath) throw new Error('databasePath is required');
  // This must precede secret separation and recovery verification: read-only
  // SQLite opens can themselves create or alter source WAL/SHM files.
  preflightActivityCommitmentVersion(databasePath);
  if (pairingCode !== null && (typeof pairingCode !== 'string' || !pairingCode.trim())) {
    throw new Error('pairingCode must be null or a non-empty string');
  }
  if (activityAdminSecret !== null && (typeof activityAdminSecret !== 'string' || activityAdminSecret.length < 16)) {
    throw new Error('activityAdminSecret must be null or an independent secret of at least 16 characters');
  }
  if (!Number.isSafeInteger(activityRetentionIntervalMs) || activityRetentionIntervalMs < 1) {
    throw new Error('activityRetentionIntervalMs must be a positive safe integer');
  }
  if (requireActivityRecoveryFloor && !activityRecoveryFloor) {
    throw new CoreStoreError('recovery_floor_required', 'A trusted activity recovery floor is required.', { status: 503 });
  }
  if (activityRecoveryFloor) {
    verifyActivityRecoveryCandidate(databasePath, activityRecoveryFloor);
    throw new CoreStoreError(
      'backup_activation_unsupported',
      'Recovery candidate verification is offline-only; this server cannot activate a backup.',
      { status: 503 },
    );
  }
  preflightAuthoritySecretSeparation(databasePath, {
    activityAdminSecret,
    workerSecret,
    pairingCode,
    shortcutMailTokenHash: shortcutMailRelay?.tokenHash ?? null,
    now: clock(),
  });
  const store = new ICoreStore(databasePath, {
    companionReplyJobsEnabled,
    clock,
    activityRecoveryFloor,
    activityRuntimeId,
    activityRuntimeLeaseMs,
    activityEnabled: Boolean(activityAdminSecret),
    activityAutoActivate: false,
    domainVerifyAuthorization,
    domainTestOnlyFault,
    domainDedupHooks,
  });
  const handleDomainRequest = createDomainRequestHandler({
    getStore: () => store.domains,
    authenticateDevice: (token) => store.authenticate(token),
  });
  let pairingEndpointEnabled = pairingCode !== null;
  let activePairingCode = pairingEndpointEnabled && !store.isPairingCodeConsumed(pairingCode)
    ? pairingCode
    : null;

  async function handle(request, response) {
    try {
      const url = new URL(request.url, 'http://core.local');
      if (request.method === 'GET' && url.pathname === '/v1/core/health') {
        json(response, 200, store.health({
          workerLeasesEnabled: Boolean(workerSecret),
          activityOwnerConfigured: Boolean(activityAdminSecret),
        }));
        return;
      }
      // Preserve synchronous legacy body listener setup, including read-only wire observers.
      const domainPath = (request.url ?? '').split('?')[0];
      if (domainPath === '/v1/core/domains' || domainPath.startsWith('/v1/core/domains/')) {
        await handleDomainRequest(request, response);
        return;
      }
      if (request.method === 'POST' && url.pathname === '/v1/core/activity/probes/pair') {
        requireActivityOwner(request, store, activityAdminSecret);
        json(response, 200, store.activity.pairProbe(await readJson(request, 32 * 1024)));
        return;
      }
      if (request.method === 'POST' && url.pathname === '/v1/core/activity/readers/pair') {
        requireActivityOwner(request, store, activityAdminSecret);
        json(response, 200, store.activity.pairSummaryReader(await readJson(request, 16 * 1024)));
        return;
      }
      if (
        request.method === 'POST'
        && url.pathname.startsWith('/v1/core/activity/principals/')
        && url.pathname.endsWith('/rotate')
      ) {
        requireActivityOwner(request, store, activityAdminSecret);
        const principalId = pathIdentity(
          url.pathname.slice(0, -'/rotate'.length),
          '/v1/core/activity/principals/',
        );
        json(response, 200, store.activity.rotatePrincipal(principalId));
        return;
      }
      if (request.method === 'POST' && url.pathname === '/v1/core/activity/events') {
        const principal = requireActivityPrincipal(request, store, activityAdminSecret);
        json(response, 200, store.activity.appendEvents(
          principal,
          await readJson(request, ACTIVITY_MAX_REQUEST_BYTES),
        ));
        return;
      }
      if (request.method === 'GET' && url.pathname === '/v1/core/activity/summary') {
        const principal = requireActivityPrincipal(request, store, activityAdminSecret);
        json(response, 200, store.activity.summary(principal));
        return;
      }
      if (request.method === 'GET' && url.pathname === '/v1/core/activity/changes') {
        const principal = requireActivityPrincipal(request, store, activityAdminSecret);
        const cursor = url.searchParams.get('cursor');
        const limitRaw = url.searchParams.get('limit') ?? '100';
        if (!/^\d+$/.test(limitRaw)) throw new CoreStoreError('invalid_request', 'limit must be a positive integer.');
        json(response, 200, store.activity.changes(principal, cursor, Number(limitRaw)));
        return;
      }
      if (request.method === 'GET' && url.pathname === '/v1/core/activity/snapshot') {
        const principal = requireActivityPrincipal(request, store, activityAdminSecret);
        json(response, 200, store.activity.snapshot(principal));
        return;
      }
      if (request.method === 'POST' && url.pathname === '/v1/core/activity/ack') {
        const principal = requireActivityPrincipal(request, store, activityAdminSecret);
        json(response, 200, store.activity.acknowledge(principal, await readJson(request, 4096)));
        return;
      }
      if (
        request.method === 'POST'
        && url.pathname.startsWith('/v1/core/activity/probes/')
        && url.pathname.endsWith('/revoke')
      ) {
        requireActivityOwner(request, store, activityAdminSecret);
        const probeId = pathIdentity(
          url.pathname.slice(0, -'/revoke'.length),
          '/v1/core/activity/probes/',
        );
        json(response, 200, store.activity.revokeProbe(probeId));
        return;
      }
      const deleteProbeId = request.method === 'DELETE'
        ? pathIdentity(url.pathname, '/v1/core/activity/probes/')
        : null;
      if (deleteProbeId) {
        requireActivityOwner(request, store, activityAdminSecret);
        json(response, 200, store.activity.deleteProbe(deleteProbeId));
        return;
      }
      const deleteDeviceId = request.method === 'DELETE'
        ? pathIdentity(url.pathname, '/v1/core/activity/devices/')
        : null;
      if (deleteDeviceId) {
        requireActivityOwner(request, store, activityAdminSecret);
        json(response, 200, store.activity.deleteDevice(deleteDeviceId));
        return;
      }
      if (request.method === 'POST' && url.pathname === '/v1/core/activity/admin/retention') {
        requireActivityOwner(request, store, activityAdminSecret);
        json(response, 200, store.activity.runRetention());
        return;
      }
      if (request.method === 'GET' && url.pathname === '/v1/core/activity/admin/export') {
        requireActivityOwner(request, store, activityAdminSecret);
        json(response, 200, store.activity.adminExport());
        return;
      }
      if (request.method === 'GET' && url.pathname === '/v1/core/activity/admin/audit') {
        requireActivityOwner(request, store, activityAdminSecret);
        json(response, 200, { audit: store.activity.audit() });
        return;
      }
      if (request.method === 'POST' && url.pathname === '/v1/core/devices/pair') {
        if (!pairingEndpointEnabled) {
          throw new CoreStoreError(
            'pairing_disabled',
            'Device pairing is disabled. Start a deliberate pairing window first.',
            { status: 403 },
          );
        }
        const body = await readJson(request);
        if (!equalSecret(body.pairing_code, activePairingCode)) {
          throw new CoreStoreError('invalid_pairing_code', 'The pairing code is invalid.', { status: 401 });
        }
        const paired = store.pairDevice(body, activePairingCode);
        activePairingCode = null;
        json(response, 200, paired);
        return;
      }
      if (request.method === 'POST' && url.pathname === '/v1/core/chat/messages') {
        const device = requireDevice(request, store);
        json(response, 200, store.submitMessages(device.device_id, await readJson(request)));
        return;
      }
      if (request.method === 'GET' && url.pathname === '/v1/core/changes') {
        requireFeedReader(request, store);
        const cursor = url.searchParams.get('cursor') ?? store.encodeCursor(0);
        const limitRaw = url.searchParams.get('limit') ?? '100';
        if (!/^\d+$/.test(limitRaw)) {
          throw new CoreStoreError('invalid_request', 'limit must be a positive integer.');
        }
        json(response, 200, store.getChanges(cursor, Number(limitRaw)));
        return;
      }
      if (request.method === 'POST' && url.pathname === '/v1/core/devices/ack') {
        const device = requireFeedReader(request, store);
        json(response, 200, store.acknowledgeCursor(device.device_id, await readJson(request)));
        return;
      }
      if (
        request.method === 'POST'
        && url.pathname === '/v1/core/actions/shortcut-email/manual-test'
      ) {
        const token = requireShortcutMailRelay(request, shortcutMailRelay);
        const workflow = shortcutMailTestBody(await readJson(request, 1024));
        const receipt = await shortcutMailRelay.send({
          workflow,
          token,
          idempotency_key: idempotencyKey(request),
        });
        json(response, 200, { receipt });
        return;
      }
      const shortcutReceiptPrefix =
        '/v1/core/actions/shortcut-email/manual-test/receipts/';
      if (
        request.method === 'GET'
        && url.pathname.startsWith(shortcutReceiptPrefix)
      ) {
        const token = requireShortcutMailRelay(request, shortcutMailRelay);
        const encodedKey = url.pathname.slice(shortcutReceiptPrefix.length);
        let key;
        try {
          key = decodeURIComponent(encodedKey);
        } catch (_) {
          throw new CoreStoreError(
            'invalid_request',
            'The receipt idempotency key is not valid URL encoding.',
          );
        }
        const receipt = await shortcutMailRelay.getReceipt({
          token,
          idempotency_key: key,
        });
        json(response, 200, { receipt });
        return;
      }
      if (url.pathname === '/v1/core/workers/leases') {
        requireWorker(request, workerSecret);
        if (request.method === 'GET') {
          json(response, 200, store.listWorkerLeases());
          return;
        }
        if (request.method === 'POST') {
          json(response, 200, store.acquireWorkerLease(await readJson(request)));
          return;
        }
      }
      if (request.method === 'POST' && url.pathname === '/v1/core/workers/leases/renew') {
        requireWorker(request, workerSecret);
        json(response, 200, store.renewWorkerLease(await readJson(request)));
        return;
      }
      if (request.method === 'POST' && url.pathname === '/v1/core/workers/leases/release') {
        requireWorker(request, workerSecret);
        json(response, 200, store.releaseWorkerLease(await readJson(request)));
        return;
      }
      if (request.method === 'POST' && url.pathname === '/v1/core/workers/chat/messages') {
        requireWorker(request, workerSecret);
        json(response, 200, store.publishCompanionMessages(await readJson(request)));
        return;
      }
      if (request.method === 'POST' && url.pathname === '/v1/core/workers/companion-replies/claim') {
        requireWorker(request, workerSecret);
        json(response, 200, store.claimCompanionReplyJob(await readJson(request)));
        return;
      }
      if (request.method === 'POST' && url.pathname === '/v1/core/workers/companion-replies/complete') {
        requireWorker(request, workerSecret);
        json(response, 200, store.completeCompanionReplyJob(await readJson(request)));
        return;
      }
      if (request.method === 'POST' && url.pathname === '/v1/core/workers/companion-replies/shadow-complete') {
        requireWorker(request, workerSecret);
        json(response, 200, store.completeCompanionReplyShadow(await readJson(request)));
        return;
      }
      throw new CoreStoreError('not_found', 'The requested core endpoint does not exist.', { status: 404 });
    } catch (error) {
      const known = error instanceof CoreStoreError
        ? error
        : error?.name === 'ActivityControlPlaneError'
          ? new CoreStoreError(error.code, error.message, {
              status: error.status,
              retryable: error.retryable,
              details: error.details,
            })
        : error instanceof ShortcutMailRelayError
          ? new CoreStoreError(error.code, error.message, {
              status: error.status,
              retryable: false,
              details: error.details,
            })
          : new CoreStoreError('core_error', error instanceof Error ? error.message : String(error), { status: 500 });
      json(response, known.status, errorBody(known));
    }
  }

  let server;
  try {
    server = certPath && keyPath
      ? https.createServer({
          cert: readFileSync(certPath),
          key: readFileSync(keyPath),
          minVersion: 'TLSv1.2',
        }, handle)
      : http.createServer(handle);
  } catch (error) {
    try {
      if (ownsShortcutMailRelay) shortcutMailRelay?.close();
    } catch {
      // Preserve the construction error while still releasing the Core store below.
    }
    try {
      store.close();
    } catch {
      // Preserve the construction error.
    }
    throw error;
  }
  let closed = false;
  let ownedRelayClosed = false;
  let activityRetentionTimer = null;
  let domainRetentionTimer = null;
  function closeOwnedRelay() {
    if (!ownsShortcutMailRelay || ownedRelayClosed) return;
    try {
      shortcutMailRelay?.close();
    } finally {
      ownedRelayClosed = true;
    }
  }
  async function closeResources() {
    let firstError = null;
    if (activityRetentionTimer !== null) {
      clearInterval(activityRetentionTimer);
      activityRetentionTimer = null;
    }
    if (domainRetentionTimer !== null) {
      clearInterval(domainRetentionTimer);
      domainRetentionTimer = null;
    }
    if (server.listening) {
      try {
        server.closeIdleConnections?.();
        await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
      } catch (error) {
        firstError ??= error;
      }
    }
    try {
      closeOwnedRelay();
    } catch (error) {
      firstError ??= error;
    }
    try {
      store.close();
    } catch (error) {
      firstError ??= error;
    }
    if (firstError) throw firstError;
  }
  async function closeAfterStartupFailure() {
    if (closed) return;
    closed = true;
    await closeResources();
  }
  if (store.domains) {
    domainRetentionTimer = setInterval(() => {
      if (closed) return;
      try {
        const result = store.domains.runRetention();
        store.domainRetentionError = result.status === 200 ? null : 'domain_retention_failed';
      } catch {
        store.domainRetentionError = 'domain_retention_failed';
      }
    }, activityRetentionIntervalMs);
    domainRetentionTimer.unref();
  }
  return {
    server,
    store,
    replacePairingCode(value) {
      if (typeof value !== 'string' || !value.trim()) {
        throw new Error('pairing code must be a non-empty string');
      }
      if (store.isPairingCodeConsumed(value)) {
        throw new Error('pairing code has already been consumed; generate a new code');
      }
      store.assertAuthoritySecretSeparation({
        activityAdminSecret,
        workerSecret,
        pairingCode: value,
        shortcutMailTokenHash: shortcutMailRelay?.tokenHash ?? null,
        now: clock(),
      });
      pairingEndpointEnabled = true;
      activePairingCode = value;
    },
    async listen({ host = '127.0.0.1', port = 47841 } = {}) {
      try {
        await new Promise((resolve, reject) => {
          const cleanup = () => {
            server.off('error', onError);
            server.off('listening', onListening);
          };
          const onError = (error) => {
            cleanup();
            reject(error);
          };
          const onListening = () => {
            cleanup();
            resolve();
          };
          server.once('error', onError);
          server.once('listening', onListening);
          server.listen(port, host);
        });
        if (activityAdminSecret) {
          store.activateActivity();
          activityRetentionTimer = setInterval(() => {
            try {
              store.activity.runRetention(clock());
            } catch {
              // Authority/schema failures are reflected by health and fail closed on data access.
            }
          }, activityRetentionIntervalMs);
          activityRetentionTimer.unref?.();
        }
        return server.address();
      } catch (error) {
        try {
          await closeAfterStartupFailure();
        } catch {
          // Preserve the listen/activation error after attempting every cleanup.
        }
        throw error;
      }
    },
    async close() {
      if (closed) return;
      closed = true;
      await closeResources();
    },
  };
}

export function isShortcutMailManualTestEnabled(environment = process.env) {
  return environment.I_CORE_SHORTCUT_MAIL_MANUAL_TEST_ENABLED === '1';
}

export function installICoreGracefulShutdown(core, {
  processObject = process,
  onError = (error) => console.error(`i core failed to stop cleanly: ${error.message}`),
} = {}) {
  let shutdownPromise = null;
  const removeHandlers = () => {
    processObject.off('SIGINT', onSignal);
    processObject.off('SIGTERM', onSignal);
  };
  const shutdown = () => {
    if (shutdownPromise) return shutdownPromise;
    shutdownPromise = (async () => {
      try {
        await core.close();
      } catch (error) {
        processObject.exitCode = 1;
        onError(error);
        throw error;
      } finally {
        removeHandlers();
      }
    })();
    return shutdownPromise;
  };
  const onSignal = () => {
    void shutdown().catch(() => {});
  };
  processObject.once('SIGINT', onSignal);
  processObject.once('SIGTERM', onSignal);
  return { shutdown, dispose: removeHandlers };
}

async function main() {
  const databasePath = process.env.I_CORE_DATABASE ?? path.join(moduleDir, '.state', 'i-core.sqlite');
  const pairingCode = process.env.I_CORE_PAIRING_CODE?.trim()
    ? process.env.I_CORE_PAIRING_CODE
    : null;
  const host = process.env.I_CORE_HOST ?? '127.0.0.1';
  const port = Number(process.env.I_CORE_PORT ?? 47841);
  const shortcutMailConfigPath = process.env.I_CORE_SHORTCUT_MAIL_CONFIG
    ?? path.join(moduleDir, '.state', 'shortcut-mail-relay.json');
  const shortcutMailDatabasePath = process.env.I_CORE_SHORTCUT_MAIL_DATABASE
    ?? path.join(moduleDir, '.state', 'shortcut-mail-journal.sqlite');
  let shortcutMailRelay = null;
  if (isShortcutMailManualTestEnabled() && existsSync(shortcutMailConfigPath)) {
    try {
      shortcutMailRelay = createConfiguredShortcutMailRelay({
        configPath: shortcutMailConfigPath,
        databasePath: shortcutMailDatabasePath,
      });
    } catch (error) {
      console.error(
        `Shortcut mail relay is disabled because its local configuration is invalid: ${error.message}`,
      );
    }
  }
  const core = createICoreServer({
    databasePath,
    pairingCode,
    certPath: process.env.I_CORE_CERT ?? null,
    keyPath: process.env.I_CORE_KEY ?? null,
    workerSecret: process.env.I_CORE_WORKER_SECRET ?? null,
    companionReplyJobsEnabled: process.env.I_CORE_COMPANION_REPLY_JOBS === '1',
    shortcutMailRelay,
    ownsShortcutMailRelay: Boolean(shortcutMailRelay),
    activityAdminSecret: process.env.I_CORE_ACTIVITY_ADMIN_SECRET ?? null,
  });
  const address = await core.listen({ host, port });
  installICoreGracefulShutdown(core);
  const protocol = process.env.I_CORE_CERT && process.env.I_CORE_KEY ? 'https' : 'http';
  console.log(`i core ${CORE_PROTOCOL_VERSION} listening on ${protocol}://${address.address}:${address.port}`);
  if (!pairingCode) {
    console.log('Device pairing is disabled. Existing paired devices can continue using their tokens.');
  }
  console.log(
    shortcutMailRelay
      ? 'Manual Shortcut mail test relay is enabled.'
      : 'Manual Shortcut mail test relay is disabled.',
  );
  if (protocol === 'http') {
    console.log('Keep this bound to loopback and expose it through Tailscale Serve for phone access.');
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(modulePath)) {
  main().catch((error) => {
    console.error(`i core failed to start: ${error.message}`);
    process.exitCode = 1;
  });
}
