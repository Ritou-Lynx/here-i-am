import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { once } from 'node:events';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import net from 'node:net';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const scriptPath = fileURLToPath(new URL('./start_bridge.ps1', import.meta.url));
const windowsTest = process.platform === 'win32'
  ? test
  : (name, fn) => test(name, { skip: 'Windows-only PowerShell launcher test.' }, fn);

function createFakeNode(exitCode, markerPath = null) {
  const root = mkdtempSync(path.join(tmpdir(), 'hereiam-start-bridge-test-'));
  const bin = path.join(root, 'bin');
  const nodeShim = path.join(bin, 'node.cmd');
  mkdirSync(bin);
  const markerLines = markerPath
    ? `> "${markerPath}" (echo %DEV_AGENT_EXPERIMENTAL_RUNTIME_ADAPTER%&echo %DEV_AGENT_EXPERIMENTAL_APP_SERVER_COMMAND%&echo %DEV_AGENT_EXPERIMENTAL_APP_SERVER_ARGS_JSON%)\r\n`
    : '';
  writeFileSync(nodeShim, `@echo off\r\n${markerLines}exit /b ${exitCode}\r\n`, 'utf8');
  return { root, bin };
}

function runStartBridge(bin, args = [], env = {}) {
  const result = spawnSync(
    'powershell.exe',
    ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath, ...args],
    {
      encoding: 'utf8',
      env: {
        ...process.env,
        ...env,
        PATH: `${bin};${process.env.PATH}`,
        DEV_AGENT_EXPERIMENTAL_RUNTIME_ADAPTER:
          env.DEV_AGENT_EXPERIMENTAL_RUNTIME_ADAPTER || '',
      },
      timeout: 15_000,
      windowsHide: true,
    },
  );
  assert.ifError(result.error);
  return result;
}

function currentWindowsIdentity() {
  const result = spawnSync(
    'powershell.exe',
    ['-NoProfile', '-Command', '[Security.Principal.WindowsIdentity]::GetCurrent().Name'],
    { encoding: 'utf8', timeout: 15_000, windowsHide: true },
  );
  assert.ifError(result.error);
  assert.equal(result.status, 0, result.stderr);
  return result.stdout.trim();
}

windowsTest('returns the node entrypoint exit code without starting a real Bridge', async (t) => {
  const { root, bin } = createFakeNode(23);
  t.after(() => rmSync(root, { recursive: true, force: true }));

  const reservation = net.createServer();
  reservation.listen(0, '127.0.0.1');
  await once(reservation, 'listening');
  const port = reservation.address().port;
  reservation.close();
  await once(reservation, 'close');

  const result = runStartBridge(bin, ['-Port', String(port)]);
  assert.equal(result.status, 23, result.stderr);
});

windowsTest('refuses to replace a listening port before invoking the node entrypoint', async (t) => {
  const { root, bin } = createFakeNode(0);
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const listener = net.createServer();
  t.after(() => listener.close());
  listener.listen(0, '127.0.0.1');
  await once(listener, 'listening');
  const port = listener.address().port;

  const result = runStartBridge(bin, ['-Port', String(port)]);
  assert.notEqual(result.status, 0, `${result.stdout}\n${result.stderr}`);
  assert.match(`${result.stdout}\n${result.stderr}`, /was not started and did not replace the existing listener/i);
});

windowsTest('rejects an explicit missing Codex executable without reading authentication state', (t) => {
  const { root, bin } = createFakeNode(0);
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const missingExe = path.join(root, 'missing-codex.exe');

  const result = runStartBridge(bin, [
    '-EnableExperimentalRuntime',
    '-CodexExecutable', missingExe,
  ]);
  assert.notEqual(result.status, 0);
  assert.match(`${result.stdout}\n${result.stderr}`, /Codex executable was not found/i);
});

windowsTest('refuses Experimental Runtime from a Codex sandbox identity for both enable paths', (t) => {
  const identity = currentWindowsIdentity();
  if (!/\\CodexSandbox(?:Offline|Online)$/i.test(identity)) {
    t.skip('This assertion only applies while the test itself runs in a Codex sandbox identity.');
    return;
  }
  const { root, bin } = createFakeNode(0);
  t.after(() => rmSync(root, { recursive: true, force: true }));

  const switchResult = runStartBridge(bin, ['-EnableExperimentalRuntime']);
  assert.notEqual(switchResult.status, 0);
  assert.match(`${switchResult.stdout}\n${switchResult.stderr}`, /current Windows identity is .*CodexSandbox/i);

  const environmentResult = runStartBridge(bin, [], {
    DEV_AGENT_EXPERIMENTAL_RUNTIME_ADAPTER: '1',
  });
  assert.notEqual(environmentResult.status, 0);
  assert.match(`${environmentResult.stdout}\n${environmentResult.stderr}`, /current Windows identity is .*CodexSandbox/i);
});

windowsTest('starts an enabled Runtime with an explicit existing exe from a normal user identity', async (t) => {
  const identity = currentWindowsIdentity();
  if (/\\CodexSandbox(?:Offline|Online)$/i.test(identity)) {
    t.skip('This positive case must run from the ordinary user session or approved host.');
    return;
  }
  const root = mkdtempSync(path.join(tmpdir(), 'hereiam-start-bridge-positive-'));
  const markerPath = path.join(root, 'runtime-env.txt');
  const fakeCodexExe = path.join(root, 'codex.exe');
  writeFileSync(fakeCodexExe, 'fixture only', 'utf8');
  const { root: fakeNodeRoot, bin } = createFakeNode(0, markerPath);
  t.after(() => {
    rmSync(root, { recursive: true, force: true });
    rmSync(fakeNodeRoot, { recursive: true, force: true });
  });

  const reservation = net.createServer();
  reservation.listen(0, '127.0.0.1');
  await once(reservation, 'listening');
  const port = reservation.address().port;
  reservation.close();
  await once(reservation, 'close');

  const result = runStartBridge(bin, [
    '-Port', String(port),
    '-EnableExperimentalRuntime',
    '-CodexExecutable', fakeCodexExe,
  ]);
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  assert.deepEqual(
    readFileSync(markerPath, 'utf8').trim().split(/\r?\n/),
    ['1', fakeCodexExe, '["app-server","--stdio"]'],
  );
});
