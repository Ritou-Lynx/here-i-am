import { createHash } from 'node:crypto';
import { existsSync, lstatSync, realpathSync } from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { DatabaseSync } from 'node:sqlite';

export const INSPECTION_MARKER = '.i-core-inspection.json';
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const reject = code => { throw Object.assign(new Error(code), { code }); };
const quote = name => '"' + name.replaceAll('"', '""') + '"';
const samePath = (a, b) => process.platform === 'win32' ? a.toLowerCase() === b.toLowerCase() : a === b;

export function assertInspectionDatabasePath(databasePath) {
  if (!path.isAbsolute(databasePath) || path.normalize(databasePath) !== databasePath || databasePath.includes(':', 2)) reject('inspection_path_invalid');
  for (let current = databasePath;; current = path.dirname(current)) {
    const s = lstatSync(current);
    if (s.isSymbolicLink() || !samePath(realpathSync.native(current), current)
        || (current === databasePath ? !s.isFile() || s.nlink !== 1 : !s.isDirectory())) reject('inspection_link_rejected');
    if (current === path.dirname(current)) break;
  }
  for (const suffix of ['-wal', '-shm', '-journal']) {
    try { lstatSync(databasePath + suffix); } catch (error) { if (error.code === 'ENOENT') continue; throw error; }
    reject('inspection_sidecar_rejected');
  }
}

export function isInspectionDatabasePath(databasePath) {
  for (let dir = path.dirname(path.resolve(databasePath));; dir = path.dirname(dir)) {
    if (existsSync(path.join(dir, INSPECTION_MARKER))) return true;
    if (dir === path.dirname(dir)) return false;
  }
}

// Stable typed row digests include every column and preserve duplicate rows.
// Neither row values, tokens nor the full node/device IDs leave this module.
function cell(value) {
  if (value === null) return ['null'];
  if (typeof value === 'bigint') return ['integer', value.toString()];
  if (value instanceof Uint8Array) return ['blob', Buffer.from(value).toString('base64')];
  if (typeof value === 'number') return ['real', Object.is(value, -0) ? '-0' : String(value)];
  return ['text', value];
}

export function fingerprintInspectionDatabase(db) {
  if (db.prepare('PRAGMA integrity_check').get().integrity_check !== 'ok') reject('inspection_integrity_failed');
  const value = key => db.prepare('SELECT value FROM core_metadata WHERE key=?').get(key)?.value;
  const node = value('node_id'), schema = Number(value('schema_version'));
  if (typeof node !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(node) || ![4, 5, 6].includes(schema)) reject('inspection_metadata_invalid');
  const schemaRows = db.prepare("SELECT type,name,tbl_name,sql FROM sqlite_master WHERE name NOT GLOB 'sqlite_*' ORDER BY type,name").all();
  const tables = [];
  for (const { name } of schemaRows.filter(r => r.type === 'table').sort((a,b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0)) {
    const statement = db.prepare(`SELECT * FROM ${quote(name)}`); statement.setReadBigInts(true);
    const rows = [];
    for (const row of statement.iterate()) rows.push(sha(JSON.stringify(Object.entries(row).map(([key, value]) => [key, cell(value)]))));
    rows.sort(); const hash = createHash('sha256'); for (const row of rows) hash.update(row + '\n');
    tables.push({ name, rows: rows.length, sha256: hash.digest('hex') });
  }
  const deviceTable = tables.find(t => t.name === 'devices');
  const devices = deviceTable ? db.prepare('SELECT device_id FROM devices ORDER BY device_id').all().map(r => String(r.device_id).slice(0, 8)) : [];
  const result = { schemaVersion: schema, nodeIdPrefix: node.slice(0, 8), nodeIdSha256: sha(node), schemaSha256: sha(JSON.stringify(schemaRows)),
    devices: { count: deviceTable?.rows ?? 0, sha256: deviceTable?.sha256 ?? sha(''), idPrefixes: devices }, tables };
  return { ...result, dataSha256: sha(JSON.stringify(result)) };
}

export function openInspectionDatabase(databasePath) {
  assertInspectionDatabasePath(databasePath);
  const db = new DatabaseSync(`${pathToFileURL(databasePath).href}?mode=ro&immutable=1`, { readOnly: true });
  try { db.exec('PRAGMA query_only=ON; PRAGMA trusted_schema=OFF'); return db; }
  catch (error) { db.close(); throw error; }
}

export function databaseInspectionFingerprint(databasePath) {
  const db = openInspectionDatabase(databasePath);
  try { return fingerprintInspectionDatabase(db); } finally { db.close(); assertInspectionDatabasePath(databasePath); }
}

// An explicit Core mode: no ICoreStore constructor, migration, lease, timer,
// pairing, background job, relay or normal business handler is instantiated.
export function createInspectionReadOnlyCore({ databasePath }) {
  const db = openInspectionDatabase(databasePath);
  let inspection;
  try { inspection = fingerprintInspectionDatabase(db); } catch (error) { db.close(); throw error; }
  let closed = false;
  const server = http.createServer((request, response) => {
    const health = request.method === 'GET' && request.url === '/v1/core/health';
    const payload = health ? { status: 'inspection_only', mode: 'inspection_read_only', read_only: true, immutable: true,
      business_routes_enabled: false, pairing_enabled: false, background_jobs_enabled: false, relay_enabled: false,
      schema_version: inspection.schemaVersion, node_id_prefix: inspection.nodeIdPrefix, database_fingerprint_sha256: inspection.dataSha256 }
      : { error: { code: 'inspection_read_only', message: 'This Core permits only inspection health.' } };
    const body = JSON.stringify(payload);
    response.writeHead(health ? 200 : 403, { 'content-type': 'application/json', 'content-length': Buffer.byteLength(body), 'cache-control': 'no-store', connection: 'close' });
    response.end(body); request.resume();
  });
  return {
    server,
    inspection: () => { if (closed) reject('inspection_closed'); return fingerprintInspectionDatabase(db); },
    enablePairing: () => reject('inspection_read_only'),
    async listen({ host = '127.0.0.1', port = 0 } = {}) {
      if (host !== '127.0.0.1' || !Number.isInteger(port) || port < 0 || port > 65535) reject('inspection_loopback_required');
      if (closed) reject('inspection_closed');
      await new Promise((resolve, rejectPromise) => {
        const error = e => { server.off('listening', listening); rejectPromise(e); };
        const listening = () => { server.off('error', error); resolve(); };
        server.once('error', error); server.once('listening', listening); server.listen(port, host);
      });
      return server.address();
    },
    async close() {
      if (closed) return; closed = true;
      try { if (server.listening) { const done = new Promise((resolve, rejectPromise) => server.close(e => e ? rejectPromise(e) : resolve())); server.closeAllConnections(); await done; } }
      finally { db.close(); assertInspectionDatabasePath(databasePath); }
    },
  };
}
