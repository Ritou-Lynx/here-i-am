import assert from 'node:assert/strict';
import { mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { sha256 } from '../package.mjs';
import { closedStateSnapshot, stateDigest, validatePrevious, MARKER, LOCK } from './common.mjs';
import { adapter, raw, scaleFixture } from '../../test_fixtures/release_schema6/recovery/scale_fixture.mjs';
import { assertOfflineLease, syntheticLease } from '../../test_fixtures/release_schema6/recovery/synthetic_lease.mjs';

test('closed snapshot preserves the previous sorted inventory digest and only excludes root marker/lock',t=>{
 const f=scaleFixture(t),nested=path.join(f.state,'nested');mkdirSync(nested);
 writeFileSync(path.join(f.state,'grants.json'),'synthetic grant');
 writeFileSync(path.join(nested,MARKER),'nested marker is state');
 writeFileSync(path.join(nested,LOCK),'nested lock is state');
 writeFileSync(path.join(nested,'z.json'),'nested payload');
 const digest=name=>sha256(readFileSync(path.join(f.state,...name.split('/'))));
 // Golden ordered inventory uses the old whole-buffer hashing contract,
 // independently of the new streaming walk and stateDigest wrapper.
 const entries=[['grants.json',digest('grants.json')],['i-core.sqlite',digest('i-core.sqlite')],['nested/',null],
  ['nested/'+MARKER,digest('nested/'+MARKER)],['nested/'+LOCK,digest('nested/'+LOCK)],['nested/z.json',digest('nested/z.json')]];
 const expected=sha256(JSON.stringify(entries)),snapshot=closedStateSnapshot(f.state);
 assert.deepEqual(snapshot,{stateTreeSha256:expected,databaseSha256:digest('i-core.sqlite')});
 assert.equal(stateDigest(f.state),expected);
 for(const name of [MARKER,LOCK])writeFileSync(path.join(f.state,name),'excluded synthetic control');
 assert.deepEqual(closedStateSnapshot(f.state),snapshot);
 writeFileSync(path.join(nested,MARKER),'changed nested marker');
 assert.notEqual(stateDigest(f.state),expected);
});

test('a closed snapshot reads current database bytes and cannot cache a later database modification',t=>{
 const f=scaleFixture(t),before=closedStateSnapshot(f.state),saved={...before};
 assert.equal(before.databaseSha256,raw.rawFileHash(f.o.databasePath));
 f.mutate(db=>db.prepare('INSERT INTO core_metadata(key,value) VALUES(?,?)').run('synthetic_snapshot_change','changed'));
 const after=closedStateSnapshot(f.state);
 assert.notEqual(after.databaseSha256,before.databaseSha256);
 assert.notEqual(after.stateTreeSha256,before.stateTreeSha256);
 assert.equal(after.databaseSha256,raw.rawFileHash(f.o.databasePath));
 assert.deepEqual(before,saved);
});

test('an earlier close snapshot cannot hide later non-database state changes from restart validation',t=>{
 const f=scaleFixture(t),grant=path.join(f.state,'grants.json');writeFileSync(grant,'synthetic grant');
 const snapshot=closedStateSnapshot(f.state),config={state:f.state,manifest_sha256:'a'.repeat(64)},configurationHash='b'.repeat(64);
 const before={database_sha256:snapshot.databaseSha256,nodeId:f.nodeId};
 const marker={format:'schema6-lifecycle-v1',phase:'clean_closed',database_path:f.o.databasePath,
  database_sha256:before.database_sha256,node_id:f.nodeId,manifest_sha256:config.manifest_sha256,
  configuration_sha256:configurationHash,state_tree_sha256:snapshot.stateTreeSha256,custody_sha256:'c'.repeat(64),
  supervisor:{job_empty_confirmed:true,child_exit_code:0,guardian_exit_code:0,termination_requested:false}};
 assert.equal(validatePrevious(marker,config,before,configurationHash),marker);
 writeFileSync(grant,'changed synthetic grant');
 assert.equal(closedStateSnapshot(f.state).databaseSha256,snapshot.databaseSha256);
 assert.notEqual(stateDigest(f.state),snapshot.stateTreeSha256);
 assert.throws(()=>validatePrevious(marker,config,before,configurationHash),/recovery_required/);
});

test('database modification after floor persistence is rejected by final SHA before head advances',t=>{
 const f=scaleFixture(t),headPath=path.join(f.o.custodyDirectory,'current-head.json');
 const beforeHead=readFileSync(headPath),beforeHash=raw.rawFileHash(f.o.databasePath);
 const beforeFloors=readdirSync(f.o.custodyDirectory).filter(name=>name.endsWith('.floor.json')).length;
 f.setLease();
 const evidence=assertOfflineLease(f.o.supervisorLease,{databasePath:f.o.databasePath,phase:'synthetic_test_snapshot'});
 let modifications=0;
 f.o.supervisorLease=syntheticLease(evidence,phase=>{
  if(phase==='after_custody_write'){
   modifications++;
   // Inject precisely at the post-floor proof; the final full-file hash must
   // still reject this change before the independent head can advance.
   f.mutate(db=>db.prepare('INSERT INTO core_metadata(key,value) VALUES(?,?)').run('synthetic_after_floor','changed'));
  }
 });
 assert.throws(()=>adapter.sealClosedRecovery(f.o),/database_changed_during_inspection/);
 assert.equal(modifications,1);
 assert.notEqual(raw.rawFileHash(f.o.databasePath),beforeHash);
 assert.deepEqual(readFileSync(headPath),beforeHead);
 assert.equal(readdirSync(f.o.custodyDirectory).filter(name=>name.endsWith('.floor.json')).length,beforeFloors+1);
});
