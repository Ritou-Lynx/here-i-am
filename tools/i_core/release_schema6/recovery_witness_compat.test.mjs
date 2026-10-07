import assert from 'node:assert/strict';
import { createHmac, randomUUID } from 'node:crypto';
import { existsSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { DomainStore, canonicalJSON } from '../domain_store.mjs';
import { sha256 } from './package.mjs';
import { scaleFixture, raw } from '../test_fixtures/release_schema6/recovery/scale_fixture.mjs';
import { domainFlow } from '../test_fixtures/release_schema6/recovery/domain_flow.mjs';

const encode=value=>JSON.stringify(value,(_,v)=>typeof v==='bigint'?{integer:String(v)}:v instanceof Uint8Array?{bytes:Buffer.from(v).toString('base64')}:v);
const headPath=f=>path.join(f.o.custodyDirectory,'current-head.json');
function readFloor(f){
 const head=JSON.parse(readFileSync(headPath(f)));
 return JSON.parse(readFileSync(path.join(f.o.custodyDirectory,head.custodySha256+'.floor.json')));
}

// These keys belong only to the disposable synthetic fixture. Re-signing creates
// a valid historical v1 floor/head; it does not model an attacker obtaining keys.
function installLegacyFloor(f,{withoutOperationAuthentication=false}={}){
 const {authentication:headAuth,...head}=JSON.parse(readFileSync(headPath(f)));
 const {authentication:floorAuth,...floor}=readFloor(f);
 f.mutate(db=>{
  if(withoutOperationAuthentication){
   const op=db.prepare('SELECT * FROM domain_ops').get();
   const {recovery_auth,recovery_rows,...metadata}=JSON.parse(op.op_meta_json);
   db.prepare('UPDATE domain_ops SET op_meta_json=? WHERE namespace=? AND principal_id=? AND domain=? AND op_id=?')
    .run(canonicalJSON(metadata),op.namespace,op.principal_id,op.domain,op.op_id);
  }
  floor.progressWitness.format='i-core-progress-witness-v1';
  floor.progressWitness.domainRecords=db.prepare('SELECT * FROM domain_records ORDER BY namespace,domain,id').all().map(row=>({
   namespace:row.namespace,domain:row.domain,id:row.id,revision:row.revision,rowSha256:sha256(encode(row)),
  }));
  // Reproduce the old prefix encoding, including BigInt rowids. The unsigned
  // operation case must fail on missing evidence, not a stale fixture digest.
  const old=floor.progressWitness.prefixes.find(prefix=>prefix.table==='domain_ops');
  const statement=db.prepare('SELECT rowid AS _rowid_,* FROM domain_ops WHERE rowid<=? ORDER BY rowid');
  statement.setReadBigInts(true);
  const rows=statement.all(old.cut);old.count=rows.length;old.sha256=sha256(rows.map(row=>encode(row)+'\n').join(''));
 });
 floor.databaseSha256=raw.rawFileHash(f.o.databasePath);
 const sign=body=>Buffer.from(JSON.stringify({...body,authentication:createHmac('sha256',f.o.custodyKey)
  .update('i-core-floor-custody-v1\0').update(JSON.stringify(body)).digest('hex')})+'\n');
 const floorRaw=sign(floor);head.custodySha256=sha256(floorRaw);
 writeFileSync(path.join(f.o.custodyDirectory,head.custodySha256+'.floor.json'),floorRaw,{flag:'wx'});
 const headRaw=sign(head),headSha256=sha256(headRaw);
 // Keep the authentic immediate predecessor and generation; replace only this
 // fixture's current v2 head with its v1 equivalent and matching immutable copy.
 writeFileSync(path.join(f.o.custodyDirectory,headSha256+'.head.json'),headRaw,{flag:'wx'});
 writeFileSync(headPath(f),headRaw);
 f.pin({custodySha256:head.custodySha256,headSha256});
 assert.equal(readFloor(f).progressWitness.format,'i-core-progress-witness-v1');
 assert.equal(readFloor(f).progressWitness.domainRecords.length,1);
}

function fixture(t,options){
 const f=scaleFixture(t),flow=domainFlow(f.mutate);flow.submit('create');f.seal();installLegacyFloor(f,options);
 return {f,flow};
}
function originalFiles(f){
 return Object.fromEntries(raw.RAW_SUFFIXES.map(suffix=>{
  const filename=f.o.databasePath+suffix;
  return [suffix,existsSync(filename)?{bytes:readFileSync(filename),ino:statSync(filename,{bigint:true}).ino}:null];
 }));
}
function assertRejectedWithoutReplacement(f,code){
 const before=originalFiles(f),head=readFileSync(headPath(f));
 const custody=JSON.parse(head).custodySha256,floorPath=path.join(f.o.custodyDirectory,custody+'.floor.json'),floor=readFileSync(floorPath);
 assert.throws(()=>f.recover(),error=>{assert.equal(error.code??error.message,code);return true;});
 assert.deepEqual(originalFiles(f),before);
 assert.deepEqual(readFileSync(headPath(f)),head);
 assert.deepEqual(readFileSync(floorPath),floor);
}

test('authenticated v1 row-array floor upgrades to bounded v2 and remains recoverable',t=>{
 const {f,flow}=fixture(t),before=f.mutate(db=>db.prepare('SELECT * FROM domain_records WHERE id=?').get(flow.id));
 f.seal();
 const witness=readFloor(f).progressWitness;
 assert.equal(witness.format,'i-core-progress-witness-v2');
 assert.equal(witness.domainRecords.format,'i-core-domain-record-witness-v2');
 assert.equal(Array.isArray(witness.domainRecords),false);
 assert.equal(witness.domainRecords.count,1);assert.equal(witness.domainRecords.maxRevision,1);
 assert.match(witness.domainRecords.sha256,/^[a-f0-9]{64}$/);
 assert.equal(f.recover().ok,true);
 assert.deepEqual(f.mutate(db=>db.prepare('SELECT * FROM domain_records WHERE id=?').get(flow.id)),before);
});

test('v1 row-array floor rejects changed body at the same revision without replacing originals',t=>{
 const {f,flow}=fixture(t);
 f.mutate(db=>{
  const row=db.prepare('SELECT body_json FROM domain_records WHERE id=?').get(flow.id),body=JSON.parse(row.body_json);
  body.data.title='synthetic same-revision corruption';
  db.prepare('UPDATE domain_records SET body_json=? WHERE id=?').run(canonicalJSON(body),flow.id);
 });
 assertRejectedWithoutReplacement(f,'domain_record_rollback_rejected');
});

test('valid operation HMACs cannot authorize conflicting commitments at one revision',t=>{
 const {f,flow}=fixture(t);
 f.mutate(db=>{
  const cursorSecret=db.prepare("SELECT value FROM core_metadata WHERE key='cursor_secret'").get().value;
  const store=new DomainStore(db,{nodeId:f.nodeId,cursorSecret});
  const row=db.prepare('SELECT * FROM domain_records WHERE id=?').get(flow.id),op=db.prepare('SELECT * FROM domain_ops').get();
  const {receipt_auth,...oldReceipt}=JSON.parse(db.prepare('SELECT receipt_json FROM domain_receipts').get().receipt_json);
  const {recovery_auth,recovery_rows,...metadata}=JSON.parse(op.op_meta_json);
  const opId=randomUUID(),receipt={...oldReceipt,receipt_id:randomUUID(),accepted_op_id:opId};receipt.receipt_auth=store.mac(receipt);
  const result=JSON.parse(op.result_json);result.body.op_id=opId;result.body.receipt=receipt;
  const digest=store.mac({synthetic:'conflicting-row-commitment',opId}),body=JSON.parse(row.body_json);body.data.title='synthetic conflicting commitment';
  db.exec('BEGIN IMMEDIATE');
  try{
   // Use the real result-authentication factory over a deliberately inconsistent
   // synthetic state, then restore the row before appending the conflicting op.
   db.prepare('UPDATE domain_records SET body_json=? WHERE id=?').run(canonicalJSON(body),flow.id);
   const conflicting=store.recoveryMetadata(op.namespace,op.principal_id,op.domain,opId,digest,result,metadata);
   db.prepare('UPDATE domain_records SET body_json=? WHERE id=?').run(row.body_json,flow.id);
   assert.notEqual(conflicting.recovery_rows[0].row_auth,recovery_rows[0].row_auth);
   db.prepare('INSERT INTO domain_receipts VALUES(?,?,?,?)').run(receipt.receipt_id,op.namespace,op.domain,canonicalJSON(receipt));
   db.prepare('INSERT INTO domain_ops VALUES(?,?,?,?,?,?,?)').run(op.namespace,op.principal_id,op.domain,opId,digest,canonicalJSON(result),canonicalJSON(conflicting));
   db.exec('COMMIT');
  }catch(error){db.exec('ROLLBACK');throw error;}
 });
 assertRejectedWithoutReplacement(f,'domain_record_materialization_mismatch');
});

test('unchanged v1 row without authenticated operation evidence fails closed without replacing originals',t=>{
 const {f}=fixture(t,{withoutOperationAuthentication:true});
 assertRejectedWithoutReplacement(f,'old_domain_witness_unverifiable');
});
