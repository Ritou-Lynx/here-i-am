import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { prepareRelease, ReleaseError, PINNED_NODE_SHA256, sha256, plainPath } from './package.mjs';
import { preflight } from './preflight.mjs';

export async function run(args) {
  const [command, ...rest] = args;
  if (sha256(readFileSync(process.execPath)) !== PINNED_NODE_SHA256) throw new ReleaseError('node_hash_mismatch');
  if (command === 'prepare' && [3, 4].includes(rest.length)) return prepareRelease({ repository: rest[0], output: rest[1], gitPath: rest[2], sourceCommit: rest[3] ?? 'HEAD' });
  if (['capture-baseline', 'preflight'].includes(command) && rest.length === 3) {
    const [release, manifestHash, configPath] = rest;
    const config = JSON.parse(readFileSync(plainPath(configPath), 'utf8').replace(/^\uFEFF/, ''));
    return preflight({ release, manifestHash, config, capture: command === 'capture-baseline' });
  }
  throw new ReleaseError('usage_prepare_or_explicit_preflight_only');
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { console.log(JSON.stringify(await run(process.argv.slice(2)))); }
  catch (error) { console.error(JSON.stringify({ rejected: true,
    code: error instanceof ReleaseError ? error.code : 'invalid_or_unreadable_input', deployed: false, services_started: 0 })); process.exitCode = 2; }
}
