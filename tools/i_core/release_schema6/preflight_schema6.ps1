[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$ReleaseDirectory,
  [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$ManifestSha256,
  [Parameter(Mandatory=$true)][string]$ConfigurationPath,
  [Parameter(Mandatory=$true)][ValidateSet('legacy_b3')][string]$CompanionUploadMode,
  [switch]$CaptureBaseline
)
$ErrorActionPreference='Stop'
# This is an offline preflight entry, deliberately without a Start switch.
$before=@{}
foreach($entry in [Environment]::GetEnvironmentVariables('Process').GetEnumerator()) { $before[$entry.Key]=$entry.Value }
try {
  # Windows PowerShell must not autoload inherited PowerShell 7 modules.
  $env:PSModulePath=Join-Path $PSHOME 'Modules'
  $node=Join-Path $ReleaseDirectory 'runtime\node.exe'
  if((Get-FileHash -LiteralPath $node -Algorithm SHA256).Hash.ToLowerInvariant() -ne '58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f') { throw 'node_hash_mismatch' }
  # Remove inherited Core/Node/proxy/model/PowerShell configuration before Node starts.
  foreach($name in @([Environment]::GetEnvironmentVariables('Process').Keys)) {
    if($name.ToUpperInvariant() -notin @('SYSTEMROOT','WINDIR','TEMP','TMP','COMSPEC')) { [Environment]::SetEnvironmentVariable($name,$null,'Process') }
  }
  $env:PATHEXT='.EXE'
  $command=if($CaptureBaseline) {'capture-baseline'} else {'preflight'}
  $global:LASTEXITCODE=$null
  & $node (Join-Path $PSScriptRoot 'cli.mjs') $command $ReleaseDirectory $ManifestSha256 $ConfigurationPath
  if($null -eq $LASTEXITCODE) { throw 'node_invocation_unconfirmed' }
  $result=$LASTEXITCODE
} finally {
  foreach($name in @([Environment]::GetEnvironmentVariables('Process').Keys)) { [Environment]::SetEnvironmentVariable($name,$null,'Process') }
  foreach($name in $before.Keys) { [Environment]::SetEnvironmentVariable($name,$before[$name],'Process') }
}
exit $result
