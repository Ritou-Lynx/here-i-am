import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { createHash, createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { fileURLToPath } from 'node:url';

export const hash = (value) => createHash('sha256').update(value).digest('hex');
export const fail = (code) => { throw Object.assign(new Error(code), { code }); };
export const encode = (value) => Buffer.from(JSON.stringify(value));
export function windowsHelper(script) {
  const system = process.env.SystemRoot;
  if (!system) fail('windows_environment_missing');
  return spawn(path.join(system,'System32','WindowsPowerShell','v1.0','powershell.exe'),
    ['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',script], {
      windowsHide:true, stdio:['pipe','pipe','pipe'],
      // PowerShell 7's inherited PSModulePath breaks Windows PowerShell modules.
      // No inherited application configuration/credential variables reach helper.
      env:{SystemRoot:system,WINDIR:system,TEMP:process.env.TEMP,TMP:process.env.TMP,
        PATH:path.join(system,'System32')},
    });
}

export class ProtectedStore {
  static async open(root, binding, { fresh = false } = {}) {
    if (process.platform !== 'win32') fail('windows_required');
    const instance = new ProtectedStore();
    instance.root = path.resolve(root);
    instance.aad = encode({ version: 1, root: instance.root.toLowerCase(), binding });
    instance.guard = windowsHelper(fileURLToPath(new URL('./windows_guard.ps1', import.meta.url)));
    instance.pending = [];
    instance.dead = false;
    // Never forward helper stderr; errors are fixed codes.
    instance.guard.stderr.resume();
    const lines = createInterface({ input: instance.guard.stdout });
    lines.on('line', (line) => {
      const pending = instance.pending.shift();
      if (!pending) return;
      try { const reply = JSON.parse(line); reply.ok ? pending.resolve(reply) : pending.reject(new Error(/^windows_protection_rejected_[a-z_0-9]+$/.test(reply.code) ? reply.code : 'windows_protection_rejected')); }
      catch { pending.reject(new Error('windows_protection_rejected')); }
    });
    instance.guard.on('error', () => instance.died());
    instance.guard.stdin.on('error', () => instance.died());
    instance.guard.on('exit', (code,signal) => { instance.guardExit={code,signal}; instance.died(); });
    try {
      const reply = await instance.command(JSON.stringify({ root: instance.root, fresh, entropy: createHash('sha256').update(instance.aad).digest('base64') }));
      instance.key = Buffer.from(reply.key, 'base64');
      instance.filename = path.join(instance.root, 'queue', 'state.sqlite');
      if (!fresh && !fs.existsSync(instance.filename)) fail('queue_missing');
      await instance.validate();
      instance.db = new DatabaseSync(instance.filename);
      instance.db.exec('PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA secure_delete=ON; PRAGMA wal_autocheckpoint=1;');
      if (fresh) instance.db.exec('CREATE TABLE sealed_state (id INTEGER PRIMARY KEY CHECK(id=1), revision INTEGER NOT NULL, envelope BLOB NOT NULL) STRICT;');
      return instance;
    } catch (e) { await instance.close(); throw e; }
  }
  died() { this.dead = true; for (const p of this.pending.splice(0)) p.reject(new Error('protection_owner_lost')); }
  command(text) {
    if (this.dead) return Promise.reject(new Error('protection_owner_lost'));
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => { this.guard.kill(); reject(new Error('guard_timeout')); }, 15000);
      this.pending.push({ resolve: (v) => { clearTimeout(timeout); resolve(v); }, reject: (e) => { clearTimeout(timeout); reject(e); } });
      this.guard.stdin.write(text + '\n');
    });
  }
  async validate() {
    await this.command('validate');
    const walk = (p) => {
      const stat = fs.lstatSync(p);
      if (stat.isSymbolicLink()) fail('reparse_rejected');
      if (stat.isDirectory()) for (const name of fs.readdirSync(p)) walk(path.join(p, name));
      else if (stat.nlink !== 1) fail('hardlink_rejected');
    };
    walk(this.root);
  }
  seal(state) {
    const nonce = randomBytes(12), cipher = createCipheriv('aes-256-gcm', this.key, nonce);
    cipher.setAAD(this.aad);
    const plaintext = encode(state);
    try { return Buffer.concat([Buffer.from([1]), nonce, cipher.update(plaintext), cipher.final(), cipher.getAuthTag()]); }
    finally { plaintext.fill(0); }
  }
  read() {
    const row = this.db.prepare('SELECT revision,envelope FROM sealed_state WHERE id=1').get();
    if (!row) return null;
    const bytes = Buffer.from(row.envelope);
    let plain;
    try {
      if (bytes[0] !== 1 || bytes.length < 30) fail('storage_version_rejected');
      const decipher = createDecipheriv('aes-256-gcm', this.key, bytes.subarray(1, 13));
      decipher.setAAD(this.aad); decipher.setAuthTag(bytes.subarray(-16));
      plain = Buffer.concat([decipher.update(bytes.subarray(13, -16)), decipher.final()]);
      const state = JSON.parse(plain.toString());
      if (state.version !== 1 || state.revision !== row.revision) fail('storage_version_rejected');
      return { state, digest: hash(bytes) };
    } catch { fail('queue_integrity_rejected'); }
    finally { plain?.fill(0); }
  }
  write(expected, state, envelope, barrier = () => {}) {
    this.db.exec('BEGIN IMMEDIATE');
    try {
      const row = this.db.prepare('SELECT revision FROM sealed_state WHERE id=1').get();
      if ((row?.revision ?? -1) !== expected) fail('disk_cas_conflict');
      this.db.prepare('INSERT INTO sealed_state VALUES(1,?,?) ON CONFLICT(id) DO UPDATE SET revision=excluded.revision,envelope=excluded.envelope').run(state.revision, envelope);
      barrier('during_sqlite');
      this.db.exec('COMMIT');
      barrier('after_sqlite');
    } catch (e) { if (this.db.isTransaction) this.db.exec('ROLLBACK'); throw e; }
  }
  async close() {
    if (this.db) { this.db.close(); this.db = null; }
    this.key?.fill(0);
    if (this.guard && !this.dead) {
      const exit = new Promise((resolve) => this.guard.once('exit', resolve));
      this.guard.stdin.end('close\n'); await exit;
    }
    return { guardPid:this.guard?.pid, guardExit:this.guardExit, databaseClosed:!this.db };
  }
}
