import { mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { repository, sha } from '../test_fixtures/migration_m3/lab.mjs';
import { startSupervised } from './supervision.mjs';

const resume = process.argv[3] === '--resume-pin';
if (process.argv[2] !== '--synthetic' || process.argv.length !== (resume ? 4 : 3)) {
  console.error('Explicit --synthetic required. This runner creates its own temporary databases only.');
  process.exit(2);
}
const output = path.join(repository, 'docs/development/activity/mda2/migration/m3/evidence');
mkdirSync(output, { recursive: true });
const core = fileURLToPath(new URL('../', import.meta.url));
const suites = [
  ['migration', 'migration', [fileURLToPath(new URL('./migration.test.mjs', import.meta.url))]],
  ['core-regression', 'core', readdirSync(core).filter(name => name.endsWith('.test.mjs')).sort().map(name => path.join(core, name))],
  ['supervision', 'supervision', [fileURLToPath(new URL('./supervision.test.mjs', import.meta.url))]],
  ['v4-pin-regression', 'pin', [path.join(core, 'runtime_pin/runtime_pin.test.mjs')]],
];
const results = [];
if (resume) {
  // This recovery run reuses only already-passing, byte-identical inputs.
  // The two shared hashes were captured before the initial sandbox pin failure.
  for (const [name, expected] of [
    ['activity_control_plane.mjs','93ca104158fac15eb567f6d66857bdb9dcabfd4093cd33ea79158ba9718553ff'],
    ['i_core_store.mjs','234ec17834622519174d470e21489f803f0ddcab0eaa4445a74b284e3844b302'],
  ]) if (sha(readFileSync(path.join(core, name))) !== expected) throw new Error('shared_input_changed_rerun_all');
  const prior = JSON.parse(readFileSync(path.join(output, 'sandbox-run.json')));
  for (const name of ['migration', 'core-regression']) {
    const result = prior.results.find(result => result.name === name);
    if (result?.exit_code !== 0) throw new Error('missing_prior_pass');
    for (const input of result.input_hashes) if (sha(readFileSync(path.join(repository, input.path))) !== input.sha256) throw new Error('prior_test_input_changed');
    results.push({ ...result, reused_unchanged_source_evidence: true, supervision: 'historical_pre_job_runner' });
  }
}
for (const [name, mode, files] of suites.filter(([name]) => !resume || !['migration', 'core-regression'].includes(name))) {
  const started = performance.now();
  const receipt = await startSupervised({ mode, timeout: mode === 'core' ? 240000 : 120000 }).wait();
  const log = receipt.log;
  writeFileSync(path.join(output, `${name}.tap`), log);
  writeFileSync(path.join(output, `${name}-supervisor.json`), JSON.stringify({ ...receipt, log: undefined }, null, 2) + '\n');
  const totals = Object.fromEntries([...log.matchAll(/^# (tests|pass|fail|cancelled|skipped) (\d+)$/gm)].map(match => [match[1], Number(match[2])]));
  const status = receipt.result.reason === 'completed' && receipt.suite?.exit_code === 0 && receipt.result.child_exit_code === 0 ? 0 : 1;
  const entry = { name, exit_code: status, signal: receipt.suite?.signal ?? null, error: null,
    duration_ms: Math.round(performance.now() - started), totals, log_sha256: sha(log),
    input_hashes: files.map(filename => ({ path: path.relative(repository, filename).replaceAll('\\', '/'), sha256: sha(readFileSync(filename)) })) };
  results.push(entry); console.log(JSON.stringify(entry));
  if (status !== 0) break;
}
writeFileSync(path.join(output, 'regressions.json'), JSON.stringify({ node_version: process.version,
  node_sha256: sha(readFileSync(process.execPath)), results }, null, 2) + '\n');
if (results.length !== suites.length || results.some(result => result.exit_code !== 0)) process.exitCode = 1;
