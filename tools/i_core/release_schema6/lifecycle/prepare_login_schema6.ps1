[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$ReleaseDirectory,
 [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$ManifestSha256,
 [Parameter(Mandatory=$true)][string]$LoginConfigurationPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$LoginConfigurationSha256,
 [Parameter(Mandatory=$true)][string]$OutputXml,
 [Parameter(Mandatory=$true)][switch]$PrepareOnly
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

if(-not $PrepareOnly){throw 'prepare_only_required'}
if(Test-Path -LiteralPath $OutputXml){throw 'fresh_output_required'}
$ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$login=Join-Path $ReleaseDirectory 'tools/i_core/release_schema6/lifecycle/login_schema6.ps1'
if([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..')) -cne $ReleaseDirectory){throw 'prepare_release_binding_mismatch'}
Assert-BootstrapPath $ReleaseDirectory -Root
foreach($item in Get-ChildItem -LiteralPath $ReleaseDirectory -Recurse -Force){Assert-BootstrapPath $item.FullName}
$manifestPath=Join-Path $ReleaseDirectory 'manifest.json'
$locks += Open-BootstrapFile $manifestPath
if((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash -ne $ManifestSha256){throw 'prepare_manifest_mismatch'}
$manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json
$entry=@($manifest.files|Where-Object{$_.path -ceq 'tools/i_core/release_schema6/lifecycle/login_schema6.ps1'})
$locks += Open-BootstrapFile $login
if($entry.Count -ne 1 -or (Get-FileHash -LiteralPath $login -Algorithm SHA256).Hash -ne $entry[0].sha256){throw 'prepare_login_hash_mismatch'}
$raw=Invoke-BootstrapValidation $ps @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$login,'-ReleaseDirectory',$ReleaseDirectory,'-ManifestSha256',$ManifestSha256,'-LoginConfigurationPath',$LoginConfigurationPath,'-LoginConfigurationSha256',$LoginConfigurationSha256,'-ValidateOnly')
$verified=$raw|ConvertFrom-Json
if($verified.mcp_managed -ne $true){throw 'managed_mcp_required_for_login_task'}
if($verified.validated -ne $true -or $verified.core_port -le 0){throw 'fixed_nonzero_production_port_required'}
function Quote-Argument([string]$value){if($value.Contains('"') -or $value.EndsWith('\') -or $value.Contains("`n") -or $value.Contains("`r")){throw 'task_argument_rejected'};'"'+$value+'"'}
$arguments=@('-NoProfile','-NonInteractive','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',$login,'-ReleaseDirectory',$ReleaseDirectory,'-ManifestSha256',$ManifestSha256,'-LoginConfigurationPath',$LoginConfigurationPath,'-LoginConfigurationSha256',$LoginConfigurationSha256)
$argumentText=($arguments|ForEach-Object{Quote-Argument $_}) -join ' '
$document=New-Object Xml.XmlDocument
$document.LoadXml('<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task"><Triggers><LogonTrigger><Enabled>true</Enabled><UserId /></LogonTrigger></Triggers><Principals><Principal id="Owner"><UserId /><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals><Settings><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy><DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries><StopIfGoingOnBatteries>false</StopIfGoingOnBatteries><AllowHardTerminate>false</AllowHardTerminate><StartWhenAvailable>true</StartWhenAvailable><Enabled>true</Enabled><Hidden>true</Hidden><ExecutionTimeLimit>PT0S</ExecutionTimeLimit></Settings><Actions Context="Owner"><Exec><Command /><Arguments /></Exec></Actions></Task>')
$ns=New-Object Xml.XmlNamespaceManager($document.NameTable);$ns.AddNamespace('t',$document.DocumentElement.NamespaceURI)
foreach($node in $document.SelectNodes('//t:UserId',$ns)){$node.InnerText=$verified.owner_sid}
$document.SelectSingleNode('//t:Command',$ns).InnerText=$ps
$document.SelectSingleNode('//t:Arguments',$ns).InnerText=$argumentText
$stream=[IO.File]::Open($OutputXml,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{$document.Save($stream);$stream.Flush($true)}finally{$stream.Dispose()}
@{prepared=$true;registered=$false;started=$false;manifest_sha256=$ManifestSha256;login_configuration_sha256=$LoginConfigurationSha256}|ConvertTo-Json -Compress

} catch {
 [Console]::Error.WriteLine('schema6_login_prepare_rejected:configuration_or_release_rejected')
 exit 2
} finally {foreach($handle in $locks){$handle.Dispose()}}
