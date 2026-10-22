# Hosted CI only: nonce tasks, never enabled or started, identity-bound cleanup.
param([Parameter(Mandatory=$true)][string]$Bridge,[Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
[Console]::InputEncoding=[Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
if($env:CI -cne 'true' -or $env:SCHEMA6_SYNTHETIC_TASK_TEST -cne '1'){throw 'synthetic_com_ci_gate_required'}
. $Bridge
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$service=New-Object -ComObject 'Schedule.Service';$service.Connect();$folder=$service.GetFolder('\')
$nonce=[Guid]::NewGuid().ToString('N');$oldName='HereIAm-Synthetic-McpSource-A-'+$nonce;$newName='HereIAm-Synthetic-McpSource-B-'+$nonce
$created=[Collections.Generic.List[string]]::new();$result=[ordered]@{format='schema6-mcp-source-com-v1';created=$false;disabled=$false;arguments_preserved=$false;old_unchanged=$false;duplicate_rejected=$false;candidate_acl_rejected=$false;security_duplicate_equal=$false;security_extra_principal_rejected=$false;security_changed_rights_rejected=$false;deleted=$false}
function Assert-OwnedTask([string]$Name){
 if($Name -notin @($oldName,$newName)){throw 'synthetic_task_name_rejected'}
 $task=$folder.GetTask($Name)
 if($task.Definition.RegistrationInfo.Source -cne $nonce -or $task.Definition.Triggers.Count -ne 0 -or $task.Definition.Actions.Count -ne 1 -or $task.Definition.Actions.Item(1).Path -cne $env:ComSpec){throw 'synthetic_task_identity_changed'}
 return $task
}
try{
 # The existing normalizer accepts only redundant identical-principal ALLOW
 # rights, never a newly added principal or newly granted permission bits.
 $securityBase='O:'+$sid+'G:'+$sid+'D:P(A;;0x3;;;'+$sid+')'
 $normalized=Convert-TaskSecurity $securityBase
 $result.security_duplicate_equal=((Convert-TaskSecurity ($securityBase+'(A;;0x1;;;'+$sid+')')) -ceq $normalized)
 $result.security_extra_principal_rejected=((Convert-TaskSecurity ($securityBase+'(A;;0x1;;;WD)')) -cne $normalized)
 $result.security_changed_rights_rejected=((Convert-TaskSecurity ($securityBase+'(A;;0x4;;;'+$sid+')')) -cne $normalized)
 if(-not $result.security_duplicate_equal -or -not $result.security_extra_principal_rejected -or -not $result.security_changed_rights_rejected){throw 'synthetic_security_normalization_failed'}
 $state=Join-Path $Root 'state';$control=Join-Path $Root 'sessions'
 $null=New-Item -ItemType Directory -Path $state,$control
 $login=[ordered]@{format='schema6-login-v1';owner_sid=$sid;state_directory=$state;control_root=$control;core_port=47861}
 $oldLogin=Join-Path $Root '旧 login.json';$newLogin=Join-Path $Root '新 login.json'
 foreach($p in @($oldLogin,$newLogin)){if($p -eq $newLogin){$login.core_port=47863};[IO.File]::WriteAllText($p,($login|ConvertTo-Json),[Text.UTF8Encoding]::new($false))}
 $oldHash=(Get-FileHash -LiteralPath $oldLogin -Algorithm SHA256).Hash.ToLowerInvariant();$newHash=(Get-FileHash -LiteralPath $newLogin -Algorithm SHA256).Hash.ToLowerInvariant()
 $arguments='/c exit 0  "-ConfigurationPath" "'+$oldLogin+'"   -ConfigurationSha256 '+$oldHash+'  "untouched value"'
 $definition=$service.NewTask(0);$definition.RegistrationInfo.Source=$nonce;$definition.Principal.UserId=$sid;$definition.Principal.LogonType=2
 $definition.Settings.Enabled=$false;$definition.Settings.Hidden=$true;$definition.Settings.ExecutionTimeLimit='PT1M'
 $action=$definition.Actions.Create(0);$action.Path=$env:ComSpec;$action.Arguments=$arguments
 $null=$folder.RegisterTaskDefinition($oldName,$definition,2,$sid,$null,2,$null);$created.Add($oldName)
 $old=Assert-OwnedTask $oldName;$beforeXml=$old.Xml;$beforeSddl=$old.GetSecurityDescriptor(7);$beforeLastRun=$old.LastRunTime
 $source=Invoke-Schema6McpSourceTask ([pscustomobject]@{operation='read';fromTask=$oldName;newTask=$newName})
 $request=[pscustomobject]@{operation='check';fromTask=$oldName;newTask=$newName;source=$source;loginPath=$newLogin;loginSha256=$newHash;candidateRuntime=$Root}
 # An inherited-only root must be rejected read-only before any new task exists.
 $inherited=Join-Path $Root 'inherited-candidate'
 $null=New-Item -ItemType Directory -Path $inherited
 $sections=[Security.AccessControl.AccessControlSections]::All
 $beforeAcl=(Get-Acl -LiteralPath $inherited).GetSecurityDescriptorSddlForm($sections)
 if((Get-Acl -LiteralPath $inherited).AreAccessRulesProtected){throw 'synthetic_expected_inherited_acl'}
 $request.candidateRuntime=$inherited
 try{$null=Invoke-Schema6McpSourceTask $request}catch{if($_.Exception.Message -cne 'protected_root_required'){throw};$result.candidate_acl_rejected=$true}
 if(-not $result.candidate_acl_rejected -or (Invoke-Schema6UpdateTaskOperation 'Exists' $newName $null) -or (Get-Acl -LiteralPath $inherited).GetSecurityDescriptorSddlForm($sections) -cne $beforeAcl){throw 'synthetic_candidate_acl_gate_failed'}
 $request.candidateRuntime=$Root
 $planned=Invoke-Schema6McpSourceTask $request
 if(Invoke-Schema6UpdateTaskOperation 'Exists' $newName $null){throw 'check_created_task'}
 $request.operation='register'
 # Record candidate before invoking so any partial registration remains owned cleanup.
 $created.Add($newName);$registered=Invoke-Schema6McpSourceTask $request
 $result.created=$registered.registered;$new=Assert-OwnedTask $newName
 $result.disabled=(-not $new.Enabled -and $new.GetInstances(0).Count -eq 0)
 $expected=$arguments.Replace('"'+$oldLogin+'"','"'+$newLogin+'"').Replace($oldHash,$newHash)
 $result.arguments_preserved=([string]$new.Definition.Actions.Item(1).Arguments -ceq $expected)
 $old=Assert-OwnedTask $oldName
 $result.old_unchanged=($old.Xml -ceq $beforeXml -and $old.GetSecurityDescriptor(7) -ceq $beforeSddl -and $old.LastRunTime -eq $beforeLastRun)
 try{$null=Invoke-Schema6McpSourceTask $request}catch{if($_.Exception.Message -cne 'new_task_already_exists'){throw};$result.duplicate_rejected=$true}
 if($new.Definition.Principal.LogonType -ne $old.Definition.Principal.LogonType -or (Convert-TaskSecurity $new.GetSecurityDescriptor(7)) -cne (Convert-TaskSecurity $beforeSddl)){throw 'synthetic_security_changed'}
}finally{
 # Report only comparison booleans and counts, even if a readback assertion
 # failed. Raw security descriptors and account identifiers are never printed.
 try{
 if((Invoke-Schema6UpdateTaskOperation 'Exists' $oldName $null) -and (Invoke-Schema6UpdateTaskOperation 'Exists' $newName $null)){
  $oldSecurity=[string](Assert-OwnedTask $oldName).GetSecurityDescriptor(7)
  $newSecurity=[string](Assert-OwnedTask $newName).GetSecurityDescriptor(7)
  $before=[Security.AccessControl.RawSecurityDescriptor]::new($oldSecurity)
  $after=[Security.AccessControl.RawSecurityDescriptor]::new($newSecurity)
  $result.raw_equal=($oldSecurity -ceq $newSecurity)
  $result.semantic_equal=((Convert-TaskSecurity $oldSecurity) -ceq (Convert-TaskSecurity $newSecurity))
  $result.owner_equal=($before.Owner.Value -ceq $after.Owner.Value)
  $result.group_equal=($before.Group.Value -ceq $after.Group.Value)
  $result.protected_equal=([bool]($before.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclProtected) -eq [bool]($after.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclProtected))
  $result.old_ace_count=$before.DiscretionaryAcl.Count;$result.new_ace_count=$after.DiscretionaryAcl.Count
  $result.old_control_flags=[int]$before.ControlFlags;$result.new_control_flags=[int]$after.ControlFlags
 }
 }catch{$result.security_diagnostics_failed=$true}
 foreach($name in $created){
  if(Invoke-Schema6UpdateTaskOperation 'Exists' $name $null){$task=Assert-OwnedTask $name;if($task.Enabled -or $task.GetInstances(0).Count -ne 0){throw 'synthetic_task_unexpectedly_running'};$folder.DeleteTask($name,0)}
  if(Invoke-Schema6UpdateTaskOperation 'Exists' $name $null){throw 'synthetic_task_cleanup_failed'}
 }
 $result.deleted=$true
 [Console]::Out.WriteLine(($result|ConvertTo-Json -Compress))
}
