# Full-wrapper synthetic support. Task actions point only to this fixture's inert release.
param([Parameter(Mandatory=$true)][string]$InputPath,[Parameter(Mandatory=$true)][ValidateSet('Prepare','EnableOld','DisableOld','CheckAbsent','Check','Cleanup')][string]$Mode)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$c=Get-Content -LiteralPath $InputPath -Raw|ConvertFrom-Json
if($c.format-cne 'synthetic-mcp-registration-e2e-v1'-or $c.nonce-cnotmatch '^[a-f0-9]{32}$'-or $c.oldName-cne ('HereIAm-Synthetic-McpFull-'+$c.nonce+'-Old')-or $c.newName-cne ('HereIAm-Synthetic-McpFull-'+$c.nonce+'-New')){throw 'synthetic_scope_required'}
foreach($p in @($c.oldXml,$c.newXml,$c.sourceRoot,$c.release,$c.registrationXml,$c.oldSnapshot)) {if(!$p.StartsWith($c.root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'synthetic_path_scope'}}
. (Join-Path $c.sourceRoot 'tools/i_core/maintenance/register_task_primitives.ps1')
. (Join-Path $c.sourceRoot 'tools/i_core/maintenance/task_security_policy.ps1')
$service=New-Object -ComObject 'Schedule.Service';$service.Connect();$folder=$service.GetFolder('\')
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
function Assert-SyntheticTask($Task){
 if($Task.Path-cne ('\'+$c.oldName)-and $Task.Path-cne ('\'+$c.newName)){throw 'synthetic_task_scope'}
 if($Task.Definition.Actions.Count-ne 1-or !$Task.Definition.Actions.Item(1).Arguments.Contains($c.release)){throw 'synthetic_action_scope'}
 if((Convert-TaskSid $Task.Definition.Principal.UserId)-cne $sid){throw 'synthetic_owner_scope'}
}
function Get-NonceTask([string]$Name){foreach($task in $folder.GetTasks(1)){if($task.Name-ceq $Name){return $task}};return $null}
if($Mode-ceq 'Prepare'){
 $inputSddl='O:'+$sid+'G:'+$sid+'D:(A;;FA;;;'+$sid+')(A;;FA;;;SY)(A;;FA;;;BA)';$parent=$folder.GetSecurityDescriptor(7)
 $expectedSddl=Get-TaskPolicyExpectedSecurity $inputSddl $parent $sid
 $expected=$service.NewTask(0);$expected.XmlText=[IO.File]::ReadAllText($c.newXml);$expected.Settings.Enabled=$false
 [IO.File]::WriteAllText($c.registrationXml,$expected.XmlText,[Text.UTF8Encoding]::new($false))
 $old=$service.NewTask(0);$old.XmlText=[IO.File]::ReadAllText($c.oldXml);$old.Settings.Enabled=$false
 $created=New-ApprovedTask $service $folder $c.oldName $old.XmlText $sid $inputSddl
 Assert-RegisteredTask $created $old $c.oldName $expectedSddl
 [IO.File]::WriteAllText($c.oldSnapshot,$created.Xml,[Text.UTF8Encoding]::new($false))
 $sd=$created.GetSecurityDescriptor(7)
 @{ownerSid=$sid;registrationSddl=$inputSddl;expectedRegisteredSddl=$expectedSddl;parentSddlSha256=(Get-TaskSecuritySha256 $parent);taskSecurityPolicyVersion='windows-file-oi-v1';inheritedReadOnlyPrincipals=(Get-TaskInheritedReadOnlyPrincipals $expectedSddl $sid);oldSddl=$sd;oldSddlSha256=(Get-TaskSecuritySha256 $sd)}|ConvertTo-Json -Depth 8 -Compress
}elseif($Mode-ceq 'EnableOld'-or $Mode-ceq 'DisableOld'){
 $task=$folder.GetTask($c.oldName);Assert-SyntheticTask $task;$task.Enabled=($Mode-ceq 'EnableOld');@{enabled=$task.Enabled}|ConvertTo-Json -Compress
}elseif($Mode-ceq 'CheckAbsent'){
 @{absent=($null-eq (Get-NonceTask $c.newName));oldDisabled=(!$folder.GetTask($c.oldName).Enabled)}|ConvertTo-Json -Compress
}elseif($Mode-ceq 'Check'){
 $task=$folder.GetTask($c.newName);Assert-SyntheticTask $task
 @{disabled=(!$task.Enabled);instancesZero=($task.GetInstances(0).Count-eq 0);oldDisabled=(!$folder.GetTask($c.oldName).Enabled);oldInstancesZero=($folder.GetTask($c.oldName).GetInstances(0).Count-eq 0);sddl=$task.GetSecurityDescriptor(7)}|ConvertTo-Json -Compress
}else{
 $count=0
 foreach($name in @($c.newName,$c.oldName)){
  $task=Get-NonceTask $name;if($null-eq $task){continue};Assert-SyntheticTask $task;$task.Enabled=$false
  if($task.GetInstances(0).Count-ne 0){throw 'synthetic_cleanup_running'}
  $folder.DeleteTask($name,0);$count++
 }
 @{cleaned=$count}|ConvertTo-Json -Compress
}
