import { createHash, createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import { closeSync, existsSync, fstatSync, fsyncSync, lstatSync, mkdirSync, openSync, readSync, readdirSync, realpathSync, linkSync, writeSync, unlinkSync, rmdirSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { DatabaseSync } from 'node:sqlite';
import { assertActivityRecoveryFloorForDatabase } from '../activity_control_plane.mjs';
import { databaseInspectionFingerprint, INSPECTION_MARKER } from '../inspection_read_only.mjs';

export const BACKUP_ROLES = Object.freeze(['database', 'release', 'configuration', 'task', 'credentials', 'domain_policy', 'transcript_grants', 'replay_approvals', 'recovery_custody']);
export const BACKUP_LIMITS = Object.freeze({ files: 10000, manifest: 8 * 1024 * 1024, file: 2 * 1024 ** 3, total: 4 * 1024 ** 3, chunk: 64 * 1024, custody: 1024 * 1024 });
const MAGIC = Buffer.from('ICRUNB01'), HASH = /^[a-f0-9]{64}$/, FORMAT = 'i-core-runtime-backup-v1';
const fail = code => { const error = new Error(code); error.code = code; throw error; };
const parseJson = bytes => { try { return JSON.parse(bytes); } catch { fail('backup_json_invalid'); } };
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const eqPath = (a,b) => process.platform === 'win32' ? a.toLowerCase() === b.toLowerCase() : a === b;
const inside = (root,p) => { const r = path.relative(root,p); return !r || (!r.startsWith('..' + path.sep) && r !== '..' && !path.isAbsolute(r)); };
const exact = (o,keys) => o && typeof o === 'object' && !Array.isArray(o) && Object.keys(o).sort().join() === [...keys].sort().join();
function absolute(p) {
  if (typeof p !== 'string' || !path.isAbsolute(p) || path.normalize(p) !== p || p.includes('\0') || p.includes(':',2) || p.length > 4096) fail('plain_absolute_path_required');
  if (process.platform === 'win32' && (!/^[A-Za-z]:/.test(p) || p.charCodeAt(2) !== 92)) fail('local_drive_path_required');
  return p;
}
function safe(p, directory = false) {
  absolute(p);
  for (let current = p;; current = path.dirname(current)) {
    const s = lstatSync(current);
    if (s.isSymbolicLink() || !eqPath(realpathSync.native(current),current)) fail('linked_path_rejected');
    if (current === p ? directory ? !s.isDirectory() : !s.isFile() || s.nlink !== 1 : !s.isDirectory()) fail('unsafe_path');
    if (path.dirname(current) === current) break;
  }
  if (process.platform === 'win32' && (!/^[A-Za-z]:/.test(p) || p.charCodeAt(2) !== 92)) fail('local_drive_path_required');
  return p;
}
function identity(s) { return [s.dev,s.ino,s.size,s.mtimeNs,s.ctimeNs].map(String).join(':'); }
function sidecars(p) { for (const suffix of ['-wal','-shm','-journal']) { try { lstatSync(p + suffix); } catch(error) { if(error.code==='ENOENT') continue; throw error; } fail('database_sidecar_rejected'); } }
function scan(root) {
  const found = []; let visited = 0;
  function walk(dir, prefix = '', depth = 0) {
    if (depth > 64) fail('inventory_limit_exceeded'); safe(dir,true);
    for (const d of readdirSync(dir, { withFileTypes: true })) {
      if (++visited > BACKUP_LIMITS.files * 2) fail('inventory_limit_exceeded');
      const full = path.join(dir,d.name), name = prefix + d.name;
      if (d.isDirectory()) walk(full,name + '/',depth + 1);
      else { safe(full); found.push(name); }
    }
  }
  walk(root); return found.sort();
}
function readStable(p, consume, limit = BACKUP_LIMITS.file) {
  safe(p); const fd = openSync(p,'r');
  try {
    const before = fstatSync(fd,{bigint:true});
    if (before.nlink !== 1n || before.size > BigInt(limit)) fail('input_size_exceeded');
    const buffer = Buffer.allocUnsafe(BACKUP_LIMITS.chunk), hash = createHash('sha256'); let total = 0;
    try {
      for (;;) { const n = readSync(fd,buffer,0,buffer.length,null); if (!n) break; total += n;
        if (total > limit || BigInt(total) > before.size) fail('source_changed');
        const chunk = buffer.subarray(0,n); hash.update(chunk); consume?.(chunk);
      }
    } finally { buffer.fill(0); }
    safe(p);
    if (BigInt(total) !== before.size || identity(before) !== identity(fstatSync(fd,{bigint:true})) || identity(before) !== identity(lstatSync(p,{bigint:true}))) fail('source_changed');
    return { bytes:total, sha256:hash.digest('hex'), identity:identity(before) };
  } finally { closeSync(fd); }
}
function small(p,limit = BACKUP_LIMITS.custody) {
  const chunks = []; readStable(p,c=>chunks.push(Buffer.from(c)),limit);
  const result = Buffer.concat(chunks); for (const c of chunks) c.fill(0); return result;
}
function validName(name) {
  if (typeof name !== 'string' || name.length > 1024 || !name || name.includes('\\') || name.includes(':') || name.startsWith('/') || name.split('/').some(s=>!s || s === '.' || s === '..' || /[\x00-\x1f<>"|?*]/.test(s) || /[. ]$/.test(s) || /^(con|prn|aux|nul|com[0-9¹²³]|lpt[0-9¹²³])(?:\.|$)/i.test(s))) fail('logical_name_invalid');
}
function validate(spec, stored = false) {
  if (!exact(spec,['format','source_schema','node_id','canonical_database_path','old_release_root','old_release_manifest_sha256','entries']) || spec.format !== 'i-core-runtime-backup-spec-v1'
      || ![4,5,6].includes(spec.source_schema) || !/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(spec.node_id ?? '') || !HASH.test(spec.old_release_manifest_sha256 ?? '')
      || !Array.isArray(spec.entries) || spec.entries.length < 9 || spec.entries.length > BACKUP_LIMITS.files) fail('backup_spec_invalid');
  absolute(spec.canonical_database_path); absolute(spec.old_release_root);
  const names = new Set(), paths = new Set(); let total = 0;
  for (const e of spec.entries) {
    const keys = ['role','name','source_path','sha256']; if ('state' in e) keys.push('state'); if ('custody_context' in e) keys.push('custody_context'); if (stored) keys.push('bytes');
    if (!exact(e,keys) || !BACKUP_ROLES.includes(e.role) || !HASH.test(e.sha256 ?? '') || ('state' in e && !['present','disabled'].includes(e.state))) fail('inventory_entry_invalid');
    if ('custody_context' in e && (e.role !== 'recovery_custody' || e.custody_context !== true)) fail('custody_context_invalid');
    validName(e.name); absolute(e.source_path);
    const n = e.name.toLowerCase(), p = process.platform === 'win32' ? e.source_path.toLowerCase() : e.source_path;
    if (names.has(n) || paths.has(p)) fail('duplicate_inventory_entry'); names.add(n); paths.add(p);
    if (stored && (!Number.isSafeInteger(e.bytes) || e.bytes < 0 || (e.bytes === 0 && e.role !== 'release') || e.bytes > BACKUP_LIMITS.file || (total += e.bytes) > BACKUP_LIMITS.total)) fail('input_size_exceeded');
    if (e.role === 'release' && !eqPath(path.join(spec.old_release_root,...e.name.split('/')),e.source_path)) fail('release_path_mismatch');
  }
  if (BACKUP_ROLES.some(r=>!spec.entries.some(e=>e.role === r))) fail('inventory_role_missing');
  for (const r of ['database']) if (spec.entries.filter(e=>e.role===r).length !== 1) fail('singleton_role_required');
  const custody = spec.entries.filter(e=>e.role==='recovery_custody');
  if(custody.length>1 && custody.filter(e=>e.custody_context===true).length!==1) fail('custody_context_required');
  const database = spec.entries.find(e=>e.role==='database');
  if (!eqPath(database.source_path,spec.canonical_database_path) || database.state === 'disabled') fail('database_binding_mismatch');
  const manifest = spec.entries.find(e=>e.role==='release' && e.name==='manifest.json');
  if (!manifest || manifest.sha256 !== spec.old_release_manifest_sha256) fail('old_manifest_anchor_mismatch');
  return spec;
}
function checkRelease(spec) {
  const expected = spec.entries.filter(e=>e.role==='release').map(e=>e.name).sort();
  if (JSON.stringify(scan(spec.old_release_root)) !== JSON.stringify(expected)) fail('release_inventory_mismatch');
}
function checkMetadata(spec,key,custody) {
  sidecars(spec.canonical_database_path); safe(spec.canonical_database_path);
  const db = new DatabaseSync(`${pathToFileURL(spec.canonical_database_path).href}?mode=ro&immutable=1`,{readOnly:true});
  try {
    if (db.prepare('PRAGMA integrity_check').get().integrity_check !== 'ok') fail('database_integrity_failed');
    const value = key=>db.prepare('SELECT value FROM core_metadata WHERE key=?').get(key)?.value;
    const secret = value('cursor_secret');
    if (value('node_id') !== spec.node_id || value('schema_version') !== String(spec.source_schema) || typeof secret !== 'string' || !secret) fail('database_metadata_mismatch');
    if (value('domain_backup_role') || db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='activity_metadata'").get() && db.prepare("SELECT value FROM activity_metadata WHERE key='database_role'").get()?.value === 'backup_read_only') fail('backup_activation_unsupported');
    if (key.equals(Buffer.from(secret,'base64url')) || key.equals(Buffer.from(secret,'hex'))) fail('independent_backup_key_required');
    if (custody.format !== 'i-core-recovery-custody-v1' || custody.node_id !== spec.node_id || custody.database_path !== spec.canonical_database_path) fail('recovery_custody_invalid');
    if (spec.source_schema === 4) {
      if (!exact(custody,['format','mode','node_id','database_path']) || custody.mode !== 'initial_schema4') fail('recovery_custody_invalid');
    } else {
      if (!exact(custody,['format','mode','node_id','database_path','activity_recovery_floor']) || custody.mode !== 'activity_floor') fail('activity_floor_required');
      assertActivityRecoveryFloorForDatabase(db,custody.activity_recovery_floor,{nodeId:spec.node_id,cursorSecret:secret});
    }
  } finally { db.close(); sidecars(spec.canonical_database_path); }
}
function keyCopy(key) { if (!(key instanceof Uint8Array) || key.length !== 32) fail('backup_key_required'); return Buffer.from(key); }
function writeAll(fd,bytes) { let offset = 0; while (offset < bytes.length) offset += writeSync(fd,bytes,offset,bytes.length-offset); }
function protect(dir) {
  if (process.platform !== 'win32') { if ((lstatSync(dir).mode & 0o077) !== 0) fail('private_output_required'); return; }
  const system = process.env.SystemRoot;
  if (!system || !path.isAbsolute(system)) fail('windows_acl_unavailable');
  const ps = path.join(system,'System32','WindowsPowerShell','v1.0','powershell.exe');
  const script = "$ErrorActionPreference='Stop'; $p=[Console]::In.ReadToEnd(); $sid=[System.Security.Principal.WindowsIdentity]::GetCurrent().User; $acl=New-Object System.Security.AccessControl.DirectorySecurity; $acl.SetOwner($sid); $acl.SetAccessRuleProtection($true,$false); foreach($s in @($sid.Value,'S-1-5-18')) { $r=New-Object System.Security.AccessControl.FileSystemAccessRule(([System.Security.Principal.SecurityIdentifier]$s),'FullControl','ContainerInherit,ObjectInherit','None','Allow'); $acl.AddAccessRule($r) }; Set-Acl -LiteralPath $p -AclObject $acl; $v=Get-Acl -LiteralPath $p; if(!$v.AreAccessRulesProtected){throw 'ACL not protected'}; foreach($r in $v.Access){if($r.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value -notin @($sid.Value,'S-1-5-18') -or $r.AccessControlType -ne 'Allow'){throw 'unexpected ACL'}}";
  execFileSync(ps,['-NoProfile','-NonInteractive','-Command',script],{input:dir,windowsHide:true,env:{SystemRoot:system,WINDIR:system},stdio:['pipe','pipe','pipe'],maxBuffer:65536});
}

// Explicit inventory evidence only. This API neither acquires writer leases nor attests production completeness.
export function createRuntimeBackup({spec,outputDirectory,key}) {
  spec = validate(parseJson(JSON.stringify(spec))); const secret = keyCopy(key); let fd, temp;
  try {
    absolute(outputDirectory); safe(path.dirname(outputDirectory),true);
    if (existsSync(outputDirectory)) fail('fresh_output_required');
    if (inside(spec.old_release_root,outputDirectory) || inside(path.dirname(spec.canonical_database_path),outputDirectory) || spec.entries.some(e=>inside(outputDirectory,e.source_path))) fail('independent_output_required');
    checkRelease(spec); sidecars(spec.canonical_database_path);
    const snapshots = []; let total = 0;
    for (const e of spec.entries) {
      const s = readStable(e.source_path); if (s.sha256 !== e.sha256) fail('external_file_hash_mismatch');
      if ((!s.bytes && e.role !== 'release') || (total += s.bytes) > BACKUP_LIMITS.total) fail('input_size_exceeded'); snapshots.push(s); e.bytes=s.bytes;
      if (e.state === 'disabled') {
        if (['database','release','recovery_custody','configuration'].includes(e.role)) fail('component_cannot_be_disabled');
        const b=small(e.source_path); let control; try { control=parseJson(b); } finally { b.fill(0); }
        if (!exact(control,['format','role','enabled','configuration_sha256']) || control.format!=='i-core-runtime-component-state-v1' || control.role!==e.role || control.enabled!==false
          || !spec.entries.some(c=>c.role==='configuration' && c.sha256===control.configuration_sha256)) fail('disabled_component_evidence_required');
      }
    }
    const custodyBytes=small(spec.entries.find(e=>e.role==='recovery_custody' && (e.custody_context===true || spec.entries.filter(c=>c.role==='recovery_custody').length===1)).source_path); let custody;
    try { custody=parseJson(custodyBytes); } finally { custodyBytes.fill(0); }
    checkMetadata(spec,secret,custody);
    const databaseInspection=databaseInspectionFingerprint(spec.canonical_database_path);
    const manifest=Buffer.from(JSON.stringify({format:FORMAT,scope:'inventory_only',production_completeness_not_attested:true,activation_supported:false,spec}));
    if (manifest.length > BACKUP_LIMITS.manifest) fail('manifest_size_exceeded');
    mkdirSync(outputDirectory,{mode:0o700}); protect(outputDirectory); safe(outputDirectory,true);
    const artifactPath=path.join(outputDirectory,'runtime.aes256gcm'); temp=path.join(outputDirectory,'.runtime.partial');
    fd=openSync(temp,'wx',0o600); const nonce=randomBytes(12), cipher=createCipheriv('aes-256-gcm',secret,nonce); cipher.setAAD(MAGIC);
    writeAll(fd,Buffer.concat([MAGIC,nonce])); const size=Buffer.alloc(4); size.writeUInt32BE(manifest.length);
    writeAll(fd,cipher.update(size)); writeAll(fd,cipher.update(manifest)); manifest.fill(0);
    for (let i=0;i<spec.entries.length;i++) {
      const e=spec.entries[i], current=readStable(e.source_path,c=>writeAll(fd,cipher.update(c)));
      if (JSON.stringify(current)!==JSON.stringify(snapshots[i])) fail('source_changed');
    }
    writeAll(fd,cipher.final()); writeAll(fd,cipher.getAuthTag()); fsyncSync(fd); closeSync(fd); fd=undefined;
    checkRelease(spec); sidecars(spec.canonical_database_path);
    for (let i=0;i<spec.entries.length;i++) if (JSON.stringify(readStable(spec.entries[i].source_path))!==JSON.stringify(snapshots[i])) fail('source_changed');
    // Atomic no-replace publication; remove the internal staging link before verification.
    if (existsSync(artifactPath)) fail('fresh_output_required'); linkSync(temp,artifactPath); unlinkSync(temp); temp=undefined;
    if (process.platform!=='win32') { const d=openSync(outputDirectory,'r'); try { fsyncSync(d); } finally { closeSync(d); } }
    const artifactSha256=readStable(artifactPath,undefined,BACKUP_LIMITS.total+BACKUP_LIMITS.manifest+40).sha256;
    const report=verifyRuntimeBackup({artifactPath,artifactSha256,key:secret});
    return {...report,artifactPath,artifactSha256,databaseInspection};
  } finally { if(fd!==undefined) closeSync(fd); if(temp && existsSync(temp)) unlinkSync(temp); secret.fill(0); }
}

// No compression, extraction, database overwrite or activation: bounded streaming verification only.
export function verifyRuntimeBackup({artifactPath,artifactSha256,key}) {
  return readRuntimeBackup({artifactPath,artifactSha256,key});
}

function readRuntimeBackup({artifactPath,artifactSha256,key}, sink = null) {
  if (!HASH.test(artifactSha256 ?? '')) fail('artifact_anchor_required'); const secret=keyCopy(key);
  let pending=Buffer.alloc(0), manifest, remaining=0, index=0, entryHash, length, manifestSha256;
  try {
    const before=readStable(artifactPath,undefined,BACKUP_LIMITS.total+BACKUP_LIMITS.manifest+40);
    if (before.sha256!==artifactSha256 || before.bytes<40) fail('artifact_hash_mismatch');
    const fd=openSync(safe(artifactPath),'r'); let header=Buffer.alloc(20), tag=Buffer.alloc(16);
    try {
      if(readSync(fd,header,0,20,0)!==20 || readSync(fd,tag,0,16,before.bytes-16)!==16 || !header.subarray(0,8).equals(MAGIC)) fail('backup_format_invalid');
    } finally { closeSync(fd); }
    const decipher=createDecipheriv('aes-256-gcm',secret,header.subarray(8)); decipher.setAAD(MAGIC); decipher.setAuthTag(tag);
    const beginEntry=()=> {
      while(index<manifest.spec.entries.length) { remaining=manifest.spec.entries[index].bytes;entryHash=createHash('sha256');sink?.begin(manifest.spec.entries[index]);if(remaining) return;if(entryHash.digest('hex')!==manifest.spec.entries[index].sha256) fail('backup_entry_hash_mismatch');sink?.end();index++; }
      remaining=0;
    };
    const accept=chunk=> {
      if (!manifest) {
        pending=Buffer.concat([pending,chunk]);
        if(length===undefined && pending.length>=4) { length=pending.readUInt32BE(0); if(length<1 || length>BACKUP_LIMITS.manifest) fail('manifest_size_exceeded'); }
        if(length===undefined || pending.length<length+4) return;
        const body=pending.subarray(4,length+4); manifestSha256=sha(body); manifest=parseJson(body.toString('utf8'));
        if(!exact(manifest,['format','scope','production_completeness_not_attested','activation_supported','spec']) || manifest.format!==FORMAT || manifest.scope!=='inventory_only' || manifest.production_completeness_not_attested!==true || manifest.activation_supported!==false) fail('backup_manifest_invalid');
        validate(manifest.spec,true); sink?.manifest(manifest.spec); const rest=Buffer.from(pending.subarray(length+4)); pending.fill(0); pending=Buffer.alloc(0); chunk=rest;
        beginEntry();
      }
      let offset=0;
      while(offset<chunk.length) {
        if(index>=manifest.spec.entries.length) fail('backup_trailing_data');
        const n=Math.min(remaining,chunk.length-offset); entryHash.update(chunk.subarray(offset,offset+n)); sink?.chunk(chunk.subarray(offset,offset+n)); remaining-=n; offset+=n;
        if(!remaining) { if(entryHash.digest('hex')!==manifest.spec.entries[index].sha256) fail('backup_entry_hash_mismatch'); sink?.end(); index++;
          beginEntry();
        }
      }
      chunk.fill(0);
    };
    let position=0;
    const after=readStable(artifactPath,c=> {
      const start=Math.max(20-position,0), end=Math.min(c.length,before.bytes-16-position);
      if(end>start) { const plaintext=decipher.update(c.subarray(start,end)); try { accept(plaintext); } finally { plaintext.fill(0); } }
      position+=c.length;
    },BACKUP_LIMITS.total+BACKUP_LIMITS.manifest+40);
    try { accept(decipher.final()); } catch(error) { if(error.code) throw error; fail('backup_authentication_failed'); }
    if(JSON.stringify(before)!==JSON.stringify(after)) fail('artifact_changed');
    if(!manifest || index!==manifest.spec.entries.length || remaining!==0) fail('backup_truncated');
    return {verified:true,scope:'inventory_only',production_completeness_not_attested:true,activation_supported:false,
      artifactSha256,inventorySha256:manifestSha256,sourceSchema:manifest.spec.source_schema,nodeId:manifest.spec.node_id,
      databasePath:manifest.spec.canonical_database_path,databaseSha256:manifest.spec.entries.find(e=>e.role==='database').sha256,
      files:manifest.spec.entries.length};
  } finally { secret.fill(0); pending.fill(0); }
}

// This only extracts an authenticated inventory into a new private inspection
// root. The caller must run the read-only Core probe before publishing a receipt.
export function extractRuntimeBackupForInspection({artifactPath,artifactSha256,key,outputDirectory}) {
  const verified=verifyRuntimeBackup({artifactPath,artifactSha256,key});
  absolute(outputDirectory); safe(path.dirname(outputDirectory),true);
  if(existsSync(outputDirectory)) fail('fresh_output_required');
  const files=[],directories=[],extracted=[]; let fd, databasePath, created=false,activeEntry;
  const clean=()=> {
    if(fd!==undefined) { closeSync(fd);fd=undefined; }
    // Delete only exact files and empty directories created by this operation;
    // never recursively traverse a destination that may have been replaced.
    for(const file of [...files].reverse()) { safe(path.dirname(file),true); if(existsSync(file)) unlinkSync(file); }
    for(const dir of [...directories].reverse()) { safe(dir,true);rmdirSync(dir); }
  };
  try {
    const report=readRuntimeBackup({artifactPath,artifactSha256,key},{
      manifest(spec) {
        if(inside(spec.old_release_root,outputDirectory) || inside(path.dirname(spec.canonical_database_path),outputDirectory)
            || inside(outputDirectory,artifactPath) || spec.entries.some(e=>inside(outputDirectory,e.source_path))) fail('independent_output_required');
        const targets=spec.entries.map(e=>path.join(outputDirectory,e.role,...e.name.split('/')));
        for(let i=0;i<targets.length;i++) {
          if(!inside(outputDirectory,targets[i]) || eqPath(outputDirectory,targets[i])) fail('inspection_path_escape');
          for(let j=0;j<i;j++) if(inside(targets[i],targets[j]) || inside(targets[j],targets[i])) fail('inspection_path_collision');
        }
        mkdirSync(outputDirectory,{mode:0o700}); created=true;directories.push(outputDirectory);protect(outputDirectory);safe(outputDirectory,true);
        const marker=path.join(outputDirectory,INSPECTION_MARKER);fd=openSync(marker,'wx',0o600);files.push(marker);
        writeAll(fd,Buffer.from(JSON.stringify({format:'i-core-inspection-root-v1',mode:'inspection_read_only',activation_supported:false,artifactSha256})));fsyncSync(fd);closeSync(fd);fd=undefined;
      },
      begin(entry) {
        activeEntry=entry;
        const target=path.join(outputDirectory,entry.role,...entry.name.split('/'));
        let current=outputDirectory;
        for(const segment of path.relative(outputDirectory,path.dirname(target)).split(path.sep).filter(Boolean)) {
          current=path.join(current,segment);if(!existsSync(current)){mkdirSync(current,{mode:0o700});directories.push(current);} safe(current,true);
        }
        safe(outputDirectory,true);fd=openSync(target,'wx',0o600);files.push(target);
        if(entry.role==='database') databasePath=target;
      },
      chunk(bytes) { writeAll(fd,bytes); },
      end() { fsyncSync(fd);closeSync(fd);fd=undefined;const target=files.at(-1);if(readStable(target).sha256!==activeEntry.sha256) fail('inspection_file_changed');extracted.push({target,sha256:activeEntry.sha256}); },
    });
    if(report.inventorySha256!==verified.inventorySha256) fail('artifact_changed');
    // An independent last digest catches replacement between authentication
    // and extraction even when the replacement's GCM tag is otherwise valid.
    if(readStable(artifactPath,undefined,BACKUP_LIMITS.total+BACKUP_LIMITS.manifest+40).sha256!==artifactSha256) fail('artifact_changed');
    for(const file of files) safe(file);
    for(const file of extracted) if(readStable(file.target).sha256!==file.sha256) fail('inspection_file_changed');
    return { ...report, databasePath, outputDirectory, cleanup:clean };
  } catch(error) { if(created) { try { clean(); } catch { error.cleanupIncomplete=true; } } throw error; }
}

export function verifyInitialRuntimeBackup({artifactPath,artifactSha256,key,databasePath,nodeId}) {
  const report=verifyRuntimeBackup({artifactPath,artifactSha256,key});
  safe(databasePath); sidecars(databasePath);
  if(report.sourceSchema!==4 || report.nodeId!==nodeId || !eqPath(report.databasePath,databasePath)) fail('initial_backup_binding_mismatch');
  const before=readStable(databasePath); if(before.sha256!==report.databaseSha256) fail('initial_backup_database_mismatch');
  const secret=keyCopy(key);
  try { checkMetadata({canonical_database_path:databasePath,node_id:nodeId,source_schema:4},secret,{format:'i-core-recovery-custody-v1',mode:'initial_schema4',node_id:nodeId,database_path:databasePath}); }
  finally { secret.fill(0); }
  if(JSON.stringify(before)!==JSON.stringify(readStable(databasePath))) fail('source_changed');
  return report;
}

// Shared strict file primitives; no change to offline source validation.
export const backupFilePrimitives = Object.freeze({ safe, readStable, small, protect, validate, checkRelease, sidecars });
