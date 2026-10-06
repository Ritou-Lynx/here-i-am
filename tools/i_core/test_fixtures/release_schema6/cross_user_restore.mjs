// Synthetic CI fixture only. Secrets arrive exclusively on stdin, never argv.
import assert from 'node:assert/strict';
import { createHash, randomBytes } from 'node:crypto';
import { copyFileSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { DatabaseSync } from 'node:sqlite';

const sha = b => createHash('sha256').update(b).digest('hex');
const json = p => JSON.parse(readFileSync(p, 'utf8'));
const write = (p, v) => writeFileSync(p, JSON.stringify(v), {flag:'wx',mode:0o600});
const [mode, productionRoot, workspace] = process.argv.slice(2);
let password, phase='input';
try {
  assert.equal(process.argv.length, 5);
  assert.ok(['factory','restore'].includes(mode));
  const chunks=[];let length=0;
  for await (const chunk of process.stdin) {length+=chunk.length;assert.ok(length<=48);chunks.push(chunk);}
  password=Buffer.concat(chunks);for(const c of chunks)c.fill(0);
  assert.equal(password.length,48);
  const load = name => import(pathToFileURL(path.join(productionRoot,'tools/i_core',name)));
  if(mode==='restore') {
    const transport=json(path.join(workspace,'transport.json'));
    for(const file of transport.files) {
      assert.match(file.name,/^[a-zA-Z0-9_./-]+$/);assert.ok(!file.name.split('/').includes('..'));
      assert.equal(sha(readFileSync(path.join(workspace,file.name))),file.sha256);
    }
    assert.equal(sha(readFileSync(process.execPath)),transport.nodeSha256);
  }
  phase='module_load';
  const backup=await load('release_schema6/backup_bundle.mjs');
  const portable=await load('release_schema6/portable_key_custody.mjs');
  let summary;
  if(mode==='factory') {
    phase='factory_runtime';const pkg=await load('release_schema6/package.mjs');
    assert.equal(process.version,'v24.14.1');
    assert.equal(sha(readFileSync(process.execPath)),pkg.PINNED_NODE_SHA256);
    phase='factory_source';const source=path.join(workspace,'source'),transfer=path.join(workspace,'transfer');
    mkdirSync(source);backup.backupFilePrimitives.protect(source);mkdirSync(transfer);
    const oldRelease=path.join(source,'old-release');mkdirSync(oldRelease);
    const dbPath=path.join(source,'synthetic.sqlite'),db=new DatabaseSync(dbPath);
    try {
      db.exec('CREATE TABLE core_metadata(key TEXT PRIMARY KEY,value TEXT); CREATE TABLE devices(device_id TEXT PRIMARY KEY,token_hash TEXT); CREATE TABLE synthetic_rows(payload BLOB,body TEXT,n INTEGER,optional TEXT);');
      const put=db.prepare('INSERT INTO core_metadata VALUES (?,?)');
      for(const [k,v] of [['schema_version','4'],['node_id','cross-user-synthetic-node'],['cursor_secret',randomBytes(32).toString('base64url')]])put.run(k,v);
      db.prepare('INSERT INTO devices VALUES (?,?)').run('synthetic-device',sha(randomBytes(32)));
      const putRow=db.prepare('INSERT INTO synthetic_rows VALUES (?,?,?,?)');
      putRow.run(Buffer.from([0,255]),'synthetic only',9007199254740993n,null);
      putRow.run(Buffer.from([1]),'duplicate',-3n,'');putRow.run(Buffer.from([1]),'duplicate',-3n,'');
    } finally {db.close();}
    const entries=[];
    const add=(role,name,source_path)=>entries.push({role,name,source_path,sha256:sha(readFileSync(source_path))});
    add('database','data/core.sqlite',dbPath);
    const manifest=path.join(oldRelease,'manifest.json');write(manifest,{synthetic:true});add('release','manifest.json',manifest);
    for(const role of backup.BACKUP_ROLES.filter(r=>!['database','release'].includes(r))) {
      const file=path.join(source,role+'.json');
      write(file,role==='recovery_custody'?{format:'i-core-recovery-custody-v1',mode:'initial_schema4',node_id:'cross-user-synthetic-node',database_path:dbPath}:{synthetic:true,role});
      add(role,'inputs/'+role+'.json',file);
    }
    const spec={format:'i-core-runtime-backup-spec-v1',source_schema:4,node_id:'cross-user-synthetic-node',canonical_database_path:dbPath,old_release_root:oldRelease,old_release_manifest_sha256:entries[1].sha256,entries};
    const key=randomBytes(32);
    try {
      phase='factory_archive';const report=backup.createRuntimeBackup({spec,key,outputDirectory:path.join(workspace,'archive')});
      const envelope=portable.wrapBackupKey({key,password,backupSetId:sha(randomBytes(32))});
      const binding=portable.bindPortableArtifact({key,envelope,report});
      const payload=path.join(transfer,'payload');mkdirSync(payload);
      copyFileSync(report.artifactPath,path.join(payload,'archive.aes256gcm'));
      write(path.join(payload,'envelope.json'),envelope);write(path.join(payload,'binding.json'),binding);
      write(path.join(payload,'expected.json'),report.databaseInspection);
      phase='factory_copy';const files=[];
      const record=name=>files.push({name,sha256:sha(readFileSync(path.join(transfer,name)))});
      for(const name of pkg.INVENTORY) {
        const relative='runtime/'+name,target=path.join(transfer,relative);mkdirSync(path.dirname(target),{recursive:true});
        copyFileSync(name==='runtime/node.exe'?process.execPath:path.join(productionRoot,name),target);record(relative);
      }
      for(const n of ['archive.aes256gcm','envelope.json','binding.json','expected.json'])record('payload/'+n);
      write(path.join(transfer,'transport.json'),{files,nodeSha256:pkg.PINNED_NODE_SHA256});
      summary={factoryVerified:true,transportSha256:sha(readFileSync(path.join(transfer,'transport.json'))),artifactSha256:report.artifactSha256,databaseFingerprintSha256:report.databaseInspection.dataSha256,tableCount:report.databaseInspection.tables.length,deviceCount:report.databaseInspection.devices.count};
    } finally {key.fill(0);}
  } else {
    phase='restore';const payload=path.join(workspace,'payload'),expected=json(path.join(payload,'expected.json'));
    const report=await portable.restorePortableBackupForInspection({envelope:json(path.join(payload,'envelope.json')),password,binding:json(path.join(payload,'binding.json')),artifactPath:path.join(payload,'archive.aes256gcm'),outputDirectory:path.join(workspace,'inspection')});
    assert.deepEqual(report.databaseInspection,expected);
    assert.equal(report.passwordOnly,true);assert.equal(report.dpapiUsed,false);
    assert.equal(report.inspectionOnly,true);assert.equal(report.activation_supported,false);
    assert.equal(report.coreHealth.mode,'inspection_read_only');assert.equal(report.coreHealth.immutable,true);
    assert.equal(report.deniedRoutes.length,5);assert.ok(report.deniedRoutes.every(r=>r.status===403));
    assert.equal(report.databaseBytesUnchanged,true);assert.equal(report.sidecarsAbsent,true);
    summary={restored:true,passwordOnly:true,dpapiUsed:false,inspectionOnly:true,activationSupported:false,realCoreVerified:true,deniedRouteCount:5,databaseBytesUnchanged:true,sidecarsAbsent:true,nodeSha256:expected.nodeIdSha256,schemaVersion:expected.schemaVersion,deviceCount:expected.devices.count,devicesSha256:expected.devices.sha256,tableCount:expected.tables.length,rowCount:expected.tables.reduce((n,t)=>n+t.rows,0),allTablesSha256:sha(JSON.stringify(expected.tables)),databaseFingerprintSha256:expected.dataSha256};
  }
  summary.inputByteCount=password.length;summary.binaryInputExact=password.length===48;
  process.stdout.write(JSON.stringify(summary)+'\n');
} catch(error) {process.stderr.write(JSON.stringify({fixtureRejected:true,phase,errorCodeSha256:sha(String(error.code??error.name))})+'\n');process.exitCode=2;}
finally {password?.fill(0);}
