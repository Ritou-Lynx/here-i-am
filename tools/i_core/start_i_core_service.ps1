[CmdletBinding()]
param(
  [string]$NodePath = '',
  [string]$StateDirectory = '',
  [string]$RuntimeLockPath = '',
  [ValidateRange(1, 65535)][int]$CorePort = 47841
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repositoryRoot = Split-Path -Parent (Split-Path -Parent $scriptRoot)
$serverPath = Join-Path $scriptRoot 'i_core_server.mjs'
if ([string]::IsNullOrWhiteSpace($StateDirectory)) { $StateDirectory = Join-Path $scriptRoot '.state' }
$StateDirectory = [System.IO.Path]::GetFullPath($StateDirectory)
$databasePath = Join-Path $StateDirectory 'i-core.sqlite'
$shortcutMailEnableMarker = Join-Path $StateDirectory 'shortcut-mail-relay.enabled'
$shortcutMailConfigureLock = Join-Path $StateDirectory 'shortcut-mail-relay.configure.lock'
if ([string]::IsNullOrWhiteSpace($RuntimeLockPath)) { $RuntimeLockPath = Join-Path $StateDirectory 'shortcut-mail-relay.runtime.lock' }
$RuntimeLockPath = [System.IO.Path]::GetFullPath($RuntimeLockPath)
foreach ($protectedPath in @($databasePath, $shortcutMailEnableMarker, $shortcutMailConfigureLock)) {
  if ([string]::Equals($RuntimeLockPath, [System.IO.Path]::GetFullPath($protectedPath), [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'The Shortcut mail relay runtime lock path collides with iCore state.'
  }
}

if (-not (Test-Path -LiteralPath $serverPath -PathType Leaf)) {
  throw "iCore server entry was not found: $serverPath"
}

if ([string]::IsNullOrWhiteSpace($NodePath)) {
  $NodePath = (Get-Command node -ErrorAction Stop).Source
}
$resolvedNode = (Resolve-Path -LiteralPath $NodePath -ErrorAction Stop).Path
New-Item -ItemType Directory -Force -Path $StateDirectory | Out-Null
$runtimeLock = $null
try {
  $runtimeLock = [System.IO.File]::Open(
    $RuntimeLockPath,
    [System.IO.FileMode]::OpenOrCreate,
    [System.IO.FileAccess]::ReadWrite,
    [System.IO.FileShare]::None
  )
} catch {
  throw 'The Shortcut mail relay runtime is active or being rotated; iCore start is closed.'
}

# The always-on service is deliberately unable to pair devices or run workers.
# Pairing and worker cutovers remain separate, short-lived owner actions.
$env:I_CORE_DATABASE = $databasePath
$env:I_CORE_HOST = '127.0.0.1'
$env:I_CORE_PORT = [string]$CorePort
Remove-Item Env:I_CORE_PAIRING_CODE -ErrorAction SilentlyContinue
Remove-Item Env:I_CORE_CERT -ErrorAction SilentlyContinue
Remove-Item Env:I_CORE_KEY -ErrorAction SilentlyContinue
Remove-Item Env:I_CORE_WORKER_SECRET -ErrorAction SilentlyContinue
Remove-Item Env:I_CORE_COMPANION_REPLY_JOBS -ErrorAction SilentlyContinue
Remove-Item Env:I_CORE_SHORTCUT_MAIL_MANUAL_TEST_ENABLED -ErrorAction SilentlyContinue
if (
  (Test-Path -LiteralPath $shortcutMailEnableMarker -PathType Leaf) -and
  -not (Test-Path -LiteralPath $shortcutMailConfigureLock -PathType Leaf)
) {
  $env:I_CORE_SHORTCUT_MAIL_MANUAL_TEST_ENABLED = '1'
}

Push-Location $repositoryRoot
try {
  & $resolvedNode $serverPath
  $exitCode = $LASTEXITCODE
} finally {
  Pop-Location
  if ($null -ne $runtimeLock) { $runtimeLock.Dispose() }
}

if ($null -eq $exitCode) {
  exit 1
}
exit $exitCode
