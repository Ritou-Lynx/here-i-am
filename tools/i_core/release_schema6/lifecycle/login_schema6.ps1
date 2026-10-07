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
# Self-contained gate runs before any candidate helper.
# Current-user candidate boundary. Same-user/admin compromise is outside this contract.
function Assert-BootstrapPath([string]$Target, [switch]$Root) {
  if ($Target -notmatch '^[A-Za-z]:[\\/]' -or $Target.Substring(2).Contains(':') -or
      -not ([IO.Path]::GetFullPath($Target).Equals($Target.Replace('/','\'),[StringComparison]::OrdinalIgnoreCase))) { throw 'canonical_absolute_path_required' }
  $current = $Target
  while ($current) {
    if (([IO.File]::GetAttributes($current) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'linked_path_rejected' }
    $parent = [IO.Directory]::GetParent($current)
    $current = if ($parent) { $parent.FullName } else { $null }
  }
  $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  $acl = Get-Acl -LiteralPath $Target
  if ($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -ne $sid) { throw 'protected_owner_mismatch' }
  if ($Root -and -not $acl.AreAccessRulesProtected) { throw 'protected_root_required' }
  $own = $false
  foreach ($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])) {
    if ($rule.AccessControlType -eq 'Allow') {
      if ($rule.IdentityReference.Value -notin @($sid,'S-1-5-18','S-1-5-32-544')) { throw 'protected_acl_required' }
      if ($rule.IdentityReference.Value -eq $sid -and ($rule.FileSystemRights -band [Security.AccessControl.FileSystemRights]::FullControl) -eq [Security.AccessControl.FileSystemRights]::FullControl) { $own = $true }
    }
  }
  if (-not $own) { throw 'protected_user_control_required' }
}


Add-Type -TypeDefinition '
using System;
using System.IO;
using System.Text;
using System.Runtime.InteropServices;
public static class Schema6LoginBootstrap {
 [StructLayout(LayoutKind.Sequential)] struct Info {public uint attributes;public System.Runtime.InteropServices.ComTypes.FILETIME creation,access,write;public uint volume,high,low,links,indexHigh,indexLow;}
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetFileInformationByHandle(Microsoft.Win32.SafeHandles.SafeFileHandle handle,out Info info);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern uint GetFinalPathNameByHandle(Microsoft.Win32.SafeHandles.SafeFileHandle handle,StringBuilder path,uint length,uint flags);
 public static void Check(FileStream stream,string path) {
  Info info;StringBuilder canonical=new StringBuilder(32768);
  uint size=GetFinalPathNameByHandle(stream.SafeFileHandle,canonical,32768,0);
  if(!GetFileInformationByHandle(stream.SafeFileHandle,out info)||info.links!=1||size==0||size>=32768||!canonical.ToString().Equals("\\\\?\\"+path,StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("bootstrap_file_rejected");
 }
}'

function Invoke-BootstrapValidation([string]$PowerShell,[string[]]$Arguments) {
 $quoted=@($Arguments|ForEach-Object{if($_.Contains('"') -or $_.EndsWith('\') -or $_.Contains([char]13) -or $_.Contains([char]10)){throw 'validator_argument_rejected'};'"'+$_+'"'})
 $info=New-Object Diagnostics.ProcessStartInfo
 $info.FileName=$PowerShell;$info.Arguments=$quoted -join ' ';$info.UseShellExecute=$false;$info.CreateNoWindow=$true
 $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
 $process=New-Object Diagnostics.Process;$process.StartInfo=$info
 try{
  $null=$process.Start();$output=$process.StandardOutput.ReadToEndAsync();$errors=$process.StandardError.ReadToEndAsync();$process.WaitForExit()
  $null=$errors.GetAwaiter().GetResult();if($process.ExitCode -ne 0){throw 'fixed_validator_rejected'}
  return $output.GetAwaiter().GetResult()
 }finally{$process.Dispose()}
}

function Open-BootstrapFile([string]$Target) {
 Assert-BootstrapPath $Target
 $handle=[IO.File]::Open($Target,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
 try{[Schema6LoginBootstrap]::Check($handle,$Target);return $handle}catch{$handle.Dispose();throw}
}

  # Bootstrap only reads/hash-checks files. No candidate helper executes first.
  if([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..')) -cne $ReleaseDirectory){throw 'login_release_binding_mismatch'}
  Assert-BootstrapPath $ReleaseDirectory -Root
  foreach($item in Get-ChildItem -LiteralPath $ReleaseDirectory -Recurse -Force){Assert-BootstrapPath $item.FullName}
  $manifestPath=Join-Path $ReleaseDirectory 'manifest.json'
  $locks += Open-BootstrapFile $manifestPath
  if((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash -ne $ManifestSha256){throw 'login_manifest_mismatch'}
  $manifest=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  foreach($entry in $manifest.files){
    if($entry.path -notmatch '^[A-Za-z0-9_/-]+\.[A-Za-z0-9]+$' -or $entry.path.Contains('..') -or $entry.path.StartsWith('/')){throw 'login_manifest_path_invalid'}
    $target=Join-Path $ReleaseDirectory $entry.path
    $locks += Open-BootstrapFile $target
    if((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $entry.sha256){throw 'login_release_hash_mismatch'}
  }
  # Reuse the unchanged full inventory / pinned Node / plain path / ACL gate.
  $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $null=Invoke-BootstrapValidation $ps @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'start_schema6.ps1'),'-ManifestSha256',$ManifestSha256)
  . (Join-Path $PSScriptRoot 'protected_paths.ps1')
  Assert-ProtectedPath $LoginConfigurationPath
  Assert-ProtectedPath ([IO.Path]::GetDirectoryName($LoginConfigurationPath)) -Root
  $locks += (Open-BootstrapFile $LoginConfigurationPath)
  if((Get-FileHash -LiteralPath $LoginConfigurationPath -Algorithm SHA256).Hash -ne $LoginConfigurationSha256){throw 'login_configuration_hash_mismatch'}
  $configuration=Get-Content -LiteralPath $LoginConfigurationPath -Raw | ConvertFrom-Json
  $expected=@('format','owner_sid','release_directory','manifest_sha256','state_directory','control_root','core_configuration_path','core_configuration_sha256','core_port','backup_configuration_path','backup_configuration_sha256','backup_key_directory','backup_interval_seconds')
  $mcpFields=@($configuration.PSObject.Properties.Name|Where-Object{$_ -in @('mcp_configuration_path','mcp_configuration_sha256')})
  if($mcpFields.Count -eq 2){$expected += @('mcp_configuration_path','mcp_configuration_sha256')}
  if(@(Compare-Object ($expected|Sort-Object) ($configuration.PSObject.Properties.Name|Sort-Object)).Count -ne 0 -or $configuration.format -ne 'schema6-login-v1'){throw 'login_configuration_contract_invalid'}
  $owner=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  if($configuration.owner_sid -ne $owner -or $configuration.release_directory -cne $ReleaseDirectory -or $configuration.manifest_sha256 -ne $ManifestSha256){throw 'login_configuration_binding_mismatch'}
  if($configuration.core_port -isnot [int] -or $configuration.core_port -lt 0 -or $configuration.core_port -gt 65535 -or $configuration.backup_interval_seconds -isnot [int] -or $configuration.backup_interval_seconds -lt 10 -or $configuration.backup_interval_seconds -gt 86400){throw 'login_numeric_configuration_invalid'}
  foreach($directory in @($configuration.state_directory,$configuration.control_root)) {Assert-ProtectedPath $directory -Root}
  if($configuration.state_directory -eq $configuration.control_root -or $configuration.control_root.StartsWith($configuration.state_directory+'\',[StringComparison]::OrdinalIgnoreCase) -or $configuration.state_directory.StartsWith($configuration.control_root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'login_separate_control_required'}
  Assert-ProtectedPath $configuration.core_configuration_path
  $locks += (Open-BootstrapFile $configuration.core_configuration_path)
  if($configuration.core_configuration_sha256 -notmatch '^[a-f0-9]{64}$' -or (Get-FileHash -LiteralPath $configuration.core_configuration_path -Algorithm SHA256).Hash -ne $configuration.core_configuration_sha256){throw 'login_core_configuration_hash_mismatch'}
  $null=Get-Content -LiteralPath $configuration.core_configuration_path -Raw | ConvertFrom-Json
  $backupArgs=[string[]]@()
  if($configuration.backup_configuration_path){
    foreach($file in @($configuration.backup_configuration_path)){Assert-ProtectedPath $file;$locks += (Open-BootstrapFile $file)}
    Assert-ProtectedPath $configuration.backup_key_directory -Root
    if($configuration.backup_configuration_sha256 -notmatch '^[a-f0-9]{64}$' -or (Get-FileHash -LiteralPath $configuration.backup_configuration_path -Algorithm SHA256).Hash -ne $configuration.backup_configuration_sha256){throw 'login_backup_configuration_hash_mismatch'}
    $null=Get-Content -LiteralPath $configuration.backup_configuration_path -Raw | ConvertFrom-Json
    $backupArgs=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $ReleaseDirectory 'tools/i_core/release_schema6/scheduler_once_schema6.ps1'),'-ReleaseDirectory',$ReleaseDirectory,'-ManifestSha256',$ManifestSha256,'-KeyDirectory',$configuration.backup_key_directory,'-ConfigPath',$configuration.backup_configuration_path,'-ConfigSha256',$configuration.backup_configuration_sha256)
  } elseif($null -ne $configuration.backup_configuration_sha256 -or $null -ne $configuration.backup_key_directory){throw 'login_partial_backup_configuration'}
  . (Join-Path $PSScriptRoot 'mcp_configuration.ps1')
  $mcpConfiguration=Read-Schema6McpConfiguration $configuration ([ref]$locks)
  if($ValidateOnly){@{validated=$true;mcp_managed=([bool]$mcpConfiguration);core_port=$configuration.core_port;owner_sid=$owner}|ConvertTo-Json -Compress;exit 0}
  $session=Join-Path $configuration.control_root ('session-'+[Guid]::NewGuid().ToString('N'))
  [IO.Directory]::CreateDirectory($session)|Out-Null;Protect-NewDirectory $session
  $control=Join-Path $session ('control-'+[Guid]::NewGuid().ToString('N'))
  [IO.Directory]::CreateDirectory($control)|Out-Null;Protect-NewDirectory $control
  . (Join-Path $PSScriptRoot 'session_window.ps1')
  $result=[Schema6SessionWindow]::Run($ps,$ReleaseDirectory,$ManifestSha256,$configuration.state_directory,$control,$session,$configuration.core_configuration_path,$InitializeEmpty.IsPresent,$backupArgs,$configuration.backup_interval_seconds,$configuration.core_port,$mcpConfiguration)
  exit $result
} catch {
  [Console]::Error.WriteLine('schema6_login_rejected:configuration_or_release_rejected')
  exit 2
} finally {foreach($handle in $locks){$handle.Dispose()}}
