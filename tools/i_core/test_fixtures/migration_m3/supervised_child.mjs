import { spawn } from 'node:child_process';
import { appendFileSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const [root, token, mode] = process.argv.slice(2);
const owner = JSON.parse(readFileSync(path.join(root, 'owner.json')));
if (owner.token !== token || owner.mode !== mode) throw new Error('owner_mismatch');
writeFileSync(path.join(root, 'ready'), token);
if (mode === 'normal') process.exit(0);
if (mode === 'descendants') {
  const descendant = spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], { windowsHide: true, stdio: 'ignore' });
  descendant.once('spawn', () => writeFileSync(path.join(root, 'descendant-ready'), JSON.stringify({ token, pid: descendant.pid })));
  setInterval(() => {}, 1000);
} else if (['pin','migration','core','supervision'].includes(mode)) {
  const core = fileURLToPath(new URL('../../', import.meta.url));
  const entries = mode === 'core' ? readdirSync(core).filter(name => name.endsWith('.test.mjs')).sort().map(name => path.join(core, name))
    : [path.join(core, mode === 'pin' ? 'runtime_pin/runtime_pin.test.mjs' : `migration_m3/${mode === 'migration' ? 'migration' : 'supervision'}.test.mjs`)];
  const child = spawn(process.execPath, ['--test', '--test-reporter=tap', '--test-concurrency=1', ...entries], {
    cwd: fileURLToPath(new URL('../../../../', import.meta.url)),
    windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'],
    env: { ...process.env, TEMP: path.join(root, 'scratch'), TMP: path.join(root, 'scratch') },
  });
  child.stdout.on('data', chunk => appendFileSync(path.join(root, 'output.log'), chunk));
  child.stderr.on('data', chunk => appendFileSync(path.join(root, 'output.log'), chunk));
  child.once('error', error => { writeFileSync(path.join(root, 'suite.json'), JSON.stringify({ error: error.code })); process.exit(2); });
  child.once('close', (code, signal) => {
    writeFileSync(path.join(root, 'suite.json'), JSON.stringify({ exit_code: code, signal }));
    process.exit(code === 0 ? 0 : 1);
  });
} else throw new Error('fixed_mode_required');
