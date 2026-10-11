[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$ControlDirectory,
  [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$RunId,
  [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$ManifestSha256,
  [ValidateSet('close','stop')][string]$Action = 'close'
)
$ErrorActionPreference='Stop'
$env:PSModulePath="$PSHOME\Modules"
try {
  . (Join-Path $PSScriptRoot 'protected_paths.ps1')
  Assert-ProtectedPath $ControlDirectory -Root
  foreach($name in @('launch.json','stop.key')) { Assert-ProtectedPath (Join-Path $ControlDirectory $name) }
  $launch=Get-Content -LiteralPath (Join-Path $ControlDirectory 'launch.json') -Raw | ConvertFrom-Json
  if($launch.token -ne $RunId -or $launch.manifest_sha256 -ne $ManifestSha256) { throw 'stop_binding_mismatch' }
  $key=[IO.File]::ReadAllText((Join-Path $ControlDirectory 'stop.key'))
  if($key -notmatch '^[a-f0-9]{64}$') { throw 'stop_key_invalid' }
  $hmac=[Security.Cryptography.HMACSHA256]::new([Text.Encoding]::UTF8.GetBytes($key))
  try { $mac=([BitConverter]::ToString($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes("$RunId|$ManifestSha256|$Action")))).Replace('-','').ToLowerInvariant() } finally { $hmac.Dispose() }
  $target=Join-Path $ControlDirectory $Action
  if(Test-Path -LiteralPath $target) { Assert-ProtectedPath $target; if([IO.File]::ReadAllText($target) -ne $mac) { throw 'existing_stop_mismatch' } }
  else {
    $temporary=Join-Path $ControlDirectory ('stop-request-'+[Guid]::NewGuid().ToString('N')+'.tmp')
    $file=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $bytes=[Text.Encoding]::UTF8.GetBytes($mac); $file.Write($bytes,0,$bytes.Length); $file.Flush($true) } finally { $file.Dispose() }
    [IO.File]::Move($temporary,$target)
  }
  @{status='stop_requested';run_id=$RunId;action=$Action;completion_confirmed=$false} | ConvertTo-Json -Compress
} catch { [Console]::Error.WriteLine('protected_stop_rejected'); exit 2 }
