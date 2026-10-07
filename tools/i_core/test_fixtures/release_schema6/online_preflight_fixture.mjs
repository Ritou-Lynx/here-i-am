import assert from 'node:assert/strict';
import {fork,spawnSync} from 'node:child_process';
import {once} from 'node:events';
import {existsSync,lstatSync,mkdirSync,readFileSync,realpathSync,rmSync,writeFileSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {DatabaseSync} from 'node:sqlite';
import {ICoreStore} from '../../i_core_store.mjs';
import {rollbackActivitySchema} from '../../activity_control_plane.mjs';
import {digest} from '../../release_schema6/preflight.mjs';
import {cleanEnvironment,plainPath,prepareRelease,sha256,verifyRelease} from '../../release_schema6/package.mjs';
import {syntheticRoot,syntheticFixedNode} from './synthetic_paths.mjs';

const allowed=cleanEnvironment(process.env);for(const key of Object.keys(process.env))if(!(key in allowed))delete process.env[key];
const repository=path.resolve(fileURLToPath(new URL('../../../../',import.meta.url)));
const adapter=fileURLToPath(new URL('../../maintenance/precutover_validate_copy.mjs',import.meta.url));
const writer=fileURLToPath(new URL('./online_preflight_writer.mjs',import.meta.url));
const quote=s=>"'"+s.replaceAll("'","''")+"'";
function seed(root,missingGrant){
  const databasePath=path.join(root,'synthetic-core.sqlite'),approvalsPath=path.join(root,'approvals.json'),grantsPath=path.join(root,'grants.json');
  const store=new ICoreStore(databasePath,{activityEnabled:false,companionUploadMode:'legacy_b3',companionReplyJobsEnabled:false});
  const token=store.pairDevice({device_id:'synthetic-phone',display_name:'Synthetic',platform:'android',client_version:'test',capabilities:[]},'synthetic-code').device_token;
  const records=[];
  const messages=Array.from({length:72},(_,index)=>{
    const incoming={sync_id:`synthetic-${index}`,origin_device_id:'synthetic-phone',origin_sequence:index,character_id:'i',sender:'user',content:`synthetic body ${index}`,created_at_ms:1700000000000+index,message_type:'chat',asset_refs:[],addenda:[]};
    const existing={...incoming,origin_device_id:'v3-history-0123456789abcdef0123',origin_sequence:index+1,created_at_ms:incoming.created_at_ms+123,addenda:[{kind:'historical_import',source:'hereiam_v3'}]};
    records.push({sync_id:incoming.sync_id,device_id:incoming.origin_device_id,origin_sequence:incoming.origin_sequence,incoming_digest:digest(incoming),existing_digest:digest(existing)});return existing;
  });
  store.importMessages('v3-history-0123456789abcdef0123',messages);
  const approved={version:1,approved_replays:records};
  store.db.prepare('INSERT INTO core_metadata(key,value) VALUES(?,?)').run('historical_replay_approvals_v1',JSON.stringify(approved));store.close();
  const db=new DatabaseSync(databasePath);try{db.exec('PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode=DELETE');rollbackActivitySchema(db);assert.equal(db.prepare("SELECT value FROM core_metadata WHERE key='schema_version'").get().value,'4');}finally{db.close();}
  writeFileSync(approvalsPath,JSON.stringify(approved));
  writeFileSync(grantsPath,JSON.stringify({version:1,grants:missingGrant?[]:[{device_id:'synthetic-phone',character_id:'i',credential_sha256:sha256(token),from_created_at_ms:1700000000000}]}));
  return {databasePath,approvalsPath,grantsPath};
}
function observe(filename){return ['','-wal','-shm'].map(suffix=>{
  const target=filename+suffix;if(!existsSync(target))return {exists:false};plainPath(target);
  const st=lstatSync(target,{bigint:true}),bytes=readFileSync(target);
  return {exists:true,size:Number(st.size),dev:String(st.dev),ino:String(st.ino),sha256:sha256(bytes),bytes};
});}
function brief({bytes,...meta}){return meta;}
async function message(child,type){return new Promise((resolve,reject)=>{
  const timer=setTimeout(()=>finish(new Error('fixture IPC timeout')),10000);
  const msg=m=>{if(m.type===type)finish(null,m);};const exit=(c,s)=>finish(new Error(`fixture exited ${c}/${s}`));
  function finish(e,v){clearTimeout(timer);child.off('message',msg);child.off('exit',exit);e?reject(e):resolve(v);}
  child.on('message',msg);child.once('exit',exit);
});}
async function status(child){const pending=message(child,'status');child.send('status');return pending;}
async function kill(child){if(child.exitCode!==null||child.signalCode!==null)return;const exited=once(child,'exit');child.kill('SIGKILL');await exited;}
function inspectVersion(filename,immutable=false){const db=new DatabaseSync(pathToFileURL(filename).href+'?mode=ro'+(immutable?'&immutable=1':''),{readOnly:true});try{return {version:db.prepare("SELECT value FROM core_metadata WHERE key='schema_version'").get().value,activityTables:db.prepare("SELECT count(*) AS n FROM sqlite_master WHERE name LIKE 'activity_%' OR name LIKE 'domain_%'").get().n,messages:db.prepare('SELECT count(*) AS n FROM chat_messages').get().n};}finally{db.close();}}
export async function runCase({mode,gitPath,releaseDirectory,manifestSha256}){
  assert.equal(process.platform,'win32','production fixed Node/ACL adapter integration runs on Windows only');
  assert.ok(['direct','missing-grant','cli'].includes(mode));
  const root=syntheticRoot('schema6-online-preflight-'),rootStat=lstatSync(root);let child;
  try{
    if(!releaseDirectory){releaseDirectory=path.join(root,'release');const node=syntheticFixedNode(root);manifestSha256=prepareRelease({repository,output:releaseDirectory,nodePath:node,gitPath,sourceCommit:'HEAD'}).manifest_sha256;}
    const verified=verifyRelease(releaseDirectory,manifestSha256);
    const sourceDirectory=path.join(root,'source');mkdirSync(sourceDirectory);
    const source=seed(sourceDirectory,mode==='missing-grant'),outputDirectory=path.join(root,'output');mkdirSync(outputDirectory);
    const protect=path.join(releaseDirectory,'tools','i_core','release_schema6','lifecycle','protected_paths.ps1');
    const ps=path.join(process.env.SystemRoot,'System32','WindowsPowerShell','v1.0','powershell.exe');
    const protection=spawnSync(ps,['-NoProfile','-NonInteractive','-Command',"$ErrorActionPreference='Stop'; . "+quote(protect)+'; Protect-NewDirectory '+quote(outputDirectory)],{env:cleanEnvironment(),windowsHide:true,encoding:'utf8',timeout:15000});
    assert.equal(protection.status,0,protection.stderr);
    const config={releaseDirectory,manifestSha256,...source,outputDirectory};
    child=fork(writer,[root,source.databasePath],{execPath:process.execPath,execArgv:[],env:cleanEnvironment(),cwd:root,windowsHide:true,stdio:['ignore','ignore','pipe','ipc']});
    const ready=await message(child,'ready');assert.notEqual(ready.pid,process.pid);assert.equal(ready.sealed,true);assert.equal(ready.sqlCallsAfterReady,0);
    const beforeStatus=await status(child),before=observe(source.databasePath);assert.ok(before[1].exists&&before[1].size>32);
    const externalBefore=[source.approvalsPath,source.grantsPath].map(p=>sha256(readFileSync(p)));
    let report,rejected=null;
    if(mode==='cli'){
      const configPath=path.join(root,'fixture-config.json');writeFileSync(configPath,JSON.stringify(config));
      const cli=spawnSync(process.execPath,[adapter,'--config',configPath],{env:cleanEnvironment(),cwd:root,windowsHide:true,encoding:'utf8',timeout:45000,maxBuffer:1024*1024});
      assert.equal(cli.error,undefined);assert.equal(cli.status,0,cli.stderr);const stdout=JSON.parse(cli.stdout);assert.equal(stdout.passed,true);assert.equal(stdout.exact_bindings,72);assert.equal(stdout.grants,1);assert.equal(stdout.deployed,false);
      report=JSON.parse(readFileSync(path.join(outputDirectory,'precutover-validation-receipt.json'),'utf8'));
    }else{
      const {validatePrecutoverCopy}=await import(pathToFileURL(adapter).href);
      if(mode==='missing-grant'){
        await assert.rejects(validatePrecutoverCopy(config),error=>{rejected=error.code;return error.code==='nonempty_grants_required';});
        report=JSON.parse(readFileSync(path.join(outputDirectory,'precutover-validation-rejected.json'),'utf8'));
        assert.equal(report.passed,false);assert.equal(existsSync(path.join(outputDirectory,'precutover-validation-receipt.json')),false);
      }else report=await validatePrecutoverCopy(config);
    }
    // Measure first. Inspecting source schema below is itself another WAL read.
    const after=observe(source.databasePath),afterStatus=await status(child);
    assert.deepEqual(beforeStatus,afterStatus);assert.equal(child.exitCode,null);assert.equal(child.signalCode,null);
    for(const n of [0,1])assert.deepEqual(brief(after[n]),brief(before[n]),'source DB/WAL changed');
    assert.equal(after[2].exists,true);assert.equal(after[2].size,before[2].size);assert.equal(after[2].dev,before[2].dev);assert.equal(after[2].ino,before[2].ino);
    const changed=[];for(let i=0;i<before[2].bytes.length;i++)if(before[2].bytes[i]!==after[2].bytes[i])changed.push(i);
    assert.ok(changed.length>0);assert.ok(changed.every(i=>i>=100&&i<120));assert.equal(report.rawStable,true);assert.equal(typeof report.comparison_policy,'string');
    assert.deepEqual([source.approvalsPath,source.grantsPath].map(p=>sha256(readFileSync(p))),externalBefore);
    const original=inspectVersion(source.databasePath);assert.deepEqual(original,{version:'4',activityTables:0,messages:72});
    const captured=inspectVersion(path.join(outputDirectory,'source-schema4.sqlite'),true);assert.deepEqual(captured,original);
    const migrated=inspectVersion(path.join(outputDirectory,'preflight-schema5.sqlite'),true);assert.equal(migrated.version,'5');assert.ok(migrated.activityTables>0);assert.equal(migrated.messages,72);
    assert.equal(report.legacyDigestVerified,true);assert.equal(report.sourceCopyUnchanged,true);
    if(mode!=='missing-grant'){assert.equal(report.passed,true);assert.equal(report.preflight.preflight_passed,true);assert.equal(report.preflight.exact_bindings,72);assert.equal(report.preflight.grants,1);assert.equal(report.externalSourcesUnchanged,true);assert.equal(report.preflight.services_started,0);}
    return {mode,passed:true,sourceCommit:verified.source_commit,fixedReleaseCapture:true,writerAliveAfter:true,sqlCallsAfterReady:afterStatus.sqlCallsAfterReady,sourceSchema:original.version,capturedSchema:captured.version,migratedSchema:migrated.version,originalDbWalStable:true,shmChangedOffsets:changed,rejected,exactBindings:report.preflight?.exact_bindings??null,grants:report.preflight?.grants??null};
  }finally{if(child)await kill(child);plainPath(root);const st=lstatSync(root);assert.equal(realpathSync.native(root),root);assert.equal(st.dev,rootStat.dev);assert.equal(st.ino,rootStat.ino);assert.match(path.basename(root),/^schema6-online-preflight-/);rmSync(root,{recursive:true,force:true});}
}
if(process.argv[1]===fileURLToPath(import.meta.url))process.stdout.write(JSON.stringify(await runCase(JSON.parse(process.argv[2])))+'\n');
