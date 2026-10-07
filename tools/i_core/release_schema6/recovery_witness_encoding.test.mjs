import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
import { canonicalJSON } from '../domain_store.mjs';

// Test-only exports from an independent source module; production keeps these
// encoders private and exposes no test injection or alternative digest path.
const anchor=new URL('./recovery_adapter.mjs',import.meta.url);
const source=readFileSync(anchor,'utf8').replace(/from '([^']+)'/g,(all,dependency)=>dependency.startsWith('.')?`from '${new URL(dependency,anchor).href}'`:all)
 +'\nexport { encodeRecoveryRow, canonicalRecoveryJSON, encode as originalEncode };\n';
const {encodeRecoveryRow,canonicalRecoveryJSON,originalEncode}=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));

test('flat SQLite row encoding preserves original bytes for null, Unicode, NUL, blobs, real and signed 64-bit integers',()=>{
 const db=new DatabaseSync(':memory:');
 try{
  db.exec('CREATE TABLE encoding_fixture(text_value TEXT, null_value TEXT, blob_value BLOB, real_value REAL, big_value INTEGER)');
  const insert=db.prepare('INSERT INTO encoding_fixture VALUES(?,?,?,?,?)');
  const cases=[
   ['雪と雨 😀\0tail',null,new Uint8Array([0,1,127,128,255]),1.2345678901234567,9223372036854775807n],
   ['',null,new Uint8Array(0),-0,-9223372036854775808n],
   ['é e\u0301 " \\ \n',null,new Uint8Array([255,0,255]),-Number.MIN_VALUE,-9007199254740993n],
   ['plain',null,new Uint8Array([7]),Number.MAX_VALUE,9007199254740993n],
  ];
  for(const values of cases)insert.run(...values);
  const query=db.prepare('SELECT rowid AS _rowid_,* FROM encoding_fixture ORDER BY rowid');query.setReadBigInts(true);
  let count=0;
  for(const row of query.iterate()){
   assert.equal(typeof row._rowid_,'bigint');assert.ok(row.blob_value instanceof Uint8Array);
   assert.equal(encodeRecoveryRow(row)===originalEncode(row),true,'flat SQLite row '+count+' must preserve all historical bytes');count++;
  }
  assert.equal(count,cases.length);
 }finally{db.close();}
});

test('flat row encoding preserves unusual SQLite property names and numeric-key enumeration',()=>{
 const db=new DatabaseSync(':memory:');
 try{
  const query=db.prepare('SELECT 1 AS _rowid_, NULL AS "__proto__", 7 AS "constructor", 10 AS "10", 2 AS "2", 1 AS "01", ? AS "雪"');query.setReadBigInts(true);
  const row=query.get('synthetic');
  assert.equal(Object.hasOwn(row,'__proto__'),true);
  assert.equal(encodeRecoveryRow(row)===originalEncode(row),true,'every own SQLite column must remain encoded');
  assert.equal(encodeRecoveryRow({})===originalEncode({}),true);
 }finally{db.close();}
});

test('canonical fast path and fallback preserve sorted, unsorted, nested, array and numeric-key JSON bytes',()=>{
 const cases=[null,true,false,0,-0,1.5,'雪\0😀',[],{},
  {a:1,b:2},{z:0,a:1},{a:{b:1,c:{d:2}},z:[]},
  {a:{z:1,b:2},c:3},[{a:1,b:2},{b:2,a:1},[{y:null,x:'value'}]],
  {'2':'two','10':'ten','01':'one',a:null},JSON.parse('{"10":{"z":1,"a":2},"2":[{"b":2,"a":1}],"01":0}'),
  {'雪':{'😀':1,a:2},'é':null}, {a:[],b:{},c:[null,{},[],false,'']},
 ];
 for(let i=0;i<cases.length;i++)assert.equal(canonicalRecoveryJSON(cases[i])===canonicalJSON(cases[i]),true,'JSON case '+i+' must preserve DomainStore MAC bytes');
});

test('canonical encoder preserves historical unusual JSON keys and legacy non-plain values',()=>{
 const cases=[JSON.parse('{"__proto__":{"z":1,"a":2},"constructor":0}'),Object.assign(Object.create(null),{z:1,a:{z:2,a:1}}),new Uint8Array([1,2]),new Date('2026-01-01T00:00:00.000Z'),{a:undefined,b:NaN,c:Infinity},[undefined,NaN,Infinity]];
 for(let i=0;i<cases.length;i++)assert.equal(canonicalRecoveryJSON(cases[i])===canonicalJSON(cases[i]),true,'legacy JSON case '+i+' must preserve bytes');
});
