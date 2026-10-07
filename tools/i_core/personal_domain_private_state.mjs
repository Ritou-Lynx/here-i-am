// Windows-only private state for personal-domain owner grants and manifests.
// Plaintext is passed to DPAPI through pipes and is never written to disk.
import { createHash, randomUUID } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import {
  closeSync,
  existsSync,
  fsyncSync,
  lstatSync,
  mkdirSync,
  openSync,
  readFileSync,
  renameSync,
  statSync,
  unlinkSync,
  writeSync,
} from 'node:fs';
import { dirname, isAbsolute, join, resolve } from 'node:path';

const FORMAT = 'i-core-personal-domain-private-state-v1';
const PROVIDER = 'windows-dpapi-current-user';
const CONTEXT = 'i-core/personal-domain-owner-state/v1';
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const exact = (value, keys) => object(value) && Object.keys(value).length === keys.length
  && keys.every(key => Object.hasOwn(value, key));
const identifier = value => typeof value === 'string' && /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,199}$/.test(value);
const fail = code => { throw Object.assign(new Error(code), { code }); };
const hash = value => createHash('sha256').update(value).digest('hex');

const DPAPI_SCRIPT = String.raw`
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
$inputStream = [Console]::OpenStandardInput()
$memory = New-Object System.IO.MemoryStream
$inputStream.CopyTo($memory)
$inputBytes = $memory.ToArray()
$entropy = [Convert]::FromBase64String($env:I_CORE_PERSONAL_STATE_ENTROPY)
if ($env:I_CORE_PERSONAL_STATE_OPERATION -eq 'protect') {
  $outputBytes = [System.Security.Cryptography.ProtectedData]::Protect(
    $inputBytes, $entropy, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
} elseif ($env:I_CORE_PERSONAL_STATE_OPERATION -eq 'unprotect') {
  $outputBytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
    $inputBytes, $entropy, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
} else {
  throw 'unsupported operation'
}
$output = [Console]::OpenStandardOutput()
$output.Write($outputBytes, 0, $outputBytes.Length)
$output.Flush()
`;

function defaultPowerShell(environment) {
  const root = environment.SystemRoot || environment.SYSTEMROOT;
  return root ? join(root, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe') : null;
}

function writeDurableTemporary(filePath, bytes) {
  const handle = openSync(filePath, 'wx', 0o600);
  try {
    writeSync(handle, bytes);
    fsyncSync(handle);
  } finally {
    closeSync(handle);
  }
}

export function createWindowsDpapiPersonalDomainStateAdapter({
  statePath,
  coreInstanceId,
  platform = process.platform,
  environment = process.env,
  powershellPath = defaultPowerShell(environment),
  spawnProvider = spawnSync,
  clock = Date.now,
} = {}) {
  if (!isAbsolute(statePath ?? '') || resolve(statePath) !== statePath || !identifier(coreInstanceId)
    || typeof clock !== 'function') fail('invalid_personal_domain_private_state_configuration');
  const parent = dirname(statePath), pathDigest = hash(Buffer.from(statePath.toLocaleLowerCase('en-US'), 'utf8'));
  const lockPath = `${statePath}.lock`;
  const entropy = createHash('sha256').update(`${CONTEXT}\0${coreInstanceId}\0${pathDigest}`, 'utf8').digest();

  function assertSupported() {
    if (platform !== 'win32' || !powershellPath || !existsSync(powershellPath)) {
      fail('personal_domain_private_state_unavailable');
    }
  }

  function assertPlainFile() {
    if (!existsSync(statePath)) return;
    const link = lstatSync(statePath), stat = statSync(statePath);
    if (!link.isFile() || link.isSymbolicLink() || !stat.isFile() || stat.nlink !== 1) {
      fail('personal_domain_private_state_path_rejected');
    }
  }

  function invoke(operation, input) {
    assertSupported();
    const result = spawnProvider(powershellPath, ['-NoLogo', '-NoProfile', '-NonInteractive', '-EncodedCommand',
      Buffer.from(DPAPI_SCRIPT, 'utf16le').toString('base64')], {
      input,
      env: { ...environment, I_CORE_PERSONAL_STATE_OPERATION: operation,
        I_CORE_PERSONAL_STATE_ENTROPY: entropy.toString('base64') },
      windowsHide: true,
      timeout: 15_000,
      maxBuffer: 4 * 1024 * 1024,
      encoding: null,
    });
    if (result.error || result.status !== 0 || !Buffer.isBuffer(result.stdout) || result.stdout.length === 0) {
      fail('personal_domain_private_state_unavailable');
    }
    return Buffer.from(result.stdout);
  }

  function parseEnvelope() {
    let envelope;
    try { envelope = JSON.parse(readFileSync(statePath, 'utf8').replace(/^\uFEFF/, '')); } catch {
      fail('invalid_personal_domain_private_state');
    }
    if (!exact(envelope, ['format', 'provider', 'scope', 'core_instance_id', 'state_path_sha256',
      'ciphertext', 'saved_at']) || envelope.format !== FORMAT || envelope.provider !== PROVIDER
      || envelope.scope !== 'CurrentUser' || envelope.core_instance_id !== coreInstanceId
      || envelope.state_path_sha256 !== pathDigest || typeof envelope.saved_at !== 'string'
      || !Number.isFinite(Date.parse(envelope.saved_at))
      || typeof envelope.ciphertext !== 'string' || !/^[A-Za-z0-9+/]+={0,2}$/.test(envelope.ciphertext)) {
      fail('invalid_personal_domain_private_state');
    }
    return envelope;
  }

  return Object.freeze({
    statePath,
    acquireExclusive() {
      assertSupported();
      mkdirSync(parent, { recursive: true });
      const nonce = randomUUID(), document = `${JSON.stringify({
        format: 'i-core-personal-domain-private-state-lock-v1',
        core_instance_id: coreInstanceId,
        pid: process.pid,
        nonce,
      })}\n`;
      let handle;
      try {
        handle = openSync(lockPath, 'wx', 0o600);
        writeSync(handle, Buffer.from(document, 'utf8'));
        fsyncSync(handle);
      } catch (error) {
        try { if (handle !== undefined) closeSync(handle); } catch {}
        fail(error?.code === 'EEXIST' ? 'personal_domain_private_state_busy'
          : 'personal_domain_private_state_unavailable');
      }
      let released = false;
      return () => {
        if (released) return;
        released = true;
        try { closeSync(handle); } catch { fail('personal_domain_private_state_lock_compromised'); }
        try {
          const link = lstatSync(lockPath), stat = statSync(lockPath);
          if (!link.isFile() || link.isSymbolicLink() || !stat.isFile() || stat.nlink !== 1
            || readFileSync(lockPath, 'utf8') !== document) fail('personal_domain_private_state_lock_compromised');
          unlinkSync(lockPath);
        } catch (error) {
          if (error?.code === 'personal_domain_private_state_lock_compromised') throw error;
          fail('personal_domain_private_state_lock_compromised');
        }
      };
    },
    load() {
      assertSupported();
      if (!existsSync(statePath)) return null;
      assertPlainFile();
      const envelope = parseEnvelope();
      let value;
      try {
        const plaintext = invoke('unprotect', Buffer.from(envelope.ciphertext, 'base64'));
        value = JSON.parse(plaintext.toString('utf8'));
        plaintext.fill(0);
      } catch (error) {
        if (error?.code) throw error;
        fail('invalid_personal_domain_private_state');
      }
      return structuredClone(value);
    },
    save(value) {
      assertSupported();
      mkdirSync(parent, { recursive: true });
      assertPlainFile();
      const plaintext = Buffer.from(JSON.stringify(value), 'utf8');
      let ciphertext;
      try { ciphertext = invoke('protect', plaintext); } finally { plaintext.fill(0); }
      const envelope = { format: FORMAT, provider: PROVIDER, scope: 'CurrentUser', core_instance_id: coreInstanceId,
        state_path_sha256: pathDigest, ciphertext: ciphertext.toString('base64'),
        saved_at: new Date(clock()).toISOString() };
      ciphertext.fill(0);
      const temporary = `${statePath}.${process.pid}.${randomUUID()}.tmp`;
      try {
        writeDurableTemporary(temporary, Buffer.from(`${JSON.stringify(envelope)}\n`, 'utf8'));
        renameSync(temporary, statePath);
      } catch (error) {
        try { if (existsSync(temporary)) unlinkSync(temporary); } catch {}
        fail(error?.code === 'EEXIST' ? 'personal_domain_private_state_path_rejected'
          : 'personal_domain_private_state_unavailable');
      }
      assertPlainFile();
    },
  });
}
