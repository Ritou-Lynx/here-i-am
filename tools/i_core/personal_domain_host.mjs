// Source-only personal-domain host composition. Importing this module has no
// effect; callers must explicitly enable it and pass the returned serverOptions.
import { canonicalJSON, DOMAIN_POLICY } from './domain_store.mjs';
import {
  PERSONAL_DOMAINS,
  PERSONAL_HOOK_VERSION,
  PERSONAL_SCHEMAS,
  createPersonalDataHooks,
  personalDedupHooks,
} from './personal_data_domains.mjs';

const modes = ['off', 'shadow', 'frozen', 'authoritative'];
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const identifier = value => typeof value === 'string' && /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,199}$/.test(value);
const fail = code => { throw Object.assign(new Error(code), { code }); };

function expectedRegistration(domain, mode) {
  return { mode, policy_version: DOMAIN_POLICY.version, schema: PERSONAL_SCHEMAS[domain],
    requiredHooksVersion: PERSONAL_HOOK_VERSION,
    serverDerivedFields: domain === 'plan_items' ? ['completed_at'] : [] };
}

function resolvedModes({ mode, domainModes } = {}) {
  if (mode !== undefined && domainModes !== undefined) fail('invalid_personal_domain_configuration');
  if (mode !== undefined) {
    if (!modes.includes(mode)) fail('invalid_personal_domain_configuration');
    return Object.fromEntries(PERSONAL_DOMAINS.map(domain => [domain, mode]));
  }
  if (!object(domainModes) || canonicalJSON(Object.keys(domainModes).sort()) !== canonicalJSON([...PERSONAL_DOMAINS].sort())
    || Object.values(domainModes).some(value => !modes.includes(value))) fail('invalid_personal_domain_configuration');
  return structuredClone(domainModes);
}

function assertRegisteredDomain(store, domain, mode) {
  const actual = store.domain(domain), expected = expectedRegistration(domain, mode);
  if (actual.mode !== expected.mode || actual.policy_version !== expected.policy_version
    || actual.requiredHooksVersion !== expected.requiredHooksVersion
    || canonicalJSON(actual.schema) !== canonicalJSON(expected.schema)
    || canonicalJSON(actual.serverDerivedFields) !== canonicalJSON(expected.serverDerivedFields)) {
    fail('personal_domain_configuration_mismatch');
  }
  return actual;
}

export function configurePersonalDomains(store, options = {}) {
  const domainModes = resolvedModes(options);
  if (!store || typeof store.registerDomain !== 'function' || typeof store.domain !== 'function') {
    fail('invalid_personal_domain_configuration');
  }
  const rows = store.db.prepare(`SELECT domain FROM domain_registry WHERE domain IN (${PERSONAL_DOMAINS.map(() => '?').join(',')})`)
    .all(...PERSONAL_DOMAINS).map(row => row.domain);
  if (rows.length !== 0 && rows.length !== PERSONAL_DOMAINS.length) fail('personal_domain_configuration_mismatch');
  if (rows.length === 0) {
    store.db.exec('BEGIN IMMEDIATE');
    try {
      for (const domain of PERSONAL_DOMAINS) {
        const expected = expectedRegistration(domain, domainModes[domain]);
        store.registerDomain(domain, structuredClone(expected.schema), { mode: expected.mode,
          policyVersion: expected.policy_version, requiredHooksVersion: expected.requiredHooksVersion,
          serverDerivedFields: expected.serverDerivedFields });
      }
      store.db.exec('COMMIT');
    } catch (error) {
      try { store.db.exec('ROLLBACK'); } catch {}
      throw error;
    }
  }
  for (const domain of PERSONAL_DOMAINS) assertRegisteredDomain(store, domain, domainModes[domain]);
  return { enabled: true, domain_modes: domainModes, domains: [...PERSONAL_DOMAINS] };
}

export function transitionPersonalDomainMode(store, { domain, expectedMode, nextMode } = {}) {
  if (!PERSONAL_DOMAINS.includes(domain) || !modes.includes(expectedMode) || !modes.includes(nextMode)) {
    fail('invalid_personal_domain_transition');
  }
  assertRegisteredDomain(store, domain, expectedMode);
  store.setMode(domain, nextMode);
  const current = store.domain(domain);
  if (current.mode !== nextMode) fail('personal_domain_configuration_mismatch');
  return { domain, previous_mode: expectedMode, mode: nextMode, frozen_from: current.frozen_from ?? null };
}

export function createPersonalDomainHost({ enabled = false, mode, domainModes, coreInstanceId, authorityRegistry,
  verifyWebAuthorization = () => false, plannerPrincipalIds = [], processorPrincipals = {},
  captureSourcesByPrincipal = {}, webPrincipalIds = [], resolveDerivedReferences = null } = {}) {
  if (enabled !== true) return Object.freeze({ enabled: false, serverOptions: Object.freeze({}) });
  const configuredModes = resolvedModes({ mode, domainModes });
  if (!identifier(coreInstanceId) || !object(authorityRegistry)
    || authorityRegistry.coreInstanceId !== coreInstanceId
    || typeof authorityRegistry.verifyPhoneAuthorization !== 'function'
    || typeof authorityRegistry.verifyLegacyAdoption !== 'function'
    || typeof authorityRegistry.captureSourcesForPrincipal !== 'function'
    || typeof verifyWebAuthorization !== 'function' || !Array.isArray(plannerPrincipalIds)
    || !Array.isArray(webPrincipalIds) || webPrincipalIds.some(value => !identifier(value))
    || new Set(webPrincipalIds).size !== webPrincipalIds.length
    || !object(processorPrincipals) || !object(captureSourcesByPrincipal)) {
    fail('invalid_personal_domain_configuration');
  }
  const configuredCaptureSources = structuredClone(captureSourcesByPrincipal);
  const dynamicCaptureSources = new Proxy(configuredCaptureSources, { get(target, principalId, receiver) {
    if (typeof principalId !== 'string') return Reflect.get(target, principalId, receiver);
    return authorityRegistry.captureSourcesForPrincipal(principalId) ?? Reflect.get(target, principalId, receiver);
  } });
  const hooks = createPersonalDataHooks({ captureSourcesByPrincipal: dynamicCaptureSources,
    webPrincipalIds: [...webPrincipalIds], verifyWebAuthorization,
    plannerPrincipalIds: [...plannerPrincipalIds],
    processorPrincipals: structuredClone(processorPrincipals),
    resolveDerivedReferences });
  const verifyAuthorization = context => {
    try {
      if (context?.request?.actor === 'user_direct') return authorityRegistry.verifyPhoneAuthorization(context) === true;
      if (context?.request?.actor === 'user_via_agent') {
        const result = verifyWebAuthorization(context);
        if (result && typeof result.then === 'function') {
          Promise.resolve(result).catch(() => {});
          return false;
        }
        return result === true;
      }
      return false;
    } catch { return false; }
  };
  const serverOptions = Object.freeze({ domainHooks: hooks, domainDedupHooks: personalDedupHooks(),
    domainVerifyAuthorization: verifyAuthorization,
    domainVerifyLegacyAdoption: context => authorityRegistry.verifyLegacyAdoption(context) === true,
    domainConfigure: store => {
      if (store.nodeId !== coreInstanceId) fail('personal_domain_core_identity_mismatch');
      return configurePersonalDomains(store, { domainModes: configuredModes });
    } });
  return Object.freeze({ enabled: true, domainModes: Object.freeze(configuredModes), coreInstanceId, serverOptions });
}
