// Explicit trusted-UI signing boundary. This module creates no listener, keys,
// principal, or grant. OAuth, a chat message, and model output cannot approve.
import { createHash, createPrivateKey, createPublicKey, KeyObject, sign, verify } from 'node:crypto';
import { canonicalJSON } from './domain_store.mjs';

const object = v => v !== null && typeof v === 'object' && !Array.isArray(v);
const id = v => typeof v === 'string' && /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,199}$/.test(v);
const keyId = v => typeof v === 'string' && /^[A-Za-z0-9_-]{1,40}$/.test(v);
const digest = v => createHash('sha256').update(canonicalJSON(v)).digest('hex');
const exact = (v, fields) => object(v) && Object.keys(v).sort().join('|') === [...fields].sort().join('|');
const MAX_VALIDITY_MS = 5 * 60 * 1000;
const fields = ['protocol', 'key_id', 'domain', 'binding', 'request_digest', 'issued_at', 'expires_at'];

function permitted(domain, request) {
  if (domain !== 'captures' || !object(request) || request.actor !== 'user_via_agent') return false;
  if (request.kind === 'create') return request.data?.source === 'claude_web'
    && request.provenance?.source === 'claude_web';
  if (request.kind === 'patch') return exact(request.patch, ['text']) && typeof request.patch.text === 'string';
  return request.kind === 'delete';
}
function bindingValid(b) {
  return exact(b, ['core_instance_id', 'principal_id', 'credential_generation', 'installation_id'])
    && id(b.core_instance_id) && id(b.principal_id) && id(b.installation_id)
    && Number.isSafeInteger(b.credential_generation) && b.credential_generation > 0;
}
function unsigned(request) {
  const { authorization_ref: ignored, ...intent } = request;
  return intent;
}
function validChallenge(c) {
  return exact(c, fields) && c.protocol === 'i-web-action-v1' && keyId(c.key_id)
    && c.domain === 'captures' && bindingValid(c.binding) && /^[a-f0-9]{64}$/.test(c.request_digest)
    && Number.isSafeInteger(c.issued_at) && Number.isSafeInteger(c.expires_at)
    && c.expires_at > c.issued_at && c.expires_at - c.issued_at <= MAX_VALIDITY_MS;
}

function publicVerificationKey(value) {
  if (value instanceof KeyObject) {
    if (value.type !== 'public') throw new Error('invalid_web_verification_key');
    return value;
  }
  // Accept only an explicit SPKI public PEM. createPublicKey by itself also
  // accepts private keys, which would silently defeat the deployment boundary.
  const pem = typeof value === 'string' ? value.trim() : Buffer.isBuffer(value) ? value.toString('utf8').trim() : '';
  if (!/^-----BEGIN PUBLIC KEY-----\r?\n(?:[A-Za-z0-9+/=]+\r?\n)+-----END PUBLIC KEY-----$/.test(pem)) {
    throw new Error('invalid_web_verification_key');
  }
  return createPublicKey({key:pem, format:'pem', type:'spki'});
}

// Public proposal: safe to construct in an untrusted caller. It is NOT authority.
// The trusted surface must render the exact full request and current binding
// before signing; changing anything requires a new review and a new signature.
export function createWebActionChallenge({domain, binding, request, keyId: signerId, now = Date.now(), validityMs = MAX_VALIDITY_MS}) {
  if (!permitted(domain, request) || !bindingValid(binding) || !keyId(signerId)
    || request.core_instance_id !== binding.core_instance_id
    || !Number.isSafeInteger(now) || !Number.isSafeInteger(validityMs) || validityMs < 1 || validityMs > MAX_VALIDITY_MS
    || !Number.isFinite(Date.parse(request.expires_at)) || Date.parse(request.expires_at) <= now) {
    throw new Error('invalid_web_action');
  }
  return {protocol:'i-web-action-v1', key_id:signerId, domain, binding:structuredClone(binding),
    request_digest:digest(unsigned(request)), issued_at:now,
    expires_at:Math.min(now + validityMs, Date.parse(request.expires_at))};
}

// LOCAL TRUSTED UI ONLY. Never expose this function/private key as an MCP tool,
// generic HTTP endpoint, model command, or function authorized by an OAuth token.
export function approveWebActionChallenge({challenge, domain, binding, request, privateKey, now = Date.now()}) {
  if (!validChallenge(challenge) || !Number.isSafeInteger(now) || now < challenge.issued_at || now >= challenge.expires_at
    || canonicalJSON(createWebActionChallenge({domain, binding, request, keyId:challenge.key_id,
      now:challenge.issued_at, validityMs:challenge.expires_at - challenge.issued_at})) !== canonicalJSON(challenge)) {
    throw new Error('invalid_web_action');
  }
  let key;
  try { key = privateKey?.type === 'private' ? privateKey : createPrivateKey(privateKey); }
  catch { throw new Error('invalid_web_signing_key'); }
  if (key.asymmetricKeyType !== 'ed25519') throw new Error('invalid_web_signing_key');
  const payload = Buffer.from(canonicalJSON(challenge));
  return 'wua1.' + payload.toString('base64url') + '.' + sign(null, payload, key).toString('base64url');
}

// getTrustedKeys reads owner-controlled CURRENT configuration every time.
// Each entry: {key_id, public_key, binding, kinds}. public_key is a public
// KeyObject or SPKI public PEM string/Buffer. Private key input is rejected.
// Removing a key or changing generation/install revokes unexecuted approvals.
// DomainStore owns durable op-id deduplication; no second approval ledger/DB.
export function createTrustedWebAuthorizationVerifier({coreInstanceId, getTrustedKeys = () => [], now = Date.now}) {
  if (!id(coreInstanceId) || typeof getTrustedKeys !== 'function' || typeof now !== 'function') {
    throw new Error('invalid_web_authority_configuration');
  }
  return ({principal, request, domain, authorizationRef}) => {
    try {
      if (!permitted(domain, request) || request.core_instance_id !== coreInstanceId
        || !principal?.actors?.includes('user_via_agent') || typeof authorizationRef !== 'string'
        || authorizationRef.length > 4096 || request.authorization_ref !== authorizationRef) return false;
      const match = /^wua1\.([A-Za-z0-9_-]+)\.([A-Za-z0-9_-]{86})$/.exec(authorizationRef);
      if (!match) return false;
      const payload = Buffer.from(match[1], 'base64url'), signature = Buffer.from(match[2], 'base64url');
      if (payload.toString('base64url') !== match[1] || signature.toString('base64url') !== match[2]) return false;
      const c = JSON.parse(payload.toString('utf8'));
      const current = now();
      if (!validChallenge(c) || !Number.isSafeInteger(current) || current < c.issued_at || current >= c.expires_at
        || payload.toString('utf8') !== canonicalJSON(c) || c.domain !== domain
        || c.request_digest !== digest(unsigned(request))) return false;
      const binding = {core_instance_id:coreInstanceId, principal_id:principal.principal_id,
        credential_generation:principal.generation, installation_id:principal.installation_id};
      if (canonicalJSON(binding) !== canonicalJSON(c.binding)) return false;
      const keys = getTrustedKeys();
      if (keys && typeof keys.then === 'function') {
        Promise.resolve(keys).catch(() => {});
        return false;
      }
      if (!Array.isArray(keys) || keys.length > 32) return false;
      const matches = keys.filter(k => k?.key_id === c.key_id);
      if (matches.length !== 1) return false;
      const grant = matches[0];
      if (!exact(grant, ['key_id', 'public_key', 'binding', 'kinds']) || !bindingValid(grant.binding)
        || canonicalJSON(grant.binding) !== canonicalJSON(binding) || !Array.isArray(grant.kinds)
        || !grant.kinds.length || new Set(grant.kinds).size !== grant.kinds.length
        || grant.kinds.some(k => !['create','patch','delete'].includes(k)) || !grant.kinds.includes(request.kind)) return false;
      const key = publicVerificationKey(grant.public_key);
      return key.type === 'public' && key.asymmetricKeyType === 'ed25519' && verify(null, payload, key, signature);
    } catch { return false; }
  };
}
