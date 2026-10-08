// Formal opt-in assembly for the personal-domain host. Configuration contains
// policy and paths only; owner secrets remain in the DPAPI state adapter.
import { lstatSync, readFileSync, statSync } from 'node:fs';
import { isAbsolute, resolve } from 'node:path';
import { createPersonalDomainHost } from './personal_domain_host.mjs';
import { createPersonalDomainAuthorityRegistry, createPersonalDomainOwner } from './personal_domain_owner.mjs';
import { createWindowsDpapiPersonalDomainStateAdapter } from './personal_domain_private_state.mjs';

export const PERSONAL_DOMAIN_RUNTIME_FORMAT = 'i-core-personal-domain-runtime-v1';
export const WEB_DOMAIN_SCOPES = Object.freeze([
  'captures:read', 'captures:create', 'captures:patch', 'captures:delete',
]);
export const WEB_DOMAIN_ACTORS = Object.freeze(['agent_inferred', 'user_via_agent']);

const DOMAINS = ['captures', 'plan_items', 'plan_weeks', 'plan_days'];
const MODES = ['off', 'shadow', 'frozen', 'authoritative'];
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const exact = (value, keys) => object(value) && Object.keys(value).length === keys.length
  && keys.every(key => Object.hasOwn(value, key));
const identifier = value => typeof value === 'string' && /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,199}$/.test(value);
const fail = code => { throw Object.assign(new Error(code), { code }); };

function parseStrictJson(text) {
  const value = JSON.parse(text), stack = [];
  for (let index = 0; index < text.length; index++) {
    if (text[index] === '"') {
      const start = index;
      for (index++; index < text.length; index++) {
        if (text[index] === '\\') index++;
        else if (text[index] === '"') break;
      }
      const top = stack.at(-1);
      if (top?.keys && top.expectKey) {
        const key = JSON.parse(text.slice(start, index + 1));
        if (top.keys.has(key)) fail('invalid_personal_domain_runtime_configuration');
        top.keys.add(key); top.expectKey = false;
      }
    } else if (text[index] === '{') stack.push({ keys: new Set(), expectKey: true });
    else if (text[index] === '[') stack.push({});
    else if (text[index] === '}' || text[index] === ']') stack.pop();
    else if (text[index] === ',' && stack.at(-1)?.keys) stack.at(-1).expectKey = true;
  }
  return value;
}

function plainTrustedFile(filePath) {
  if (!isAbsolute(filePath ?? '') || resolve(filePath) !== filePath) fail('invalid_personal_domain_runtime_configuration');
  const link = lstatSync(filePath), stat = statSync(filePath);
  if (!link.isFile() || link.isSymbolicLink() || !stat.isFile() || stat.nlink !== 1) {
    fail('invalid_personal_domain_runtime_configuration');
  }
}

function validatePrincipal(value) {
  return exact(value, ['principal_id', 'installation_id', 'origin_device_id', 'character_id'])
    && identifier(value.principal_id) && identifier(value.installation_id)
    && identifier(value.origin_device_id) && identifier(value.character_id);
}

export function loadPersonalDomainRuntimeConfig(configPath) {
  plainTrustedFile(configPath);
  let value;
  try { value = parseStrictJson(readFileSync(configPath, 'utf8').replace(/^\uFEFF/, '')); } catch {
    fail('invalid_personal_domain_runtime_configuration');
  }
  if (!exact(value, ['format', 'enabled', 'core_instance_id', 'private_state_path', 'domain_modes',
    'web_user_message_principals']) || value.format !== PERSONAL_DOMAIN_RUNTIME_FORMAT || value.enabled !== true
    || !identifier(value.core_instance_id) || !isAbsolute(value.private_state_path ?? '')
    || resolve(value.private_state_path) !== value.private_state_path
    || !exact(value.domain_modes, DOMAINS) || Object.values(value.domain_modes).some(mode => !MODES.includes(mode))
    || !Array.isArray(value.web_user_message_principals) || value.web_user_message_principals.length < 1
    || value.web_user_message_principals.length > 32 || !value.web_user_message_principals.every(validatePrincipal)) {
    fail('invalid_personal_domain_runtime_configuration');
  }
  for (const key of ['principal_id', 'installation_id', 'origin_device_id']) {
    if (new Set(value.web_user_message_principals.map(row => row[key])).size
      !== value.web_user_message_principals.length) fail('invalid_personal_domain_runtime_configuration');
  }
  if (value.private_state_path === configPath) fail('invalid_personal_domain_runtime_configuration');
  return structuredClone(value);
}

function validateConfiguredWebPrincipals(core, config) {
  for (const configured of config.web_user_message_principals) {
    const row = core.store.db.prepare('SELECT * FROM domain_principals WHERE principal_id=?').get(configured.principal_id);
    if (!row || row.status !== 'active' || row.device_id !== configured.origin_device_id
      || row.installation_id !== configured.installation_id) fail('personal_domain_web_principal_not_ready');
    let principal;
    try { principal = JSON.parse(row.config_json); } catch {
      fail('personal_domain_web_principal_not_ready');
    }
    if (!exact(principal, ['principal_id', 'device_id', 'installation_id', 'scopes', 'actors',
      'trusted_interactive', 'origin_device_only'])
      || principal.principal_id !== configured.principal_id || principal.device_id !== configured.origin_device_id
      || principal.installation_id !== configured.installation_id || principal.trusted_interactive !== false
      || principal.origin_device_only !== true
      || JSON.stringify(principal.scopes) !== JSON.stringify(WEB_DOMAIN_SCOPES)
      || JSON.stringify(principal.actors) !== JSON.stringify(WEB_DOMAIN_ACTORS)) {
      fail('personal_domain_web_principal_not_ready');
    }
  }
}

export async function createConfiguredPersonalDomainRuntime({
  databasePath,
  configPath,
  createServer,
  serverOptions = {},
  requireWebPrincipals = true,
  stateAdapterFactory = createWindowsDpapiPersonalDomainStateAdapter,
  webAuthorizationVerifierFactory = null,
  platform = process.platform,
  environment = process.env,
  spawnProvider = undefined,
  clock = Date.now,
} = {}) {
  if (!isAbsolute(databasePath ?? '') || resolve(databasePath) !== databasePath
    || typeof createServer !== 'function' || !object(serverOptions) || typeof clock !== 'function') {
    fail('invalid_personal_domain_runtime_configuration');
  }
  const config = loadPersonalDomainRuntimeConfig(configPath);
  const stateAdapter = stateAdapterFactory({ statePath: config.private_state_path,
    coreInstanceId: config.core_instance_id, platform, environment,
    ...(spawnProvider ? { spawnProvider } : {}), clock });
  if (typeof stateAdapter?.acquireExclusive !== 'function') fail('invalid_personal_domain_runtime_configuration');
  const releaseExclusive = stateAdapter.acquireExclusive();
  if (typeof releaseExclusive !== 'function') fail('invalid_personal_domain_runtime_configuration');
  let database = null, core, released = false;
  const release = () => { if (!released) { released = true; releaseExclusive(); } };
  try {
    const authorityRegistry = createPersonalDomainAuthorityRegistry({ coreInstanceId: config.core_instance_id,
      stateAdapter, now: clock });
    const factory = webAuthorizationVerifierFactory ?? (await import('./web_user_message_authorization.mjs'))
      .createWebUserMessageAuthorizationVerifier;
    if (typeof factory !== 'function') fail('invalid_personal_domain_runtime_configuration');
    const verifyWebAuthorization = factory({ coreInstanceId: config.core_instance_id,
      getDatabase: () => {
        if (!database) fail('personal_domain_runtime_not_ready');
        return database;
      }, principals: structuredClone(config.web_user_message_principals) });
    if (typeof verifyWebAuthorization !== 'function') fail('invalid_personal_domain_runtime_configuration');
    const webPrincipalIds = config.web_user_message_principals.map(row => row.principal_id);
    const host = createPersonalDomainHost({ enabled: true, domainModes: config.domain_modes,
      coreInstanceId: config.core_instance_id, authorityRegistry, verifyWebAuthorization,
      webPrincipalIds, captureSourcesByPrincipal: Object.fromEntries(webPrincipalIds.map(id => [id, ['claude_web']])) });
    core = createServer({ databasePath, ...serverOptions, ...host.serverOptions, clock });
    const closeCore = core.close.bind(core), listenCore = core.listen.bind(core);
    core.close = async () => { try { await closeCore(); } finally { database = null; release(); } };
    core.listen = async options => {
      try { return await listenCore(options); } catch (error) {
        try { await core.close(); } catch {}
        throw error;
      }
    };
    database = core.store.db;
    if (core.store.nodeId !== config.core_instance_id) fail('personal_domain_core_identity_mismatch');
    if (requireWebPrincipals) validateConfiguredWebPrincipals(core, config);
    const owner = createPersonalDomainOwner({ domainStore: core.store.domains, authorityRegistry });
    return Object.freeze({ core, owner, authorityRegistry, config: Object.freeze(config), host });
  } catch (error) {
    database = null;
    if (core?.close) await core.close().catch(() => {});
    else release();
    throw error;
  }
}

export function grantConfiguredWebPrincipal({ runtime, principalId } = {}) {
  if (!runtime?.core?.store?.domains || !runtime?.config || !identifier(principalId)) {
    fail('invalid_personal_domain_web_grant');
  }
  const configured = runtime.config.web_user_message_principals.find(row => row.principal_id === principalId);
  if (!configured) fail('invalid_personal_domain_web_grant');
  if (runtime.core.store.db.prepare('SELECT 1 FROM domain_principals WHERE principal_id=?').get(principalId)) {
    fail('personal_domain_web_principal_already_exists');
  }
  const issued = runtime.core.store.domains.configurePrincipal({ principal_id: configured.principal_id,
    device_id: configured.origin_device_id, installation_id: configured.installation_id,
    scopes: [...WEB_DOMAIN_SCOPES], actors: [...WEB_DOMAIN_ACTORS], trusted_interactive: false,
    origin_device_only: true });
  return { format: 'i-core-web-domain-access-export-v1', web_domain_access: {
    protocol_version: 1, core_instance_id: runtime.config.core_instance_id, principal_id: configured.principal_id,
    credential_generation: issued.generation, installation_id: configured.installation_id,
    device_id: configured.origin_device_id, token: issued.token, scopes: [...WEB_DOMAIN_SCOPES],
    actors: [...WEB_DOMAIN_ACTORS] } };
}
