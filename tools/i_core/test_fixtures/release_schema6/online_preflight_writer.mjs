import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {realpathSync} from 'node:fs';
import path from 'node:path';
import {cleanEnvironment,plainPath} from '../../release_schema6/package.mjs';
const allowed=cleanEnvironment(process.env);for(const key of Object.keys(process.env))if(!(key in allowed))delete process.env[key];
const [root,filename]=process.argv.slice(2);
assert.match(path.basename(root),/^schema6-online-preflight-/);assert.equal(realpathSync.native(root),root);assert.equal(path.dirname(filename),path.join(root,'source'));plainPath(filename);
const db=new DatabaseSync(filename);
let sealed=false,sqlCalls=0;
const sql=text=>{assert.equal(sealed,false);sqlCalls++;db.exec(text);};
sql('PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0');
sql('CREATE TABLE online_preflight_synthetic_marker(id INTEGER PRIMARY KEY, value TEXT)');
sql("BEGIN; INSERT INTO online_preflight_synthetic_marker VALUES(1,'synthetic committed WAL'); COMMIT");
sealed=true;
// Only IPC holds this independent writer alive after ready. No SQL or timers.
const status=type=>({type,pid:process.pid,sealed,sqlCalls,sqlCallsAfterReady:0});
process.on('message',m=>{if(m==='status')process.send(status('status'));else if(m==='close'){db.close();process.disconnect();}else throw new Error('unknown IPC command');});
process.send(status('ready'));
