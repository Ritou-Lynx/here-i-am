[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$ReleaseDirectory,
 [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$ManifestSha256,
 [Parameter(Mandatory=$true)][string]$KeyDirectory,
 [Parameter(Mandatory=$true)][string]$ConfigPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$ConfigSha256
)
# Called by an already authorized user-session supervisor. No registration,
# daemon, password, real-data discovery or external destination selection here.
& (Join-Path $PSScriptRoot 'backup_bundle_schema6.ps1') -Operation Automatic -ReleaseDirectory $ReleaseDirectory -ManifestSha256 $ManifestSha256 -KeyDirectory $KeyDirectory -ConfigPath $ConfigPath -ConfigSha256 $ConfigSha256
exit $LASTEXITCODE
