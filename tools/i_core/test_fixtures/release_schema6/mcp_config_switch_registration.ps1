# Synthetic COM fixture only. Two nonce-named disabled tasks; never calls Run or enables them.
param([Parameter(Mandatory=$true)][string]$SourceRoot)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
. (Join-Path $SourceRoot 'tools/i_core/maintenance/register_task_primitives.ps1')
. (Join-Path $SourceRoot 'tools/i_core/maintenance/task_security_policy.ps1')
$parseTokens=$null;$parseErrors=$null
$syntax=[Management.Automation.Language.Parser]::ParseFile((Join-Path $SourceRoot 'tools/i_core/maintenance/register-mcp-config-switch-login.ps1'),[ref]$parseTokens,[ref]$parseErrors)
if($parseErrors.Count){throw 'wrapper_parse_rejected'}
$helper=$syntax.Find({param($ast) $ast -is [Management.Automation.Language.FunctionDefinitionAst] -and $ast.Name-ceq 'Assert-McpInventoryProfile'},$false)
if(!$helper){throw 'inventory_helper_missing'}
. ([ScriptBlock]::Create($helper.Extent.Text))
$baseNames=@('i_remote_mcp/server.mjs','i_remote_mcp/oauth.mjs','i_remote_mcp/mcp.mjs','i_remote_mcp/diagnostics.mjs','i_remote_mcp/writeback.mjs','i_memory/i_memory_read.mjs')
$oldProfile=[pscustomobject]@{entrypoint='tools/i_remote_mcp/server.mjs';source_files=@($baseNames|ForEach-Object{[pscustomobject]@{path='tools/'+$_}})}
$newProfile=[pscustomobject]@{entrypoint='i_remote_mcp/server.mjs';source_files=@($baseNames|ForEach-Object{[pscustomobject]@{path=$_}})}
Assert-McpInventoryProfile $oldProfile 'fromArtifacts';Assert-McpInventoryProfile $newProfile 'toArtifacts'
foreach($pair in @(@($newProfile,'fromArtifacts'),@($oldProfile,'toArtifacts'))){$denied=$false;try{Assert-McpInventoryProfile $pair[0] $pair[1]}catch{$denied=$true};if(!$denied){throw 'wrong_prefix_accepted'}}
$service=New-Object -ComObject 'Schedule.Service';$service.Connect();$folder=$service.GetFolder('\')
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$prefix='HereIAm-Synthetic-McpConfig-'+[Guid]::NewGuid().ToString('N')+'-'
$names=@(($prefix+'Old'),($prefix+'New'));$created=New-Object 'System.Collections.Generic.List[string]'
$result=@{passed=$false;created=0;cleaned=0;started=$false;existingRejected=$false;changedActionRejected=$false;inventoryProfiles=$true}
try{
 $task=$service.NewTask(0);$task.Principal.Id='Owner';$task.Actions.Context='Owner';$task.Principal.UserId=$sid;$task.Principal.LogonType=3;$task.Principal.RunLevel=0
 $trigger=$task.Triggers.Create(9);$trigger.UserId=$sid;$trigger.Enabled=$true
 $action=$task.Actions.Create(0);$action.Path=Join-Path $env:SystemRoot 'System32\cmd.exe';$action.Arguments='/d /c exit 0'
 $task.Settings.Enabled=$false;$task.Settings.Hidden=$true;$task.Settings.AllowHardTerminate=$false;$task.Settings.UseUnifiedSchedulingEngine=$true
 $inputSddl='O:'+ $sid +'G:'+ $sid +'D:(A;;FA;;;'+$sid+')(A;;FA;;;SY)(A;;FA;;;BA)'
 $parent=$folder.GetSecurityDescriptor(7);$expectedSddl=Get-TaskPolicyExpectedSecurity $inputSddl $parent $sid
 $policy=[pscustomobject]@{ownerSid=$sid;registrationSddl=$inputSddl;expectedRegisteredSddl=$expectedSddl;parentSddlSha256=(Get-TaskSecuritySha256 $parent);taskSecurityPolicyVersion='windows-file-oi-v1';inheritedReadOnlyPrincipals=(Get-TaskInheritedReadOnlyPrincipals $expectedSddl $sid)}
 foreach($name in $names){
  $null=Assert-TaskSecurityPolicy $policy ($folder.GetSecurityDescriptor(7))
  $registered=New-ApprovedTask $service $folder $name $task.XmlText $sid $inputSddl;$created.Add($name);$result.created++
  Assert-RegisteredTask ($folder.GetTask($name)) $task $name $expectedSddl
  $null=Assert-TaskSecurityPolicy $policy ($folder.GetSecurityDescriptor(7))
 }
 $before=$folder.GetTask($names[0]).Xml
 try{$null=New-ApprovedTask $service $folder $names[0] $task.XmlText $sid $inputSddl}catch{$result.existingRejected=$true}
 if(!$result.existingRejected -or $folder.GetTask($names[0]).Xml-cne $before){throw 'existing_task_changed'}
 $bad=$service.NewTask(0);$bad.XmlText=$task.XmlText;$bad.Actions.Item(1).Arguments='/d /c exit 1'
 try{Assert-TaskDefinition $folder.GetTask($names[1]).Definition $bad}catch{$result.changedActionRejected=$true}
 if(!$result.changedActionRejected){throw 'action_change_accepted'}
 foreach($name in $names){Assert-RegisteredTask ($folder.GetTask($name)) $task $name $expectedSddl}
 $result.passed=$true
}finally{
 foreach($name in $created){
  if(!$name.StartsWith($prefix,[StringComparison]::Ordinal)){throw 'cleanup_scope_rejected'}
  $owned=$folder.GetTask($name)
  if($owned.Path-cne ('\'+$name)-or $owned.Enabled-or $owned.GetInstances(0).Count-ne 0){throw 'cleanup_state_rejected'}
  $folder.DeleteTask($name,0);$result.cleaned++
 }
}
$result|ConvertTo-Json -Compress
