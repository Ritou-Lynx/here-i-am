import { createHash, randomUUID, timingSafeEqual } from 'node:crypto';
import { mkdirSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';
import { DatabaseSync } from 'node:sqlite';

export const SHORTCUT_WORKFLOW = 'ios_shortcut_test_v0';
export const SHORTCUT_SUBJECT_CODE = 'sleep_chat_v0';
export const RELAY_STATUSES = Object.freeze([
  'reserved',
  'send_started',
  'provider_accepted',
  'failed_before_send',
  'outcome_unknown',
]);
export const DEFAULT_MIN_INTERVAL_MS = 5 * 60 * 1000;
export const DEFAULT_DAILY_LIMIT = 3;

const moduleDir = path.dirname(fileURLToPath(import.meta.url));
const REQUEST_FIELDS = new Set(['workflow', 'token', 'idempotency_key']);
const RECEIPT_FIELDS = new Set(['token', 'idempotency_key']);
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export class ShortcutMailRelayError extends Error {
  constructor(code, message, { status = 400, details = {} } = {}) {
    super(message);
    this.name = 'ShortcutMailRelayError';
    this.code = code;
    this.status = status;
    this.details = details;
  }
}

function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

function equalSecret(left, right) {
  if (typeof left !== 'string' || typeof right !== 'string') return false;
  const a = Buffer.from(left);
  const b = Buffer.from(right);
  return a.length === b.length && timingSafeEqual(a, b);
}

function requireNonEmptyString(value, field) {
  if (typeof value !== 'string' || !value.trim()) {
    throw new ShortcutMailRelayError('invalid_request', `${field} must be a non-empty string.`);
  }
  return value;
}

function utcDayKey(timeMs) {
  return new Date(timeMs).toISOString().slice(0, 10);
}

function responseFromRow(row, { replay = false } = {}) {
  return {
    workflow: row.workflow,
    subject_code: SHORTCUT_SUBJECT_CODE,
    idempotency_key: row.idempotency_key,
    status: row.status,
    receipt_id: row.receipt_id,
    receiver_hint: row.receiver_hint,
    requested_at: new Date(Number(row.created_at_ms)).toISOString(),
    updated_at: new Date(Number(row.updated_at_ms)).toISOString(),
    ...(row.provider_receipt_id ? { provider_receipt_id: row.provider_receipt_id } : {}),
    replay,
  };
}

/**
 * A deliberately narrow relay: the caller chooses neither addressing nor content.
 * The journal is separate from i-core and never stores the request token or mail body.
 */
export class ShortcutMailRelay {
  constructor({
    databasePath,
    tokenHash,
    tokenExpiresAtMs = null,
    receiverHint,
    dispatcher,
    now = () => Date.now(),
    minIntervalMs = DEFAULT_MIN_INTERVAL_MS,
    dailyLimit = DEFAULT_DAILY_LIMIT,
    logger = () => {},
  } = {}) {
    requireNonEmptyString(databasePath, 'databasePath');
    if (!/^[a-f0-9]{64}$/i.test(tokenHash ?? '')) {
      throw new Error('tokenHash must be a SHA-256 hexadecimal digest.');
    }
    if (
      tokenExpiresAtMs !== null
      && (!Number.isSafeInteger(tokenExpiresAtMs) || tokenExpiresAtMs < 1)
    ) {
      throw new Error('tokenExpiresAtMs must be a positive safe integer or null.');
    }
    requireNonEmptyString(receiverHint, 'receiverHint');
    if (typeof dispatcher !== 'function') throw new Error('dispatcher must be a function.');
    if (!Number.isSafeInteger(minIntervalMs) || minIntervalMs < 0) {
      throw new Error('minIntervalMs must be a non-negative integer.');
    }
    if (!Number.isSafeInteger(dailyLimit) || dailyLimit < 1) {
      throw new Error('dailyLimit must be a positive integer.');
    }
    mkdirSync(path.dirname(databasePath), { recursive: true });
    this.db = new DatabaseSync(databasePath);
    this.db.exec('PRAGMA journal_mode = WAL; PRAGMA busy_timeout = 5000;');
    this.tokenHash = tokenHash.toLowerCase();
    this.tokenExpiresAtMs = tokenExpiresAtMs;
    this.receiverHint = receiverHint;
    this.dispatcher = dispatcher;
    this.now = now;
    this.minIntervalMs = minIntervalMs;
    this.dailyLimit = dailyLimit;
    this.logger = logger;
    this.#migrate();
    this.#recoverInterruptedAttempts();
  }

  #migrate() {
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS shortcut_mail_journal (
        idempotency_key TEXT PRIMARY KEY,
        request_digest TEXT NOT NULL,
        token_scope_hash TEXT,
        workflow TEXT NOT NULL,
        receipt_id TEXT NOT NULL UNIQUE,
        receiver_hint TEXT NOT NULL,
        status TEXT NOT NULL CHECK(status IN (
          'reserved', 'send_started', 'provider_accepted',
          'failed_before_send', 'outcome_unknown'
        )),
        provider_receipt_id TEXT,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        send_started_at_ms INTEGER,
        terminal_at_ms INTEGER
      );
      CREATE INDEX IF NOT EXISTS shortcut_mail_journal_send_idx
        ON shortcut_mail_journal(send_started_at_ms);
    `);
    const columns = this.db.prepare('PRAGMA table_info(shortcut_mail_journal)').all();
    if (!columns.some((column) => column.name === 'token_scope_hash')) {
      this.db.exec('ALTER TABLE shortcut_mail_journal ADD COLUMN token_scope_hash TEXT;');
    }
  }

  #recoverInterruptedAttempts() {
    const recoveredAt = this.now();
    this.db.exec('BEGIN IMMEDIATE');
    try {
      this.db.prepare(`
        UPDATE shortcut_mail_journal
        SET status = 'failed_before_send', updated_at_ms = ?, terminal_at_ms = ?
        WHERE status = 'reserved'
      `).run(recoveredAt, recoveredAt);
      this.db.prepare(`
        UPDATE shortcut_mail_journal
        SET status = 'outcome_unknown', updated_at_ms = ?, terminal_at_ms = ?
        WHERE status = 'send_started'
      `).run(recoveredAt, recoveredAt);
      this.db.exec('COMMIT');
    } catch (error) {
      this.db.exec('ROLLBACK');
      throw error;
    }
  }

  #log(event, fields) {
    // Deliberately permit only identifiers, time and receiver hint. Never pass request/body/token.
    try {
      this.logger({ event, ...fields });
    } catch (_) {
      // Observability must not change the mail outcome or trigger a repeat attempt.
    }
  }

  #validateRequest(raw) {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
      throw new ShortcutMailRelayError('invalid_request', 'Request must be an object.');
    }
    for (const key of Object.keys(raw)) {
      if (!REQUEST_FIELDS.has(key)) {
        throw new ShortcutMailRelayError('fixed_template_only', `Request field ${key} is not allowed.`);
      }
    }
    const workflow = requireNonEmptyString(raw.workflow, 'workflow');
    if (workflow !== SHORTCUT_WORKFLOW) {
      throw new ShortcutMailRelayError('unsupported_workflow', 'Only ios_shortcut_test_v0 is enabled.', { status: 403 });
    }
    const token = requireNonEmptyString(raw.token, 'token');
    if (!equalSecret(sha256(token), this.tokenHash)) {
      throw new ShortcutMailRelayError('unauthorized', 'The scoped relay token is invalid.', { status: 401 });
    }
    if (this.tokenExpiresAtMs !== null && this.now() >= this.tokenExpiresAtMs) {
      throw new ShortcutMailRelayError('token_expired', 'The scoped relay token has expired.', {
        status: 401,
        details: { expired_at: new Date(this.tokenExpiresAtMs).toISOString() },
      });
    }
    const idempotencyKey = requireNonEmptyString(raw.idempotency_key, 'idempotency_key');
    if (!UUID_PATTERN.test(idempotencyKey)) {
      throw new ShortcutMailRelayError('invalid_request', 'idempotency_key must be a UUID.');
    }
    return { workflow, idempotencyKey, requestDigest: sha256(JSON.stringify({ workflow })) };
  }

  #authenticateReceiptQuery(raw) {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
      throw new ShortcutMailRelayError('invalid_request', 'Receipt query must be an object.');
    }
    for (const key of Object.keys(raw)) {
      if (!RECEIPT_FIELDS.has(key)) {
        throw new ShortcutMailRelayError('invalid_request', `Receipt query field ${key} is not allowed.`);
      }
    }
    const token = requireNonEmptyString(raw.token, 'token');
    if (!equalSecret(sha256(token), this.tokenHash)) {
      throw new ShortcutMailRelayError('unauthorized', 'The scoped relay token is invalid.', { status: 401 });
    }
    if (this.tokenExpiresAtMs !== null && this.now() >= this.tokenExpiresAtMs) {
      throw new ShortcutMailRelayError('token_expired', 'The scoped relay token has expired.', {
        status: 401,
        details: { expired_at: new Date(this.tokenExpiresAtMs).toISOString() },
      });
    }
    const idempotencyKey = requireNonEmptyString(raw.idempotency_key, 'idempotency_key');
    if (!UUID_PATTERN.test(idempotencyKey)) {
      throw new ShortcutMailRelayError('invalid_request', 'idempotency_key must be a UUID.');
    }
    return idempotencyKey;
  }

  #checkLimits(now) {
    const mostRecent = this.db.prepare(`
      SELECT send_started_at_ms FROM shortcut_mail_journal
      WHERE send_started_at_ms IS NOT NULL
      ORDER BY send_started_at_ms DESC LIMIT 1
    `).get();
    if (mostRecent && now - Number(mostRecent.send_started_at_ms) < this.minIntervalMs) {
      throw new ShortcutMailRelayError('rate_limited_interval', 'The relay may send once per five minutes.', {
        status: 429,
        details: { retry_at_ms: Number(mostRecent.send_started_at_ms) + this.minIntervalMs },
      });
    }
    const dayStart = Date.parse(`${utcDayKey(now)}T00:00:00.000Z`);
    const dayEnd = dayStart + 24 * 60 * 60 * 1000;
    const daily = this.db.prepare(`
      SELECT COUNT(*) AS value FROM shortcut_mail_journal
      WHERE send_started_at_ms >= ? AND send_started_at_ms < ?
    `).get(dayStart, dayEnd);
    if (Number(daily.value) >= this.dailyLimit) {
      throw new ShortcutMailRelayError('rate_limited_daily', 'The relay daily limit has been reached.', {
        status: 429,
        details: { reset_at_ms: dayEnd },
      });
    }
  }

  #row(key) {
    return this.db.prepare('SELECT * FROM shortcut_mail_journal WHERE idempotency_key = ?').get(key);
  }

  #checkTokenUnused() {
    const consumed = this.db.prepare(`
      SELECT 1 AS value FROM shortcut_mail_journal
      WHERE token_scope_hash = ? LIMIT 1
    `).get(this.tokenHash);
    if (consumed) {
      throw new ShortcutMailRelayError(
        'token_consumed',
        'This scoped token has already been used for its one permitted test send.',
        { status: 409 },
      );
    }
  }

  async send(raw) {
    const { workflow, idempotencyKey, requestDigest } = this.#validateRequest(raw);
    const now = this.now();
    let row;
    this.db.exec('BEGIN IMMEDIATE');
    try {
      row = this.#row(idempotencyKey);
      if (row) {
        if (row.token_scope_hash !== this.tokenHash) {
          throw new ShortcutMailRelayError(
            'receipt_not_found',
            'No relay receipt exists for this idempotency key.',
            { status: 404 },
          );
        }
        if (row.request_digest !== requestDigest) {
          throw new ShortcutMailRelayError('idempotency_conflict', 'idempotency_key is already bound to another request.', { status: 409 });
        }
        this.db.exec('COMMIT');
        this.#log('shortcut_mail_replay', {
          receipt_id: row.receipt_id, receiver_hint: row.receiver_hint, time_ms: now, status: row.status,
        });
        return responseFromRow(row, { replay: true });
      }
      this.#checkTokenUnused();
      this.#checkLimits(now);
      row = {
        idempotency_key: idempotencyKey,
        request_digest: requestDigest,
        token_scope_hash: this.tokenHash,
        workflow,
        receipt_id: randomUUID(),
        receiver_hint: this.receiverHint,
        status: 'send_started',
        created_at_ms: now,
        updated_at_ms: now,
        send_started_at_ms: now,
      };
      this.db.prepare(`
        INSERT INTO shortcut_mail_journal(
          idempotency_key, request_digest, token_scope_hash, workflow, receipt_id, receiver_hint,
          status, created_at_ms, updated_at_ms, send_started_at_ms
        ) VALUES (?, ?, ?, ?, ?, ?, 'send_started', ?, ?, ?)
      `).run(
        row.idempotency_key, row.request_digest, row.token_scope_hash,
        row.workflow, row.receipt_id,
        row.receiver_hint, row.created_at_ms, row.updated_at_ms,
        row.send_started_at_ms,
      );
      this.db.exec('COMMIT');
    } catch (error) {
      this.db.exec('ROLLBACK');
      throw error;
    }

    try {
      const dispatched = await this.dispatcher({
        workflow, receiptId: row.receipt_id, requestedAtMs: row.created_at_ms,
      });
      if (!dispatched || dispatched.accepted !== true) {
        throw new Error('Dispatcher did not confirm provider acceptance.');
      }
      const acceptedAt = this.now();
      const providerReceiptId = typeof dispatched.providerReceiptId === 'string'
        ? dispatched.providerReceiptId.slice(0, 200)
        : null;
      this.db.prepare(`
        UPDATE shortcut_mail_journal
        SET status = 'provider_accepted', provider_receipt_id = ?, updated_at_ms = ?, terminal_at_ms = ?
        WHERE idempotency_key = ? AND status = 'send_started'
      `).run(providerReceiptId, acceptedAt, acceptedAt, idempotencyKey);
      const accepted = this.#row(idempotencyKey);
      this.#log('shortcut_mail_provider_accepted', {
        receipt_id: accepted.receipt_id, receiver_hint: accepted.receiver_hint, time_ms: acceptedAt,
      });
      return responseFromRow(accepted);
    } catch (_) {
      // The dispatcher was entered only after durable send_started. Delivery is unknowable.
      const unknownAt = this.now();
      this.db.prepare(`
        UPDATE shortcut_mail_journal
        SET status = 'outcome_unknown', updated_at_ms = ?, terminal_at_ms = ?
        WHERE idempotency_key = ? AND status = 'send_started'
      `).run(unknownAt, unknownAt, idempotencyKey);
      const unknown = this.#row(idempotencyKey);
      this.#log('shortcut_mail_outcome_unknown', {
        receipt_id: unknown.receipt_id, receiver_hint: unknown.receiver_hint, time_ms: unknownAt,
      });
      return responseFromRow(unknown);
    }
  }

  getReceipt(raw) {
    const idempotencyKey = this.#authenticateReceiptQuery(raw);
    const row = this.#row(idempotencyKey);
    if (!row || row.token_scope_hash !== this.tokenHash) {
      throw new ShortcutMailRelayError('receipt_not_found', 'No relay receipt exists for this idempotency key.', { status: 404 });
    }
    const now = this.now();
    this.#log('shortcut_mail_receipt_read', {
      receipt_id: row.receipt_id, receiver_hint: row.receiver_hint, time_ms: now, status: row.status,
    });
    return responseFromRow(row);
  }

  close() {
    this.db.close();
  }
}

export function createPowerShellSmtpDispatcher({
  configPath,
  powerShellPath = 'powershell.exe',
  timeoutMs = 45_000,
  maxOutputBytes = 4096,
} = {}) {
  requireNonEmptyString(configPath, 'configPath');
  if (!Number.isSafeInteger(timeoutMs) || timeoutMs < 1) throw new Error('timeoutMs must be a positive integer.');
  if (!Number.isSafeInteger(maxOutputBytes) || maxOutputBytes < 1) throw new Error('maxOutputBytes must be a positive integer.');
  return async ({ receiptId, requestedAtMs }) => new Promise((resolve, reject) => {
    const child = spawn(powerShellPath, [
      '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
      '-File', path.join(moduleDir, 'send_shortcut_mail.ps1'),
      '-ConfigPath', configPath,
      '-ReceiptId', receiptId,
      '-RequestedAtMs', String(requestedAtMs),
    ], { shell: false, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    let stdout = Buffer.alloc(0);
    let stderr = Buffer.alloc(0);
    let settled = false;
    const timer = setTimeout(() => {
      child.kill();
      finish(reject, new Error('PowerShell SMTP dispatcher timed out.'));
    }, timeoutMs);
    const finish = (callback, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      callback(value);
    };
    const appendOutput = (current, chunk) => {
      const next = Buffer.concat([current, chunk]);
      if (next.length > maxOutputBytes) {
        child.kill();
        finish(reject, new Error('PowerShell SMTP dispatcher exceeded output limit.'));
        return null;
      }
      return next;
    };
    child.stdout.on('data', (chunk) => { if (!settled) stdout = appendOutput(stdout, chunk) ?? stdout; });
    child.stderr.on('data', (chunk) => { if (!settled) stderr = appendOutput(stderr, chunk) ?? stderr; });
    child.once('error', (error) => finish(reject, error));
    child.once('close', (code) => {
      if (settled) return;
      if (code !== 0) {
        finish(reject, new Error(`PowerShell SMTP dispatcher exited with ${code}.`));
        return;
      }
      try {
        const result = JSON.parse(stdout.toString('utf8'));
        if (result?.accepted !== true) throw new Error('PowerShell dispatcher did not accept mail.');
        finish(resolve, result.provider_receipt_id
          ? { accepted: true, providerReceiptId: result.provider_receipt_id }
          : { accepted: true });
      } catch (error) {
        finish(reject, error);
      }
    });
  });
}

export function loadShortcutMailRelayConfig(configPath) {
  const config = JSON.parse(readFileSync(configPath, 'utf8'));
  if (
    config?.workflow !== SHORTCUT_WORKFLOW
    || !/^[a-f0-9]{64}$/i.test(config?.token_hash ?? '')
    || !Number.isSafeInteger(config?.token_expires_at_ms)
    || config.token_expires_at_ms < 1
    || config?.smtp?.use_ssl !== true
  ) {
    throw new Error('Shortcut mail relay configuration is invalid.');
  }
  return config;
}

export function createConfiguredShortcutMailRelay({ configPath, databasePath, ...options } = {}) {
  const config = loadShortcutMailRelayConfig(configPath);
  return new ShortcutMailRelay({
    databasePath,
    tokenHash: config.token_hash,
    tokenExpiresAtMs: config.token_expires_at_ms,
    receiverHint: config.receiver_hint,
    dispatcher: createPowerShellSmtpDispatcher({ configPath }),
    ...options,
  });
}
