import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {existsSync, realpathSync} from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {cleanEnvironment, plainPath} from '../../release_schema6/package.mjs';

const [role, root, filename] = process.argv.slice(2);
const allowed=cleanEnvironment(process.env); for(const key of Object.keys(process.env))if(!(key in allowed))delete process.env[key];
assert.ok(Object.keys(process.env).length===Object.keys(allowed).length, 'child environment must be clean');
assert.match(path.basename(root), /^schema6-online-shm-/);
assert.equal(realpathSync.native(root), root);
assert.equal(path.dirname(filename), root);
plainPath(root);
if (role === 'writer') {
  assert.equal(existsSync(filename), false, 'writer must create a new synthetic database');
  const db = new DatabaseSync(filename);
  let sqlCalls = 0;
  let sealed = false;
  const sql = text => { assert.equal(sealed, false); sqlCalls++; db.exec(text); };
  sql('PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0');
  sql('CREATE TABLE synthetic_payload(id INTEGER PRIMARY KEY, value TEXT NOT NULL)');
  sql("BEGIN; INSERT INTO synthetic_payload VALUES (1, 'synthetic-one'), (2, 'synthetic-two'); COMMIT");
  sealed = true;
  const status = () => ({pid:process.pid, sealed, sqlCalls, sqlCallsAfterReady:0, backgroundSql:false});
  // IPC alone keeps this process alive. No timers, SELECTs, PRAGMAs, checkpoints,
  // or SQL calls occur after ready. status does not touch db.
  process.on('message', message => {
    if(message === 'status') process.send({type:'status', ...status()});
    else if(message === 'close') {db.close(); process.disconnect();}
    else throw new Error('unknown IPC message');
  });
  process.send({type:'ready', ...status()});
} else if(role === 'reader') {
  const db = new DatabaseSync(pathToFileURL(filename).href+'?mode=ro', {readOnly:true});
  try {
    const rows = db.prepare('SELECT id, value FROM synthetic_payload ORDER BY id').all();
    process.stdout.write(JSON.stringify({rows,selectCalls:1,pid:process.pid}));
  } finally {db.close();}
} else throw new Error('unsupported synthetic worker role');
