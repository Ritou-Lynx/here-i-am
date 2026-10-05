import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, lstatSync, mkdirSync, readFileSync, readdirSync, realpathSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// Same accepted source bytes, addressed through the public sanitized history.
export const BASELINE = 'f605d5017cbc0a8eb69983e00c25cd1bba08a0eb';
export const NODE_SHA256 = '58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f';
export const SOURCES = Object.freeze({
  'tools/i_core/i_core_server.mjs': '7d22539e0af4fb9bcdea276dfcabea3d8af8985bb96c855aacce35de9bede679',
  'tools/i_core/i_core_store.mjs': '883a35c128ee88f7689b737de2245ef073f0c6b96902385241f30c08eb8f816d',
  'tools/i_core/shortcut_mail_relay.mjs': '841756bb88cee7eb406e9dd682e8eb547dc3c144d7bb8c1e68659e3c55cf9185',
  'tools/i_core/send_shortcut_mail.ps1': '0766737642349896379d545a22ca974ef0933ef514261ab9079642fc35d70919',
  'tools/i_core/strict_smtp_tls_validation.ps1': '395e1c810f186a4136ad8b16ee4734e32322a4ba8064508f034ee0f21b6812ed',
  'tools/i_core/activity_control_plane.mjs': '525295357490814c69fb204358e019f862e916c09efc5f5ff85b99043f83f222',
});
export const CANDIDATE_ID = 'i-core-r3-sanitized-f605d501';
export const SOURCE_MODE = 'sanitized-fixed-source-baseline';
export const SOURCE_PROVENANCE = Object.freeze({
  baseline_commit: BASELINE,
  source_normalization: 'none; exact sanitized Git blobs',
  m3_patch_sha256: '4e81ee2c036b22d62875477a4f7aa77a1a98aa508569f8baf2c9a0d869d9bef8',
  m3_verification_sha256: '9fa6e9d41503747e8c91837b9ef96e4127b9eefd6245b7d0f79e349f9d280b81',
  files: Object.freeze(Object.entries(SOURCES).map(([name, sha256]) => Object.freeze({
    path: name, sha256, original_sha256: sha256, origin: 'sanitized-baseline-git',
  }))),
});
export const WRAPPERS = Object.freeze(['package.mjs', 'start_schema5.ps1', 'owned_job.ps1', 'runtime_child.mjs', 'configuration.mjs', 'protected_paths.ps1', 'request_stop.ps1', 'job_guardian.ps1']);
export const INVENTORY = Object.freeze([...Object.keys(SOURCES), ...WRAPPERS, 'verify_v4_state.mjs', 'runtime/node.exe'].sort());
export const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
export function cleanEnvironment(env = process.env) {
  const clean = Object.fromEntries(Object.entries(env).filter(([key]) => !key.toUpperCase().startsWith('I_CORE_')
    && !['NODE_OPTIONS', 'NODE_PATH', 'NODE_EXTRA_CA_CERTS', 'OPENSSL_CONF', 'SSL_CERT_FILE', 'SSL_CERT_DIR', 'PSMODULEPATH'].includes(key.toUpperCase())));
  // A Windows PowerShell 5.1 child must not autoload inherited PowerShell 7 modules.
  if (process.platform === 'win32') clean.PSModulePath = path.join(process.env.SystemRoot, 'System32/WindowsPowerShell/v1.0/Modules');
  return clean;
}
export function plainPath(target, { existing = true } = {}) {
  if (typeof target !== 'string' || !/^[A-Za-z]:[\\/]/.test(target)
      || path.normalize(target).toLowerCase() !== target.replaceAll('/', '\\').toLowerCase()
      || target.includes(':', 2)) throw new Error('canonical_absolute_path_required');
  for (let current = target;; current = path.dirname(current)) {
    try {
      const stat = lstatSync(current);
      if (stat.isSymbolicLink() || (stat.isFile() && stat.nlink !== 1)) throw new Error('linked_path_rejected');
    } catch (error) { if (error.code !== 'ENOENT') throw error; }
    if (path.dirname(current) === current) break;
  }
  if (existing && realpathSync.native(target).toLowerCase() !== path.normalize(target).toLowerCase()) throw new Error('canonical_absolute_path_required');
  return target;
}
export function separatePaths(...paths) {
  const values = paths.map(p => plainPath(p).toLowerCase().replace(/[\\/]+$/, ''));
  for (let i = 0; i < values.length; i++) for (let j = 0; j < values.length; j++) {
    if (i !== j && (values[i] === values[j] || values[i].startsWith(values[j] + '\\'))) throw new Error('paths_must_be_separate');
  }
}
export function assertNode(node = process.execPath) {
  plainPath(node);
  if (process.platform !== 'win32' || sha256(readFileSync(node)) !== NODE_SHA256) throw new Error('node_fingerprint_mismatch');
}
function filesIn(root, relative = '') {
  return readdirSync(path.join(root, relative), { withFileTypes: true }).flatMap(entry => {
    const name = relative ? `${relative}/${entry.name}` : entry.name;
    plainPath(path.join(root, name));
    if (entry.isDirectory()) {
      const result = filesIn(root, name);
      if (!result.length) throw new Error('release_inventory_mismatch');
      return result;
    }
    if (!entry.isFile()) throw new Error('release_inventory_mismatch');
    return [name];
  }).sort();
}
export function verifyRelease(release, manifestHash) {
  plainPath(release);
  plainPath(path.join(release, 'manifest.json'));
  const raw = readFileSync(path.join(release, 'manifest.json'));
  if (!/^[a-f0-9]{64}$/.test(manifestHash ?? '') || sha256(raw) !== manifestHash) throw new Error('manifest_fingerprint_mismatch');
  const manifest = JSON.parse(raw);
  if (manifest.candidate_id !== CANDIDATE_ID || manifest.source_mode !== SOURCE_MODE
      || JSON.stringify(manifest.source_provenance) !== JSON.stringify(SOURCE_PROVENANCE)
      || manifest.format !== 'i-core-schema5-candidate-r3' || manifest.source_commit !== BASELINE
      || manifest.core_schema_version !== 5 || manifest.node_sha256 !== NODE_SHA256 || manifest.node_version !== 'v24.14.1'
      || JSON.stringify(manifest.files?.map(f => f.path).sort()) !== JSON.stringify(INVENTORY)) throw new Error('manifest_contract_mismatch');
  if (JSON.stringify(filesIn(release)) !== JSON.stringify([...INVENTORY, 'manifest.json'].sort())) throw new Error('release_inventory_mismatch');
  for (const file of manifest.files) {
    const bytes = readFileSync(path.join(release, file.path));
    if (bytes.length !== file.bytes || sha256(bytes) !== file.sha256
        || (SOURCES[file.path] && SOURCES[file.path] !== file.sha256)
        || (file.path === 'runtime/node.exe' && file.sha256 !== NODE_SHA256)) throw new Error('release_content_mismatch');
  }
  return { status: 'verified_only', source_commit: BASELINE, manifest_sha256: manifestHash, node_sha256: NODE_SHA256,
    files: INVENTORY.length, state_opened: false, services_started: 0, runtime_deployed: false };
}
export function prepareRelease({ repository, output, nodePath = process.execPath }) {
  assertNode(nodePath);
  plainPath(repository); plainPath(output, { existing: false });
  if (existsSync(output)) throw new Error('new_release_required');
  const here = path.dirname(fileURLToPath(import.meta.url));
  const content = new Map();
  for (const [name, hash] of Object.entries(SOURCES)) {
    const bytes = execFileSync('git', ['-C', repository, 'show', `${BASELINE}:${name}`],
        { windowsHide: true, timeout: 20000, env: cleanEnvironment(), maxBuffer: 4 * 1024 * 1024 });
    if (sha256(bytes) !== hash) throw new Error('accepted_source_mismatch');
    content.set(name, bytes);
  }
  for (const name of WRAPPERS) { plainPath(path.join(here, name)); content.set(name, readFileSync(path.join(here, name))); }
  content.set('verify_v4_state.mjs', execFileSync('git', ['-C', repository, 'show', `${BASELINE}:tools/i_core/runtime_pin/verify_v4_state.mjs`],
    { windowsHide: true, timeout: 20000, env: cleanEnvironment() }));
  content.set('runtime/node.exe', readFileSync(nodePath));
  const files = INVENTORY.map(name => ({ path: name, bytes: content.get(name).length, sha256: sha256(content.get(name)) }));
  const manifest = Buffer.from(JSON.stringify({ format: 'i-core-schema5-candidate-r3', source_commit: BASELINE,
    candidate_id: CANDIDATE_ID, source_mode: SOURCE_MODE, source_provenance: SOURCE_PROVENANCE,
    core_schema_version: 5, node_version: 'v24.14.1', node_sha256: NODE_SHA256,
    support: 'continuous explicit-stop loopback candidate; original-path clean-close only; no production authorization', files }, null, 2) + '\n');
  mkdirSync(output);
  const quote = s => "'" + s.replaceAll("'", "''") + "'";
  execFileSync(path.join(process.env.SystemRoot, 'System32/WindowsPowerShell/v1.0/powershell.exe'),
    ['-NoProfile', '-NonInteractive', '-Command', `$ErrorActionPreference='Stop'; . ${quote(path.join(here, 'protected_paths.ps1'))}; Protect-NewDirectory ${quote(output)}`],
    { env: cleanEnvironment(), windowsHide: true, timeout: 10000 });
  for (const [name, bytes] of [...content, ['manifest.json', manifest]]) {
    mkdirSync(path.dirname(path.join(output, name)), { recursive: true });
    writeFileSync(path.join(output, name), bytes, { flag: 'wx' });
  }
  return verifyRelease(output, sha256(manifest));
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const [mode, a, b, ...rest] = process.argv.slice(2);
    if (rest.length) throw new Error('invalid_arguments');
    let result;
    if (!mode && !a && !b) { assertNode(); result = { status: 'verified_only', node_sha256: NODE_SHA256, state_opened: false, services_started: 0 }; }
    else if (mode === '--prepare' && a && b) result = prepareRelease({ repository: a, output: b });
    else if (mode === '--verify' && a && b) result = verifyRelease(a, b);
    else throw new Error('invalid_arguments');
    console.log(JSON.stringify(result));
  } catch (error) { console.error(JSON.stringify({ status: 'rejected', code: error.message })); process.exitCode = 2; }
}
