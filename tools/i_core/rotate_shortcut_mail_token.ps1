[CmdletBinding()]
param(
  [string]$ConfigPath = '',
  [string]$EnableMarkerPath = '',
  [string]$ConfigureLockPath = '',
  [string]$RuntimeLockPath = '',
  [ValidateRange(1, 65535)][int]$CorePort = 47841,
  [ValidateRange(15, 1440)][int]$TokenLifetimeMinutes = 240,
  [switch]$EnableManualTest
)

$ErrorActionPreference = 'Stop'
function Assert-DistinctPaths([string[]]$Paths) {
  for ($left = 0; $left -lt $Paths.Length; $left++) {
    for ($right = $left + 1; $right -lt $Paths.Length; $right++) {
      if ([string]::Equals($Paths[$left], $Paths[$right], [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Shortcut mail relay paths must be distinct.'
      }
    }
  }
}
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
  $ConfigPath = Join-Path $scriptRoot '.state\shortcut-mail-relay.json'
}
if ([string]::IsNullOrWhiteSpace($EnableMarkerPath)) {
  $EnableMarkerPath = Join-Path $scriptRoot '.state\shortcut-mail-relay.enabled'
}
if ([string]::IsNullOrWhiteSpace($ConfigureLockPath)) {
  $ConfigureLockPath = Join-Path $scriptRoot '.state\shortcut-mail-relay.configure.lock'
}
if ([string]::IsNullOrWhiteSpace($RuntimeLockPath)) {
  $RuntimeLockPath = Join-Path $scriptRoot '.state\shortcut-mail-relay.runtime.lock'
}
try {
  $ConfigPath = [System.IO.Path]::GetFullPath($ConfigPath)
  $EnableMarkerPath = [System.IO.Path]::GetFullPath($EnableMarkerPath)
  $ConfigureLockPath = [System.IO.Path]::GetFullPath($ConfigureLockPath)
  $RuntimeLockPath = [System.IO.Path]::GetFullPath($RuntimeLockPath)
} catch { throw 'Shortcut mail relay paths are invalid.' }
Assert-DistinctPaths @($ConfigPath, $EnableMarkerPath, $ConfigureLockPath, $RuntimeLockPath)
if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
  throw 'Shortcut mail relay configuration is not available for token rotation.'
}
try { $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json }
catch { throw 'Shortcut mail relay configuration is invalid.' }
if ($config.workflow -ne 'ios_shortcut_test_v0') { throw 'Shortcut mail relay configuration is invalid.' }
if (
  [string]::IsNullOrWhiteSpace([string]$config.credential_path) -or
  [string]::IsNullOrWhiteSpace([string]$config.token_credential_path) -or
  -not [System.IO.Path]::IsPathRooted([string]$config.credential_path) -or
  -not [System.IO.Path]::IsPathRooted([string]$config.token_credential_path) -or
  -not (Test-Path -LiteralPath ([string]$config.credential_path) -PathType Leaf)
) { throw 'Shortcut mail relay configuration is incomplete.' }
if (([string]$config.token_hash) -notmatch '^[a-fA-F0-9]{64}$' -or $null -eq $config.token_expires_at_ms) {
  throw 'Shortcut mail relay configuration is invalid.'
}
$configFullPath = $ConfigPath
$tokenCredentialPath = [System.IO.Path]::GetFullPath([string]$config.token_credential_path)
$smtpCredentialPath = [System.IO.Path]::GetFullPath([string]$config.credential_path)
Assert-DistinctPaths @($configFullPath, $EnableMarkerPath, $ConfigureLockPath, $RuntimeLockPath, $smtpCredentialPath, $tokenCredentialPath)
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ConfigureLockPath) | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $RuntimeLockPath) | Out-Null
if (Test-Path -LiteralPath $ConfigureLockPath -PathType Leaf) {
  try {
    $staleLock = [System.IO.File]::Open(
      [System.IO.Path]::GetFullPath($ConfigureLockPath),
      [System.IO.FileMode]::Open,
      [System.IO.FileAccess]::ReadWrite,
      [System.IO.FileShare]::None
    )
    $staleLock.Dispose()
    Remove-Item -LiteralPath $ConfigureLockPath -Force
  } catch {
    throw 'Another Shortcut mail relay configuration is already in progress.'
  }
}

$configureLock = $null
$ownsConfigureLock = $false
$portGuard = $null
$runtimeLock = $null
$token = $null
$tokenBytes = $null
$tokenUtf8Bytes = $null
$tokenSecure = $null
$tokenCredential = $null
$tokenHash = $null
$tempConfigPath = $null
$tempTokenCredentialPath = $null
$configBackupPath = $null
$tokenBackupPath = $null
$configRollbackPath = $null
try {
  try {
    $configureLock = [System.IO.File]::Open(
      [System.IO.Path]::GetFullPath($ConfigureLockPath),
      [System.IO.FileMode]::CreateNew,
      [System.IO.FileAccess]::Write,
      [System.IO.FileShare]::None
    )
    $ownsConfigureLock = $true
  } catch {
    throw 'Another Shortcut mail relay configuration is already in progress.'
  }

  try {
    $runtimeLock = [System.IO.File]::Open(
      $RuntimeLockPath,
      [System.IO.FileMode]::OpenOrCreate,
      [System.IO.FileAccess]::ReadWrite,
      [System.IO.FileShare]::None
    )
  } catch {
    throw 'The Shortcut mail relay runtime is active or being started; rotation is closed.'
  }

  try {
    $portGuard = [System.Net.Sockets.TcpListener]::new(
      [System.Net.IPAddress]::Loopback,
      $CorePort
    )
    $portGuard.ExclusiveAddressUse = $true
    $portGuard.Start()
  } catch {
    throw "iCore may still be listening on 127.0.0.1:$CorePort. Stop HereIAm-iCore before rotating the relay."
  }

  # Fail closed before generating a token or writing either configuration file.
  if (Test-Path -LiteralPath $EnableMarkerPath) {
    Remove-Item -LiteralPath $EnableMarkerPath -Force -ErrorAction Stop
  }
  if (Test-Path -LiteralPath $EnableMarkerPath) {
    throw 'Shortcut mail relay could not be disabled for token rotation.'
  }

  $tokenBytes = New-Object byte[] 32
  $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  try { $rng.GetBytes($tokenBytes) }
  finally { $rng.Dispose() }
  $token = [Convert]::ToBase64String($tokenBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
  if ($token.Length -ne 43) { throw 'Token generation failed.' }
  $tokenSecure = [System.Security.SecureString]::new()
  foreach ($tokenCharacter in $token.ToCharArray()) { $tokenSecure.AppendChar($tokenCharacter) }
  $tokenSecure.MakeReadOnly()
  $tokenCredential = [System.Management.Automation.PSCredential]::new('shortcut-mail-manual-test', $tokenSecure)
  $tokenUtf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($token)
  $sha256 = [System.Security.Cryptography.SHA256]::Create()
  try { $tokenHash = -join ($sha256.ComputeHash($tokenUtf8Bytes) | ForEach-Object { $_.ToString('x2') }) }
  finally { $sha256.Dispose() }

  $config.token_hash = $tokenHash
  $config.token_expires_at_ms = [DateTimeOffset]::UtcNow.AddMinutes($TokenLifetimeMinutes).ToUnixTimeMilliseconds()
  $configJson = $config | ConvertTo-Json -Depth 4
  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  $tempConfigPath = "$configFullPath.rotate-$([guid]::NewGuid().ToString('N')).tmp"
  $tempTokenCredentialPath = "$tokenCredentialPath.rotate-$([guid]::NewGuid().ToString('N')).tmp"
  $configBackupPath = "$configFullPath.rotate-$([guid]::NewGuid().ToString('N')).bak"
  $tokenBackupPath = "$tokenCredentialPath.rotate-$([guid]::NewGuid().ToString('N')).bak"
  $configRollbackPath = "$configFullPath.rotate-$([guid]::NewGuid().ToString('N')).rollback"
  [System.IO.File]::WriteAllText($tempConfigPath, $configJson, $utf8NoBom)
  $tokenCredential | Export-Clixml -LiteralPath $tempTokenCredentialPath -Force
  try {
    [System.IO.File]::Replace($tempConfigPath, $configFullPath, $configBackupPath)
  } catch {
    throw 'Shortcut mail relay configuration update failed.'
  }
  $tempConfigPath = $null
  try {
    if (Test-Path -LiteralPath $tokenCredentialPath -PathType Leaf) {
      [System.IO.File]::Replace($tempTokenCredentialPath, $tokenCredentialPath, $tokenBackupPath)
    } else {
      [System.IO.File]::Move($tempTokenCredentialPath, $tokenCredentialPath)
    }
  } catch {
    try {
      [System.IO.File]::Replace($configBackupPath, $configFullPath, $configRollbackPath)
      $configBackupPath = $null
      Remove-Item -LiteralPath $configRollbackPath -Force -ErrorAction SilentlyContinue
      $configRollbackPath = $null
    } catch { }
    throw 'Shortcut mail relay token update failed; the relay remains disabled.'
  }
  $tempTokenCredentialPath = $null
  if (Test-Path -LiteralPath $configBackupPath -PathType Leaf) {
    Remove-Item -LiteralPath $configBackupPath -Force -ErrorAction Stop
  }
  $configBackupPath = $null
  if (Test-Path -LiteralPath $tokenBackupPath -PathType Leaf) {
    Remove-Item -LiteralPath $tokenBackupPath -Force -ErrorAction Stop
  }
  $tokenBackupPath = $null

  if ($EnableManualTest) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $EnableMarkerPath) | Out-Null
    [System.IO.File]::WriteAllText(
      [System.IO.Path]::GetFullPath($EnableMarkerPath),
      'enabled-v1',
      $utf8NoBom
    )
  }
  if ($EnableManualTest) {
    Write-Output 'Shortcut mail relay token rotated and explicitly enabled.'
  } else {
    Write-Output 'Shortcut mail relay token rotated but remains disabled.'
  }
} finally {
  if ($null -ne $tokenSecure) { $tokenSecure.Dispose() }
  if ($null -ne $tokenBytes) { [System.Array]::Clear($tokenBytes, 0, $tokenBytes.Length) }
  if ($null -ne $tokenUtf8Bytes) { [System.Array]::Clear($tokenUtf8Bytes, 0, $tokenUtf8Bytes.Length) }
  $token = $null
  $tokenBytes = $null
  $tokenUtf8Bytes = $null
  $tokenCredential = $null
  $tokenHash = $null
  if ($null -ne $tempConfigPath) { Remove-Item -LiteralPath $tempConfigPath -Force -ErrorAction SilentlyContinue }
  if ($null -ne $tempTokenCredentialPath) { Remove-Item -LiteralPath $tempTokenCredentialPath -Force -ErrorAction SilentlyContinue }
  if ($null -ne $portGuard) { $portGuard.Stop() }
  if ($null -ne $runtimeLock) { $runtimeLock.Dispose() }
  if ($null -ne $configureLock) { $configureLock.Dispose() }
  if ($ownsConfigureLock) {
    Remove-Item -LiteralPath $ConfigureLockPath -Force -ErrorAction SilentlyContinue
  }
}
