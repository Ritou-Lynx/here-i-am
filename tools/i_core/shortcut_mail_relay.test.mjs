import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import {
  existsSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { createServer } from 'node:net';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import {
  ShortcutMailRelay,
  ShortcutMailRelayError,
  SHORTCUT_SUBJECT_CODE,
  SHORTCUT_WORKFLOW,
} from './shortcut_mail_relay.mjs';

function tokenHash(token) { return createHash('sha256').update(token).digest('hex'); }
function fixture({ dispatcher = async () => ({ accepted: true, providerReceiptId: 'smtp-ok' }), now = () => 1_700_000_000_000, ...options } = {}) {
  const dir = mkdtempSync(path.join(os.tmpdir(), 'shortcut-mail-relay-'));
  const relay = new ShortcutMailRelay({
    databasePath: path.join(dir, 'journal.sqlite'), tokenHash: tokenHash('scoped-token'),
    receiverHint: 'r***@example.test', dispatcher, now, ...options,
  });
  return { relay, dispose: () => { relay.close(); rmSync(dir, { recursive: true, force: true }); } };
}
const KEY_ONE = '8c0a6191-7fe3-4df0-a6f4-8f829e44ba36';
const KEY_TWO = '023489e5-cd79-446d-bcc4-3f2215df1f0b';
const KEY_THREE = '98f15b8a-f3e2-4c75-8798-ae07c952737f';
const KEY_FOUR = '41dc861f-a17b-4e59-b91e-50729eeb4a65';
function request(key = KEY_ONE, token = 'scoped-token') {
  return { workflow: SHORTCUT_WORKFLOW, token, idempotency_key: key };
}

async function freeLoopbackPort() {
  const server = createServer();
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
  const address = server.address();
  await new Promise((resolve) => server.close(resolve));
  return address.port;
}

async function holdExclusive(filePath) {
  const command = [
    '$filePath = $env:I_CORE_TEST_LOCK_PATH',
    '$handle = [System.IO.File]::Open($filePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)',
    "try { [Console]::Out.WriteLine('READY'); [Console]::Out.Flush(); [void][Console]::In.ReadLine() } finally { $handle.Dispose() }",
  ].join('; ');
  const child = spawn('powershell.exe', [
    '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
    '-Command', command,
  ], {
    env: { ...process.env, I_CORE_TEST_LOCK_PATH: filePath },
    stdio: ['pipe', 'pipe', 'pipe'],
    windowsHide: true,
  });
  let stdout = '';
  let stderr = '';
  await new Promise((resolve, reject) => {
    let ready = false;
    const timer = setTimeout(() => reject(new Error(`exclusive holder timed out: ${stderr}`)), 5_000);
    child.stdout.on('data', (chunk) => {
      stdout += chunk.toString();
      if (!ready && stdout.includes('READY')) {
        ready = true;
        clearTimeout(timer);
        resolve();
      }
    });
    child.stderr.on('data', (chunk) => { stderr += chunk.toString(); });
    child.once('exit', (code) => {
      if (!ready) {
        clearTimeout(timer);
        reject(new Error(`exclusive holder exited ${code}: ${stderr}`));
      }
    });
  });
  return async () => {
    child.stdin.end('\n');
    if (child.exitCode !== null) return;
    await new Promise((resolve, reject) => {
      child.once('exit', (code) => code === 0 ? resolve() : reject(new Error(`exclusive holder exited ${code}: ${stderr}`)));
    });
  };
}

test('fixed-template request reaches injected dispatcher and records provider acceptance', async () => {
  const calls = [];
  const { relay, dispose } = fixture({ dispatcher: async (input) => { calls.push(input); return { accepted: true, providerReceiptId: 'smtp-1' }; } });
  try {
    const result = await relay.send(request());
    assert.equal(result.status, 'provider_accepted');
    assert.equal(result.idempotency_key, KEY_ONE);
    assert.equal(result.subject_code, SHORTCUT_SUBJECT_CODE);
    assert.equal(result.receiver_hint, 'r***@example.test');
    assert.equal(calls.length, 1);
    assert.deepEqual(Object.keys(calls[0]).sort(), ['receiptId', 'requestedAtMs', 'workflow']);
  } finally { dispose(); }
});

test('same idempotency key never dispatches a second time', async () => {
  let calls = 0;
  const { relay, dispose } = fixture({ dispatcher: async () => { calls += 1; return { accepted: true }; } });
  try {
    const first = await relay.send(request());
    const replay = await relay.send(request());
    assert.equal(calls, 1);
    assert.equal(replay.replay, true);
    assert.equal(replay.receipt_id, first.receipt_id);
  } finally { dispose(); }
});

test('one scoped token permits one new send while preserving same-key replay', async () => {
  let calls = 0;
  const { relay, dispose } = fixture({ dispatcher: async () => { calls += 1; return { accepted: true }; } });
  try {
    await relay.send(request(KEY_ONE));
    await assert.rejects(
      () => relay.send(request(KEY_TWO)),
      (error) => error.code === 'token_consumed' && error.status === 409,
    );
    assert.equal((await relay.send(request(KEY_ONE))).replay, true);
    assert.equal(calls, 1);
  } finally { dispose(); }
});

test('expired scoped token cannot send or query a receipt', async () => {
  let time = 1_700_000_000_000;
  const { relay, dispose } = fixture({
    now: () => time,
    tokenExpiresAtMs: time + 60_000,
  });
  try {
    await relay.send(request(KEY_ONE));
    time += 60_000;
    await assert.rejects(
      () => relay.send(request(KEY_ONE)),
      (error) => error.code === 'token_expired' && error.status === 401,
    );
    assert.throws(
      () => relay.getReceipt({ token: 'scoped-token', idempotency_key: KEY_ONE }),
      (error) => error.code === 'token_expired' && error.status === 401,
    );
  } finally { dispose(); }
});

test('rejects caller-selected mail fields and invalid scoped token', async () => {
  const { relay, dispose } = fixture();
  try {
    await assert.rejects(() => relay.send({ ...request(), to: 'attacker@example.test' }), (error) => error.code === 'fixed_template_only');
    await assert.rejects(() => relay.send({ ...request(), token: 'wrong' }), (error) => error.code === 'unauthorized');
    await assert.rejects(() => relay.send(request('not-a-uuid')), (error) => error.code === 'invalid_request');
  } finally { dispose(); }
});

test('dispatcher errors become outcome_unknown and are never retried', async () => {
  let calls = 0;
  const { relay, dispose } = fixture({ dispatcher: async () => { calls += 1; throw new Error('transport dropped'); } });
  try {
    const first = await relay.send(request());
    const replay = await relay.send(request());
    assert.equal(first.status, 'outcome_unknown');
    assert.equal(replay.status, 'outcome_unknown');
    assert.equal(calls, 1);
  } finally { dispose(); }
});

test('five-minute and daily limits count send_started attempts', async () => {
  let time = 1_700_000_000_000;
  const dir = mkdtempSync(path.join(os.tmpdir(), 'shortcut-mail-limits-'));
  const databasePath = path.join(dir, 'journal.sqlite');
  const open = (token) => new ShortcutMailRelay({
    databasePath,
    tokenHash: tokenHash(token),
    receiverHint: 'r***@example.test',
    dispatcher: async () => ({ accepted: true }),
    now: () => time,
    minIntervalMs: 300_000,
    dailyLimit: 3,
  });
  let relay = open('token-one');
  try {
    await relay.send(request(KEY_ONE, 'token-one'));
    relay.close();
    relay = open('token-two');
    await assert.rejects(
      () => relay.send(request(KEY_TWO, 'token-two')),
      (error) => error instanceof ShortcutMailRelayError && error.code === 'rate_limited_interval',
    );
    time += 300_000;
    await relay.send(request(KEY_TWO, 'token-two'));
    relay.close();
    relay = open('token-three');
    time += 300_000;
    await relay.send(request(KEY_THREE, 'token-three'));
    relay.close();
    relay = open('token-four');
    time += 300_000;
    await assert.rejects(
      () => relay.send(request(KEY_FOUR, 'token-four')),
      (error) => error.code === 'rate_limited_daily',
    );
  } finally {
    relay.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test('a concurrent different request cannot bypass single-use token consumption', async () => {
  let releaseDispatch;
  let calls = 0;
  const { relay, dispose } = fixture({
    dispatcher: async () => {
      calls += 1;
      return new Promise((resolve) => { releaseDispatch = resolve; });
    },
  });
  try {
    const first = relay.send(request(KEY_ONE));
    await assert.rejects(
      () => relay.send(request(KEY_TWO)),
      (error) => error.code === 'token_consumed',
    );
    assert.equal(calls, 1);
    releaseDispatch({ accepted: true });
    assert.equal((await first).status, 'provider_accepted');
  } finally { dispose(); }
});

test('authenticated receipt query returns persisted response and absent receipts are typed 404', async () => {
  const { relay, dispose } = fixture();
  try {
    const sent = await relay.send(request());
    const receipt = relay.getReceipt({ token: 'scoped-token', idempotency_key: KEY_ONE });
    assert.equal(receipt.receipt_id, sent.receipt_id);
    assert.equal(receipt.subject_code, SHORTCUT_SUBJECT_CODE);
    assert.throws(
      () => relay.getReceipt({ token: 'scoped-token', idempotency_key: KEY_TWO }),
      (error) => error instanceof ShortcutMailRelayError && error.code === 'receipt_not_found' && error.status === 404,
    );
    assert.throws(
      () => relay.getReceipt({ token: 'wrong', idempotency_key: KEY_ONE }),
      (error) => error.code === 'unauthorized',
    );
  } finally { dispose(); }
});

test('restart terminalizes interrupted attempts without dispatching again', () => {
  const dir = mkdtempSync(path.join(os.tmpdir(), 'shortcut-mail-recovery-'));
  const databasePath = path.join(dir, 'journal.sqlite');
  const options = {
    databasePath,
    tokenHash: tokenHash('scoped-token'),
    receiverHint: 'r***@example.test',
    dispatcher: async () => ({ accepted: true }),
    now: () => 1_700_000_100_000,
  };
  const first = new ShortcutMailRelay(options);
  first.db.prepare(`
    INSERT INTO shortcut_mail_journal(
      idempotency_key, request_digest, token_scope_hash, workflow, receipt_id, receiver_hint,
      status, created_at_ms, updated_at_ms, send_started_at_ms
    ) VALUES (?, 'digest', ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(
    KEY_ONE,
    tokenHash('scoped-token'),
    SHORTCUT_WORKFLOW,
    'receipt-reserved',
    'r***@example.test',
    'reserved',
    1_700_000_000_000,
    1_700_000_000_000,
    null,
  );
  first.db.prepare(`
    INSERT INTO shortcut_mail_journal(
      idempotency_key, request_digest, token_scope_hash, workflow, receipt_id, receiver_hint,
      status, created_at_ms, updated_at_ms, send_started_at_ms
    ) VALUES (?, 'digest', ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(
    KEY_TWO,
    tokenHash('scoped-token'),
    SHORTCUT_WORKFLOW,
    'receipt-started',
    'r***@example.test',
    'send_started',
    1_700_000_000_000,
    1_700_000_000_010,
    1_700_000_000_010,
  );
  first.close();

  const restarted = new ShortcutMailRelay(options);
  try {
    assert.equal(
      restarted.getReceipt({ token: 'scoped-token', idempotency_key: KEY_ONE }).status,
      'failed_before_send',
    );
    assert.equal(
      restarted.getReceipt({ token: 'scoped-token', idempotency_key: KEY_TWO }).status,
      'outcome_unknown',
    );
  } finally {
    restarted.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test('PowerShell artifacts are static-safe for subject, configuration, and dispatcher bounds', () => {
  const script = readFileSync(new URL('./send_shortcut_mail.ps1', import.meta.url), 'utf8');
  const tlsHelper = readFileSync(new URL('./strict_smtp_tls_validation.ps1', import.meta.url), 'utf8');
  const configure = readFileSync(new URL('./configure_shortcut_mail_relay.ps1', import.meta.url), 'utf8');
  const rotateToken = readFileSync(new URL('./rotate_shortcut_mail_token.ps1', import.meta.url), 'utf8');
  const copyToken = readFileSync(new URL('./copy_shortcut_mail_token.ps1', import.meta.url), 'utf8');
  const relay = readFileSync(new URL('./shortcut_mail_relay.mjs', import.meta.url), 'utf8');
  assert.match(script, /0x54C4, 0x7761, 0x804A, 0x5929/);
  assert.doesNotMatch(script, /smtp-accepted:/);
  assert.doesNotMatch(script, /System\.Net\.Mail\.SmtpClient/);
  assert.doesNotMatch(script, /Send-MailMessage/);
  assert.match(script, /System\.Net\.Dns\]::BeginGetHostAddresses\(\$SmtpHost/);
  assert.match(script, /Get-TransportRemainingMs 5000/);
  assert.match(script, /AddressFamily\]::InterNetwork/);
  assert.match(script, /Sort-Object -Property IPAddressToString -Unique/);
  assert.match(script, /Select-Object -First 8/);
  assert.match(script, /foreach \(\$ipv4Address in \$ipv4Addresses\)/);
  assert.match(script, /BeginConnect\(\$ipv4Address, \$SmtpPort/);
  assert.match(script, /return \$tcpClient/);
  assert.ok(
    script.indexOf('$tcpClient = Connect-SmtpIPv4') < script.indexOf('$tlsHandshake = $sslStream.BeginAuthenticateAsClient('),
    'IPv4 selection must finish before TLS begins',
  );
  assert.match(script, /System\.Net\.Security\.SslStream/);
  assert.match(script, /New-StrictSmtpTlsValidationCallback/);
  assert.match(
    script,
    /\$sslStream\.BeginAuthenticateAsClient\(\s*\$smtpHost,\s*\$null,\s*\[System\.Security\.Authentication\.SslProtocols\]::Tls12,\s*\$false,\s*\$null,\s*\$null\s*\)/,
  );
  assert.doesNotMatch(script, /AuthenticateAsClient\(\$ipv4Address/);
  assert.match(script, /transportBudgetMs = 35000/);
  assert.match(script, /Get-TransportRemainingMs 20000/);
  assert.match(script, /Relay configuration could not be loaded\./);
  assert.match(script, /SMTP credential could not be loaded\./);
  assert.match(script, /Read-SmtpLine[\s\S]*characterCount -le 4096/);
  assert.match(script, /replyCharacterCount -gt 32768/);
  assert.match(script, /smtp\.gmail\.com[\s\S]*\$smtpPort -ne 587/);
  assert.match(script, /server did not advertise STARTTLS/);
  assert.match(script, /UserName\.Equals\(\$sender, \[System\.StringComparison\]::OrdinalIgnoreCase\)/);
  assert.match(script, /Guid\]::TryParseExact\(\$ReceiptId, 'D'/);
  assert.match(script, /Send-SmtpCommand[\s\S]*'STARTTLS'/);
  assert.match(script, /Send-SmtpCommand[\s\S]*'AUTH LOGIN'/);
  const probeIndex = script.indexOf('if ($AuthenticationProbe)');
  const mailFromIndex = script.indexOf('-Command "MAIL FROM:<$Sender>"');
  assert.ok(probeIndex >= 0 && probeIndex < mailFromIndex, 'authentication probe must return before MAIL FROM');
  assert.match(script.slice(probeIndex, mailFromIndex), /-Command 'QUIT'[\s\S]*return \[pscustomobject\][\s\S]*message_sent = \$false/);
  assert.match(script, /'=\?UTF-8\?B\?' \+ \[Convert\]::ToBase64String\(\$bytes\) \+ '\?='/);
  assert.match(script, /Subject: \$encodedSubject/);
  assert.match(script, /if \(\$messageLine\.StartsWith\('\.'\)\) \{ \$messageLine = '\.' \+ \$messageLine \}/);
  assert.match(script, /\$Writer\.Write\("\.\`r\`n"\)[\s\S]*ExpectedCodes @\(250\) -Stage 'message acceptance'[\s\S]*try \{[\s\S]*QUIT after acceptance[\s\S]*\} catch \{\}[\s\S]*accepted = \$true/);
  assert.match(script, /Content-Transfer-Encoding: 7bit/);
  assert.match(script, /try \{ if \(\$null -ne \$writer\) \{ \$writer\.Dispose\(\) \} \} catch \{\}/);
  assert.match(script, /\$networkCredential\.Password = \$null/);
  assert.match(configure, /\[switch\]\$Force/);
  assert.match(configure, /Test-Path -LiteralPath \$ConfigPath/);
  assert.match(configure, /MailAddress/);
  assert.match(configure, /\$parsedSender = \[System\.Net\.Mail\.MailAddress\]::new\(\$sender\)/);
  assert.match(configure, /\$parsedRecipient = \[System\.Net\.Mail\.MailAddress\]::new\(\$recipient\)/);
  assert.doesNotMatch(configure, /\$senderAddress = \[System\.Net\.Mail\.MailAddress\]/i);
  assert.doesNotMatch(configure, /\$recipientAddress = \[System\.Net\.Mail\.MailAddress\]/i);
  assert.match(configure, /RandomNumberGenerator\]::Create\(\)/);
  assert.match(configure, /\.GetBytes\(\$tokenBytes\)/);
  assert.match(configure, /UTF8Encoding\]::new\(\$false\)/);
  assert.doesNotMatch(configure, /Join-Path \$PSScriptRoot/);
  assert.match(configure, /Split-Path -Parent \$MyInvocation\.MyCommand\.Path/);
  assert.doesNotMatch(copyToken, /Join-Path \$PSScriptRoot/);
  assert.match(configure, /use_ssl = \$true/);
  assert.match(configure, /token_expires_at_ms/);
  assert.match(configure, /FileMode\]::CreateNew/);
  assert.match(configure, /TcpListener\]::new/);
  assert.match(configure, /ExclusiveAddressUse = \$true/);
  assert.match(configure, /\$portGuard\.Start\(\)/);
  assert.match(configure, /Stop HereIAm-iCore before configuring or rotating/);
  assert.match(configure, /Export-Clixml -LiteralPath \$TokenCredentialPath/);
  assert.doesNotMatch(configure, /Set-Clipboard/);
  assert.match(configure, /\[switch\]\$UsePasswordDialog/);
  assert.match(configure, /System\.Windows\.Controls\.PasswordBox/);
  assert.match(configure, /ConvertTo-NormalizedGmailAppPassword \$passwordBox\.SecurePassword/);
  assert.doesNotMatch(configure, /\$passwordBox\.SecurePassword\.Copy\(\)/);
  assert.doesNotMatch(configure, /\$passwordBox\.Password\b/);
  assert.match(configure, /function ConvertTo-NormalizedGmailAppPassword\(\[System\.Security\.SecureString\]\$SecurePassword\)/);
  assert.match(configure, /\[char\]::IsWhiteSpace\(\$character\)/);
  assert.match(configure, /SecureStringToBSTR\(\$SecurePassword\)/);
  assert.match(configure, /ZeroFreeBSTR\(\$bstr\)/);
  assert.match(configure, /\$normalizedPassword\.AppendChar\(\$character\)/);
  assert.match(configure, /Received \$\(\$normalization\.NonWhitespaceCount\) non-whitespace characters and \$\(\$normalization\.WhitespaceCount\) whitespace characters\./);
  assert.match(configure, /\$window\.Tag = \$normalization\.NormalizedPassword/);
  assert.ok(
    configure.indexOf('if (-not $passwordAlreadyNormalized)')
      < configure.indexOf('Export-Clixml -LiteralPath $CredentialPath'),
    'the non-GUI validation must precede credential export',
  );
  assert.equal(/[^\x00-\x7f]/u.test(configure), false);
  assert.match(configure, /Enter a NEW Gmail app password/);
  assert.match(configure, /Input is masked and is not saved to terminal history/);
  assert.match(copyToken, /CanIncludeInClipboardHistory/);
  assert.match(copyToken, /CanUploadToCloudClipboard/);
  assert.match(copyToken, /ExcludeClipboardContentFromMonitorProcessing/);
  assert.match(copyToken, /GetClipboardSequenceNumber/);
  assert.match(copyToken, /ClearIfSequence\(uint expected\)/);
  assert.doesNotMatch(copyToken, /Write-(Output|Host).*\$token/);
  assert.match(script, /TLS is mandatory/);
  assert.match(tlsHelper, /errors != SslPolicyErrors\.None/);
  assert.match(tlsHelper, /CERT_CHAIN_REVOCATION_CHECK_CHAIN_EXCLUDE_ROOT/);
  assert.match(tlsHelper, /CERT_CHAIN_REVOCATION_CHECK_CACHE_ONLY/);
  assert.match(tlsHelper, /CERT_CHAIN_CACHE_ONLY_URL_RETRIEVAL/);
  assert.match(tlsHelper, /CERT_CHAIN_DISABLE_AIA/);
  assert.match(tlsHelper, /TrustStatus\.dwErrorStatus != 0/);
  assert.match(tlsHelper, /CertVerifyCertificateChainPolicy/);
  assert.match(relay, /shell: false/);
  assert.match(relay, /timeoutMs = 45_000/);
  assert.match(relay, /maxOutputBytes = 4096/);
  assert.match(relay, /child\.kill\(\)/);
  assert.doesNotMatch(relay, /stderr\.toString\(/);
  assert.match(rotateToken, /\[ValidateRange\(15, 1440\)\]\[int\]\$TokenLifetimeMinutes = 240/);
  assert.match(rotateToken, /\[System\.IO\.File\]::Open\([\s\S]*FileMode\]::CreateNew/);
  assert.match(rotateToken, /TcpListener\]::new/);
  assert.match(rotateToken, /ExclusiveAddressUse = \$true/);
  assert.match(rotateToken, /Remove-Item -LiteralPath \$EnableMarkerPath -Force -ErrorAction Stop/);
  assert.match(rotateToken, /Assert-DistinctPaths/);
  assert.match(rotateToken, /RuntimeLockPath/);
  assert.match(rotateToken, /FileMode\]::OpenOrCreate/);
  assert.match(rotateToken, /credential_path/);
  assert.match(rotateToken, /token_credential_path/);
  assert.match(rotateToken, /-not \(Test-Path -LiteralPath \(\[string\]\$config\.credential_path\) -PathType Leaf\)/);
  assert.doesNotMatch(rotateToken, /Test-Path -LiteralPath \(\[string\]\$config\.token_credential_path\) -PathType Leaf/);
  assert.match(rotateToken, /RandomNumberGenerator\]::Create\(\)/);
  assert.match(rotateToken, /\$token\.Length -ne 43/);
  assert.match(rotateToken, /Export-Clixml -LiteralPath \$tempTokenCredentialPath/);
  assert.match(rotateToken, /UTF8Encoding\]::new\(\$false\)/);
  assert.match(rotateToken, /File\]::Replace\(\$tempConfigPath, \$configFullPath, \$configBackupPath\)/);
  assert.match(rotateToken, /Export-Clixml -LiteralPath \$tempTokenCredentialPath/);
  assert.match(rotateToken, /\[System\.Array\]::Clear\(\$tokenBytes, 0, \$tokenBytes\.Length\)/);
  assert.match(rotateToken, /\$token = \$null/);
  assert.doesNotMatch(rotateToken, /Import-Clixml/);
  assert.doesNotMatch(rotateToken, /Set-Clipboard/);
  assert.doesNotMatch(rotateToken, /Write-(Output|Host).*\$(token|tokenHash|smtpCredentialPath|tokenCredentialPath)/i);
  assert.equal(/[^\x00-\x7f]/u.test(rotateToken), false);
});

test('raw SMTP transport parses under Windows PowerShell 5.1 without executing it', () => {
  const scriptPath = fileURLToPath(new URL('./send_shortcut_mail.ps1', import.meta.url));
  const command = [
    '$tokens = $null',
    '$errors = $null',
    '[void][System.Management.Automation.Language.Parser]::ParseFile($env:I_CORE_SMTP_SCRIPT, [ref]$tokens, [ref]$errors)',
    "if ($errors.Count -gt 0) { [Console]::Error.WriteLine('parse failed'); exit 1 }",
  ].join('; ');
  const result = spawnSync('powershell.exe', [
    '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', command,
  ], {
    env: { ...process.env, I_CORE_SMTP_SCRIPT: scriptPath },
    encoding: 'utf8',
    timeout: 5_000,
  });
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
});

test('strict SMTP TLS helper parses and compiles under Windows PowerShell 5.1', () => {
  const helperPath = fileURLToPath(new URL('./strict_smtp_tls_validation.ps1', import.meta.url));
  const command = [
    '$tokens = $null',
    '$errors = $null',
    '[void][System.Management.Automation.Language.Parser]::ParseFile($env:I_CORE_TLS_HELPER, [ref]$tokens, [ref]$errors)',
    "if ($errors.Count -gt 0) { [Console]::Error.WriteLine('parse failed'); exit 1 }",
    '. $env:I_CORE_TLS_HELPER',
    'Initialize-StrictSmtpTlsValidation',
    "if (-not ('HereIam.ICore.Security.StrictSmtpTlsValidation' -as [type])) { exit 1 }",
  ].join('; ');
  const result = spawnSync('powershell.exe', [
    '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', command,
  ], {
    env: { ...process.env, I_CORE_TLS_HELPER: helperPath },
    encoding: 'utf8',
    timeout: 15_000,
  });
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
});

test('strict SMTP TLS source is fail-closed and never mutates global certificate stores', () => {
  const helper = readFileSync(new URL('./strict_smtp_tls_validation.ps1', import.meta.url), 'utf8');
  assert.doesNotMatch(helper, /DangerousAcceptAnyServerCertificateValidator|ServerCertificateValidationCallback\s*=|RemoteCertificateNameMismatch\s*\)/);
  assert.doesNotMatch(helper, /X509Store|StoreLocation\.(?:CurrentUser|LocalMachine)|CERT_STORE_OPEN_EXISTING_FLAG/);
  assert.doesNotMatch(helper, /SECURITY_FLAG_IGNORE|CERT_CHAIN_POLICY_IGNORE|IGNORE_(?:UNKNOWN_CA|WRONG_USAGE|CERT_DATE_INVALID)/);
  assert.match(helper, /CertStoreProvMemory = new IntPtr\(2\)/);
  assert.match(helper, /CERT_STORE_CREATE_NEW_FLAG/);
  assert.match(helper, /handler\.UseProxy = false/);
  assert.match(helper, /handler\.AllowAutoRedirect = false/);
  assert.match(helper, /response\.StatusCode != HttpStatusCode\.OK/);
  assert.match(helper, /MaxCrlUrls = 8/);
  assert.match(helper, /MaxCrlBytes = 4 \* 1024 \* 1024/);
  assert.match(helper, /MaxTotalCrlBytes = 12 \* 1024 \* 1024/);
  assert.match(helper, /CERT_CHAIN_DISABLE_AUTH_ROOT_AUTO_UPDATE/);
  assert.match(helper, /CertFreeCertificateChain\(chainContext\)/);
  assert.match(helper, /CertFreeCertificateChainEngine\(chainEngine\)/);
  assert.match(helper, /CertFreeCRLContext/);
  assert.match(helper, /CertCloseStore\(memoryStore, 0\)/);
});

test('strict SMTP TLS URL, response, body, cleanup, and callback guards execute offline', () => {
  const helperPath = fileURLToPath(new URL('./strict_smtp_tls_validation.ps1', import.meta.url));
  const dir = mkdtempSync(path.join(os.tmpdir(), 'shortcut-mail-strict-tls-'));
  const harnessPath = path.join(dir, 'strict-tls-harness.ps1');
  const harness = String.raw`
. $env:I_CORE_TLS_HELPER
Initialize-StrictSmtpTlsValidation

Add-Type -ReferencedAssemblies @('System.Net.Http.dll') -TypeDefinition @'
using System;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;

public sealed class TrackingStream : MemoryStream {
  public static bool WasDisposed;
  public TrackingStream(byte[] bytes) : base(bytes, false) { WasDisposed = false; }
  protected override void Dispose(bool disposing) { WasDisposed = true; base.Dispose(disposing); }
}

public sealed class FixtureHandler : HttpMessageHandler {
  public static bool WasDisposed;
  private readonly HttpStatusCode status;
  private readonly byte[] body;
  private readonly long? declaredLength;
  public FixtureHandler(int status, byte[] body, long? declaredLength) {
    WasDisposed = false;
    this.status = (HttpStatusCode)status;
    this.body = body;
    this.declaredLength = declaredLength;
  }
  protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) {
    HttpResponseMessage response = new HttpResponseMessage(status);
    response.Content = new StreamContent(new TrackingStream(body));
    if (declaredLength.HasValue) response.Content.Headers.ContentLength = declaredLength.Value;
    return Task.FromResult(response);
  }
  protected override void Dispose(bool disposing) { WasDisposed = true; base.Dispose(disposing); }
}
'@

function Invoke-Fixture([int]$Status, [byte[]]$Body, [Nullable[Int64]]$DeclaredLength, [int]$Limit) {
  $handler = [FixtureHandler]::new($Status, $Body, $DeclaredLength)
  try {
    $bytes = [HereIam.ICore.Security.StrictSmtpTlsValidation]::DownloadForTest(
      $handler, 'http://c.pki.goog/test.crl', 1000, $Limit)
    return [pscustomobject]@{ accepted = $true; length = $bytes.Length; handler = [FixtureHandler]::WasDisposed; stream = [TrackingStream]::WasDisposed }
  } catch {
    return [pscustomobject]@{ accepted = $false; length = 0; handler = [FixtureHandler]::WasDisposed; stream = [TrackingStream]::WasDisposed }
  }
}

$ok = Invoke-Fixture 200 ([byte[]](1,2,3)) ([Nullable[Int64]]3) 16
$partial = Invoke-Fixture 206 ([byte[]](1,2,3)) ([Nullable[Int64]]3) 16
$oversized = Invoke-Fixture 200 ([byte[]](1,2,3,4,5)) $null 4
$truncated = Invoke-Fixture 200 ([byte[]](1,2,3)) ([Nullable[Int64]]4) 16
$type = [HereIam.ICore.Security.StrictSmtpTlsValidation]
[pscustomobject]@{
  allowed_http = $type::IsAllowedCrlUri('http://c.pki.goog/a.crl')
  allowed_https = $type::IsAllowedCrlUri('https://crl.pki.goog/a.crl')
  evil_suffix = $type::IsAllowedCrlUri('http://c.pki.goog.evil.test/a.crl')
  userinfo = $type::IsAllowedCrlUri('http://c.pki.goog@evil.test/a.crl')
  custom_port = $type::IsAllowedCrlUri('http://c.pki.goog:8080/a.crl')
  file_scheme = $type::IsAllowedCrlUri('file:///tmp/a.crl')
  ok = $ok
  partial = $partial
  oversized = $oversized
  truncated = $truncated
  null_callback = $type::InvokeFailClosedCallbackForTest([System.Net.Security.SslPolicyErrors]::None)
  mismatch_callback = $type::InvokeFailClosedCallbackForTest([System.Net.Security.SslPolicyErrors]::RemoteCertificateNameMismatch)
} | ConvertTo-Json -Compress -Depth 4
`;
  try {
    writeFileSync(harnessPath, harness, 'utf8');
    const result = spawnSync('powershell.exe', [
      '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', harnessPath,
    ], {
      env: { ...process.env, I_CORE_TLS_HELPER: helperPath },
      encoding: 'utf8',
      timeout: 15_000,
    });
    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
    const evidence = JSON.parse(result.stdout.trim());
    assert.equal(evidence.allowed_http, true);
    assert.equal(evidence.allowed_https, true);
    assert.equal(evidence.evil_suffix, false);
    assert.equal(evidence.userinfo, false);
    assert.equal(evidence.custom_port, false);
    assert.equal(evidence.file_scheme, false);
    assert.deepEqual(evidence.ok, { accepted: true, length: 3, handler: true, stream: true });
    assert.deepEqual(evidence.partial, { accepted: false, length: 0, handler: true, stream: true });
    assert.deepEqual(evidence.oversized, { accepted: false, length: 0, handler: true, stream: true });
    assert.deepEqual(evidence.truncated, { accepted: false, length: 0, handler: true, stream: true });
    assert.equal(evidence.null_callback, false);
    assert.equal(evidence.mismatch_callback, false);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('production SMTP parser, command writer, and envelope branches execute offline', () => {
  const script = readFileSync(new URL('./send_shortcut_mail.ps1', import.meta.url), 'utf8');
  const functionsEnd = script.indexOf('# SMTP runtime starts here.');
  assert.ok(functionsEnd > 0, 'production protocol functions must remain extractable');
  const dir = mkdtempSync(path.join(os.tmpdir(), 'shortcut-mail-smtp-protocol-'));
  const harnessPath = path.join(dir, 'protocol-harness.ps1');
  const harness = String.raw`
Add-Type -TypeDefinition @'
using System;
using System.IO;
public sealed class ChunkedReadStream : MemoryStream {
  private readonly int chunkSize;
  public ChunkedReadStream(byte[] bytes, int chunkSize) : base(bytes, false) {
    this.chunkSize = chunkSize;
  }
  public override int Read(byte[] buffer, int offset, int count) {
    return base.Read(buffer, offset, Math.Min(count, chunkSize));
  }
}
'@

function New-ChunkedReader([string]$Text, [int]$ChunkSize) {
  $bytes = [System.Text.Encoding]::ASCII.GetBytes($Text)
  return New-SmtpTextReader ([ChunkedReadStream]::new($bytes, $ChunkSize))
}

function New-Capture {
  $stream = [System.IO.MemoryStream]::new()
  return [pscustomobject]@{ Stream = $stream; Writer = (New-SmtpTextWriter $stream) }
}

function Get-CaptureText($Capture) {
  $Capture.Writer.Flush()
  return [System.Text.Encoding]::UTF8.GetString($Capture.Stream.ToArray())
}

function Test-Rejected([scriptblock]$Action) {
  try { $null = & $Action; return $false } catch { return $true }
}

function Assert-Harness([bool]$Condition, [string]$Label) {
  if (-not $Condition) { throw "Offline SMTP harness assertion failed: $Label" }
}

$crlf = [string][char]13 + [string][char]10

# One-byte underlying reads exercise fragmentation. The second reply is already
# coalesced in the same stream when the first multiline reply is parsed.
$combinedReader = New-ChunkedReader ("250-first" + $crlf + "250-STARTTLS" + $crlf + "250 ready" + $crlf + "220 next" + $crlf) 1
$firstReply = Read-SmtpReply -Reader $combinedReader -ExpectedCodes @(250) -Stage 'fragmented multiline'
$secondReply = Read-SmtpReply -Reader $combinedReader -ExpectedCodes @(220) -Stage 'coalesced next reply'
Assert-Harness ($firstReply.Code -eq 250 -and $firstReply.Lines.Count -eq 3 -and $secondReply.Code -eq 220) 'fragmented/coalesced replies'

$bareLfRejected = Test-Rejected {
  $reader = New-ChunkedReader ("250 invalid" + [string][char]10) 1
  Read-SmtpReply -Reader $reader -ExpectedCodes @(250) -Stage 'bare LF'
}
$oversizedRejected = Test-Rejected {
  $reader = New-ChunkedReader ("250 " + ('x' * 4097) + $crlf) 7
  Read-SmtpReply -Reader $reader -ExpectedCodes @(250) -Stage 'oversized line'
}
$changedCodeRejected = Test-Rejected {
  $reader = New-ChunkedReader ("250-first" + $crlf + "550 changed" + $crlf) 2
  Read-SmtpReply -Reader $reader -ExpectedCodes @(250) -Stage 'changed continuation code'
}
Assert-Harness $bareLfRejected 'bare LF rejection'
Assert-Harness $oversizedRejected 'oversized line rejection'
Assert-Harness $changedCodeRejected 'continuation code lock'

$commandReader = New-ChunkedReader ("250 ok" + $crlf) 2
$commandCapture = New-Capture
$null = Send-SmtpCommand -Writer $commandCapture.Writer -Reader $commandReader -Command 'NOOP' -ExpectedCodes @(250) -Stage 'command CRLF'
$commandText = Get-CaptureText $commandCapture
Assert-Harness ($commandText -ceq ("NOOP" + $crlf)) 'command CRLF'
$injectionCapture = New-Capture
$injectionRejected = Test-Rejected {
  $reader = New-ChunkedReader ("250 ok" + $crlf) 2
  Send-SmtpCommand -Writer $injectionCapture.Writer -Reader $reader -Command ("NOOP" + [string][char]10 + "MAIL") -ExpectedCodes @(250) -Stage 'injection'
}
Assert-Harness ($injectionRejected -and (Get-CaptureText $injectionCapture).Length -eq 0) 'command newline rejection'

$matrixCases = @(
  [pscustomobject]@{ Name = 'auth_challenge'; Command = 'AUTH LOGIN'; Expected = @(334); Good = @(334); Bad = 250 },
  [pscustomobject]@{ Name = 'auth_success'; Command = 'ZHVtbXk='; Expected = @(235); Good = @(235); Bad = 535 },
  [pscustomobject]@{ Name = 'mail'; Command = 'MAIL FROM:<sender@example.test>'; Expected = @(250); Good = @(250); Bad = 550 },
  [pscustomobject]@{ Name = 'rcpt'; Command = 'RCPT TO:<recipient@example.test>'; Expected = @(250, 251); Good = @(250, 251); Bad = 550 },
  [pscustomobject]@{ Name = 'data'; Command = 'DATA'; Expected = @(354); Good = @(354); Bad = 250 }
)
$matrixPassed = $true
foreach ($matrixCase in $matrixCases) {
  foreach ($goodCode in $matrixCase.Good) {
    $reader = New-ChunkedReader (([string]$goodCode) + " good" + $crlf) 3
    $capture = New-Capture
    $null = Send-SmtpCommand -Writer $capture.Writer -Reader $reader -Command $matrixCase.Command -ExpectedCodes $matrixCase.Expected -Stage $matrixCase.Name
    $matrixPassed = $matrixPassed -and ((Get-CaptureText $capture) -ceq ($matrixCase.Command + $crlf))
  }
  $badRejected = Test-Rejected {
    $reader = New-ChunkedReader (([string]$matrixCase.Bad) + " bad" + $crlf) 3
    $capture = New-Capture
    Send-SmtpCommand -Writer $capture.Writer -Reader $reader -Command $matrixCase.Command -ExpectedCodes $matrixCase.Expected -Stage $matrixCase.Name
  }
  $matrixPassed = $matrixPassed -and $badRejected
}
$finalAccepted = (Read-SmtpReply -Reader (New-ChunkedReader ("250 queued" + $crlf) 2) -ExpectedCodes @(250) -Stage 'final DATA').Code -eq 250
$finalRejected = Test-Rejected {
  Read-SmtpReply -Reader (New-ChunkedReader ("550 rejected" + $crlf) 2) -ExpectedCodes @(250) -Stage 'final DATA'
}
Assert-Harness ($matrixPassed -and $finalAccepted -and $finalRejected) 'reply code matrix'

$probeReader = New-ChunkedReader ("221 bye" + $crlf) 1
$probeCapture = New-Capture
$probeResult = Invoke-SmtpEnvelope -Writer $probeCapture.Writer -Reader $probeReader -Sender 'sender@example.test' -Recipient 'recipient@example.test' -MessageLines $null -AuthenticationProbe
$probeTranscript = Get-CaptureText $probeCapture
Assert-Harness ($probeResult.authenticated -and -not $probeResult.message_sent) 'probe result'
Assert-Harness ($probeTranscript -ceq ("QUIT" + $crlf)) 'probe zero-envelope transcript'

# RCPT 251 is accepted, DATA final 250 establishes acceptance, and a later
# QUIT 500 is swallowed without reversing it.
$sendReplies = "250 mail" + $crlf + "251 rcpt" + $crlf + "354 data" + $crlf + "250 queued" + $crlf + "500 quit" + $crlf
$sendReader = New-ChunkedReader $sendReplies 2
$sendCapture = New-Capture
$sendResult = Invoke-SmtpEnvelope -Writer $sendCapture.Writer -Reader $sendReader -Sender 'sender@example.test' -Recipient 'recipient@example.test' -MessageLines @('Header: value', '', 'line', '.leading')
$sendTranscript = Get-CaptureText $sendCapture
Assert-Harness $sendResult.accepted 'send acceptance'

[pscustomobject]@{
  fragmented_coalesced = $true
  bare_lf_rejected = $bareLfRejected
  oversized_rejected = $oversizedRejected
  changed_code_rejected = $changedCodeRejected
  command_text = $commandText
  matrix_passed = $matrixPassed
  final_rejected = $finalRejected
  probe_transcript = $probeTranscript
  send_accepted = [bool]$sendResult.accepted
  send_transcript = $sendTranscript
} | ConvertTo-Json -Compress
`;
  try {
    writeFileSync(harnessPath, `${script.slice(0, functionsEnd)}\n${harness}`, 'utf8');
    const result = spawnSync('powershell.exe', [
      '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
      '-File', harnessPath, '-ConfigPath', 'offline-unused',
    ], { encoding: 'utf8', timeout: 10_000 });
    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
    const evidence = JSON.parse(result.stdout.trim());
    assert.equal(evidence.fragmented_coalesced, true);
    assert.equal(evidence.bare_lf_rejected, true);
    assert.equal(evidence.oversized_rejected, true);
    assert.equal(evidence.changed_code_rejected, true);
    assert.equal(evidence.command_text, 'NOOP\r\n');
    assert.equal(evidence.matrix_passed, true);
    assert.equal(evidence.final_rejected, true);
    assert.equal(evidence.probe_transcript, 'QUIT\r\n');
    assert.doesNotMatch(evidence.probe_transcript, /MAIL FROM|RCPT TO|DATA/);
    assert.equal(evidence.send_accepted, true);
    assert.match(evidence.send_transcript, /^MAIL FROM:<sender@example\.test>\r\nRCPT TO:<recipient@example\.test>\r\nDATA\r\n/);
    assert.match(evidence.send_transcript, /\r\n\.\.leading\r\n\.\r\nQUIT\r\n$/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('Gmail app password normalizer permits grouping whitespace and fails closed outside 16 non-whitespace characters', () => {
  const configure = readFileSync(new URL('./configure_shortcut_mail_relay.ps1', import.meta.url), 'utf8');
  const normalizer = configure.match(/function ConvertTo-NormalizedGmailAppPassword[\s\S]*?\r?\n}\r?\n\$scriptRoot/);
  assert.ok(normalizer, 'normalizer function must remain extractable for isolated PowerShell verification');
  const dir = mkdtempSync(path.join(os.tmpdir(), 'shortcut-mail-app-password-validator-'));
  try {
    const command = [
      normalizer[0].replace(/\r?\n\$scriptRoot$/, ''),
      "$unicodeWhitespace = '1234' + [char]0x2003 + '5678' + [char]0x00a0 + '90abcdef'",
      "$values = @('12345678901234', '1234 5678 90abcdef', $unicodeWhitespace, '1234567890abcdefg')",
      'foreach ($value in $values) {',
      '  $secure = [System.Security.SecureString]::new()',
      '  foreach ($character in $value.ToCharArray()) { $secure.AppendChar($character) }',
      '  $secure.MakeReadOnly()',
      '  try {',
      '    $normalization = ConvertTo-NormalizedGmailAppPassword $secure',
      '    $normalizedLength = if ($null -eq $normalization.NormalizedPassword) { 0 } else { $normalization.NormalizedPassword.Length }',
      '    [Console]::WriteLine("$($normalization.NonWhitespaceCount)|$($normalization.WhitespaceCount)|$normalizedLength")',
      '    if ($null -ne $normalization.NormalizedPassword) { $normalization.NormalizedPassword.Dispose() }',
      '  } finally { $secure.Dispose() }',
      '}',
    ].join('\n');
    const result = spawnSync('powershell.exe', [
      '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', command,
    ], { cwd: dir, encoding: 'utf8', timeout: 5_000 });
    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
    assert.deepEqual(result.stdout.trim().split(/\r?\n/), ['14|0|0', '16|2|16', '16|2|16', '17|0|0']);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('configuration refuses to rotate while the iCore port is owned', async () => {
  const server = createServer();
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const dir = mkdtempSync(path.join(os.tmpdir(), 'shortcut-mail-config-lock-'));
  writeFileSync(path.join(dir, 'configure.lock'), 'stale-lock');
  const runtime = path.join(dir, 'runtime.lock');
  const address = server.address();
  assert.equal(typeof address, 'object');
  try {
    const result = spawnSync('powershell.exe', [
      '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
      '-File', fileURLToPath(new URL('./configure_shortcut_mail_relay.ps1', import.meta.url)),
      '-ConfigPath', path.join(dir, 'relay.json'),
      '-CredentialPath', path.join(dir, 'smtp.clixml'),
      '-TokenCredentialPath', path.join(dir, 'token.clixml'),
      '-EnableMarkerPath', path.join(dir, 'enabled'),
      '-ConfigureLockPath', path.join(dir, 'configure.lock'),
      '-RuntimeLockPath', runtime,
      '-CorePort', String(address.port),
      '-EnableManualTest',
    ], { encoding: 'utf8', timeout: 10_000 });
    assert.notEqual(result.status, 0);
    assert.match(`${result.stdout}\n${result.stderr}`, /iCore may still be listening/);
    assert.equal(existsSync(path.join(dir, 'relay.json')), false);
    assert.equal(existsSync(path.join(dir, 'smtp.clixml')), false);
    assert.equal(existsSync(path.join(dir, 'token.clixml')), false);
    assert.equal(existsSync(path.join(dir, 'enabled')), false);
    assert.equal(existsSync(path.join(dir, 'configure.lock')), false);
    assert.equal(existsSync(runtime), true);
  } finally {
    await new Promise((resolve) => server.close(resolve));
    rmSync(dir, { recursive: true, force: true });
  }
});

test('token-only rotation refuses while the iCore port is owned without touching its temp marker', async () => {
  const server = createServer();
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const dir = mkdtempSync(path.join(os.tmpdir(), 'shortcut-mail-token-rotation-lock-'));
  const marker = path.join(dir, 'enabled');
  const lock = path.join(dir, 'configure.lock');
  const runtime = path.join(dir, 'runtime.lock');
  writeFileSync(marker, 'enabled-v1');
  const smtp = path.join(dir, 'smtp.clixml');
  const token = path.join(dir, 'token.clixml');
  const config = path.join(dir, 'relay.json');
  writeFileSync(smtp, 'smtp-sentinel');
  writeFileSync(config, JSON.stringify({ workflow: SHORTCUT_WORKFLOW, credential_path: smtp, token_credential_path: token, token_hash: '0'.repeat(64), token_expires_at_ms: 1 }));
  const address = server.address();
  assert.equal(typeof address, 'object');
  try {
    const result = spawnSync('powershell.exe', [
      '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
      '-File', fileURLToPath(new URL('./rotate_shortcut_mail_token.ps1', import.meta.url)),
      '-ConfigPath', config,
      '-EnableMarkerPath', marker,
      '-ConfigureLockPath', lock,
      '-RuntimeLockPath', runtime,
      '-CorePort', String(address.port),
      '-EnableManualTest',
    ], { encoding: 'utf8', timeout: 5_000 });
    assert.notEqual(result.status, 0);
    assert.match(`${result.stdout}\n${result.stderr}`, /iCore may still be listening/);
    assert.equal(existsSync(marker), true);
    assert.equal(existsSync(lock), false);
  } finally {
    await new Promise((resolve) => server.close(resolve));
    rmSync(dir, { recursive: true, force: true });
  }
});

test('token-only rotation commits a missing token credential without changing SMTP or unrelated config fields', async () => {
  const dir = mkdtempSync(path.join(os.tmpdir(), 'shortcut-mail-token-rotation-success-'));
  const configPath = path.join(dir, 'relay.json');
  const smtpPath = path.join(dir, 'smtp.clixml');
  const tokenPath = path.join(dir, 'token.clixml');
  const marker = path.join(dir, 'enabled');
  const lock = path.join(dir, 'configure.lock');
  const runtime = path.join(dir, 'runtime.lock');
  writeFileSync(smtpPath, 'smtp-sentinel');
  writeFileSync(marker, 'enabled-v1');
  writeFileSync(configPath, JSON.stringify({ workflow: SHORTCUT_WORKFLOW, credential_path: smtpPath, token_credential_path: tokenPath, token_hash: '0'.repeat(64), token_expires_at_ms: 1, retained: { value: 'keep' } }));
  try {
    const result = spawnSync('powershell.exe', ['-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', fileURLToPath(new URL('./rotate_shortcut_mail_token.ps1', import.meta.url)), '-ConfigPath', configPath, '-EnableMarkerPath', marker, '-ConfigureLockPath', lock, '-RuntimeLockPath', runtime, '-CorePort', String(await freeLoopbackPort()), '-EnableManualTest'], { encoding: 'utf8', timeout: 10_000 });
    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
    const updated = JSON.parse(readFileSync(configPath, 'utf8'));
    assert.equal(updated.retained.value, 'keep');
    assert.match(updated.token_hash, /^[a-f0-9]{64}$/);
    assert.notEqual(updated.token_hash, '0'.repeat(64));
    assert.equal(readFileSync(smtpPath, 'utf8'), 'smtp-sentinel');
    assert.equal(existsSync(tokenPath), true);
    assert.equal(readFileSync(marker, 'utf8'), 'enabled-v1');
    assert.notDeepEqual([...readFileSync(configPath).subarray(0, 3)], [0xef, 0xbb, 0xbf]);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('token-only rotation rejects path collisions before touching config or credentials', async () => {
  const dir = mkdtempSync(path.join(os.tmpdir(), 'shortcut-mail-token-rotation-paths-'));
  const configPath = path.join(dir, 'relay.json');
  const smtpPath = path.join(dir, 'smtp.clixml');
  const tokenPath = path.join(dir, 'token.clixml');
  const marker = path.join(dir, 'enabled');
  const runtime = path.join(dir, 'runtime.lock');
  const configText = JSON.stringify({ workflow: SHORTCUT_WORKFLOW, credential_path: smtpPath, token_credential_path: tokenPath, token_hash: '0'.repeat(64), token_expires_at_ms: 1 });
  writeFileSync(configPath, configText);
  writeFileSync(smtpPath, 'smtp-sentinel');
  writeFileSync(marker, 'enabled-v1');
  try {
    const result = spawnSync('powershell.exe', [
      '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
      '-File', fileURLToPath(new URL('./rotate_shortcut_mail_token.ps1', import.meta.url)),
      '-ConfigPath', configPath, '-EnableMarkerPath', marker,
      '-ConfigureLockPath', smtpPath, '-RuntimeLockPath', runtime,
      '-CorePort', String(await freeLoopbackPort()), '-EnableManualTest',
    ], { encoding: 'utf8', timeout: 10_000 });
    assert.notEqual(result.status, 0);
    assert.match(`${result.stdout}\n${result.stderr}`, /paths must be distinct/);
    assert.equal(readFileSync(configPath, 'utf8'), configText);
    assert.equal(readFileSync(smtpPath, 'utf8'), 'smtp-sentinel');
    assert.equal(readFileSync(marker, 'utf8'), 'enabled-v1');
    assert.equal(existsSync(tokenPath), false);
    assert.equal(existsSync(runtime), false);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('token-only rotation fails closed when the enable marker cannot be removed', async () => {
  const dir = mkdtempSync(path.join(os.tmpdir(), 'shortcut-mail-token-rotation-marker-'));
  const configPath = path.join(dir, 'relay.json');
  const smtpPath = path.join(dir, 'smtp.clixml');
  const tokenPath = path.join(dir, 'token.clixml');
  const marker = path.join(dir, 'enabled');
  const lock = path.join(dir, 'configure.lock');
  const runtime = path.join(dir, 'runtime.lock');
  const configText = JSON.stringify({ workflow: SHORTCUT_WORKFLOW, credential_path: smtpPath, token_credential_path: tokenPath, token_hash: '0'.repeat(64), token_expires_at_ms: 1 });
  writeFileSync(configPath, configText);
  writeFileSync(smtpPath, 'smtp-sentinel');
  writeFileSync(marker, 'enabled-v1');
  const release = await holdExclusive(marker);
  let released = false;
  try {
    const result = spawnSync('powershell.exe', [
      '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
      '-File', fileURLToPath(new URL('./rotate_shortcut_mail_token.ps1', import.meta.url)),
      '-ConfigPath', configPath, '-EnableMarkerPath', marker,
      '-ConfigureLockPath', lock, '-RuntimeLockPath', runtime,
      '-CorePort', String(await freeLoopbackPort()), '-EnableManualTest',
    ], { encoding: 'utf8', timeout: 10_000 });
    assert.notEqual(result.status, 0);
    assert.equal(readFileSync(configPath, 'utf8'), configText);
    assert.equal(readFileSync(smtpPath, 'utf8'), 'smtp-sentinel');
    assert.equal(existsSync(tokenPath), false);
    assert.equal(existsSync(marker), true);
    await release();
    released = true;
    assert.equal(readFileSync(marker, 'utf8'), 'enabled-v1');
  } finally {
    if (!released) await release();
    rmSync(dir, { recursive: true, force: true });
  }
});

test('runtime lock keeps rotation and configuration closed without touching their markers', async () => {
  const dir = mkdtempSync(path.join(os.tmpdir(), 'shortcut-mail-runtime-lock-'));
  const runtime = path.join(dir, 'runtime.lock');
  const configPath = path.join(dir, 'relay.json');
  const smtpPath = path.join(dir, 'smtp.clixml');
  const tokenPath = path.join(dir, 'token.clixml');
  const marker = path.join(dir, 'enabled');
  const configLock = path.join(dir, 'configure.lock');
  const configText = JSON.stringify({ workflow: SHORTCUT_WORKFLOW, credential_path: smtpPath, token_credential_path: tokenPath, token_hash: '0'.repeat(64), token_expires_at_ms: 1 });
  writeFileSync(runtime, '');
  writeFileSync(configPath, configText);
  writeFileSync(smtpPath, 'smtp-sentinel');
  writeFileSync(marker, 'enabled-v1');
  const release = await holdExclusive(runtime);
  try {
    const rotate = spawnSync('powershell.exe', [
      '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
      '-File', fileURLToPath(new URL('./rotate_shortcut_mail_token.ps1', import.meta.url)),
      '-ConfigPath', configPath, '-EnableMarkerPath', marker,
      '-ConfigureLockPath', configLock, '-RuntimeLockPath', runtime,
      '-CorePort', String(await freeLoopbackPort()), '-EnableManualTest',
    ], { encoding: 'utf8', timeout: 10_000 });
    assert.notEqual(rotate.status, 0);
    assert.match(`${rotate.stdout}\n${rotate.stderr}`, /runtime is active or being started/);
    assert.equal(readFileSync(configPath, 'utf8'), configText);
    assert.equal(readFileSync(marker, 'utf8'), 'enabled-v1');
    assert.equal(existsSync(tokenPath), false);

    const newConfig = path.join(dir, 'new-relay.json');
    const newSmtp = path.join(dir, 'new-smtp.clixml');
    const newToken = path.join(dir, 'new-token.clixml');
    const newMarker = path.join(dir, 'new-enabled');
    const newConfigLock = path.join(dir, 'new-configure.lock');
    const configure = spawnSync('powershell.exe', [
      '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
      '-File', fileURLToPath(new URL('./configure_shortcut_mail_relay.ps1', import.meta.url)),
      '-ConfigPath', newConfig, '-CredentialPath', newSmtp, '-TokenCredentialPath', newToken,
      '-EnableMarkerPath', newMarker, '-ConfigureLockPath', newConfigLock,
      '-RuntimeLockPath', runtime, '-CorePort', String(await freeLoopbackPort()),
      '-SenderAddress', 'sender@example.test', '-RecipientAddress', 'recipient@example.test',
      '-SmtpHost', 'smtp.example.test', '-SmtpPort', '587', '-EnableManualTest',
    ], { encoding: 'utf8', timeout: 10_000 });
    assert.notEqual(configure.status, 0);
    assert.match(`${configure.stdout}\n${configure.stderr}`, /runtime is active or being started/);
    assert.equal(existsSync(newConfig), false);
    assert.equal(existsSync(newSmtp), false);
    assert.equal(existsSync(newToken), false);
    assert.equal(existsSync(newMarker), false);
  } finally {
    await release();
    rmSync(dir, { recursive: true, force: true });
  }
});
