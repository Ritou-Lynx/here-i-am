import { timingSafeEqual } from 'node:crypto';
import { readFileSync } from 'node:fs';
import http from 'node:http';
import https from 'node:https';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  CORE_PROTOCOL_VERSION,
  CoreStoreError,
  ICoreStore,
} from './i_core_store.mjs';

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

function requireDevice(request, store) {
  requireProtocol(request);
  const device = store.authenticate(bearerToken(request));
  if (!device) {
    throw new CoreStoreError('unauthorized', 'A valid device token is required.', { status: 401 });
  }
  return device;
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

export function createICoreServer({
  databasePath,
  pairingCode,
  certPath = null,
  keyPath = null,
  workerSecret = null,
  companionReplyJobsEnabled = false,
} = {}) {
  if (!databasePath) throw new Error('databasePath is required');
  if (!pairingCode) throw new Error('pairingCode is required');
  const store = new ICoreStore(databasePath, { companionReplyJobsEnabled });
  let activePairingCode = store.isPairingCodeConsumed(pairingCode)
    ? null
    : pairingCode;

  async function handle(request, response) {
    try {
      const url = new URL(request.url, 'http://core.local');
      if (request.method === 'GET' && url.pathname === '/v1/core/health') {
        json(response, 200, store.health({ workerLeasesEnabled: Boolean(workerSecret) }));
        return;
      }
      if (request.method === 'POST' && url.pathname === '/v1/core/devices/pair') {
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
        requireDevice(request, store);
        const cursor = url.searchParams.get('cursor') ?? store.encodeCursor(0);
        const limitRaw = url.searchParams.get('limit') ?? '100';
        if (!/^\d+$/.test(limitRaw)) {
          throw new CoreStoreError('invalid_request', 'limit must be a positive integer.');
        }
        json(response, 200, store.getChanges(cursor, Number(limitRaw)));
        return;
      }
      if (request.method === 'POST' && url.pathname === '/v1/core/devices/ack') {
        const device = requireDevice(request, store);
        json(response, 200, store.acknowledgeCursor(device.device_id, await readJson(request)));
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
        : new CoreStoreError('core_error', error instanceof Error ? error.message : String(error), { status: 500 });
      json(response, known.status, errorBody(known));
    }
  }

  const server = certPath && keyPath
    ? https.createServer({
        cert: readFileSync(certPath),
        key: readFileSync(keyPath),
        minVersion: 'TLSv1.2',
      }, handle)
    : http.createServer(handle);
  let closed = false;
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
      activePairingCode = value;
    },
    async listen({ host = '127.0.0.1', port = 47841 } = {}) {
      await new Promise((resolve, reject) => {
        server.once('error', reject);
        server.listen(port, host, resolve);
      });
      return server.address();
    },
    async close() {
      if (closed) return;
      closed = true;
      if (server.listening) {
        server.closeIdleConnections?.();
        await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
      }
      store.close();
    },
  };
}

async function main() {
  const databasePath = process.env.I_CORE_DATABASE ?? path.join(moduleDir, '.state', 'i-core.sqlite');
  const pairingCode = process.env.I_CORE_PAIRING_CODE;
  if (!pairingCode) {
    throw new Error('I_CORE_PAIRING_CODE is required. Choose a temporary code before starting the core.');
  }
  const host = process.env.I_CORE_HOST ?? '127.0.0.1';
  const port = Number(process.env.I_CORE_PORT ?? 47841);
  const core = createICoreServer({
    databasePath,
    pairingCode,
    certPath: process.env.I_CORE_CERT ?? null,
    keyPath: process.env.I_CORE_KEY ?? null,
    workerSecret: process.env.I_CORE_WORKER_SECRET ?? null,
    companionReplyJobsEnabled: process.env.I_CORE_COMPANION_REPLY_JOBS === '1',
  });
  const address = await core.listen({ host, port });
  const protocol = process.env.I_CORE_CERT && process.env.I_CORE_KEY ? 'https' : 'http';
  console.log(`i core ${CORE_PROTOCOL_VERSION} listening on ${protocol}://${address.address}:${address.port}`);
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
