import assert from 'node:assert/strict';
import test from 'node:test';
import { copyFileSync, existsSync, readFileSync, rmSync } from 'node:fs';
import path from 'node:path';
import { scaleFixture, seedScale, SCALE_CASES, adapter } from '../test_fixtures/release_schema6/recovery/scale_fixture.mjs';
import { domainFlow } from '../test_fixtures/release_schema6/recovery/domain_flow.mjs';

test('200k authenticated domain rows: fixed floor, valid revisions and retention, rejected historical corruption',{
 timeout:1800000,
},async t=>{
 const f=scaleFixture(t),small=f.floorBytes();
 const counts=seedScale(f,SCALE_CASES.capacity);
 const flow=domainFlow(f.mutate);flow.submit('create');
 f.seal();const large=f.floorBytes();
 assert.ok(large<65536,'floor must remain bounded well below its 4 MiB limit');
 assert.ok(large-small<16384,'record count cannot create linear floor growth');
 const head=JSON.parse(readFileSync(path.join(f.o.custodyDirectory,'current-head.json')));
 const witness=JSON.parse(readFileSync(path.join(f.o.custodyDirectory,head.custodySha256+'.floor.json'))).progressWitness.domainRecords;
 assert.deepEqual(Object.keys(witness).sort(),['count','format','maxRevision','sha256']);
 assert.equal(witness.count,SCALE_CASES.capacity.records+1);assert.equal(witness.maxRevision,1);
 assert.match(witness.sha256,/^[a-f0-9]{64}$/);
 const old=f.mutate(db=>db.prepare('SELECT * FROM domain_records WHERE id=?').get(flow.id));
 flow.submit('patch',1);flow.submit('delete',2);assert.equal(f.recover().ok,true);
 flow.retention();assert.equal(f.recover().ok,true);f.seal();
 assert.equal(f.mutate(db=>db.prepare('SELECT revision FROM domain_records WHERE id=?').get(flow.id).revision),4);
 const stable=path.join(f.root,'stable.sqlite');copyFileSync(f.o.databasePath,stable);
 const cases=[
  ['old-row',db=>db.prepare('UPDATE domain_records SET revision=?,envelope_json=?,body_json=? WHERE id=?').run(old.revision,old.envelope_json,old.body_json,flow.id)],
  ['revision',db=>db.prepare('UPDATE domain_records SET revision=revision+1 WHERE id=?').run('scale-record-1')],
  ['body',db=>db.prepare('UPDATE domain_records SET body_json=? WHERE id=?').run('{"data":{"title":"tampered"}}','scale-record-1')],
  ['missing-row',db=>db.prepare('DELETE FROM domain_records WHERE id=?').run('scale-record-1')],
  ['old-prefix',db=>db.exec("UPDATE change_events SET payload_json='{}' WHERE server_sequence=1")],
  ['device-foreign-key',db=>{
   assert.ok(db.prepare('SELECT MAX(rowid) AS n FROM domain_records').get().n>=100000,'the real parallel witness path must be selected');
   assert.equal(db.prepare('SELECT device_id FROM devices WHERE device_id=?').get('scale-device').device_id,'scale-device');
   db.exec('PRAGMA foreign_keys=OFF');
   assert.equal(db.prepare('DELETE FROM devices WHERE device_id=?').run('scale-device').changes,1);
   const violations=db.prepare('PRAGMA foreign_key_check').all();
   assert.equal(violations.length,SCALE_CASES.capacity.messages);
   assert.ok(violations.every(row=>row.table==='chat_messages'&&row.parent==='devices'));
  }],
 ];
 const rejected=[];
 for(const [kind,mutate] of cases){
  copyFileSync(stable,f.o.databasePath);const pending=path.join(f.state,adapter.RECOVERY_PENDING);if(existsSync(pending))rmSync(pending);
  f.mutate(mutate);
  if(kind==='device-foreign-key'){
   const headBefore=readFileSync(path.join(f.o.custodyDirectory,'current-head.json'));
   assert.throws(()=>f.seal(),error=>error.code==='database_integrity_failed');
   assert.deepEqual(readFileSync(path.join(f.o.custodyDirectory,'current-head.json')),headBefore);
  }
  let code=null;try{f.recover();}catch(error){code=error.code??error.message;}
  assert.ok(code,'corruption must reject: '+kind);
  if(kind==='device-foreign-key')assert.equal(code,'database_integrity_failed');
  else assert.match(code,/^(domain_|recovery_history_diverged)/);
  rejected.push({kind,code});
 }
 t.diagnostic(JSON.stringify({counts,smallFloorBytes:small,largeFloorBytes:large,rejected,rssBytes:process.memoryUsage().rss}));
});
