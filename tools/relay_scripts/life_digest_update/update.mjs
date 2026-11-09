// Narrow production update: preserve configuration, schedule and all user data.
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const OLD = '447bcbc2b022767827cbaabbb86d0aed435ad1c45a91a67ef6950cb657190b7f';
const NEW = '78feda48a79715d74b5a483ba63147c8a03fcbf22c07daa7ad41b97b7e13c93b';
export const hash = bytes => createHash('sha256').update(Buffer.from(bytes).toString('utf8').replaceAll('\r\n', '\n')).digest('hex');
function need(ok, code) { if (!ok) throw new Error(code); }
export function launcherPaths(text) {
  const plain = text.replaceAll('""', '"');
  const node = plain.match(/"([A-Za-z]:\\[^"\r\n]*?node\.exe)"/i)?.[1];
  const runner = plain.match(/"([A-Za-z]:\\[^"\r\n]*?\\tools\\life_digest\\life_digest_run\.mjs)"/i)?.[1];
  need(node && runner, 'launcher_unrecognized');
  return { node, runner };
}
function regular(p) { need(fs.lstatSync(p).isFile() && !fs.lstatSync(p).isSymbolicLink(), 'file_not_regular'); }
function under(root, target) {
  const rel = path.relative(root, target);
  need(rel && !rel.startsWith('..') && !path.isAbsolute(rel), 'path_outside_digest');
  let cursor = target;
  while (cursor !== root) { need(!fs.lstatSync(cursor).isSymbolicLink(), 'symlink_forbidden'); cursor = path.dirname(cursor); }
}
export function acceptedHash(value) { return value === OLD || value === NEW; }
export function deploy({ base, source, mode }) {
  need(mode === 'read' || mode === 'write', 'bad_mode');
  const launcher = path.join(base, 'life-digest.vbs');
  regular(launcher);
  const bytes = fs.readFileSync(launcher);
  need(bytes[0] === 255 && bytes[1] === 254, 'launcher_encoding');
  const live = launcherPaths(bytes.subarray(2).toString('utf16le'));
  under(base, live.runner); regular(live.runner); regular(live.node);
  const dest = path.join(path.dirname(live.runner), 'life_digest_lib.mjs');
  under(base, dest); regular(dest); regular(source);
  need(hash(fs.readFileSync(source)) === NEW, 'source_hash_mismatch');
  const before = hash(fs.readFileSync(dest));
  need(acceptedHash(before), 'live_version_unknown');
  const configFile = path.join(base, 'config', 'generator.json'); regular(configFile);
  const config = JSON.parse(fs.readFileSync(configFile, 'utf8').replace(/^\uFEFF/, ''));
  const data = path.resolve(config.digest_dir); under(base, data);
  const lock = path.join(data, 'work', 'run.lock');
  need(!fs.existsSync(lock), 'generator_busy');
  const result = { mode, source_verified: true, live_known: true, updated: before === NEW, regenerated: false };
  if (mode === 'read') return result;
  // Reuse the generator lock while replacing the single module. Never delete another process's lock.
  const fd = fs.openSync(lock, 'wx');
  const backup = path.join(base, 'logs', 'morning-update-' + Date.now() + '.bak');
  let changed = false;
  try {
    fs.writeFileSync(fd, String(process.pid));
    need(hash(fs.readFileSync(dest)) === before, 'live_changed');
    fs.copyFileSync(dest, backup, fs.constants.COPYFILE_EXCL);
    if (before !== NEW) {
      const tmp = dest + '.morning-update-' + process.pid;
      try { fs.copyFileSync(source, tmp, fs.constants.COPYFILE_EXCL); fs.renameSync(tmp, dest); changed = true; }
      finally { if (fs.existsSync(tmp)) fs.unlinkSync(tmp); }
    }
    need(hash(fs.readFileSync(dest)) === NEW, 'copy_verification_failed');
  } finally { fs.closeSync(fd); fs.unlinkSync(lock); }
  const run = args => {
    const r = spawnSync(live.node, [live.runner, '--config', configFile, ...args], { encoding: 'utf8', windowsHide: true, timeout: 15 * 60000, maxBuffer: 1024 * 1024 });
    // Child output is intentionally not forwarded: it may include local paths or account details.
    need(!r.error && r.status === 0, 'generator_command_failed');
  };
  try { run(['--check']); }
  catch (error) { if (changed) fs.copyFileSync(backup, dest); throw error; }
  // Local logical day is 04:00 Asia/Shanghai, matching the generator.
  const date = logicalDate(Date.now());
  const dayFile = path.join(data, 'days', date + '.json');
  if (fs.existsSync(dayFile)) fs.copyFileSync(dayFile, backup + '.day.json', fs.constants.COPYFILE_EXCL);
  run(['--stage', 'morning', '--date', date, '--no-push']);
  const day = JSON.parse(fs.readFileSync(dayFile, 'utf8'));
  need(day.date === date && typeof day.morning?.text === 'string' && day.morning.text.length > 0, 'morning_missing');
  return { ...result, updated: true, regenerated: true, date, generator: ['codex','openai','template'].includes(day.morning.generator) ? day.morning.generator : 'other' };
}
export const logicalDate = ms => new Date(ms + 4 * 3600000).toISOString().slice(0,10);
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    need(process.platform === 'win32', 'windows_required');
    const base = path.join(process.env.USERPROFILE, 'life-digest');
    const source = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../life_digest/life_digest_lib.mjs');
    console.log(JSON.stringify({ ok: true, ...deploy({ base, source, mode: process.argv[2] }) }));
  } catch (error) {
    const safe = /^[a-z_]+$/.test(error.message) ? error.message : 'update_failed';
    console.log(JSON.stringify({ ok: false, detail: safe })); process.exitCode = 1;
  }
}
