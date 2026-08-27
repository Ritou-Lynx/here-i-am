[CmdletBinding()]
param(
  [string]$NodePath = ''
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repositoryRoot = Split-Path -Parent (Split-Path -Parent $scriptRoot)
$serverPath = Join-Path $scriptRoot 'i_core_server.mjs'
$databasePath = Join-Path $scriptRoot '.state\i-core.sqlite'

if (-not (Test-Path -LiteralPath $serverPath -PathType Leaf)) {
  throw "iCore server entry was not found: $serverPath"
}

if ([string]::IsNullOrWhiteSpace($NodePath)) {
  $NodePath = (Get-Command node -ErrorAction Stop).Source
}
$resolvedNode = (Resolve-Path -LiteralPath $NodePath -ErrorAction Stop).Path

# The always-on service is deliberately unable to pair devices or run workers.
# Pairing and worker cutovers remain separate, short-lived owner actions.
$env:I_CORE_DATABASE = $databasePath
$env:I_CORE_HOST = '127.0.0.1'
$env:I_CORE_PORT = '47841'
Remove-Item Env:I_CORE_PAIRING_CODE -ErrorAction SilentlyContinue
Remove-Item Env:I_CORE_CERT -ErrorAction SilentlyContinue
Remove-Item Env:I_CORE_KEY -ErrorAction SilentlyContinue
Remove-Item Env:I_CORE_WORKER_SECRET -ErrorAction SilentlyContinue
Remove-Item Env:I_CORE_COMPANION_REPLY_JOBS -ErrorAction SilentlyContinue

Push-Location $repositoryRoot
try {
  & $resolvedNode $serverPath
  $exitCode = $LASTEXITCODE
} finally {
  Pop-Location
}

if ($null -eq $exitCode) {
  exit 1
}
exit $exitCode
