# Windows PowerShell 5.1. Explicit RegisterOnly; never starts any task.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ConfigurationPath,[Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedConfigurationSha256,[Parameter(Mandatory=$true)][switch]$RegisterOnly)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$env:PSModulePath=Join-Path $PSHOME 'Modules'
$locks=New-Object 'System.Collections.Generic.List[System.IDisposable]'
$outputScopeValidated=$false;$created=$false;$attempted=$false;$registered=$null;$config=$null;$phase='gate';$exitCode=2
$report=[ordered]@{format='schema6-approved-login-registration-v2';passed=$false;registered=$false;started=$false;old_tasks_changed=$false;database_changed=$false}
function Assert-Private([string]$P){
 if($P -notmatch '^[A-Za-z]:\\' -or [IO.Path]::GetFullPath($P)-cne $P -or $P.Substring(2).Contains(':')){throw 'absolute_path_required'}
 $q=$P;while($q){if(([IO.File]::GetAttributes($q)-band [IO.FileAttributes]::ReparsePoint)-ne 0){throw 'linked_path_rejected'};$par=[IO.Directory]::GetParent($q);$q=if($par){$par.FullName}else{$null}}
 $acl=Get-Acl -LiteralPath $P
 $owner=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 if($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value-cne $owner){throw 'private_owner_required'}
 foreach($r in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])){if($r.AccessControlType-eq 'Allow' -and $r.IdentityReference.Value-notin @($owner,'S-1-5-18','S-1-5-32-544')){throw 'private_acl_required'}}
}
Add-Type -TypeDefinition @'
using System;using System.IO;using System.Text;using System.Runtime.InteropServices;
public static class MaintenanceRegistrationPin {
 [StructLayout(LayoutKind.Sequential)] struct Info {public uint attributes;public System.Runtime.InteropServices.ComTypes.FILETIME creation,access,write;public uint volume,high,low,links,indexHigh,indexLow;}
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetFileInformationByHandle(Microsoft.Win32.SafeHandles.SafeFileHandle h,out Info i);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern uint GetFinalPathNameByHandle(Microsoft.Win32.SafeHandles.SafeFileHandle h,StringBuilder p,uint n,uint f);
 public static void Check(FileStream s,string p){Info i;var b=new StringBuilder(32768);var n=GetFinalPathNameByHandle(s.SafeFileHandle,b,32768,0);if(!GetFileInformationByHandle(s.SafeFileHandle,out i)||i.links!=1||n==0||n>=32768||!b.ToString().Equals("\\\\?\\"+p,StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("pin_file_identity_rejected");}
}
'@
function Pin-File([string]$P,[string]$Hash,[long]$Size=-1,[switch]$ReceiptWithoutExternalHash){
 if($ReceiptWithoutExternalHash){if($Hash){throw 'receipt_pin_shape_rejected'}}elseif($Hash -cnotmatch '^[a-f0-9]{64}$'){throw 'sha256_anchor_required'}
 Assert-Private $P
 $h=[IO.File]::Open($P,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
 try{[MaintenanceRegistrationPin]::Check($h,$P);if($Size-ge 0 -and $h.Length-ne $Size){throw 'file_size_changed'}
  $sha=[Security.Cryptography.SHA256]::Create();try{$got=([BitConverter]::ToString($sha.ComputeHash($h))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
  if($Hash -and $got-cne $Hash){throw 'file_hash_changed'}
  $h.Position=0;$locks.Add($h)
 }catch{$h.Dispose();throw}
}
function Assert-FrozenLive($F,$Folder){
 Assert-PrepareLiveFrozen $config $F $service $locks
}
function Write-Receipt {
 Assert-Private ([IO.Path]::GetDirectoryName($config.registrationReceiptPath))
 $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($report|ConvertTo-Json -Depth 15))
 $h=[IO.File]::Open($config.registrationReceiptPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$h.Write($bytes,0,$bytes.Length);$h.Flush($true)}finally{$h.Dispose()}
}
function Invoke-VerifiedPrepare([string]$Node,[string]$Prepare){
 $arguments=@($Prepare,'--config',$ConfigurationPath,'--config-sha256',$ExpectedConfigurationSha256,'--validate-registration')
 $quoted=@($arguments|ForEach-Object{if($_.Contains('"') -or $_.EndsWith('\') -or $_.Contains([char]13) -or $_.Contains([char]10)){throw 'prepare_argument_rejected'};'"'+$_+'"'})
 $info=New-Object Diagnostics.ProcessStartInfo;$info.FileName=$Node;$info.Arguments=$quoted -join ' ';$info.UseShellExecute=$false;$info.CreateNoWindow=$true
 $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true;$info.EnvironmentVariables.Clear()
 foreach($key in @('SystemRoot','WINDIR','TEMP','TMP','COMSPEC')){$value=[Environment]::GetEnvironmentVariable($key);if($value){$info.EnvironmentVariables[$key]=$value}}
 $info.EnvironmentVariables['PATHEXT']='.EXE'
 $child=New-Object Diagnostics.Process;$child.StartInfo=$info
 try{$null=$child.Start();$output=$child.StandardOutput.ReadToEndAsync();$errors=$child.StandardError.ReadToEndAsync()
  if(!$child.WaitForExit(120000)){$child.Kill();throw 'prepare_validation_timeout'}
  $null=$errors.GetAwaiter().GetResult();if($child.ExitCode-ne 0){throw 'preparation_binding_rejected'}
  return $output.GetAwaiter().GetResult()
 }finally{$child.Dispose()}
}
try{
 if(!$RegisterOnly){throw 'register_only_required'}
 Pin-File $ConfigurationPath $ExpectedConfigurationSha256; $config=Get-Content -LiteralPath $ConfigurationPath -Raw|ConvertFrom-Json
 if($config.ownerSid-cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'owner_mismatch'}
 if(Test-Path -LiteralPath $config.registrationReceiptPath){throw 'fresh_receipt_required'}
 $report.windowId=$config.windowId;$report.taskName=$config.taskName;$report.candidateManifestSha256=$config.candidateManifestSha256
 foreach($pair in @(@($config.ownerApprovalPath,$config.ownerApprovalSha256),@($config.frozenReceiptPath,$config.frozenReceiptSha256),@($config.aclReceiptPath,$config.aclReceiptSha256),@($config.approvedXmlPath,$config.approvedXmlSha256),@($config.outputXmlPath,$config.approvedXmlSha256),@($config.loginConfigurationPath,$config.loginConfigurationSha256))){Pin-File $pair[0] $pair[1]}
 Pin-File $config.preparedReceiptPath '' -ReceiptWithoutExternalHash
 # Pin the reviewed maintenance dependency closure and fixed runtime before executing.
 foreach($entry in $config.maintenanceFiles){Pin-File $entry.path $entry.sha256}
 $self=@($config.maintenanceFiles|Where-Object {$_.path-ceq $PSCommandPath})
 $helper=@($config.maintenanceFiles|Where-Object {$_.path-ceq (Join-Path $PSScriptRoot 'register_task_primitives.ps1')})
 $prepare=Join-Path $PSScriptRoot 'prepare-production-login.mjs'
 if($self.Count-ne 1 -or $helper.Count-ne 1 -or @($config.maintenanceFiles|Where-Object {$_.path-ceq $prepare}).Count-ne 1){throw 'maintenance_inventory_rejected'}
 foreach($required in @('acl_receipt.mjs','maintenance_window.ps1','maintenance_outputs.mjs','prepare-production-login.ps1','prepare_live_guard.ps1')){if(@($config.maintenanceFiles|Where-Object {$_.path-ceq (Join-Path $PSScriptRoot $required)}).Count-ne 1){throw 'maintenance_inventory_rejected'}}
 $package=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\release_schema6\package.mjs'))
 if(@($config.maintenanceFiles|Where-Object {$_.path-ceq $package}).Count-ne 1){throw 'maintenance_inventory_rejected'}
 . (Join-Path $PSScriptRoot 'register_task_primitives.ps1')
 . (Join-Path $PSScriptRoot 'maintenance_window.ps1')
 . (Join-Path $PSScriptRoot 'prepare_live_guard.ps1')
 Assert-Private $config.maintenanceRoot
 if(!(Test-Path -LiteralPath (Join-Path $config.maintenanceRoot 'active-window.guard') -PathType Leaf)){throw 'maintenance_guard_missing'}
 $locks.Add((Acquire-MaintenanceGuard $config.maintenanceRoot))
 $node=Join-Path $config.releaseDirectory 'runtime\node.exe';Pin-File $node $config.nodeSha256
 $gate=Invoke-VerifiedPrepare $node $prepare
 $validated=$gate|ConvertFrom-Json;if($validated.validated-ne $true -or $validated.registered-ne $false -or $validated.started-ne $false){throw 'preparation_validation_rejected'}
 $outputScopeValidated=$true
 $xml=[IO.File]::ReadAllText($config.outputXmlPath)
 $service=New-Object -ComObject 'Schedule.Service';$service.Connect();$folder=$service.GetFolder('\')
 Assert-TaskAbsent $folder $config.taskName
 $expected=$service.NewTask(0);$expected.XmlText=$xml
 if($expected.Triggers.Count-ne 1 -or $expected.Triggers.Item(1).Type-ne 9 -or !$expected.Triggers.Item(1).Enabled -or !$expected.Settings.Enabled -or (Convert-TaskSid $expected.Triggers.Item(1).UserId)-cne $config.ownerSid){throw 'approved_login_shape_rejected'}
 $frozen=Get-Content -LiteralPath $config.frozenReceiptPath -Raw|ConvertFrom-Json
 $phase='frozen_live_gate';Assert-FrozenLive $frozen $folder
 $phase='register';$attempted=$true
 $registered=New-ApprovedTask $service $folder $config.taskName $xml $config.ownerSid $config.approvedSddl
 $created=$true;$report.registered=$true
 $phase='readback';$actual=$folder.GetTask($config.taskName)
 Assert-RegisteredTask $actual $expected $config.taskName $config.approvedSddl
 Assert-FrozenLive $frozen $folder
 $report.passed=$true;$report.actions_verified=$true;$report.principals_verified=$true;$report.triggers_verified=$true;$report.settings_verified=$true;$report.sddl_verified=$true;$report.frozen_rechecked=$true;$report.instances_zero=$true
 Write-Receipt;$exitCode=0
}catch{
 $report.passed=$false;$report.phase=$phase;$report.code=if($_.Exception.Message-match '^[a-z][a-z0-9_]+$'){$_.Exception.Message}else{'registration_rejected'}
 # A failed CREATE without a returned object has unknown outcome. Never mutate
 # another task by name. A returned created object is retained disabled on failure.
 if($created -and $null-ne $registered){try{$registered.Enabled=$false;$report.created_task_disabled=(!$registered.Enabled);$report.instances_zero=($registered.GetInstances(0).Count-eq 0)}catch{$report.disable_failed=$true}}
 elseif($attempted){$report.registration_outcome_unconfirmed=$true}
 if($null-ne $config -and $outputScopeValidated){try{if(!(Test-Path -LiteralPath $config.registrationReceiptPath)){Write-Receipt}}catch{$report.receipt_write_failed=$true}}
}finally{foreach($h in $locks){$h.Dispose()}}
[Console]::Out.WriteLine(($report|ConvertTo-Json -Depth 15 -Compress));exit $exitCode
