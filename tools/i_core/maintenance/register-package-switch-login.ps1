# Same-schema CREATE-only task registration. No runtime or task is started.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ConfigurationPath,[Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedConfigurationSha256,[Parameter(Mandatory=$true)][switch]$RegisterOnly)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$env:PSModulePath=Join-Path $PSHOME 'Modules'
$locks=New-Object 'System.Collections.Generic.List[System.IDisposable]'
$created=$false;$registered=$null;$config=$null;$outputReady=$false;$exitCode=2
$report=[ordered]@{format='schema6-package-switch-registration-result-v1';passed=$false;registered=$false;started=$false;oldTasksChanged=$false;databaseChanged=$false}
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
public static class PackageSwitchRegistrationPin {
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
 try{[PackageSwitchRegistrationPin]::Check($h,$P);if($Size-ge 0 -and $h.Length-ne $Size){throw 'file_size_changed'}
  $sha=[Security.Cryptography.SHA256]::Create();try{$got=([BitConverter]::ToString($sha.ComputeHash($h))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
  if($Hash -and $got-cne $Hash){throw 'file_hash_changed'}
  $h.Position=0;$locks.Add($h)
 }catch{$h.Dispose();throw}
}
function Pin-ReleaseInventory([string]$ReleaseDirectory,[string]$ManifestSha256){
 Assert-Private $ReleaseDirectory
 if(-not (Get-Acl -LiteralPath $ReleaseDirectory).AreAccessRulesProtected){throw 'private_root_required'}
 $manifestPath=Join-Path $ReleaseDirectory 'manifest.json'
 Pin-File $manifestPath $ManifestSha256
 $manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json
 if($manifest.files -isnot [array] -or $manifest.files.Count-eq 0){throw 'candidate_inventory_rejected'}
 $fixed=@('runtime/node.exe','tools/i_core/activity_control_plane.mjs','tools/i_core/domain_http.mjs','tools/i_core/domain_migrate.mjs','tools/i_core/domain_schema.mjs','tools/i_core/domain_store.mjs','tools/i_core/i_core_server.mjs','tools/i_core/i_core_store.mjs','tools/i_core/inspection_read_only.mjs','tools/i_core/personal_data_domains.mjs','tools/i_core/release_schema6/README.md','tools/i_core/release_schema6/automatic_backup.mjs','tools/i_core/release_schema6/automatic_recovery.mjs','tools/i_core/release_schema6/backup_bundle.mjs','tools/i_core/release_schema6/backup_bundle_schema6.ps1','tools/i_core/release_schema6/backup_key_child.mjs','tools/i_core/release_schema6/cli.mjs','tools/i_core/release_schema6/key_custody.ps1','tools/i_core/release_schema6/lifecycle/common.mjs','tools/i_core/release_schema6/lifecycle/configuration.mjs','tools/i_core/release_schema6/lifecycle/job_guardian.ps1','tools/i_core/release_schema6/lifecycle/login_schema6.ps1','tools/i_core/release_schema6/lifecycle/mcp_configuration.ps1','tools/i_core/release_schema6/lifecycle/offline_lease.mjs','tools/i_core/release_schema6/lifecycle/offline_probe_client.mjs','tools/i_core/release_schema6/lifecycle/owned_job.ps1','tools/i_core/release_schema6/lifecycle/prepare_login_schema6.ps1','tools/i_core/release_schema6/lifecycle/probe_offline.ps1','tools/i_core/release_schema6/lifecycle/protected_paths.ps1','tools/i_core/release_schema6/lifecycle/request_stop.ps1','tools/i_core/release_schema6/lifecycle/runtime_child.mjs','tools/i_core/release_schema6/lifecycle/session_window.ps1','tools/i_core/release_schema6/lifecycle/start_schema6.ps1','tools/i_core/release_schema6/package.mjs','tools/i_core/release_schema6/package_switch.mjs','tools/i_core/release_schema6/portable_backup_schema6.ps1','tools/i_core/release_schema6/portable_key_custody.mjs','tools/i_core/release_schema6/preflight.mjs','tools/i_core/release_schema6/preflight_schema6.ps1','tools/i_core/release_schema6/raw_state_backup.mjs','tools/i_core/release_schema6/readonly_witness.mjs','tools/i_core/release_schema6/recovery_adapter.mjs','tools/i_core/release_schema6/recovery_witness_worker.mjs','tools/i_core/release_schema6/restore_inspection.mjs','tools/i_core/release_schema6/scheduler_once_schema6.ps1','tools/i_core/send_shortcut_mail.ps1','tools/i_core/shortcut_mail_relay.mjs','tools/i_core/strict_smtp_tls_validation.ps1')
 $old=@($fixed|Where-Object{$_-cne 'tools/i_core/release_schema6/package_switch.mjs'})
 $expected=if($manifest.files.Count-eq 47){$old}else{$fixed}
 if(@(Compare-Object ($expected|Sort-Object) (@($manifest.files.path)|Sort-Object)).Count-ne 0){throw 'candidate_inventory_rejected'}
 if($manifest.core_schema_version-ne 6-or $manifest.node_version-cne 'v24.14.1'-or $manifest.pinned_node_sha256-cne '58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f'){throw 'candidate_contract_rejected'}
 $actual=@(Get-ChildItem -LiteralPath $ReleaseDirectory -Recurse -Force|ForEach-Object{Assert-Private $_.FullName;if(-not $_.PSIsContainer){$_.FullName.Substring($ReleaseDirectory.Length+1).Replace('\','/')}})
 if(@(Compare-Object (($expected+@('manifest.json'))|Sort-Object) ($actual|Sort-Object)).Count-ne 0){throw 'candidate_inventory_rejected'}
 $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
 foreach($entry in $manifest.files){
  if($entry.path -isnot [string] -or $entry.path-cnotmatch '^[A-Za-z0-9_./-]+$' -or [IO.Path]::IsPathRooted($entry.path) -or @($entry.path.Split('/')|Where-Object{$_-in @('','.','..')}).Count -or !$seen.Add($entry.path)){throw 'candidate_relative_path_rejected'}
  if(($entry.bytes -isnot [int] -and $entry.bytes -isnot [long]) -or $entry.bytes-lt 0){throw 'candidate_size_rejected'}
 }
 foreach($entry in $manifest.files){
  Pin-File (Join-Path $ReleaseDirectory $entry.path) $entry.sha256 ([long]$entry.bytes)
 }
}

function Pin-Ref($Ref){Pin-File $Ref.path $Ref.sha256}
function Assert-BackupPrivateAcl([string]$Path){
 Assert-Private $Path
 $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;$acl=Get-Acl -LiteralPath $Path
 if(!$acl.AreAccessRulesProtected -or $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value-ne $sid){throw 'backup_acl_rejected'}
 $seen=@{};foreach($r in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])){$id=$r.IdentityReference.Value;if($id-notin @($sid,'S-1-5-18')-or $r.AccessControlType-ne 'Allow'-or $r.FileSystemRights-ne [Security.AccessControl.FileSystemRights]::FullControl){throw 'backup_acl_rejected'};$seen[$id]=$true}
 if(!$seen.ContainsKey($sid)-or !$seen.ContainsKey('S-1-5-18')){throw 'backup_acl_rejected'}
}
function Assert-OldPackageTask($Service,$Folder,$Config,[string]$OriginalXml){
 if($Config.oldTask.name-cnotmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,180}$'-or $Config.oldTask.name-ieq $Config.taskName){throw 'old_task_name_rejected'}
 $task=$Folder.GetTask($Config.oldTask.name)
 if($task.Path-cne ('\'+$Config.oldTask.name)-or $task.Enabled-or $task.GetInstances(0).Count-ne 0){throw 'old_task_not_stopped'}
 if([IO.File]::ReadAllText($Config.oldTask.xml.path)-cne [string]$task.Xml){throw 'old_task_snapshot_changed'}
 $sd=$task.GetSecurityDescriptor(7)
 if((Get-TaskSecuritySha256 $sd)-cne $Config.oldTask.sddlSha256-or (Convert-TaskSecurity $sd)-cne (Convert-TaskSecurity $Config.oldTask.sddl)){throw 'old_task_security_changed'}
 Assert-TaskAllowedRights $sd $Config.ownerSid
 $expected=$Service.NewTask(0);$expected.XmlText=$OriginalXml;$expected.Settings.Enabled=$false
 Assert-TaskDefinition $task.Definition $expected
}
function Invoke-SwitchRegistrationValidator([string]$Node,[string]$Script){
 $args=@($Script,$ConfigurationPath,$ExpectedConfigurationSha256)|ForEach-Object{if($_.Contains('"')-or $_.EndsWith('\')-or $_.Contains([char]13)-or $_.Contains([char]10)){throw 'validator_argument_rejected'};'"'+$_+'"'}
 $p=New-Object Diagnostics.Process;$p.StartInfo=New-Object Diagnostics.ProcessStartInfo
 $p.StartInfo.FileName=$Node;$p.StartInfo.Arguments=$args -join ' ';$p.StartInfo.UseShellExecute=$false;$p.StartInfo.CreateNoWindow=$true;$p.StartInfo.RedirectStandardOutput=$true;$p.StartInfo.RedirectStandardError=$true;$p.StartInfo.EnvironmentVariables.Clear()
 foreach($key in @('SystemRoot','WINDIR','TEMP','TMP')){$v=[Environment]::GetEnvironmentVariable($key);if($v){$p.StartInfo.EnvironmentVariables[$key]=$v}}
 try{$null=$p.Start();$out=$p.StandardOutput.ReadToEndAsync();$err=$p.StandardError.ReadToEndAsync();if(!$p.WaitForExit(120000)){$p.Kill();throw 'validator_timeout'};$null=$err.GetAwaiter().GetResult();if($p.ExitCode-ne 0){throw 'registration_proof_rejected'};return ($out.GetAwaiter().GetResult()|ConvertFrom-Json)}finally{$p.Dispose()}
}
function Write-SwitchRegistrationReceipt {
 $b=[Text.UTF8Encoding]::new($false).GetBytes(($report|ConvertTo-Json -Depth 8))
 Write-OwnedArtifactBytes $config.registrationReceiptPath $b $config.ownerSid
}
try{
 if(!$RegisterOnly){throw 'register_only_required'}
 Pin-File $ConfigurationPath $ExpectedConfigurationSha256;$config=Get-Content -LiteralPath $ConfigurationPath -Raw|ConvertFrom-Json
 if($config.format-cne 'schema6-package-switch-registration-v1'-or $config.approved-ne $true-or $config.registerOnly-ne $true-or $config.registerDisabled-ne $true-or $config.registrationDerivation-cne 'fixed_prepare_settings_enabled_false_only'-or $config.ownerSid-cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'registration_approval_rejected'}
 # Every local import/helper is pinned before any external code executes.
 $sourceRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
 $required=@('tools/i_core/activity_control_plane.mjs','tools/i_core/domain_http.mjs','tools/i_core/domain_migrate.mjs','tools/i_core/domain_schema.mjs','tools/i_core/domain_store.mjs','tools/i_core/i_core_server.mjs','tools/i_core/i_core_store.mjs','tools/i_core/inspection_read_only.mjs','tools/i_core/personal_data_domains.mjs','tools/i_core/release_schema6/README.md','tools/i_core/release_schema6/automatic_backup.mjs','tools/i_core/release_schema6/automatic_recovery.mjs','tools/i_core/release_schema6/backup_bundle.mjs','tools/i_core/release_schema6/backup_bundle_schema6.ps1','tools/i_core/release_schema6/backup_key_child.mjs','tools/i_core/release_schema6/cli.mjs','tools/i_core/release_schema6/key_custody.ps1','tools/i_core/release_schema6/lifecycle/common.mjs','tools/i_core/release_schema6/lifecycle/configuration.mjs','tools/i_core/release_schema6/lifecycle/job_guardian.ps1','tools/i_core/release_schema6/lifecycle/login_schema6.ps1','tools/i_core/release_schema6/lifecycle/mcp_configuration.ps1','tools/i_core/release_schema6/lifecycle/offline_lease.mjs','tools/i_core/release_schema6/lifecycle/offline_probe_client.mjs','tools/i_core/release_schema6/lifecycle/owned_job.ps1','tools/i_core/release_schema6/lifecycle/prepare_login_schema6.ps1','tools/i_core/release_schema6/lifecycle/probe_offline.ps1','tools/i_core/release_schema6/lifecycle/protected_paths.ps1','tools/i_core/release_schema6/lifecycle/request_stop.ps1','tools/i_core/release_schema6/lifecycle/runtime_child.mjs','tools/i_core/release_schema6/lifecycle/session_window.ps1','tools/i_core/release_schema6/lifecycle/start_schema6.ps1','tools/i_core/release_schema6/package.mjs','tools/i_core/release_schema6/package_switch.mjs','tools/i_core/release_schema6/portable_backup_schema6.ps1','tools/i_core/release_schema6/portable_key_custody.mjs','tools/i_core/release_schema6/preflight.mjs','tools/i_core/release_schema6/preflight_schema6.ps1','tools/i_core/release_schema6/raw_state_backup.mjs','tools/i_core/release_schema6/readonly_witness.mjs','tools/i_core/release_schema6/recovery_adapter.mjs','tools/i_core/release_schema6/recovery_witness_worker.mjs','tools/i_core/release_schema6/restore_inspection.mjs','tools/i_core/release_schema6/scheduler_once_schema6.ps1','tools/i_core/send_shortcut_mail.ps1','tools/i_core/shortcut_mail_relay.mjs','tools/i_core/strict_smtp_tls_validation.ps1','tools/i_core/maintenance/register-package-switch-login.ps1','tools/i_core/maintenance/package-switch-registration.mjs','tools/i_core/maintenance/package-switch-bindings.mjs','tools/i_core/maintenance/register_task_primitives.ps1','tools/i_core/maintenance/task_security_policy.ps1','tools/i_core/maintenance/owned_artifacts.ps1','tools/i_core/maintenance/close-schema6-session.ps1','tools/i_core/maintenance/process_image_binding.ps1')|ForEach-Object{Join-Path $sourceRoot $_}
 if(@(Compare-Object ($required|Sort-Object) (@($config.maintenanceFiles.path)|Sort-Object)).Count-ne 0-or $config.maintenanceFiles.Count-ne $required.Count){throw 'maintenance_inventory_rejected'}
 foreach($entry in $config.maintenanceFiles){Pin-Ref $entry}
 foreach($name in @('humanApproval','switchPlan','originalCloseInput','originalCloseReceipt','originalMarkerSnapshot','fixedPrepareReceipt','preparedXml','approvedXml','registrationXml')){Pin-Ref $config.$name}
 foreach($name in @('launch','child','guardian','supervisor','operation')){Pin-Ref $config.offline.$name}
 Pin-Ref $config.oldTask.xml
 $plan=Get-Content -LiteralPath $config.switchPlan.path -Raw|ConvertFrom-Json
 foreach($end in @($plan.from,$plan.to)){Pin-ReleaseInventory $end.releaseDirectory $end.manifestSha256;Pin-File $end.configurationPath $end.configurationSha256}
 if($plan.to.releaseDirectory-cne $config.releaseDirectory-or $plan.to.manifestSha256-cne $config.manifestSha256-or (Get-Content -LiteralPath (Join-Path $config.releaseDirectory 'manifest.json') -Raw|ConvertFrom-Json).files.Count-ne 48){throw 'current_candidate_required'}
 foreach($a in @($plan.fromArtifacts)+@($plan.artifacts)){Pin-Ref $a;if($a.role-ceq 'mcp'){$m=Get-Content -LiteralPath $a.path -Raw|ConvertFrom-Json;foreach($entry in $m.source_files){Pin-File (Join-Path $m.working_directory $entry.path) $entry.sha256}}}
 $close=Get-Content -LiteralPath $config.originalCloseReceipt.path -Raw|ConvertFrom-Json;$ci=Get-Content -LiteralPath $config.originalCloseInput.path -Raw|ConvertFrom-Json
 foreach($name in @('child','guardian','supervisor','close','exit')){$dir=if($name-eq 'exit'){$ci.sessionDirectory}else{$ci.controlDirectory};$file=if($name-eq 'close'){'session-close.json'}elseif($name-eq 'exit'){'session-exit.json'}else{$name+'.json'};Pin-File (Join-Path $dir $file) $close.receiptSha256.$name}
 $core=Get-Content -LiteralPath $plan.to.configurationPath -Raw|ConvertFrom-Json
 # Acquire the same two OS locks as the launcher. No synthetic NativeLease is minted.
 foreach($p in @((Join-Path ([IO.Path]::GetDirectoryName($core.database_path)) 'shortcut-mail-relay.runtime.lock'),(Join-Path $core.recovery_custody_directory 'custody.lock'))){Assert-Private $p;$h=[IO.File]::Open($p,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);[PackageSwitchRegistrationPin]::Check($h,$p);$locks.Add($h)}
 foreach($name in @('targetMarker','currentHead','switchEvent','targetFloor')){Pin-Ref $config.$name}
 $backup=@($plan.artifacts|Where-Object{$_.role-ceq 'backup'})[0];Assert-BackupPrivateAcl $backup.path
 . (Join-Path $PSScriptRoot 'register_task_primitives.ps1')
 . (Join-Path $PSScriptRoot 'task_security_policy.ps1')
 . (Join-Path $PSScriptRoot 'owned_artifacts.ps1')
 $node=Join-Path $config.releaseDirectory 'runtime/node.exe';Pin-File $node '58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f'
 $gate=Invoke-SwitchRegistrationValidator $node (Join-Path $PSScriptRoot 'package-switch-registration.mjs')
 if($gate.validated-ne $true-or $gate.registered-ne $false-or $gate.started-ne $false){throw 'registration_proof_rejected'}
 # Exclusive raw-file read proves unchanged closed bytes; no SQLite or keys.
 Assert-Private $gate.databasePath
 foreach($s in @('-wal','-shm','-journal')){if(Test-Path -LiteralPath ($gate.databasePath+$s)){throw 'database_sidecar_rejected'}}
 $db=[IO.File]::Open($gate.databasePath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None);$locks.Add($db);[PackageSwitchRegistrationPin]::Check($db,$gate.databasePath)
 $sha=[Security.Cryptography.SHA256]::Create();try{$dbHash=([BitConverter]::ToString($sha.ComputeHash($db))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()};if($dbHash-cne $gate.databaseSha256){throw 'database_changed'}
 Assert-Private ([IO.Path]::GetDirectoryName($config.registrationReceiptPath))
 foreach($root in @($gate.stateDirectory,$gate.custodyDirectory,$config.releaseDirectory)){if($config.registrationReceiptPath.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'receipt_scope_rejected'}}
 if(Test-Path -LiteralPath $config.registrationReceiptPath){throw 'fresh_receipt_required'};$outputReady=$true
 $service=New-Object -ComObject 'Schedule.Service';$service.Connect();$folder=$service.GetFolder('\')
 Assert-TaskAbsent $folder $config.taskName
 $xml=[IO.File]::ReadAllText($config.preparedXml.path);$expected=$service.NewTask(0);$expected.XmlText=$xml
 if($expected.Triggers.Count-ne 1-or $expected.Triggers.Item(1).Type-ne 9-or !$expected.Triggers.Item(1).Enabled-or !$expected.Settings.Enabled-or !$expected.Settings.UseUnifiedSchedulingEngine-or (Convert-TaskSid $expected.Triggers.Item(1).UserId)-cne $config.ownerSid){throw 'new_task_shape_rejected'}
 # RegisterOnly is deliberately disabled at CREATE; enabling is a separate approval.
 $expected.Settings.Enabled=$false;$registrationXml=$expected.XmlText
 if([IO.File]::ReadAllText($config.registrationXml.path)-cne $registrationXml){throw 'registration_derivation_changed'}
 $oldXml=[IO.File]::ReadAllText($gate.oldXmlPath)
 Assert-OldPackageTask $service $folder $config $oldXml
 $policy=Assert-TaskSecurityPolicy $config ($folder.GetSecurityDescriptor(7))
 $registered=New-ApprovedTask $service $folder $config.taskName $registrationXml $config.ownerSid $config.registrationSddl;$created=$true;$report.registered=$true
 $actual=$folder.GetTask($config.taskName)
 $null=Assert-TaskSecurityPolicy $config ($folder.GetSecurityDescriptor(7))
 Assert-RegisteredTask $actual $expected $config.taskName $config.expectedRegisteredSddl
 Assert-TaskAllowedRights ($actual.GetSecurityDescriptor(7)) $config.ownerSid
 Assert-OldPackageTask $service $folder $config $oldXml
 $null=Assert-TaskSecurityPolicy $config ($folder.GetSecurityDescriptor(7))
 $report.passed=$true;$report.createdTaskDisabled=(!$actual.Enabled);$report.registrationXmlSha256=$config.registrationXml.sha256;$report.actualDefinitionSha256=Get-TaskSecuritySha256 $actual.Definition.XmlText;$report.instancesZero=$true;$report.switchPlanSha256=$config.switchPlan.sha256;$report.targetMarkerSha256=$config.targetMarker.sha256;$report.currentHeadSha256=$config.currentHead.sha256;$report.parentSddlSha256=$policy.parentSddlSha256;$report.registrationSddlSha256=$policy.registrationSddlSha256;$report.expectedRegisteredSddlSha256=$policy.expectedRegisteredSddlSha256
 Write-SwitchRegistrationReceipt;$exitCode=0
}catch{
 $report.passed=$false;$report.code='package_switch_registration_rejected'
 if($created-and $null-ne $registered){try{$registered.Enabled=$false;$report.createdTaskDisabled=(!$registered.Enabled);$report.instancesZero=($registered.GetInstances(0).Count-eq 0)}catch{$report.disableUnconfirmed=$true}}
 if($outputReady){try{if(!(Test-Path -LiteralPath $config.registrationReceiptPath)){Write-SwitchRegistrationReceipt}}catch{$report.receiptUnconfirmed=$true}}
}finally{foreach($h in $locks){$h.Dispose()}}
[Console]::Out.WriteLine((@{passed=$report.passed;registered=$report.registered;started=$false;code=if($exitCode-eq 0){'package_switch_registered_only'}else{'package_switch_registration_rejected'}}|ConvertTo-Json -Compress));exit $exitCode
