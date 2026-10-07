import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { existsSync, readFileSync, statSync } from 'node:fs';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { sha256 } from '../../../release_schema6/package.mjs';
import { scaleFixture, seedScale, SCALE_CASES, startCore, safeClose, killSyntheticWriter, nextStartup, dailyBackup, seconds } from './scale_fixture.mjs';

// Run only after the fixed-size witness repair is present. The explicit CLI
// acknowledgement keeps preparation from accidentally starting a benchmark.
// Counts are N chat_messages PLUS N change_events, never their combined count.
// Adapter mode excludes Windows launcher, guardian, Job and named-pipe costs.
// Native mode includes the unchanged fixed production lifecycle and OS costs.
assert.ok(process.argv.includes('--witness-ready'),'explicit --witness-ready required');
const mode=process.argv.includes('--adapter')?'adapter':'native';
const sourceSha256=sha256(readFileSync(new URL('../../../release_schema6/recovery_adapter.mjs',import.meta.url)));
const names=process.argv.filter(x=>Object.hasOwn(SCALE_CASES,x));
assert.ok(names.length,'choose ten, fifty or capacity');
let phase='setup',phaseStart=performance.now(),failureEvidence=null,failureSeconds=null;
try {
for(const name of names){
 phase='setup';phaseStart=performance.now();failureEvidence=null;failureSeconds=null;
 const setup=performance.now(),size=SCALE_CASES[name];
 if(mode==='adapter'){
  const f=scaleFixture();
  try {
   const counts=seedScale(f,size),setupSeconds=seconds(setup),core=await startCore(f);
   const closeSeconds=await safeClose(f,core),floorBytes=f.floorBytes();
   await killSyntheticWriter(f);const restored=await nextStartup(f);await safeClose(f,restored.core);
   const backup=await dailyBackup(f);
   console.log(JSON.stringify({mode,name,sourceSha256,counts,setupSeconds,closeSeconds,recoverySeconds:restored.seconds,floorBytes,backup,rssBytes:process.memoryUsage().rss,peakRssBytes:process.resourceUsage().maxRSS*1024,osLifecycleIncluded:false}));
  } finally {f.cleanup();}
 } else {
  assert.equal(process.platform,'win32','native benchmark needs Windows');
  const {createRuntimeLab,cleanReceipt,until}=await import('../../../release_schema6/lifecycle/test-fixture.mjs');
  const callbacks=[],t={after:fn=>callbacks.push(fn),diagnostic:()=>{}};
  const l=await createRuntimeLab(t);let active;
  try {
   assert.equal(sha256(readFileSync(path.join(l.release,'tools/i_core/release_schema6/recovery_adapter.mjs'))),sourceSha256,'synthetic release source changed during packaging');
   active=l.launch({initial:true});const initial=await active.ready();
   const databasePath=path.join(l.state,'i-core.sqlite');
   const mutate=fn=>{const db=new DatabaseSync(databasePath);try{return fn(db);}finally{db.close();}};
   const nodeId=mutate(db=>db.prepare("SELECT value FROM core_metadata WHERE key='node_id'").get().value);
   const f={root:l.root,state:l.state,release:l.release,nodeId,mutate,o:{databasePath,custodyDirectory:path.join(l.root,'custody'),backupKey:randomBytes(32)}};
   const counts=seedScale(f,size),setupSeconds=seconds(setup);
   const seededDatabaseBytes=statSync(databasePath).size,seededWalBytes=existsSync(databasePath+'-wal')?statSync(databasePath+'-wal').size:0;
   if(process.argv.includes('--daily-only')){
    phase='daily_backup';phaseStart=performance.now();const backup=await dailyBackup(f);
    active.stop();await active.wait();cleanReceipt(active);l.completed=true;
    console.log(JSON.stringify({mode,name,sourceSha256,manifestSha256:l.manifestHash,counts,setupSeconds,dailyOnly:true,backup,backupOsSchedulingIncluded:false}));
    continue;
   }
   phase='safe_close';phaseStart=performance.now();let begin=phaseStart;const closeWall=Date.now();
   active.stop();const requestAckSeconds=seconds(begin);await active.wait();failureEvidence={exitCode:active.exit,errorCode:active.read('child.json')?.error_code??null};cleanReceipt(active);const closeSeconds=seconds(begin);
   const head=JSON.parse(readFileSync(path.join(f.o.custodyDirectory,'current-head.json'))),floorBytes=readFileSync(path.join(f.o.custodyDirectory,head.custodySha256+'.floor.json')).length;
   const closedDatabaseBytes=statSync(databasePath).size;
   const closeTimeline={requestAckSeconds,...Object.fromEntries(['child','guardian','supervisor'].map(label=>{const filename=path.join(active.control,label+'.json');return [label+'ReceiptSeconds',existsSync(filename)?Number(((statSync(filename).mtimeMs-closeWall)/1000).toFixed(3)):null];})),floorCommittedSeconds:Number(((statSync(path.join(f.o.custodyDirectory,head.custodySha256+'.floor.json')).mtimeMs-closeWall)/1000).toFixed(3))};
   console.log(JSON.stringify({phase:'safe_close',mode,name,sourceSha256,manifestSha256:l.manifestHash,counts,closeSeconds,closeTimeline,seededDatabaseBytes,seededWalBytes,closedDatabaseBytes,floorBytes,overTenSeconds:closeSeconds>10}));
   active=l.launch();const ready=await active.ready();assert.equal(initial.health.schema_version,6);
   mutate(db=>db.prepare('INSERT INTO core_metadata(key,value) VALUES(?,?)').run('synthetic_scale_committed','yes'));
   process.kill(ready.pid);await active.wait();
   await until(()=>{try{process.kill(active.read('guardian-ready.json').pid,0);return false;}catch{return true;}},20000);
   phase='next_startup';phaseStart=performance.now();begin=phaseStart;active=l.launch();const recovered=await active.ready();const recoverySeconds=seconds(begin);
   console.log(JSON.stringify({phase:'next_startup',mode,name,recoverySeconds,sourceSha256,manifestSha256:l.manifestHash}));
   assert.equal(recovered.health.schema_version,6);assert.equal(mutate(db=>db.prepare("SELECT value FROM core_metadata WHERE key='synthetic_scale_committed'").get().value),'yes');
   phase='daily_backup';phaseStart=performance.now();const backup=await dailyBackup(f);
   active.stop();await active.wait();cleanReceipt(active);l.completed=closeSeconds<=10;
   console.log(JSON.stringify({mode,name,sourceSha256,manifestSha256:l.manifestHash,counts,setupSeconds,closeSeconds,closeTimeline,recoverySeconds,floorBytes,backup,harnessRssBytes:process.memoryUsage().rss,harnessPeakRssBytes:process.resourceUsage().maxRSS*1024,osLifecycleIncluded:true,backupOsSchedulingIncluded:false,artifactsRetained:!l.completed}));
  } catch(error){
   failureSeconds=seconds(phaseStart);
   try{failureEvidence={exitCode:active?.exit??null,errorCode:active?.read('child.json')?.error_code??null};}catch{}
   throw error;
  } finally {for(const fn of callbacks.reverse())await fn();}
 }
}
} catch(error){
 const candidate=error.code??error.message;
 console.error(JSON.stringify({mode,sourceSha256,phase,phaseSeconds:failureSeconds??seconds(phaseStart),failureEvidence,ok:false,code:/^[A-Za-z0-9_]+$/.test(candidate??'')?candidate:'benchmark_failed'}));
 process.exitCode=1;
}
