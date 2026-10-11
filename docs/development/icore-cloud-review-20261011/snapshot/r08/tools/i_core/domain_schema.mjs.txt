import { DatabaseSync } from 'node:sqlite';

export const DOMAIN_SCHEMA_VERSION = 6;
export const DOMAIN_SCHEMA_SQL = `
CREATE TABLE domain_registry (
 domain TEXT PRIMARY KEY NOT NULL, mode TEXT NOT NULL, frozen_from TEXT,
 schema_json TEXT NOT NULL, policy_version TEXT NOT NULL
);
CREATE TABLE domain_records (
 namespace TEXT NOT NULL, domain TEXT NOT NULL, id TEXT NOT NULL, revision INTEGER NOT NULL,
 envelope_json TEXT NOT NULL, body_json TEXT, PRIMARY KEY(namespace,domain,id)
);
CREATE TABLE domain_ops (
 namespace TEXT NOT NULL, principal_id TEXT NOT NULL, domain TEXT NOT NULL, op_id TEXT NOT NULL,
 request_digest TEXT NOT NULL, result_json TEXT NOT NULL, op_meta_json TEXT NOT NULL,
 PRIMARY KEY(namespace,principal_id,domain,op_id)
);
CREATE TABLE domain_op_payloads (
 namespace TEXT NOT NULL, principal_id TEXT NOT NULL, domain TEXT NOT NULL, op_id TEXT NOT NULL,
 payload_json TEXT NOT NULL, expires_at TEXT, PRIMARY KEY(namespace,principal_id,domain,op_id)
);
CREATE TABLE domain_receipts (
 receipt_id TEXT PRIMARY KEY NOT NULL, namespace TEXT NOT NULL, domain TEXT NOT NULL, receipt_json TEXT NOT NULL
);
CREATE TABLE domain_changes (
 sequence INTEGER PRIMARY KEY AUTOINCREMENT, namespace TEXT NOT NULL, domain TEXT NOT NULL,
 id TEXT NOT NULL, revision INTEGER NOT NULL, domain_sequence INTEGER NOT NULL, changed_at TEXT NOT NULL
);
CREATE UNIQUE INDEX domain_changes_feed ON domain_changes(namespace,domain,domain_sequence);
CREATE TABLE domain_principals (
 principal_id TEXT PRIMARY KEY NOT NULL, token_hash TEXT NOT NULL, generation INTEGER NOT NULL,
 status TEXT NOT NULL, expires_at TEXT, device_id TEXT NOT NULL, installation_id TEXT NOT NULL, config_json TEXT NOT NULL
);
CREATE UNIQUE INDEX domain_principals_token ON domain_principals(token_hash);
CREATE TABLE domain_consumer_acks (
 namespace TEXT NOT NULL, domain TEXT NOT NULL, principal_id TEXT NOT NULL, generation INTEGER NOT NULL,
 installation_id TEXT NOT NULL, policy_version TEXT NOT NULL, cursor_sequence INTEGER NOT NULL,
 PRIMARY KEY(namespace,domain,principal_id,generation,installation_id,policy_version)
);
CREATE TABLE domain_snapshots (
 snapshot_id TEXT PRIMARY KEY NOT NULL, namespace TEXT NOT NULL, domain TEXT NOT NULL,
 principal_id TEXT NOT NULL, generation INTEGER NOT NULL, installation_id TEXT NOT NULL,
 policy_version TEXT NOT NULL, cut_sequence INTEGER NOT NULL, created_at TEXT NOT NULL,
 expires_at TEXT NOT NULL, snapshot_json TEXT NOT NULL
);
CREATE TABLE domain_purge_jobs (
 job_id TEXT PRIMARY KEY NOT NULL, namespace TEXT NOT NULL, domain TEXT NOT NULL, id TEXT NOT NULL, job_json TEXT NOT NULL
);
CREATE TABLE domain_schema_migrations (
 migration_id TEXT PRIMARY KEY NOT NULL, from_version INTEGER NOT NULL, to_version INTEGER NOT NULL, metadata_json TEXT NOT NULL
);
CREATE TABLE domain_phone_capabilities (
 device_id TEXT NOT NULL, character_id TEXT NOT NULL, token_hash TEXT NOT NULL,
 enabled INTEGER NOT NULL, configured_at TEXT NOT NULL, PRIMARY KEY(device_id,character_id)
);
`;

const normalizedSql = (sql) => String(sql ?? '').replace(/\s+/g, ' ').trim();
let expectedObjects;
function expectedSchema() {
 if (!expectedObjects) {
  const db = new DatabaseSync(':memory:');
  try {
   db.exec(DOMAIN_SCHEMA_SQL);
   expectedObjects = db.prepare("SELECT type,name,sql FROM sqlite_master WHERE name LIKE 'domain_%' ORDER BY name").all();
  } finally { db.close(); }
 }
 return expectedObjects;
}
export const DOMAIN_TABLE_NAMES = Object.freeze([
 'domain_registry', 'domain_records', 'domain_ops', 'domain_op_payloads', 'domain_receipts',
 'domain_changes', 'domain_principals', 'domain_consumer_acks', 'domain_snapshots',
 'domain_purge_jobs', 'domain_schema_migrations', 'domain_phone_capabilities',
]);

export class DomainSchemaError extends Error {
 constructor(code) { super(code); this.name = 'DomainSchemaError'; this.code = code; this.status = 503; }
}

// This is an inspection only. Service startup must never execute the DDL.
export function inspectDomainSchema(db) {
 const hasMetadata = db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='core_metadata'").get();
 const version = hasMetadata ? db.prepare("SELECT value FROM core_metadata WHERE key='schema_version'").get()?.value : null;
 const actual = db.prepare("SELECT type,name,sql FROM sqlite_master WHERE name LIKE 'domain_%' ORDER BY name").all();
 const mismatched = expectedSchema().filter((entry) => {
  const found = actual.find((item) => item.name === entry.name);
  return !found || found.type !== entry.type || normalizedSql(found.sql) !== normalizedSql(entry.sql);
 }).map((entry) => entry.name);
 const unexpected = actual.filter((entry) => !expectedSchema().some((item) => item.name === entry.name)).map((entry) => entry.name);
 return { ready: version === '6' && !mismatched.length && !unexpected.length, schema_version: Number(version ?? 0),
  reason: version !== '6' ? 'schema_not_ready' : mismatched.length || unexpected.length ? 'domain_schema_invariant_failed' : null,
  mismatched_objects: mismatched, unexpected_objects: unexpected };
}
export function assertDomainSchemaReady(db) {
 const result = inspectDomainSchema(db);
 if (!result.ready) throw new DomainSchemaError(result.reason);
 return result;
}
