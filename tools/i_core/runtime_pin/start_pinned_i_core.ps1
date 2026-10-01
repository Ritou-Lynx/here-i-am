[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ManifestSha256,
  [string]$StateDirectory = '',
  [ValidateRange(1, 65535)][int]$CorePort = 47841,
  [switch]$Start
)

$ErrorActionPreference = 'Stop'
# A Node parent may pass a PowerShell 7 module path to this Windows PowerShell 5.1
# child. This release and its SMTP child use only the host's built-in modules.
$env:PSModulePath = "$PSHOME\Modules"
$releaseRoot = [IO.Path]::GetFullPath($PSScriptRoot)

function Assert-PlainPath([string]$Target) {
  $current = [IO.Path]::GetFullPath($Target)
  while ($current) {
    $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
    if ($null -ne $item) {
      if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'Pinned runtime paths must not contain reparse points.'
      }
    }
    $parent = [IO.Directory]::GetParent($current)
    $current = if ($null -eq $parent) { $null } else { $parent.FullName }
  }
}

Assert-PlainPath $releaseRoot
$manifestPath = Join-Path $releaseRoot 'manifest.json'
Assert-PlainPath $manifestPath
if ((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash -ne $ManifestSha256) {
  throw 'Release manifest hash mismatch; refusing to start.'
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.format -ne 'i-core-runtime-pin-v1' -or
    $manifest.source_commit -ne 'bbb8025d99fc0acaa846d58b4e5a94cef90f8756' -or
    $manifest.core_schema_version -ne 4 -or $manifest.node_version -ne 'v24.14.1') {
  throw 'This launcher only accepts the reviewed schema-v4 release.'
}
$expected = @(
  'tools/i_core/i_core_server.mjs', 'tools/i_core/i_core_store.mjs',
  'tools/i_core/shortcut_mail_relay.mjs', 'tools/i_core/send_shortcut_mail.ps1',
  'tools/i_core/strict_smtp_tls_validation.ps1', 'tools/i_core/start_i_core_service.ps1',
  'start_pinned_i_core.ps1', 'verify_v4_state.mjs', 'runtime/node.exe'
)
if (@($manifest.files).Count -ne $expected.Count -or
    @(Compare-Object ($expected | Sort-Object) (@($manifest.files.path) | Sort-Object)).Count -ne 0) {
  throw 'Release dependency inventory mismatch.'
}
foreach ($entry in $manifest.files) {
  $target = Join-Path $releaseRoot $entry.path
  Assert-PlainPath $target
  if (-not (Test-Path -LiteralPath $target -PathType Leaf) -or
      (Get-Item -LiteralPath $target).Length -ne $entry.bytes -or
      (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $entry.sha256) {
    throw "Release content mismatch: $($entry.path)"
  }
}
$directories = @{
  '.' = @('manifest.json', 'start_pinned_i_core.ps1', 'verify_v4_state.mjs', 'tools', 'runtime')
  'tools' = @('i_core')
  'tools/i_core' = @('i_core_server.mjs', 'i_core_store.mjs', 'shortcut_mail_relay.mjs',
    'send_shortcut_mail.ps1', 'strict_smtp_tls_validation.ps1', 'start_i_core_service.ps1')
  'runtime' = @('node.exe')
}
foreach ($relative in $directories.Keys) {
  $directory = Join-Path $releaseRoot $relative
  Assert-PlainPath $directory
  $actual = @(Get-ChildItem -LiteralPath $directory -Force | ForEach-Object { $_.Name })
  if (@(Compare-Object ($directories[$relative] | Sort-Object) ($actual | Sort-Object)).Count -ne 0) {
    throw 'Unexpected release content; runtime packages must remain immutable.'
  }
}
# Verification is the default and never opens state or launches a child.
if (-not $Start) {
  [pscustomobject]@{ status = 'verified_only'; release = $manifest.release; files = $expected.Count } | ConvertTo-Json -Compress
  exit 0
}
if (-not [IO.Path]::IsPathRooted($StateDirectory) -or
    -not (Test-Path -LiteralPath $StateDirectory -PathType Container)) {
  throw 'Start requires an explicit, existing absolute state directory.'
}
$StateDirectory = [IO.Path]::GetFullPath($StateDirectory)
if ($StateDirectory -eq [IO.Path]::GetPathRoot($StateDirectory)) {
  throw 'A volume root is not an iCore state directory.'
}
$StateDirectory = $StateDirectory.TrimEnd('\', '/')
Assert-PlainPath $StateDirectory
if ($StateDirectory.Equals($releaseRoot, [StringComparison]::OrdinalIgnoreCase) -or
    $StateDirectory.StartsWith($releaseRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
    $releaseRoot.StartsWith($StateDirectory + '\', [StringComparison]::OrdinalIgnoreCase)) {
  throw 'Release and state directories must be separate, non-nested directories.'
}
foreach ($name in @(
  'i-core.sqlite', 'i-core.sqlite-wal', 'i-core.sqlite-shm', 'i-core.sqlite-journal',
  'shortcut-mail-relay.json', 'shortcut-mail-journal.sqlite',
  'shortcut-mail-journal.sqlite-wal', 'shortcut-mail-journal.sqlite-shm',
  'shortcut-mail-relay.enabled', 'shortcut-mail-relay.configure.lock', 'shortcut-mail-relay.runtime.lock'
)) { Assert-PlainPath (Join-Path $StateDirectory $name) }

# Only these explicit paths and the legacy marker/lock may enable runtime features.
Get-ChildItem Env: | Where-Object { $_.Name -like 'I_CORE_*' } | ForEach-Object {
  Remove-Item -LiteralPath ('Env:' + $_.Name)
}
Remove-Item Env:NODE_OPTIONS -ErrorAction SilentlyContinue
Remove-Item Env:NODE_PATH -ErrorAction SilentlyContinue
$env:I_CORE_SHORTCUT_MAIL_CONFIG = Join-Path $StateDirectory 'shortcut-mail-relay.json'
$env:I_CORE_SHORTCUT_MAIL_DATABASE = Join-Path $StateDirectory 'shortcut-mail-journal.sqlite'
# The legacy relay resolves powershell.exe through PATH; select the Windows host first.
$env:PATH = (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0') + ';' + $env:PATH
$nodePath = Join-Path $releaseRoot 'runtime\node.exe'
$runtimeLock = $null
$pushed = $false
try {
  try {
    $runtimeLock = [IO.File]::Open(
      (Join-Path $StateDirectory 'shortcut-mail-relay.runtime.lock'),
      [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None
    )
  } catch {
    throw 'The Shortcut mail relay runtime is active or being rotated; iCore start is closed.'
  }
  # A terminated task can leave an orphan Node process after releasing its lock.
  # Reject an occupied loopback port before opening even the read-only database.
  $portProbe = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $CorePort)
  $portProbe.Server.ExclusiveAddressUse = $true
  try { $portProbe.Start() } finally { $portProbe.Stop() }
  $databasePath = Join-Path $StateDirectory 'i-core.sqlite'
  & $nodePath (Join-Path $releaseRoot 'verify_v4_state.mjs') $databasePath
  if ($LASTEXITCODE -ne 0) { throw 'Schema preflight rejected this state; server was not started.' }
  $env:I_CORE_DATABASE = $databasePath
  $env:I_CORE_HOST = '127.0.0.1'
  $env:I_CORE_PORT = [string]$CorePort
  if ((Test-Path -LiteralPath (Join-Path $StateDirectory 'shortcut-mail-relay.enabled') -PathType Leaf) -and
      -not (Test-Path -LiteralPath (Join-Path $StateDirectory 'shortcut-mail-relay.configure.lock') -PathType Leaf)) {
    $env:I_CORE_SHORTCUT_MAIL_MANUAL_TEST_ENABLED = '1'
  }
  Push-Location $releaseRoot
  $pushed = $true
  & $nodePath (Join-Path $releaseRoot 'tools\i_core\i_core_server.mjs')
  $exitCode = $LASTEXITCODE
} finally {
  if ($pushed) { Pop-Location }
  if ($null -ne $runtimeLock) { $runtimeLock.Dispose() }
}
if ($null -eq $exitCode) { exit 1 }
exit $exitCode
