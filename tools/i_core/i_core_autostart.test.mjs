import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const directory = path.dirname(fileURLToPath(import.meta.url));
const read = (name) => readFileSync(path.join(directory, name), 'utf8');

function inheritedEnvironment(overrides = {}) {
  return Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.toUpperCase().startsWith('I_CORE_')).concat(Object.entries(overrides)));
}

function runLauncherWithSyntheticActivityOwner(t, launcherSource, companionUploadMode = null) {
  const temporaryDirectory = mkdtempSync(path.join(tmpdir(), 'i-core-launcher-guard-'));
  t.after(() => rmSync(temporaryDirectory, { recursive: true, force: true }));
  const launcherPath = path.join(temporaryDirectory, 'start_i_core_service.ps1');
  const serverPath = path.join(temporaryDirectory, 'i_core_server.mjs');
  const resultPath = path.join(temporaryDirectory, 'child-environment.json');
  writeFileSync(launcherPath, launcherSource, 'utf8');
  writeFileSync(serverPath, [
    "import { writeFileSync } from 'node:fs';",
    "writeFileSync(process.env.LAUNCHER_GUARD_RESULT, JSON.stringify({ activity_admin_secret: process.env.I_CORE_ACTIVITY_ADMIN_SECRET, companion_upload_mode: process.env.I_CORE_COMPANION_UPLOAD_MODE, transcript_grants_path: process.env.I_CORE_LOCAL_TRANSCRIPT_GRANTS, replay_approvals_path: process.env.I_CORE_HISTORICAL_REPLAY_APPROVALS }));",
  ].join('\n'), 'utf8');

  const powershell = process.env.SystemRoot
    ? path.join(process.env.SystemRoot, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe')
    : 'powershell.exe';
  const run = spawnSync(powershell, [
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', launcherPath,
    '-NodePath', process.execPath,
    '-StateDirectory', path.join(temporaryDirectory, 'state'),
    '-RuntimeLockPath', path.join(temporaryDirectory, 'runtime.lock'),
    '-CorePort', '48123',
    ...(companionUploadMode ? ['-CompanionUploadMode', companionUploadMode] : []),
  ], {
    env: inheritedEnvironment({
      I_CORE_ACTIVITY_ADMIN_SECRET: 'synthetic-owner-secret',
      I_CORE_COMPANION_UPLOAD_MODE: 'legacy_b3',
      I_CORE_LOCAL_TRANSCRIPT_GRANTS: 'synthetic-untrusted-grant-path',
      I_CORE_HISTORICAL_REPLAY_APPROVALS: 'synthetic-untrusted-replay-path',
      LAUNCHER_GUARD_RESULT: resultPath,
    }),
    encoding: 'utf8',
    timeout: 20_000,
    windowsHide: true,
  });
  assert.equal(run.status, 0, `launcher failed: ${run.stderr || run.stdout}`);
  return JSON.parse(readFileSync(resultPath, 'utf8'));
}

test('service launcher is loopback-only and clears all cutover credentials', () => {
  const script = read('start_i_core_service.ps1');
  assert.match(script, /\$env:I_CORE_HOST\s*=\s*'127\.0\.0\.1'/);
  assert.match(script, /\[ValidateRange\(1, 65535\)\]\[int\]\$CorePort = 47841/);
  assert.match(script, /\$env:I_CORE_PORT\s*=\s*\[string\]\$CorePort/);
  assert.match(script, /Join-Path \$StateDirectory 'i-core\.sqlite'/);
  for (const name of [
    'I_CORE_PAIRING_CODE',
    'I_CORE_CERT',
    'I_CORE_KEY',
    'I_CORE_WORKER_SECRET',
    'I_CORE_COMPANION_REPLY_JOBS',
    'I_CORE_ACTIVITY_ADMIN_SECRET',
    'I_CORE_SHORTCUT_MAIL_MANUAL_TEST_ENABLED',
  ]) {
    assert.match(script, new RegExp(`Remove-Item Env:${name}`));
  }
  assert.match(script, /Join-Path \$StateDirectory 'shortcut-mail-relay\.enabled'/);
  assert.match(script, /Join-Path \$StateDirectory 'shortcut-mail-relay\.configure\.lock'/);
  assert.match(script, /Join-Path \$StateDirectory 'shortcut-mail-relay\.runtime\.lock'/);
  assert.match(script, /FileMode\]::OpenOrCreate/);
  assert.match(script, /FileShare\]::None/);
  assert.match(script, /Test-Path -LiteralPath \$shortcutMailEnableMarker -PathType Leaf/);
  assert.match(script, /Test-Path -LiteralPath \$shortcutMailConfigureLock -PathType Leaf/);
  assert.match(script, /\$env:I_CORE_SHORTCUT_MAIL_MANUAL_TEST_ENABLED\s*=\s*'1'/);
  assert.match(script, /& \$resolvedNode \$serverPath/);
  assert.match(script, /exit \$exitCode/);
});

test('service launcher rejects an inherited synthetic activity owner before starting its child', (t) => {
  if (process.platform !== 'win32') {
    t.skip('the launcher execution guard requires Windows PowerShell');
    return;
  }
  const script = read('start_i_core_service.ps1');
  const vulnerableScript = script.replace(/Remove-Item Env:I_CORE_ACTIVITY_ADMIN_SECRET -ErrorAction SilentlyContinue\r?\n/, '');
  assert.notEqual(vulnerableScript, script, 'the vulnerable launcher fixture must remove the activity owner guard');

  const vulnerableChild = runLauncherWithSyntheticActivityOwner(t, vulnerableScript);
  assert.equal(vulnerableChild.activity_admin_secret, 'synthetic-owner-secret');

  const guardedChild = runLauncherWithSyntheticActivityOwner(t, script);
  assert.equal(guardedChild.activity_admin_secret, undefined);
});

test('installer registers a limited current-user logon task with daemon-safe settings', () => {
  const script = read('install_i_core_autostart.ps1');
  assert.match(script, /\$taskName\s*=\s*'HereIAm-iCore'/);
  assert.match(script, /\$existingTask\.Description -ne \$ownershipMarker/);
  assert.match(script, /Refusing to replace an unowned scheduled task/);
  assert.match(script, /New-ScheduledTaskTrigger -AtLogOn -User \$currentUser/);
  assert.match(script, /\$trigger\.Delay\s*=\s*'PT10S'/);
  assert.match(script, /-LogonType Interactive/);
  assert.match(script, /-RunLevel Limited/);
  assert.match(script, /-AllowStartIfOnBatteries/);
  assert.match(script, /-DontStopIfGoingOnBatteries/);
  assert.match(script, /-RestartCount 5/);
  assert.match(script, /-ExecutionTimeLimit \(\[TimeSpan\]::Zero\)/);
  assert.match(script, /-MultipleInstances IgnoreNew/);
  assert.match(script, /start_i_core_service\.ps1/);
  assert.doesNotMatch(script, /I_CORE_PAIRING_CODE|I_CORE_WORKER_SECRET/);
});

test('uninstaller removes only the scheduled task and explicitly preserves data', () => {
  const script = read('uninstall_i_core_autostart.ps1');
  assert.match(script, /\$task\.Description -ne \$ownershipMarker/);
  assert.match(script, /Refusing to remove an unowned scheduled task/);
  assert.match(script, /Unregister-ScheduledTask/);
  assert.match(script, /data_removed\s*=\s*\$false/);
  assert.doesNotMatch(script, /Remove-Item|\.state\\/);
});


test('upload mode is a deliberate launch argument and inherited approval paths never reach child', t => {
 if (process.platform !== 'win32') { t.skip('Windows launcher'); return; }
 const script = read('start_i_core_service.ps1');
 for (const [argument, expected] of [[null, 'pr10'], ['legacy_b3', 'legacy_b3'], ['disabled', 'disabled']]) {
  const child = runLauncherWithSyntheticActivityOwner(t, script, argument);
  assert.equal(child.companion_upload_mode, expected);
  assert.equal(child.transcript_grants_path, undefined);
  assert.equal(child.replay_approvals_path, undefined);
 }
});
