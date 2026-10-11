import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, lstatSync, mkdirSync, readFileSync, readdirSync, realpathSync, writeFileSync } from 'node:fs';
import path from 'node:path';

export const PINNED_NODE_SHA256 = '58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f';
export const SOURCES = Object.freeze([
  'activity_control_plane.mjs', 'domain_http.mjs', 'domain_store.mjs',
  'domain_schema.mjs', 'domain_migrate.mjs', 'i_core_server.mjs', 'i_core_store.mjs',
  'personal_data_domains.mjs', 'inspection_read_only.mjs', 'shortcut_mail_relay.mjs', 'send_shortcut_mail.ps1',
  'strict_smtp_tls_validation.ps1',
].map(name => `tools/i_core/${name}`));
export const WRAPPERS = Object.freeze([
  'package.mjs', 'preflight.mjs', 'cli.mjs', 'preflight_schema6.ps1', 'README.md',
  'recovery_adapter.mjs', 'readonly_witness.mjs', 'recovery_witness_worker.mjs', 'backup_bundle.mjs', 'backup_bundle_schema6.ps1',
  'automatic_recovery.mjs', 'raw_state_backup.mjs', 'package_switch.mjs',
  'backup_key_child.mjs', 'key_custody.ps1', 'restore_inspection.mjs',
  'portable_key_custody.mjs', 'automatic_backup.mjs', 'backup_effects.mjs', 'custody_inventory.mjs', 'due_inventory.mjs', 'export_backup_tasks.ps1', 'lifecycle/backup_native.cs', 'lifecycle/backup_evidence.cs', 'lifecycle/backup_owned_artifacts.ps1', 'portable_backup_schema6.ps1', 'scheduler_once_schema6.ps1',
  'lifecycle/start_schema6.ps1', 'lifecycle/owned_job.ps1',
  'lifecycle/job_guardian.ps1', 'lifecycle/protected_paths.ps1',
  'lifecycle/request_stop.ps1', 'lifecycle/runtime_child.mjs',
  'lifecycle/common.mjs', 'lifecycle/configuration.mjs',
  'lifecycle/offline_lease.mjs', 'lifecycle/probe_offline.ps1',
  'lifecycle/offline_probe_client.mjs',
  'lifecycle/session_window.ps1', 'lifecycle/login_schema6.ps1',
  'lifecycle/prepare_login_schema6.ps1', 'lifecycle/mcp_configuration.ps1',
]);
export const ASSEMBLY_DEPENDENCIES = Object.freeze([
  "tools/i_core/maintenance/activation-preflight.mjs" ,
  "tools/i_core/maintenance/close-schema6-session.ps1" ,
  "tools/i_core/maintenance/owned_artifacts.ps1" ,
  "tools/i_core/maintenance/p4/evidence-context-r09.mjs" ,
  "tools/i_core/maintenance/p4/evidence-contract-r08.mjs" ,
  "tools/i_core/maintenance/p4/evidence-parent-bridge-r09.mjs" ,
  "tools/i_core/maintenance/p4/p4-bounded-transport-r05.mjs" ,
  "tools/i_core/maintenance/p4/p4-health-policy-dormant-r01.mjs" ,
  "tools/i_core/maintenance/p4/p4-pinned-entry-r04.mjs" ,
  "tools/i_core/maintenance/p4/transport-endpoints-r04.json" ,
  "tools/i_core/maintenance/process_image_binding.ps1" ,
  "tools/i_core/maintenance/register_task_primitives.ps1" ,
  "tools/i_core/maintenance/task_security_policy.ps1" ,
  "tools/i_core/release_schema6/lifecycle/continuous-activation-entry.ps1" ,
  "tools/i_core/release_schema6/lifecycle/continuous-activation.ps1" ,
  "tools/i_core/release_schema6/lifecycle/evidence-native.ps1" ,
  "tools/i_core/release_schema6/lifecycle/evidence-pinned-launch.ps1" ,
  "tools/i_core/release_schema6/lifecycle/fresh-identity-native.ps1" ,
  "tools/i_core/release_schema6/lifecycle/identity-activation-proof.ps1" ,
  "tools/i_core/release_schema6/lifecycle/identity-native.cs" ,
  "tools/i_core/release_schema6/lifecycle/identity-sampler.ps1" ,
  "tools/i_core/release_schema6/lifecycle/p3-permit-library.ps1" ,
  "tools/i_core/release_schema6/lifecycle/p3-permit-producer.ps1" ,
  "tools/i_core/release_schema6/lifecycle/p4-backup-total-gate.ps1" ,
  "tools/i_core/release_schema6/lifecycle/recovery-p4-cleanup.ps1" ,
  "tools/i_core/release_schema6/lifecycle/recovery-p4-entry.ps1" ,
  "tools/i_core/release_schema6/lifecycle/recovery-p4-helper.ps1" ,
  "tools/i_core/release_schema6/lifecycle/task-caller-context.ps1" ,
  "tools/i_core/release_schema6/lifecycle/task-instance-projection.ps1" ,
  "tools/i_core/release_schema6/lifecycle/task-two-slot-evaluator.ps1"
]);
export const INVENTORY = Object.freeze([
  ...SOURCES, ...WRAPPERS.map(name => `tools/i_core/release_schema6/${name}`), ...ASSEMBLY_DEPENDENCIES, 'runtime/node.exe',
].sort());
export const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
export class ReleaseError extends Error { constructor(code) { super(code); this.code = code; } }
export const fail = code => { throw new ReleaseError(code); };
export function plainPath(filename, { missing = false } = {}) {
  if (typeof filename !== 'string' || !path.isAbsolute(filename) || path.normalize(filename) !== filename
      || filename.includes(':', 2)) fail('plain_absolute_path_required');
  for (let current = filename;; current = path.dirname(current)) {
    if (existsSync(current)) {
      const stat = lstatSync(current);
      if (stat.isSymbolicLink() || (stat.isFile() && stat.nlink !== 1)) fail('linked_path_rejected');
    }
    if (path.dirname(current) === current) break;
  }
  if (!missing && (!existsSync(filename) || realpathSync.native(filename).toLowerCase() !== filename.toLowerCase())) fail('input_missing_or_aliased');
  return filename;
}
export function cleanEnvironment(env = process.env) {
  // Allow only operating-system plumbing. No inherited Node, Core, model, proxy,
  // pairing, grant, domain, activity, relay, or PowerShell module configuration.
  const allowed = new Set(['SYSTEMROOT', 'WINDIR', 'TEMP', 'TMP', 'COMSPEC']);
  const clean = Object.fromEntries(Object.entries(env).filter(([key]) => allowed.has(key.toUpperCase())));
  // Native Windows PowerShell needs a fixed executable extension list. Never
  // inherit a caller-supplied PATHEXT or silently skip a pinned .exe invocation.
  if (process.platform === 'win32') clean.PATHEXT = '.EXE';
  return clean;
}
function files(root, relative = '') {
  return readdirSync(path.join(root, relative), { withFileTypes: true }).flatMap(entry => {
    const name = relative ? `${relative}/${entry.name}` : entry.name;
    plainPath(path.join(root, name));
    if (entry.isDirectory()) return files(root, name);
    if (!entry.isFile()) fail('inventory_invalid');
    return [name];
  }).sort();
}
function validateImports(content) {
  const known = new Set(INVENTORY);
  for (const [name, bytes] of content) {
    if (!name.endsWith('.mjs') || !known.has(name)) continue;
    const source = bytes.toString('utf8');
    // Core dependencies are static. The two fixed wrappers load only modules
    // inside a release that was already verified against its external anchor.
    if (SOURCES.includes(name) && /\bimport\s*\(|\brequire\s*\(/.test(source)) fail('dynamic_dependency_requires_review');
    for (const match of source.matchAll(/\bfrom\s+['"]([^'"]+)['"]|\bimport\s+['"]([^'"]+)['"]/g)) {
      const dependency = match[1] ?? match[2];
      if (dependency.startsWith('node:')) continue;
      if (!dependency.startsWith('.') || !known.has(path.posix.normalize(path.posix.join(path.posix.dirname(name), dependency)))) fail('unlisted_runtime_dependency');
    }
  }
}
export function verifyInventory(release, expectedManifestHash) {
  plainPath(release);
  if (!/^[a-f0-9]{64}$/.test(expectedManifestHash ?? '')) fail('manifest_anchor_required');
  const raw = readFileSync(plainPath(path.join(release, 'manifest.json')));
  if (sha256(raw) !== expectedManifestHash) fail('manifest_hash_mismatch');
  const manifest = JSON.parse(raw);
  if (manifest.format !== 'i-core-schema6-preflight-candidate-v1' || !/^[a-f0-9]{40}$/.test(manifest.source_commit ?? '')
      || manifest.core_commit !== manifest.source_commit || manifest.wrapper_commit !== manifest.source_commit
      || manifest.core_schema_version !== 6 || manifest.runtime_profile !== 'schema6-owned-lifecycle-v1'
      || manifest.activation_supported !== false
      || manifest.policy?.companion_upload_mode !== 'legacy_b3' || manifest.policy?.companion_reply_jobs !== false
      || manifest.policy?.activity_enabled !== false || manifest.policy?.domain_policy !== 'owner_managed'
      || Object.keys(manifest.policy ?? {}).sort().join(',') !== 'activity_enabled,companion_reply_jobs,companion_upload_mode,domain_policy'
      || JSON.stringify(manifest.files?.map(file => file.path).sort()) !== JSON.stringify(INVENTORY)
      || JSON.stringify(files(release)) !== JSON.stringify([...INVENTORY, 'manifest.json'].sort())) fail('manifest_contract_mismatch');
  verifyOverlayProvenance(manifest);
  for (const file of manifest.files) {
    const bytes = readFileSync(plainPath(path.join(release, file.path)));
    if (bytes.length !== file.bytes || sha256(bytes) !== file.sha256) fail('release_file_changed');
  }
  validateImports(new Map(manifest.files.filter(file=>file.path.endsWith('.mjs')).map(file=>[file.path,readFileSync(plainPath(path.join(release,file.path)))])));
  return { manifest, manifest_sha256: expectedManifestHash };
}
export function verifyRelease(release, expectedManifestHash) {
  const { manifest } = verifyInventory(release, expectedManifestHash);
  if (manifest.pinned_node_sha256 !== PINNED_NODE_SHA256 || manifest.node_version !== 'v24.14.1'
      || manifest.files.find(file => file.path === 'runtime/node.exe').sha256 !== PINNED_NODE_SHA256) fail('node_hash_mismatch');
  return { manifest_sha256: expectedManifestHash, source_commit: manifest.source_commit,
    files: INVENTORY.length, candidate_only: true, deployed: false, activation_supported: false };
}
export function readCommittedSources({ repository, gitPath, sourceCommit = 'HEAD' }) {
  plainPath(repository); plainPath(gitPath);
  if (sourceCommit !== 'HEAD' && !/^[a-f0-9]{40}$/.test(sourceCommit ?? '')) fail('source_commit_required');
  const gitOptions = { windowsHide: true, env: cleanEnvironment(), maxBuffer: 4 * 1024 * 1024 };
  const resolvedCommit = execFileSync(gitPath, ['-C', repository, 'rev-parse', '--verify', sourceCommit + '^{commit}'], gitOptions).toString('utf8').trim();
  if (!/^[a-f0-9]{40}$/.test(resolvedCommit)) fail('source_commit_unresolved');
  const content = new Map();
  for (const name of [...SOURCES, ...WRAPPERS.map(name => 'tools/i_core/release_schema6/' + name)]) {
    content.set(name, execFileSync(gitPath, ['-C', repository, 'show', resolvedCommit + ':' + name], gitOptions));
  }
  validateImports(content);
  return { resolvedCommit, content };
}
export function prepareRelease() { fail('private_overlay_assembly_required'); }
export function inventoryDigest(files) {
  return sha256(Buffer.from(JSON.stringify(files.map(({path,bytes,sha256})=>({path,bytes,sha256})).sort((a,b)=>a.path<b.path?-1:a.path>b.path?1:0))));
}
export function verifyOverlayProvenance(manifest) {
  if(manifest.source_tree_kind!=='private-candidate-overlay-v1'
      ||manifest.base_checkout_context_only!==true
      ||manifest.base_checkout_commit!==manifest.source_commit
      ||!/^[a-f0-9]{40}$/.test(manifest.base_checkout_commit??'')
      ||manifest.actual_files!==INVENTORY.length
      ||manifest.candidate_inventory_sha256!==inventoryDigest(manifest.files)
      ||!['base_frozen_source_inventory_sha256','source_patch_sha256','dependency_inventory_sha256'].every(k=>/^[a-f0-9]{64}$/.test(manifest[k]??'')))
    fail('overlay_provenance_mismatch');
  const names=new Set();
  for(const file of manifest.files){
    if(Object.keys(file).sort().join(',')!=='bytes,path,sha256'||!Number.isSafeInteger(file.bytes)||file.bytes<0
       ||!/^[a-f0-9]{64}$/.test(file.sha256??'')||names.has(file.path))fail('overlay_inventory_mismatch');
    names.add(file.path);
  }
}
export function createOverlayManifest(input) {
  if(Object.keys(input).sort().join(',')!=='baseCheckoutCommit,baseFrozenSourceInventorySha256,dependencyInventorySha256,files,sourcePatchSha256')
    fail('overlay_input_fields');
  const files=input.files.map(({path,bytes,sha256})=>({path,bytes,sha256})).sort((a,b)=>a.path<b.path?-1:a.path>b.path?1:0);
  if(JSON.stringify(files.map(x=>x.path))!==JSON.stringify(INVENTORY))fail('overlay_input_inventory');
  const m={
    format:'i-core-schema6-preflight-candidate-v1',source_commit:input.baseCheckoutCommit,core_commit:input.baseCheckoutCommit,wrapper_commit:input.baseCheckoutCommit,
    source_tree_kind:'private-candidate-overlay-v1',base_checkout_commit:input.baseCheckoutCommit,base_checkout_context_only:true,
    base_frozen_source_inventory_sha256:input.baseFrozenSourceInventorySha256,source_patch_sha256:input.sourcePatchSha256,
    dependency_inventory_sha256:input.dependencyInventorySha256,candidate_inventory_sha256:inventoryDigest(files),actual_files:files.length,
    core_schema_version:6,runtime_profile:'schema6-owned-lifecycle-v1',pinned_node_sha256:PINNED_NODE_SHA256,node_version:'v24.14.1',
    policy:{companion_upload_mode:'legacy_b3',companion_reply_jobs:false,activity_enabled:false,domain_policy:'owner_managed'},
    activation_supported:false,files
  };
  verifyOverlayProvenance(m);
  return Buffer.from(JSON.stringify(m,null,2)+'\n');
}
