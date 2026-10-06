[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$ReleaseDirectory,
 [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$ManifestSha256,
 [Parameter(Mandatory=$true)][string]$LoginConfigurationPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$LoginConfigurationSha256,
 [switch]$ValidateOnly,
 [switch]$InitializeEmpty
)
$ErrorActionPreference='Stop'
$env:PSModulePath=Join-Path $PSHOME 'Modules'
$locks=@()
try {
  # Bootstrap only reads/hash-checks files. No candidate helper executes first.
  if([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..')) -cne $ReleaseDirectory){throw 'login_release_binding_mismatch'}
  $manifestPath=Join-Path $ReleaseDirectory 'manifest.json'
  if((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash -ne $ManifestSha256){throw 'login_manifest_mismatch'}
  $manifest=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  foreach($entry in $manifest.files){
    if($entry.path -notmatch '^[A-Za-z0-9_/-]+\.[A-Za-z0-9]+$' -or $entry.path.Contains('..') -or $entry.path.StartsWith('/')){throw 'login_manifest_path_invalid'}
    $target=Join-Path $ReleaseDirectory $entry.path
    if((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $entry.sha256){throw 'login_release_hash_mismatch'}
    $locks += [IO.File]::Open($target,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  }
  # Reuse the unchanged full inventory / pinned Node / plain path / ACL gate.
  $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  & $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'start_schema6.ps1') -ManifestSha256 $ManifestSha256 | Out-Null
  if($LASTEXITCODE -ne 0){throw 'login_fixed_release_rejected'}
  . (Join-Path $PSScriptRoot 'protected_paths.ps1')
  Assert-ProtectedPath $LoginConfigurationPath
  Assert-ProtectedPath ([IO.Path]::GetDirectoryName($LoginConfigurationPath)) -Root
  $locks += [IO.File]::Open($LoginConfigurationPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  if((Get-FileHash -LiteralPath $LoginConfigurationPath -Algorithm SHA256).Hash -ne $LoginConfigurationSha256){throw 'login_configuration_hash_mismatch'}
  $configuration=Get-Content -LiteralPath $LoginConfigurationPath -Raw | ConvertFrom-Json
  $expected=@('format','owner_sid','release_directory','manifest_sha256','state_directory','control_root','core_configuration_path','core_configuration_sha256','core_port','backup_configuration_path','backup_configuration_sha256','backup_key_directory','backup_interval_seconds')
  if(@(Compare-Object ($expected|Sort-Object) ($configuration.PSObject.Properties.Name|Sort-Object)).Count -ne 0 -or $configuration.format -ne 'schema6-login-v1'){throw 'login_configuration_contract_invalid'}
  $owner=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  if($configuration.owner_sid -ne $owner -or $configuration.release_directory -cne $ReleaseDirectory -or $configuration.manifest_sha256 -ne $ManifestSha256){throw 'login_configuration_binding_mismatch'}
  if($configuration.core_port -isnot [int] -or $configuration.core_port -lt 0 -or $configuration.core_port -gt 65535 -or $configuration.backup_interval_seconds -isnot [int] -or $configuration.backup_interval_seconds -lt 10 -or $configuration.backup_interval_seconds -gt 86400){throw 'login_numeric_configuration_invalid'}
  foreach($directory in @($configuration.state_directory,$configuration.control_root)) {Assert-ProtectedPath $directory -Root}
  if($configuration.state_directory -eq $configuration.control_root -or $configuration.control_root.StartsWith($configuration.state_directory+'\',[StringComparison]::OrdinalIgnoreCase) -or $configuration.state_directory.StartsWith($configuration.control_root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'login_separate_control_required'}
  Assert-ProtectedPath $configuration.core_configuration_path
  $locks += [IO.File]::Open($configuration.core_configuration_path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  if($configuration.core_configuration_sha256 -notmatch '^[a-f0-9]{64}$' -or (Get-FileHash -LiteralPath $configuration.core_configuration_path -Algorithm SHA256).Hash -ne $configuration.core_configuration_sha256){throw 'login_core_configuration_hash_mismatch'}
  $backupArgs=[string[]]@()
  if($configuration.backup_configuration_path){
    foreach($file in @($configuration.backup_configuration_path)){Assert-ProtectedPath $file;$locks += [IO.File]::Open($file,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)}
    Assert-ProtectedPath $configuration.backup_key_directory -Root
    if($configuration.backup_configuration_sha256 -notmatch '^[a-f0-9]{64}$' -or (Get-FileHash -LiteralPath $configuration.backup_configuration_path -Algorithm SHA256).Hash -ne $configuration.backup_configuration_sha256){throw 'login_backup_configuration_hash_mismatch'}
    $backupArgs=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $ReleaseDirectory 'tools/i_core/release_schema6/scheduler_once_schema6.ps1'),'-ReleaseDirectory',$ReleaseDirectory,'-ManifestSha256',$ManifestSha256,'-KeyDirectory',$configuration.backup_key_directory,'-ConfigPath',$configuration.backup_configuration_path,'-ConfigSha256',$configuration.backup_configuration_sha256)
  } elseif($null -ne $configuration.backup_configuration_sha256 -or $null -ne $configuration.backup_key_directory){throw 'login_partial_backup_configuration'}
  if($ValidateOnly){@{validated=$true;core_port=$configuration.core_port;owner_sid=$owner}|ConvertTo-Json -Compress;exit 0}
  $session=Join-Path $configuration.control_root ('session-'+[Guid]::NewGuid().ToString('N'))
  [IO.Directory]::CreateDirectory($session)|Out-Null;Protect-NewDirectory $session
  $control=Join-Path $session ('control-'+[Guid]::NewGuid().ToString('N'))
  [IO.Directory]::CreateDirectory($control)|Out-Null;Protect-NewDirectory $control
  . (Join-Path $PSScriptRoot 'session_window.ps1')
  $result=[Schema6SessionWindow]::Run($ps,$ReleaseDirectory,$ManifestSha256,$configuration.state_directory,$control,$session,$configuration.core_configuration_path,$InitializeEmpty.IsPresent,$backupArgs,$configuration.backup_interval_seconds,$configuration.core_port)
  exit $result
} catch {
  [Console]::Error.WriteLine('schema6_login_rejected:'+$_.Exception.Message)
  exit 2
} finally {foreach($handle in $locks){$handle.Dispose()}}
