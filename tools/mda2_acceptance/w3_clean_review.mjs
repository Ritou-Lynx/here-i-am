import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

// W0-only verification harness. Exports immutable Git blobs; never edits the
// worker checkout, main checkout, index, refs, credentials, or active runtime.
const workspace = path.resolve(fileURLToPath(new URL('../../', import.meta.url)));
const [mode, sourceArgument, commit] = process.argv.slice(2);
if (mode !== 'prepare' || !sourceArgument || !/^[0-9a-f]{40}$/.test(commit ?? '')) {
  throw new Error('usage: prepare <source checkout> <full commit>');
}
const source = fs.realpathSync.native(sourceArgument);
const sha = (bytes) => createHash('sha256').update(bytes).digest('hex');
function command(binary, args, cwd = workspace) {
  const result = spawnSync(binary, args, { cwd, windowsHide: true, maxBuffer: 32 * 1024 * 1024 });
  if (result.error || result.status !== 0) throw new Error(`${binary}_failed: ${result.error?.message ?? result.stderr?.toString()}`);
  return result.stdout;
}
if (command('git', ['rev-parse', 'HEAD'], source).toString().trim() !== commit) throw new Error('source_head_changed');
if (command('git', ['status', '--porcelain'], source).length) throw new Error('source_not_clean');
const reviewBase = path.join(workspace, 'tmp');
fs.mkdirSync(reviewBase, { recursive: true });
const review = fs.mkdtempSync(path.join(reviewBase, `mda2-w3-review-${commit.slice(0, 8)}-`));
const mirror = path.join(review, 'candidate');
fs.mkdirSync(mirror);
const archive = path.join(review, 'candidate.tar');
const roots = ['tools/i_core', 'tools/mda2_windows_queue', 'tools/mda2_windows_collector',
  'docs/development/activity/mda2/windows/w2', 'docs/development/activity/mda2/windows/w3', '.gitattributes'];
command('git', ['-c', 'core.autocrlf=false', 'archive', '--format=tar', `--output=${archive}`, commit, '--', ...roots], source);
command('tar', ['-xf', archive, '-C', mirror]);
const manifestFile = 'docs/development/activity/mda2/windows/w3/SOURCE_MANIFEST.json';
const manifest = JSON.parse(fs.readFileSync(path.join(mirror, manifestFile)));
const expectations = { ...manifest.baseline_core, ...manifest.collector_sources, ...manifest.results,
  ...Object.fromEntries(Object.entries(manifest.queue_delta.changed).map(([file, value]) => [file, value.candidate_sha256])) };
const checks = Object.entries(expectations).map(([file, expected]) => {
  const actual = sha(fs.readFileSync(path.join(mirror, file)));
  return { file, expected, actual, matches: actual === expected };
});
const files = command('git', ['ls-tree', '-r', '--name-only', '-z', commit, '--', ...roots], source)
  .toString().split('\0').filter(Boolean);
const snapshot = files.map((file) => {
  const actual = sha(fs.readFileSync(path.join(mirror, file)));
  const blob = sha(command('git', ['show', `${commit}:${file}`], source));
  if (actual !== blob) throw new Error(`archive_blob_mismatch:${file}`);
  return { file, sha256: actual, gitBlobMatches: true };
});
const record = { commit, baseline: manifest.baseline_commit, source, mirror,
  archiveSha256: sha(fs.readFileSync(archive)), manifestSha256: sha(fs.readFileSync(path.join(mirror, manifestFile))),
  node: { version: process.version, sha256: sha(fs.readFileSync(process.execPath)) }, checks, snapshot,
  mismatches: checks.filter((check) => !check.matches), originalCheckoutModified: false };
fs.writeFileSync(path.join(review, 'INPUTS.json'), JSON.stringify(record, null, 2) + '\n');
if (record.mismatches.length) {
  process.stdout.write(JSON.stringify({ review, mismatches: record.mismatches }) + '\n');
  process.exitCode = 1;
} else {
  process.stdout.write(JSON.stringify({ review, mirror, commit, checked: checks.length, archivedFiles: files.length }) + '\n');
}
