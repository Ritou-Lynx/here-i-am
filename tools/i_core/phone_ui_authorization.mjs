// Owner-provisioned phone UI authority. No credential discovery, grant issuance,
// registration, route change, network listener, or production enablement here.
import { createHmac, timingSafeEqual } from 'node:crypto';
import { canonicalJSON } from './domain_store.mjs';

const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const keyIdPattern = /^[A-Za-z0-9_-]{1,40}$/;
const id = value => typeof value === 'string' && /^[a-zA-Z0-9][a-zA-Z0-9_.:-]{0,199}$/.test(value);
const grantFields = ['principal_id', 'credential_generation', 'installation_id', 'key_id', 'secret', 'domains'];
const actions = { captures: ['create', 'patch', 'delete'], plan_items: ['status'] };

function secretBytes(secret) {
  if (typeof secret !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(secret)) throw new Error('invalid_phone_ui_key');
  const bytes = Buffer.from(secret, 'base64url');
  if (bytes.length !== 32 || bytes.toString('base64url') !== secret) throw new Error('invalid_phone_ui_key');
  return bytes;
}

function permitted(domain, intent) {
  if (!object(intent) || intent.actor !== 'user_direct' || !actions[domain]?.includes(intent.kind)) return false;
  if (domain === 'captures' && intent.kind === 'create') return intent.data?.source === 'phone_quick'
    && intent.provenance?.source === 'phone_quick';
  if (domain === 'captures' && intent.kind === 'patch') return object(intent.patch)
    && Object.keys(intent.patch).length === 1 && typeof intent.patch.text === 'string';
  if (domain === 'plan_items') return object(intent.patch) && Object.keys(intent.patch).length === 1
    && ['完成', '放弃'].includes(intent.patch.status);
  return true;
}

export function phoneUiSigningPayload(domain, binding, intent) {
  if (!Object.hasOwn(actions, domain) || !object(binding) || !object(intent)) throw new Error('invalid_phone_ui_action');
  const { authorization_ref: ignored, ...unsigned } = intent;
  return { protocol: 'i-domain-ui-v1', domain, binding: {
    core_instance_id: binding.core_instance_id,
    principal_id: binding.principal_id,
    credential_generation: binding.credential_generation,
    installation_id: binding.installation_id,
  }, intent: unsigned };
}

// Reference issuer for the separately trusted interactive entry and cross-language
// fixtures. Call only after fixing the full intent in the durable UI transaction.
// A model tool call or arbitrary UUID does not authorize this function's use.
export function signPhoneUiIntent({domain, binding, intent, keyId, secret}) {
  if (!keyIdPattern.test(keyId ?? '') || !permitted(domain, intent)) throw new Error('invalid_phone_ui_action');
  const payload = canonicalJSON(phoneUiSigningPayload(domain, binding, intent));
  const mac = createHmac('sha256', secretBytes(secret)).update(payload, 'utf8').digest('base64url');
  return `uia1.${keyId}.${mac}`;
}

export function createPhoneUiAuthorizationVerifier({coreInstanceId, grants}) {
  if (!id(coreInstanceId) || !Array.isArray(grants) || grants.length > 32) throw new Error('invalid_phone_ui_configuration');
  const keys = new Map();
  for (const grant of grants) {
    if (!object(grant) || Object.keys(grant).some(key => !grantFields.includes(key))
      || !id(grant.principal_id) || !id(grant.installation_id)
      || !Number.isSafeInteger(grant.credential_generation) || grant.credential_generation < 1
      || !keyIdPattern.test(grant.key_id ?? '') || !Array.isArray(grant.domains) || !grant.domains.length
      || grant.domains.some(domain => !Object.hasOwn(actions, domain))
      || new Set(grant.domains).size !== grant.domains.length || keys.has(grant.key_id)) {
      throw new Error('invalid_phone_ui_configuration');
    }
    keys.set(grant.key_id, {...grant, domains: [...grant.domains], key: secretBytes(grant.secret)});
  }
  return ({principal, request, domain, authorizationRef}) => {
    if (!object(principal) || !permitted(domain, request) || request.core_instance_id !== coreInstanceId
      || principal.trusted_interactive !== true || !principal.actors?.includes('user_direct')
      || typeof authorizationRef !== 'string') return false;
    const match = /^uia1\.([A-Za-z0-9_-]{1,40})\.([A-Za-z0-9_-]{43})$/.exec(authorizationRef);
    if (!match) return false;
    const grant = keys.get(match[1]);
    if (!grant || principal.principal_id !== grant.principal_id
      || principal.generation !== grant.credential_generation || principal.installation_id !== grant.installation_id
      || !grant.domains.includes(domain)) return false;
    const binding = {core_instance_id:coreInstanceId,principal_id:principal.principal_id,
      credential_generation:principal.generation,installation_id:principal.installation_id};
    const expected = createHmac('sha256', grant.key)
      .update(canonicalJSON(phoneUiSigningPayload(domain, binding, request)), 'utf8').digest();
    const supplied = Buffer.from(match[2], 'base64url');
    return supplied.length === expected.length && supplied.toString('base64url') === match[2]
      && timingSafeEqual(supplied, expected);
  };
}
