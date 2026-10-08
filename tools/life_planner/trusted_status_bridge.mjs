// Inert transfer library for a plan_items/status intent already approved by a
// trusted local UI. It does not watch inboxes, sign actions, mint grants, read
// credentials, or turn capture authority into plan authority.
import { createHash, randomBytes } from 'node:crypto';
import { link, mkdir, open, readFile, unlink } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { canonicalJSON, DOMAIN_POLICY } from '../i_core/domain_store.mjs';

const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const idPattern = /^[a-zA-Z0-9][a-zA-Z0-9_.:-]{0,199}$/;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const uiRefPattern = /^uia1\.[A-Za-z0-9_-]{1,40}\.[A-Za-z0-9_-]{43}$/;
const timePattern = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;
const bindingFields = ['core_instance_id', 'principal_id', 'credential_generation', 'installation_id'];
const sourceFields = ['capture_id', 'capture_revision'];
const intentFields = ['domain_protocol_version', 'core_instance_id', 'schema_version', 'op_id', 'id', 'kind',
  'base_revision', 'created_at', 'expires_at', 'actor', 'authorization_ref', 'patch'];
const envelopeFields = ['schema_version', 'transfer_id', 'source', 'binding', 'intent'];
const receiptFields = ['receipt_id', 'core_instance_id', 'authority_mode', 'epoch', 'domain', 'accepted_op_id',
  'principal_id', 'accepted_at', 'policy_version', 'targets', 'change_sequences', 'receipt_auth'];
const ledgerPreparedFields = ['schema_version', 'op_id', 'envelope_digest', 'capture_id', 'capture_revision'];
const ledgerReceiptFields = ['schema_version', 'op_id', 'envelope_digest', 'outcome', 'receipt'];
const transportBrand = Symbol('trusted-plan-core-transport');

export class TrustedStatusBridgeError extends Error {
  constructor(code, {retryable = false} = {}) {
    super(code);
    this.name = 'TrustedStatusBridgeError';
    this.code = code;
    this.retryable = retryable;
  }
}

const fail = (code, options) => { throw new TrustedStatusBridgeError(code, options); };
const exact = (value, fields) => object(value) && Object.keys(value).length === fields.length
  && fields.every(field => Object.hasOwn(value, field));
const id = value => typeof value === 'string' && idPattern.test(value);
const timestamp = value => typeof value === 'string' && timePattern.test(value) && Number.isFinite(Date.parse(value));
const digest = value => createHash('sha256').update(canonicalJSON(value), 'utf8').digest('hex');

function validateBinding(binding) {
  if (!exact(binding, bindingFields) || !id(binding.core_instance_id) || !id(binding.principal_id)
    || !id(binding.installation_id) || !Number.isSafeInteger(binding.credential_generation)
    || binding.credential_generation < 1) fail('invalid_transfer_binding');
}

function validateIntent(intent) {
  if (!exact(intent, intentFields) || intent.domain_protocol_version !== 1 || intent.schema_version !== 1
    || !uuidPattern.test(intent.op_id ?? '') || !id(intent.id) || intent.kind !== 'status'
    || intent.actor !== 'user_direct' || !Number.isSafeInteger(intent.base_revision) || intent.base_revision < 1
    || !timestamp(intent.created_at) || !timestamp(intent.expires_at) || !uiRefPattern.test(intent.authorization_ref ?? '')
    || !exact(intent.patch, ['status']) || !['完成', '放弃'].includes(intent.patch.status)) {
    fail('invalid_plan_status_intent');
  }
  const created = Date.parse(intent.created_at), expires = Date.parse(intent.expires_at);
  if (expires <= created || expires - created > DOMAIN_POLICY.intentTtl) fail('invalid_intent_window');
}

function validateEnvelope(raw, expectedBinding) {
  if (!exact(raw, envelopeFields) || raw.schema_version !== 1 || !exact(raw.source, sourceFields)
    || !id(raw.source.capture_id) || !Number.isSafeInteger(raw.source.capture_revision)
    || raw.source.capture_revision < 1 || !object(raw.intent) || raw.transfer_id !== raw.intent.op_id) {
    fail('invalid_status_transfer');
  }
  validateBinding(raw.binding);
  validateBinding(expectedBinding);
  validateIntent(raw.intent);
  if (canonicalJSON(raw.binding) !== canonicalJSON(expectedBinding)
    || raw.intent.core_instance_id !== expectedBinding.core_instance_id) fail('transfer_binding_changed');
  return structuredClone(raw);
}

function deepFreeze(value) {
  if (!object(value) && !Array.isArray(value)) return value;
  for (const child of Object.values(value)) deepFreeze(child);
  return Object.freeze(value);
}

function publicReceipt(receipt) {
  return structuredClone(receipt);
}

function validateCoreResult(raw, envelope) {
  const result = raw?.body?.found === true ? raw.body.result : raw?.body;
  if (!object(result) || result.domain_protocol_version !== 1 || result.domain !== 'plan_items'
    || result.op_id !== envelope.intent.op_id || !['accepted', 'duplicate'].includes(result.outcome)
    || !exact(result.receipt, receiptFields)) fail('invalid_core_status_result');
  const receipt = result.receipt;
  if (!id(receipt.receipt_id) || receipt.core_instance_id !== envelope.binding.core_instance_id
    || receipt.authority_mode !== 'single_host' || receipt.epoch !== null || receipt.domain !== 'plan_items'
    || receipt.accepted_op_id !== envelope.intent.op_id || receipt.principal_id !== envelope.binding.principal_id
    || !timestamp(receipt.accepted_at) || !id(receipt.policy_version) || !/^[a-f0-9]{64}$/.test(receipt.receipt_auth ?? '')
    || !Array.isArray(receipt.change_sequences) || receipt.change_sequences.some(value=>!Number.isSafeInteger(value)||value<1)
    || receipt.targets?.length !== 1 || !exact(receipt.targets[0],['id','revision'])
    || receipt.targets[0].id !== envelope.intent.id
    || !Number.isSafeInteger(receipt.targets[0]?.revision)
    || receipt.targets[0].revision !== envelope.intent.base_revision + 1) fail('invalid_core_status_receipt');
  return {outcome: result.outcome, receipt: publicReceipt(receipt)};
}

function validateCapture(record, envelope) {
  if (!object(record) || record.id !== envelope.source.capture_id
    || record.revision !== envelope.source.capture_revision || record.core_instance_id !== envelope.binding.core_instance_id
    || record.deleted_at !== null) fail('source_capture_changed');
}

// Only application composition code may construct this adapter. Envelope data
// never selects a URL, token, callback, or principal.
export function createTrustedPlanCoreTransport({getCapture, getOperation, submitOperation}) {
  if (![getCapture, getOperation, submitOperation].every(fn => typeof fn === 'function')) {
    throw new Error('invalid_trusted_core_transport');
  }
  return Object.freeze({[transportBrand]: true, getCapture, getOperation, submitOperation});
}

async function writeExclusive(path, value) {
  const payload = canonicalJSON(value);
  // Publish only a closed, synced file. link(2) is the exclusive atomic claim:
  // a competing writer sees EEXIST only after the winner is fully readable.
  // Unsupported link semantics fail closed; never fall back to overwrite/rename.
  const temporaryPath = `${path}.tmp-${process.pid}-${randomBytes(16).toString('hex')}`;
  let handle, temporaryCreated = false;
  try {
    handle = await open(temporaryPath, 'wx', 0o600);
    temporaryCreated = true;
    await handle.writeFile(payload, 'utf8');
    await handle.sync();
    await handle.close();
    handle = null;
    try {
      await link(temporaryPath, path);
      return true;
    } catch (error) {
      if (error?.code === 'EEXIST') return false;
      throw error;
    }
  } finally {
    try { await handle?.close(); }
    finally {
      if (temporaryCreated) {
        try { await unlink(temporaryPath); }
        catch (error) { if (error?.code !== 'ENOENT') throw error; }
      }
    }
  }
}

async function readExact(path, fields, missing = null) {
  let raw;
  try { raw = await readFile(path, 'utf8'); }
  catch (error) { if (error?.code === 'ENOENT') return missing; throw error; }
  let value;
  try { value = JSON.parse(raw); } catch { fail('transfer_ledger_invalid'); }
  if (!exact(value, fields)) fail('transfer_ledger_invalid');
  return value;
}

// Two immutable, atomically published files avoid an unlocked cross-process
// read/modify/write cycle. Existing partial/corrupt files remain fail-closed;
// abandoned random temp files are not scanned or removed automatically.
export class FileTrustedTransferLedger {
  constructor(directory) {
    if (typeof directory !== 'string' || !directory) throw new Error('invalid_transfer_ledger');
    this.directory = resolve(directory);
  }
  _path(opId, suffix) { return join(this.directory, `${opId}.${suffix}.json`); }
  async prepare(envelope, envelopeDigest) {
    await mkdir(this.directory, {recursive: true});
    const value = {schema_version: 1, op_id: envelope.intent.op_id, envelope_digest: envelopeDigest,
      capture_id: envelope.source.capture_id, capture_revision: envelope.source.capture_revision};
    const path = this._path(envelope.intent.op_id, 'prepared');
    if (!await writeExclusive(path, value)) {
      const existing = await readExact(path, ledgerPreparedFields);
      if (canonicalJSON(existing) !== canonicalJSON(value)) fail('transfer_idempotency_conflict');
    }
    return this.receipt(envelope.intent.op_id, envelopeDigest);
  }
  async receipt(opId, envelopeDigest) {
    const value = await readExact(this._path(opId, 'receipt'), ledgerReceiptFields);
    if (value && (value.schema_version !== 1 || value.op_id !== opId || value.envelope_digest !== envelopeDigest
      || value.outcome !== 'accepted' || !object(value.receipt))) fail('transfer_idempotency_conflict');
    return value;
  }
  async complete(envelope, envelopeDigest, result) {
    const value = {schema_version: 1, op_id: envelope.intent.op_id, envelope_digest: envelopeDigest,
      // accepted and the same-op duplicate carry the same acceptance receipt.
      // Normalize the transport outcome so concurrent exact retries write one
      // immutable ledger value instead of racing accepted vs duplicate labels.
      outcome: 'accepted', receipt: result.receipt};
    const path = this._path(envelope.intent.op_id, 'receipt');
    if (!await writeExclusive(path, value)) {
      const existing = await readExact(path, ledgerReceiptFields);
      if (canonicalJSON(existing) !== canonicalJSON(value)) fail('transfer_receipt_conflict');
    }
    return value;
  }
}

export function pendingDecisionForUnsignedStatus({itemId = null} = {}) {
  if (!(itemId === null || id(itemId))) throw new Error('invalid_pending_item');
  return {item_id: itemId, reason: '缺少受信计划状态授权', suggestion: '请在受信手机界面确认“完成”或“放弃”；确认前保持原状态。'};
}

export class TrustedPlanStatusBridge {
  constructor({binding, transport, ledger, clock = Date.now}) {
    validateBinding(binding);
    if (transport?.[transportBrand] !== true) throw new Error('untrusted_core_transport');
    if (!ledger || typeof ledger.prepare !== 'function' || typeof ledger.complete !== 'function') {
      throw new Error('invalid_transfer_ledger');
    }
    if (typeof clock !== 'function') throw new Error('invalid_bridge_clock');
    this.binding = structuredClone(binding);
    this.transport = transport;
    this.ledger = ledger;
    this.clock = clock;
  }

  async apply(raw) {
    const envelope = validateEnvelope(raw, this.binding);
    const envelopeDigest = digest(envelope);
    let capture;
    try { capture = await this.transport.getCapture(envelope.source.capture_id); }
    catch { fail('source_capture_unknown', {retryable: true}); }
    validateCapture(capture, envelope);

    const expires = Date.parse(envelope.intent.expires_at);
    const created = Date.parse(envelope.intent.created_at);
    const now = this.clock();
    if (!Number.isFinite(now) || now < created) fail('intent_not_active');

    const completed = await this.ledger.prepare(envelope, envelopeDigest);

    let lookup;
    try { lookup = await this.transport.getOperation(envelope.intent.op_id); }
    catch { fail('core_lookup_unknown', {retryable: true}); }
    if (lookup?.state === 'found') {
      const result = validateCoreResult(lookup.response, envelope);
      if (completed && (completed.outcome !== 'accepted'
        || canonicalJSON(completed.receipt) !== canonicalJSON(result.receipt))) fail('transfer_receipt_conflict');
      await this.ledger.complete(envelope, envelopeDigest, result);
      return {status: 'complete', recovered: true, ...result};
    }
    if (lookup?.state !== 'not_found') fail('invalid_core_lookup');
    if (completed) fail('core_receipt_missing', {retryable: true});
    const submitNow=this.clock();
    if (!Number.isFinite(submitNow) || submitNow < created) fail('bridge_clock_invalid');
    if (submitNow >= expires) fail('intent_expired');

    const intent = deepFreeze(structuredClone(envelope.intent));
    let submitted;
    try { submitted = await this.transport.submitOperation(intent); }
    catch { fail('core_submit_unknown', {retryable: true}); }
    const result = validateCoreResult(submitted, envelope);
    await this.ledger.complete(envelope, envelopeDigest, result);
    return {status: 'complete', recovered: false, ...result};
  }
}
