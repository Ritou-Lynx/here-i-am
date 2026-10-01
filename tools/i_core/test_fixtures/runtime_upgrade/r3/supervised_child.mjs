import { spawn, spawnSync } from 'node:child_process';
import { closeSync, existsSync, openSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { plainPath, cleanEnvironment } from '../../../runtime_upgrade/r3/package.mjs';
const assertPlainPath = target => plainPath(target, { existing: false });

// Fixed internal fixtures only. The Windows supervisor creates this process
// suspended, attaches its real handle to an owned Job, then resumes it.
const [root, token, mode] = process.argv.slice(2);
if (!root || !path.isAbsolute(root) || !/^mda2-r3-supervised-[A-Za-z0-9]+$/.test(path.basename(root))
    || !/^[a-f0-9]{64}$/.test(token ?? '')
    || !['suite', 'normal', 'hang', 'descendant-hang', 'residual', 'grandchild', 'missing-receipt', 'forged-receipt'].includes(mode)) {
  throw new Error('invalid_internal_fixture');
}
assertPlainPath(root);
for (const name of ['owner.json', 'scratch', 'output.log', 'ready', 'grandchild-ready']) assertPlainPath(path.join(root, name));
const scratch = path.join(root, 'scratch');
const expectedParent = mode === 'grandchild' ? scratch : path.dirname(root);
if (realpathSync.native(expectedParent) !== realpathSync.native(tmpdir())) throw new Error('unowned_run_root');
const owner = JSON.parse(readFileSync(path.join(root, 'owner.json')));
if (owner.token !== token || (mode === 'grandchild' ? owner.mode !== 'descendant-hang' : owner.mode !== mode)) throw new Error('run_identity_mismatch');
assertPlainPath(scratch);
if (!existsSync(scratch)) throw new Error('owned_scratch_missing');
process.env.TEMP = scratch;
process.env.TMP = scratch;
if (mode !== 'grandchild') writeFileSync(path.join(root, 'ready'), 'ready', { flag: 'wx' });
else writeFileSync(path.join(root, 'grandchild-ready'), token, { flag: 'wx' });
if (mode === 'suite') {
  const log = openSync(path.join(root, 'output.log'), 'wx');
  try {
    const tests = ['lifecycle.test.mjs', 'faults.test.mjs', 'service.test.mjs', 'combination.test.mjs'].map(name =>
      fileURLToPath(new URL(`../../../runtime_upgrade/r3/${name}`, import.meta.url)));
    const child = spawnSync(process.execPath, ['--test', ...tests], {
      env: cleanEnvironment(), windowsHide: true, stdio: ['ignore', log, log],
    });
    process.exitCode = child.status ?? 1;
  } finally { closeSync(log); }
} else if (['normal', 'missing-receipt', 'forged-receipt'].includes(mode)) {
  writeFileSync(path.join(root, 'output.log'), 'synthetic normal completion\n');
} else if (mode === 'residual') {
  writeFileSync(path.join(scratch, 'synthetic-residual.txt'), 'must be reported, not silently removed');
} else {
  if (mode === 'descendant-hang') {
    spawn(process.execPath, [fileURLToPath(import.meta.url), root, token, 'grandchild'], {
      windowsHide: true, env: cleanEnvironment(), stdio: 'ignore',
    });
  }
  setInterval(() => {}, 1000);
}
