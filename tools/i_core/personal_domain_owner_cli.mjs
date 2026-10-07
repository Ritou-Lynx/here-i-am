// Explicit local owner workflow. It never starts a listener and never prints
// bearer tokens, HMAC secrets, legacy record bodies, or migration proofs.
import { randomUUID } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import {
  closeSync,
  existsSync,
  fsyncSync,
  lstatSync,
  linkSync,
  mkdirSync,
  openSync,
  readFileSync,
  rmdirSync,
  statSync,
  unlinkSync,
  writeSync,
} from 'node:fs';
import { dirname, isAbsolute, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createICoreServer } from './i_core_server.mjs';
import { applyPhoneCaptureMigration, freezePhoneCaptureMigration,
  PHONE_CAPTURE_MAPPING_VERSION } from './phone_capture_migration.mjs';
import { createConfiguredPersonalDomainRuntime, grantConfiguredWebPrincipal } from './personal_domain_runtime.mjs';

const modulePath = fileURLToPath(import.meta.url);
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
        if (top.keys.has(key)) fail('invalid_owner_input');
        top.keys.add(key); top.expectKey = false;
      }
    } else if (text[index] === '{') stack.push({ keys: new Set(), expectKey: true });
    else if (text[index] === '[') stack.push({});
    else if (text[index] === '}' || text[index] === ']') stack.pop();
    else if (text[index] === ',' && stack.at(-1)?.keys) stack.at(-1).expectKey = true;
  }
  return value;
}

function readOwnerJson(filePath) {
  if (!isAbsolute(filePath ?? '') || resolve(filePath) !== filePath) fail('invalid_owner_input');
  const link = lstatSync(filePath), stat = statSync(filePath);
  if (!link.isFile() || link.isSymbolicLink() || !stat.isFile() || stat.nlink !== 1 || stat.size > 16 * 1024 * 1024) {
    fail('invalid_owner_input');
  }
  try { return parseStrictJson(readFileSync(filePath, 'utf8').replace(/^\uFEFF/, '')); } catch (error) {
    if (error?.code) throw error;
    fail('invalid_owner_input');
  }
}

const ACL_SCRIPT = String.raw`
$ErrorActionPreference = 'Stop'
$path = $env:I_CORE_OWNER_PROTECTED_PATH
$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
$acl = New-Object System.Security.AccessControl.DirectorySecurity
$acl.SetOwner($identity)
$acl.SetAccessRuleProtection($true, $false)
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
  $identity,
  [System.Security.AccessControl.FileSystemRights]::FullControl,
  [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit',
  [System.Security.AccessControl.PropagationFlags]::None,
  [System.Security.AccessControl.AccessControlType]::Allow)
$acl.AddAccessRule($rule)
[System.IO.Directory]::SetAccessControl($path, $acl)
`;

function defaultPowerShell(environment) {
  const root = environment.SystemRoot || environment.SYSTEMROOT;
  return root ? join(root, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe') : null;
}

function protectDirectory(directoryPath, { platform, environment, powershellPath, spawnProvider }) {
  if (platform !== 'win32' || !powershellPath || !existsSync(powershellPath)) fail('protected_owner_output_unavailable');
  const result = spawnProvider(powershellPath, ['-NoLogo', '-NoProfile', '-NonInteractive', '-EncodedCommand',
    Buffer.from(ACL_SCRIPT, 'utf16le').toString('base64')], {
    env: { ...environment, I_CORE_OWNER_PROTECTED_PATH: directoryPath }, windowsHide: true,
    timeout: 15_000, maxBuffer: 1024 * 1024, encoding: null,
  });
  if (result.error || result.status !== 0) fail('protected_owner_output_unavailable');
}

export function writeProtectedOwnerJson(outputPath, value, {
  platform = process.platform,
  environment = process.env,
  powershellPath = defaultPowerShell(environment),
  spawnProvider = spawnSync,
} = {}) {
  if (!isAbsolute(outputPath ?? '') || resolve(outputPath) !== outputPath || existsSync(outputPath)) {
    fail('protected_owner_output_rejected');
  }
  const parent = dirname(outputPath), temporaryDirectory = join(parent, `.i-core-owner-${randomUUID()}`);
  mkdirSync(parent, { recursive: true });
  mkdirSync(temporaryDirectory, { recursive: false, mode: 0o700 });
  const temporaryFile = join(temporaryDirectory, 'output.json');
  let publishedIdentity = null;
  try {
    protectDirectory(temporaryDirectory, { platform, environment, powershellPath, spawnProvider });
    const handle = openSync(temporaryFile, 'wx', 0o600);
    try {
      writeSync(handle, Buffer.from(`${JSON.stringify(value)}\n`, 'utf8'));
      fsyncSync(handle);
    } finally { closeSync(handle); }
    const temporaryStat = statSync(temporaryFile, { bigint: true });
    linkSync(temporaryFile, outputPath);
    publishedIdentity = { dev: temporaryStat.dev, ino: temporaryStat.ino };
    unlinkSync(temporaryFile);
    const link = lstatSync(outputPath), stat = statSync(outputPath);
    if (!link.isFile() || link.isSymbolicLink() || stat.nlink !== 1) fail('protected_owner_output_rejected');
  } catch (error) {
    try { if (existsSync(temporaryFile)) unlinkSync(temporaryFile); } catch {}
    try {
      if (publishedIdentity && existsSync(outputPath)) {
        const stat = statSync(outputPath, { bigint: true });
        if (stat.dev === publishedIdentity.dev && stat.ino === publishedIdentity.ino) unlinkSync(outputPath);
      }
    } catch {}
    if (error?.code?.startsWith?.('protected_owner_')) throw error;
    if (error?.code === 'EEXIST') fail('protected_owner_output_rejected');
    fail('protected_owner_output_unavailable');
  } finally {
    try { if (existsSync(temporaryDirectory)) rmdirSync(temporaryDirectory); } catch {}
  }
}

function parseArgs(argv) {
  const command = argv[0];
  if (!['grant-phone', 'rotate-phone', 'revoke-phone', 'grant-web', 'freeze-captures', 'apply-captures'].includes(command)) {
    fail('invalid_owner_command');
  }
  const options = {};
  for (let index = 1; index < argv.length; index += 2) {
    const key = argv[index], value = argv[index + 1];
    if (!/^--[a-z-]+$/.test(key ?? '') || value === undefined || Object.hasOwn(options, key)) fail('invalid_owner_command');
    options[key] = value;
  }
  const required = {
    'grant-phone': ['--config', '--database', '--binding', '--input', '--output'],
    'rotate-phone': ['--config', '--database', '--input', '--output'],
    'revoke-phone': ['--config', '--database', '--input', '--output'],
    'grant-web': ['--config', '--database', '--input', '--output'],
    'freeze-captures': ['--config', '--database', '--app-manifest', '--legacy-records', '--batch-id', '--expires-at', '--output'],
    'apply-captures': ['--config', '--database', '--domain-access', '--legacy-records', '--migration-id', '--output'],
  }[command];
  if (Object.keys(options).length !== required.length || required.some(key => !Object.hasOwn(options, key))) {
    fail('invalid_owner_command');
  }
  for (const key of required.filter(key => !['--batch-id', '--expires-at', '--migration-id'].includes(key))) {
    if (!isAbsolute(options[key]) || resolve(options[key]) !== options[key]) fail('invalid_owner_command');
  }
  return { command, options };
}

function phoneGrantInput(raw) {
  const keys = ['principal_id', 'scopes', 'capture_sources', 'adoption_sources',
    'adoption_origin_principal_ids'];
  if (!exact(raw, ['format', 'grant']) || raw.format !== 'i-core-phone-access-grant-request-v1'
    || !exact(raw.grant, keys) || !raw.grant.scopes?.length || !Array.isArray(raw.grant.capture_sources)
    || !Array.isArray(raw.grant.adoption_sources) || !Array.isArray(raw.grant.adoption_origin_principal_ids)) fail('invalid_owner_input');
  return { principalId: raw.grant.principal_id,
    scopes: raw.grant.scopes, captureSources: raw.grant.capture_sources,
    adoptionSources: raw.grant.adoption_sources,
    adoptionOriginPrincipalIds: raw.grant.adoption_origin_principal_ids };
}

function phoneInstallationBinding(raw, runtime) {
  if (!exact(raw, ['format', 'binding']) || raw.format !== 'i-core-phone-installation-binding-v1'
    || !exact(raw.binding, ['core_instance_id', 'installation_id', 'device_id'])
    || raw.binding.core_instance_id !== runtime.config.core_instance_id
    || !identifier(raw.binding.installation_id) || raw.binding.installation_id !== raw.binding.device_id
    || !runtime.core.store.db.prepare('SELECT 1 FROM devices WHERE device_id=?').get(raw.binding.device_id)) {
    fail('invalid_owner_input');
  }
  return { installationId: raw.binding.installation_id, deviceId: raw.binding.device_id };
}

function phoneBindingInput(raw, runtime) {
  if (!exact(raw, ['format', 'binding']) || raw.format !== 'i-core-phone-access-binding-v1'
    || !exact(raw.binding, ['core_instance_id', 'principal_id', 'installation_id'])
    || raw.binding.core_instance_id !== runtime.config.core_instance_id) fail('invalid_owner_input');
  return { principalId: raw.binding.principal_id, installationId: raw.binding.installation_id };
}

function accessExport(raw) {
  if (!exact(raw, ['format', 'domain_access']) || raw.format !== 'i-core-domain-access-export-v1'
    || !object(raw.domain_access)) fail('invalid_owner_input');
  return raw.domain_access;
}

function legacyRecords(raw) {
  if (!exact(raw, ['format', 'records']) || raw.format !== 'i-core-legacy-capture-records-v1'
    || !Array.isArray(raw.records) || raw.records.length < 1 || raw.records.length > 5000) fail('invalid_owner_input');
  return raw.records;
}

export async function runPersonalDomainOwnerCommand(argv, {
  createRuntime = options => createConfiguredPersonalDomainRuntime({ ...options, createServer: createICoreServer }),
  writeOutput = writeProtectedOwnerJson,
} = {}) {
  const { command, options } = parseArgs(argv);
  let runtime;
  try {
    runtime = await createRuntime({ databasePath: options['--database'], configPath: options['--config'],
      requireWebPrincipals: false });
    let output;
    if (command === 'grant-phone') {
      const grant = phoneGrantInput(readOwnerJson(options['--input']));
      const binding = phoneInstallationBinding(readOwnerJson(options['--binding']), runtime);
      const domainAccess = runtime.owner.grantPhoneAccess({ ...grant, ...binding });
      output = { format: 'i-core-domain-access-export-v1', domain_access: domainAccess };
    } else if (command === 'rotate-phone') {
      const domainAccess = runtime.owner.rotatePhoneAccess(phoneBindingInput(readOwnerJson(options['--input']), runtime));
      output = { format: 'i-core-domain-access-export-v1', domain_access: domainAccess };
    } else if (command === 'revoke-phone') {
      const revocation = runtime.owner.revokePhoneAccess(phoneBindingInput(readOwnerJson(options['--input']), runtime));
      output = { format: 'i-core-domain-access-revocation-v1', revocation };
    } else if (command === 'grant-web') {
      const request = readOwnerJson(options['--input']);
      if (!exact(request, ['format', 'principal_id']) || request.format !== 'i-core-web-access-grant-request-v1'
        || !identifier(request.principal_id)) fail('invalid_owner_input');
      output = grantConfiguredWebPrincipal({ runtime, principalId: request.principal_id });
    } else if (command === 'freeze-captures') {
      const exported = readOwnerJson(options['--app-manifest']);
      if (!exact(exported, ['format', 'manifest'])
        || exported.format !== 'i-core-capture-migration-manifest-export-v1') fail('invalid_owner_input');
      const frozen = freezePhoneCaptureMigration({ owner: runtime.owner, appManifest: exported.manifest,
        legacyRecords: legacyRecords(readOwnerJson(options['--legacy-records'])), batchId: options['--batch-id'],
        mappingVersion: PHONE_CAPTURE_MAPPING_VERSION, expiresAt: options['--expires-at'] });
      output = { format: 'i-core-capture-migration-freeze-v1', freeze: {
        migration_id: frozen.migration_id, manifest_digest: frozen.manifest_digest, expires_at: frozen.expires_at } };
    } else {
      const access = accessExport(readOwnerJson(options['--domain-access']));
      if (access.core_instance_id !== runtime.config.core_instance_id || typeof access.token !== 'string'
        || access.principal_id === undefined || access.installation_id === undefined) fail('invalid_owner_input');
      const applied = applyPhoneCaptureMigration({ owner: runtime.owner, migrationId: options['--migration-id'],
        adoptionToken: access.token, legacyRecords: legacyRecords(readOwnerJson(options['--legacy-records'])) });
      output = { format: 'i-core-capture-migration-proof-v1', proof: applied.proof };
    }
    writeOutput(options['--output'], output);
    return { ok: true, command, output_written: true };
  } finally {
    if (runtime?.core?.close) await runtime.core.close();
  }
}

if (process.argv[1] && resolve(process.argv[1]) === resolve(modulePath)) {
  runPersonalDomainOwnerCommand(process.argv.slice(2)).then(result => {
    process.stdout.write(`${JSON.stringify(result)}\n`);
  }).catch(error => {
    process.stderr.write(`${error?.code ?? 'owner_command_failed'}\n`);
    process.exitCode = 1;
  });
}
