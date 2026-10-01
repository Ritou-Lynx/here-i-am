import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, lstatSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// This package deliberately freezes the pre-MDA schema-v4 implementation.
export const BASELINE = 'bbb8025d99fc0acaa846d58b4e5a94cef90f8756';
export const NODE_SHA256 = '58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f';
export const SOURCE_FILES = [
  'i_core_server.mjs', 'i_core_store.mjs', 'shortcut_mail_relay.mjs',
  'send_shortcut_mail.ps1', 'strict_smtp_tls_validation.ps1', 'start_i_core_service.ps1',
].map(name => `tools/i_core/${name}`);
const here = path.dirname(fileURLToPath(import.meta.url));
const sha = bytes => createHash('sha256').update(bytes).digest('hex');

function plainPath(target) {
  let current = path.resolve(target);
  for (;;) {
    if (existsSync(current) && lstatSync(current).isSymbolicLink()) {
      throw new Error('Release and runtime paths must not contain symlinks or junctions.');
    }
    const parent = path.dirname(current);
    if (parent === current) break;
    current = parent;
  }
  // isSymbolicLink also catches junctions, but Windows has other reparse types.
  // Encode only the path data; never interpolate it as executable PowerShell.
  const encodedPath = Buffer.from(path.resolve(target), 'utf8').toString('base64');
  const command = `
$ErrorActionPreference = 'Stop'
$current = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${encodedPath}'))
while ($current) {
  try {
    $attributes = [IO.File]::GetAttributes($current)
    if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Reparse point rejected.' }
  } catch [IO.FileNotFoundException] { } catch [IO.DirectoryNotFoundException] { }
  $parent = [IO.Directory]::GetParent($current)
  $current = if ($null -eq $parent) { $null } else { $parent.FullName }
}`;
  const powershell = path.join(process.env.SystemRoot ?? 'C:\\Windows', 'System32/WindowsPowerShell/v1.0/powershell.exe');
  execFileSync(powershell, ['-NoProfile', '-NonInteractive', '-EncodedCommand', Buffer.from(command, 'utf16le').toString('base64')], {
    windowsHide: true, timeout: 20_000, stdio: ['ignore', 'pipe', 'pipe'],
  });
}

export function prepareRuntimePin({ repository, output, nodePath }) {
  if (process.platform !== 'win32') throw new Error('This release is for the verified Windows runtime only.');
  for (const value of [repository, output, nodePath]) {
    if (!value || !path.isAbsolute(value)) throw new Error('All paths must be explicit and absolute.');
  }
  plainPath(output);
  plainPath(nodePath);
  if (existsSync(output)) throw new Error('Output must be a new release directory; never overwrite a release.');
  const nodeBytes = readFileSync(nodePath);
  if (sha(nodeBytes) !== NODE_SHA256) throw new Error('Node binary differs from the verified v24.14.1 runtime.');
  const source = SOURCE_FILES.map(name => {
    const ref = `${BASELINE}:${name}`;
    const bytes = execFileSync('git', ['-C', repository, 'show', ref], { windowsHide: true });
    const blob = execFileSync('git', ['-C', repository, 'rev-parse', ref], { encoding: 'utf8', windowsHide: true }).trim();
    return { name, bytes, blob };
  });
  const wrappers = ['start_pinned_i_core.ps1', 'verify_v4_state.mjs'].map(name => ({ name, bytes: readFileSync(path.join(here, name)) }));
  const files = [];
  const put = (name, bytes, blob) => {
    const destination = path.join(output, name);
    mkdirSync(path.dirname(destination), { recursive: true });
    writeFileSync(destination, bytes, { flag: 'wx' });
    files.push({ path: name, sha256: sha(bytes), bytes: bytes.length, ...(blob ? { source_blob: blob } : {}) });
  };
  for (const item of source) put(item.name, item.bytes, item.blob);
  for (const wrapper of wrappers) put(wrapper.name, wrapper.bytes);
  put('runtime/node.exe', nodeBytes);
  const manifest = {
    format: 'i-core-runtime-pin-v1', release: 'v4-bbb8025d', source_commit: BASELINE,
    core_schema_version: 4, node_version: 'v24.14.1', files,
    state_policy: 'External existing state only; no state, config, tokens or credentials are packaged.',
    platform_dependency: 'Windows PowerShell 5.1 and Windows DPAPI remain host-maintained.',
  };
  const bytes = Buffer.from(JSON.stringify(manifest, null, 2) + '\n');
  writeFileSync(path.join(output, 'manifest.json'), bytes, { flag: 'wx' });
  return { release: output, manifest_sha256: sha(bytes), source_commit: BASELINE, files: files.length };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [repository, output, nodePath, ...extra] = process.argv.slice(2);
  if (extra.length) throw new Error('Usage: prepare_runtime_pin.mjs <absolute-repository> <new-absolute-output> <absolute-node.exe>');
  console.log(JSON.stringify(prepareRuntimePin({ repository, output, nodePath }), null, 2));
}
