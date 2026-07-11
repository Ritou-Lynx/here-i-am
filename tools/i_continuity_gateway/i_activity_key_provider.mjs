import { createHash, randomBytes } from 'node:crypto';
import {
  closeSync,
  existsSync,
  fsyncSync,
  linkSync,
  mkdirSync,
  openSync,
  readFileSync,
  unlinkSync,
  writeSync,
} from 'node:fs';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

const ENTROPY_CONTEXT = 'i-continuity-gateway/activity-dek/v1';
const DPAPI_SCRIPT = String.raw`
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
$inputStream = [Console]::OpenStandardInput()
$memory = New-Object System.IO.MemoryStream
$inputStream.CopyTo($memory)
$inputBytes = $memory.ToArray()
$entropy = [System.Text.Encoding]::UTF8.GetBytes('i-continuity-gateway/activity-dek/v1')
if ($env:I_DPAPI_OPERATION -eq 'protect') {
  $outputBytes = [System.Security.Cryptography.ProtectedData]::Protect(
    $inputBytes, $entropy, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
} elseif ($env:I_DPAPI_OPERATION -eq 'unprotect') {
  $outputBytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
    $inputBytes, $entropy, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
} else {
  throw 'Unsupported DPAPI operation'
}
$outputStream = [Console]::OpenStandardOutput()
$outputStream.Write($outputBytes, 0, $outputBytes.Length)
$outputStream.Flush()
`;

function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

function writeDurable(path, content) {
  const handle = openSync(path, 'wx', 0o600);
  try {
    writeSync(handle, content);
    fsyncSync(handle);
  } finally {
    closeSync(handle);
  }
}

function defaultPowerShellPath(environment) {
  const systemRoot = environment.SystemRoot || environment.SYSTEMROOT;
  if (!systemRoot) return null;
  return join(systemRoot, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe');
}

export function createIActivityKeyProvider({
  iHome,
  platform = process.platform,
  environment = process.env,
  spawnProvider = spawnSync,
  randomBytesProvider = randomBytes,
  powershellPath = defaultPowerShellPath(environment),
} = {}) {
  if (!iHome) throw new Error('iHome is required for the activity key provider');
  const keysRoot = resolve(iHome, 'keys');
  const keyPath = join(keysRoot, 'activity-dek-v1.dpapi.json');
  let cached = null;

  function assertSupported() {
    if (platform !== 'win32') {
      throw new Error('encrypted activity is unavailable on this platform; no plaintext fallback is allowed');
    }
    if (!powershellPath || !existsSync(powershellPath)) {
      throw new Error('encrypted activity requires Windows PowerShell for DPAPI key protection');
    }
  }

  function invokeDpapi(operation, input) {
    assertSupported();
    const encodedCommand = Buffer.from(DPAPI_SCRIPT, 'utf16le').toString('base64');
    const result = spawnProvider(powershellPath, [
      '-NoLogo',
      '-NoProfile',
      '-NonInteractive',
      '-EncodedCommand',
      encodedCommand,
    ], {
      input,
      env: { ...environment, I_DPAPI_OPERATION: operation },
      windowsHide: true,
      timeout: 10000,
      maxBuffer: 1024 * 1024,
      encoding: null,
    });
    if (result.error || result.status !== 0 || !Buffer.isBuffer(result.stdout) || result.stdout.length === 0) {
      throw new Error(`Windows DPAPI ${operation} failed; encrypted activity remains unavailable`);
    }
    return Buffer.from(result.stdout);
  }

  function parseRecord() {
    let parsed;
    try {
      parsed = JSON.parse(readFileSync(keyPath, 'utf8').replace(/^\uFEFF/, ''));
    } catch {
      throw new Error('activity encryption key record is invalid');
    }
    if (parsed?.schema_version !== 1 || parsed.provider !== 'windows-dpapi' ||
        parsed.scope !== 'CurrentUser' || parsed.entropy_context !== ENTROPY_CONTEXT ||
        !/^[a-zA-Z0-9._-]{8,96}$/.test(String(parsed.key_id || '')) ||
        !/^[A-Za-z0-9+/]+={0,2}$/.test(String(parsed.wrapped_dek || '')) ||
        !/^[a-f0-9]{64}$/.test(String(parsed.key_check_sha256 || ''))) {
      throw new Error('activity encryption key record is invalid');
    }
    return parsed;
  }

  function loadKey() {
    if (cached) return cached;
    if (!existsSync(keyPath)) return null;
    const record = parseRecord();
    const key = invokeDpapi('unprotect', Buffer.from(record.wrapped_dek, 'base64'));
    if (key.length !== 32 || sha256(key) !== record.key_check_sha256) {
      throw new Error('activity encryption key could not be verified');
    }
    cached = { key, keyId: record.key_id };
    return cached;
  }

  function loadOrCreateKey() {
    const existing = loadKey();
    if (existing) return existing;
    assertSupported();
    mkdirSync(keysRoot, { recursive: true });
    const key = Buffer.from(randomBytesProvider(32));
    if (key.length !== 32) throw new Error('activity key generator did not return 32 bytes');
    const keyId = `activity-dek-${sha256(key).slice(0, 20)}`;
    const wrapped = invokeDpapi('protect', key);
    const record = {
      schema_version: 1,
      key_id: keyId,
      provider: 'windows-dpapi',
      scope: 'CurrentUser',
      entropy_context: ENTROPY_CONTEXT,
      wrapped_dek: wrapped.toString('base64'),
      key_check_sha256: sha256(key),
      created_at: new Date().toISOString(),
    };
    const tempPath = `${keyPath}.${process.pid}.${Date.now()}.tmp`;
    try {
      writeDurable(tempPath, `${JSON.stringify(record, null, 2)}\n`);
      try {
        linkSync(tempPath, keyPath);
      } catch (error) {
        if (error?.code !== 'EEXIST') throw error;
        return loadKey();
      }
    } finally {
      if (existsSync(tempPath)) {
        try { unlinkSync(tempPath); } catch { /* A later initialization can clean the temp file. */ }
      }
    }
    cached = { key, keyId };
    return cached;
  }

  return {
    keyPath,
    isSupported: platform === 'win32' && Boolean(powershellPath && existsSync(powershellPath)),
    hasKey: () => existsSync(keyPath),
    loadKey,
    loadOrCreateKey,
  };
}
