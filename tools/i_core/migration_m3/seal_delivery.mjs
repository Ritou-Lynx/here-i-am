import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { cleanEnv, repository, sha } from '../test_fixtures/migration_m3/lab.mjs';

const base = '1b6a2961ec9e9705273b8dbed3dd5a9ec5c121f5';
const docs = 'docs/development/activity/mda2/migration/m3';
const shared = ['tools/i_core/activity_control_plane.mjs', 'tools/i_core/i_core_store.mjs'];
const roots = ['tools/i_core/migration_m3', 'tools/i_core/test_fixtures/migration_m3', docs];
const generated = new Set([`${docs}/M3.patch`, `${docs}/SHARED.patch`, `${docs}/VERIFICATION.json`]);
function git(args, allowed = [0]) {
  const result = spawnSync('git', ['-C', repository, ...args], { env: cleanEnv(), windowsHide: true, timeout: 10000, maxBuffer: 16 * 1024 * 1024 });
  assert.ok(allowed.includes(result.status), result.stderr.toString());
  return result.stdout;
}
function walk(relative) {
  return readdirSync(path.join(repository, relative), { withFileTypes: true }).flatMap(entry =>
    entry.isDirectory() ? walk(`${relative}/${entry.name}`) : [`${relative}/${entry.name}`]);
}
assert.equal(git(['rev-parse', 'HEAD']).toString().trim(), base);
assert.equal(git(['branch', '--show-current']).toString().trim(), 'codex/mda2-m3-20260912');
assert.equal(git(['diff', '--cached', '--name-only']).toString(), '');
assert.deepEqual(git(['diff', '--name-only']).toString().trim().split('\n').sort(), shared);
git(['diff', '--check']);
const files = [...shared, ...roots.flatMap(walk).filter(name => !generated.has(name))].sort();
const untracked = git(['ls-files', '--others', '--exclude-standard']).toString().trim().split('\n').filter(Boolean);
assert.ok(untracked.every(name => roots.some(root => name.startsWith(root + '/'))));
const sharedPatch = git(['diff', '--binary', '--', ...shared]);
writeFileSync(path.join(repository, docs, 'SHARED.patch'), sharedPatch);
const additions = files.filter(name => !shared.includes(name)).map(name => git(['diff', '--no-index', '--binary', '--', '/dev/null', name], [1]));
const patch = Buffer.concat([sharedPatch, ...additions]);
writeFileSync(path.join(repository, docs, 'M3.patch'), patch);
// Reverse applicability verifies both modified sources and new files without touching index.
git(['apply', '--reverse', '--check', `${docs}/M3.patch`]);
const regressions = JSON.parse(readFileSync(path.join(repository, docs, 'evidence/regressions.json')));
assert.equal(regressions.results.length, 4);
assert.ok(regressions.results.every(result => result.exit_code === 0 && result.totals.fail === 0));
const manifest = {
  format: 'mda2-m3-uncommitted-v1', baseline: base, branch: 'codex/mda2-m3-20260912',
  task_id: '01a09504-1e14-74a1-be24-3befe49a7b08', node_version: process.version,
  node_sha256: sha(readFileSync(process.execPath)), shared_patch_sha256: sha(sharedPatch), patch_sha256: sha(patch),
  patch_reverse_check: true, staged: false, committed: false, integrated: false, deployed: false,
  files: files.map(name => ({ path: name, bytes: readFileSync(path.join(repository, name)).length, sha256: sha(readFileSync(path.join(repository, name))) })),
  regression_totals: regressions.results.map(({ name, totals, exit_code }) => ({ name, totals, exit_code })),
  excluded_from_patch: [...generated],
};
writeFileSync(path.join(repository, docs, 'VERIFICATION.json'), JSON.stringify(manifest, null, 2) + '\n');
console.log(JSON.stringify({ patch_sha256: manifest.patch_sha256, shared_patch_sha256: manifest.shared_patch_sha256,
  verification_sha256: sha(readFileSync(path.join(repository, docs, 'VERIFICATION.json'))), files: files.length }));
