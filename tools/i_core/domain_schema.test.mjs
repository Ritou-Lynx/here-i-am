import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';
import { DOMAIN_SCHEMA_SQL, DOMAIN_SCHEMA_VERSION, DOMAIN_TABLE_NAMES, assertDomainSchemaReady, inspectDomainSchema } from './domain_schema.mjs';

function syntheticDatabase() {
 const db = new DatabaseSync(':memory:');
 db.exec("CREATE TABLE core_metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL); INSERT INTO core_metadata VALUES('schema_version','5')");
 return db;
}
test('A23 schema inspection never upgrades a schema 5 database', () => {
 const db = syntheticDatabase();
 try {
  assert.equal(DOMAIN_SCHEMA_VERSION, 6);
  assert.equal(inspectDomainSchema(db).ready, false);
  assert.throws(() => assertDomainSchemaReady(db), { code: 'schema_not_ready' });
  assert.equal(db.prepare("SELECT COUNT(*) AS n FROM sqlite_master WHERE name LIKE 'domain_%'").get().n, 0);
 } finally { db.close(); }
});
test('A23 complete schema 6 DDL and exact shape required, marker alone insufficient', () => {
 const db = syntheticDatabase();
 try {
  db.exec("UPDATE core_metadata SET value='6'");
  assert.equal(inspectDomainSchema(db).ready, false);
  db.exec(DOMAIN_SCHEMA_SQL);
  assert.equal(assertDomainSchemaReady(db).ready, true);
  assert.equal(DOMAIN_TABLE_NAMES.length, 12);
  const insert = db.prepare('INSERT INTO domain_changes(namespace,domain,id,revision,domain_sequence,changed_at) VALUES(?,?,?,?,?,?)');
  insert.run('production','example_a','a',1,1,'2026-10-05T00:00:00.000Z');
  insert.run('production','example_b','b',1,1,'2026-10-05T00:00:00.000Z');
  insert.run('shadow','example_a','a',1,1,'2026-10-05T00:00:00.000Z');
  insert.run('production','example_a','a',2,2,'2026-10-05T00:00:00.000Z');
  assert.deepEqual(db.prepare('SELECT sequence,domain_sequence FROM domain_changes ORDER BY sequence').all().map(row=>[row.sequence,row.domain_sequence]),[[1,1],[2,1],[3,1],[4,2]]);
  assert.throws(()=>insert.run('production','example_a','other',1,1,'2026-10-05T00:00:00.000Z'),/UNIQUE/);
  assert.throws(()=>insert.run('production','example_a','other',1,null,'2026-10-05T00:00:00.000Z'),/NOT NULL/);
  assert.throws(()=>insert.run('production','example_a','other',1,3,null),/NOT NULL/);
  db.exec('DROP INDEX domain_changes_feed');
  assert.throws(() => assertDomainSchemaReady(db), { code: 'domain_schema_invariant_failed' });
 } finally { db.close(); }
});
test('A23 schema drift and unexpected domain objects fail closed', () => {
 const db = syntheticDatabase();
 try {
  db.exec(DOMAIN_SCHEMA_SQL);
  db.exec("UPDATE core_metadata SET value='6'; ALTER TABLE domain_records ADD COLUMN accidental TEXT");
  assert.deepEqual(inspectDomainSchema(db).mismatched_objects, ['domain_records']);
  db.exec('CREATE TABLE domain_surprise(secret TEXT)');
  assert.deepEqual(inspectDomainSchema(db).unexpected_objects, ['domain_surprise']);
 } finally { db.close(); }
});
