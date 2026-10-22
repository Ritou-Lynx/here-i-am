# Synthetic task fixture only. Every created task is disabled and nonce-scoped.
param([Parameter(Mandatory=$true)][string]$ConfigurationPath,[Parameter(Mandatory=$true)][ValidateSet('Prepare','BootstrapOld','VerifyOldEvidence','SnapshotFolder','CreateOld','Check','Cleanup','CleanupOld','AssertOldReject')][string]$Mode,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$c=Get-Content -LiteralPath $ConfigurationPath -Raw|ConvertFrom-Json
if($c.taskName-cnotmatch '^HereIAm-Synthetic-Switch-New-[a-f0-9]{32}$'-or $c.oldTask.name-cnotmatch '^HereIAm-Synthetic-Switch-Old-[a-f0-9]{32}$'){throw 'synthetic_task_scope_rejected'}
$maintenance=Split-Path -Parent (@($c.maintenanceFiles|Where-Object{[IO.Path]::GetFileName($_.path)-ceq 'register_task_primitives.ps1'})[0].path)
. (Join-Path $maintenance 'register_task_primitives.ps1')
. (Join-Path $maintenance 'task_security_policy.ps1')
. (Join-Path $maintenance 'owned_artifacts.ps1')
$s=New-Object -ComObject 'Schedule.Service';$s.Connect();$folder=$s.GetFolder('\')
$plan=Get-Content -LiteralPath $c.switchPlan.path -Raw|ConvertFrom-Json
$oldPath=@($plan.fromArtifacts|Where-Object{$_.role-ceq 'task'})[0].path
$old=$s.NewTask(0);$old.XmlText=[IO.File]::ReadAllText($oldPath);$old.Settings.Enabled=$false
$result=@{passed=$true;started=$false}
function Hash-Text([string]$text){return Get-TaskSecuritySha256 $text}
if($Mode-eq 'SnapshotFolder'){
 # stdout only: the preview check must not create snapshot evidence files.
 [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
 $tasks=$folder.GetTasks(1);$items=@()
 for($index=1;$index-le $tasks.Count;$index++){
  $task=$tasks.Item($index)
  $items+=@([pscustomobject][ordered]@{name=[string]$task.Name;path=[string]$task.Path;xml=[string]$task.Xml;sddl=[string]$task.GetSecurityDescriptor(7);enabled=[bool]$task.Enabled})
 }
 $snapshot=[ordered]@{parentSddl=[string]$folder.GetSecurityDescriptor(7);tasks=@($items|Sort-Object -Property name)}
 [Console]::Out.WriteLine(($snapshot|ConvertTo-Json -Depth 12 -Compress))
 return
}elseif($Mode-eq 'Prepare'){
 $definition=$s.NewTask(0);$definition.XmlText=[IO.File]::ReadAllText($c.preparedXml.path);$definition.Settings.Enabled=$false
 if(Test-Path -LiteralPath $c.registrationXml.path){
  # Generator already produced this immutable file. The historical caller's
  # Prepare step may only confirm identical bytes and the private owner ACL.
  Assert-OwnedArtifact $c.registrationXml.path $c.ownerSid
  if([IO.File]::ReadAllText($c.registrationXml.path) -cne $definition.XmlText){throw 'synthetic_prepared_xml_changed'}
 }else{Write-OwnedArtifactBytes $c.registrationXml.path ([Text.UTF8Encoding]::new($false).GetBytes($definition.XmlText)) $c.ownerSid}
 $result.registrationXml=@{path=$c.registrationXml.path;sha256=(Hash-Text $definition.XmlText)}
 # Compatibility fields come from the production generator, never fixture policy.
 $result.expectedRegisteredSddl=$c.expectedRegisteredSddl;$result.parentSddlSha256=$c.parentSddlSha256;$result.inheritedReadOnlyPrincipals=$c.inheritedReadOnlyPrincipals
}elseif($Mode-eq 'BootstrapOld'){
 $created=New-ApprovedTask $s $folder $c.oldTask.name $old.XmlText $c.ownerSid $c.registrationSddl
 $live=$folder.GetTask($c.oldTask.name);Assert-TaskDefinition $live.Definition $old
 if($live.Enabled-or $live.GetInstances(0).Count-ne 0-or $live.Definition.Triggers.Count-ne 1){throw 'synthetic_old_safety_rejected'}
 $result.xml=$live.Xml;$result.parentSddl=$folder.GetSecurityDescriptor(7)
 $result.oldTask=@{name=$c.oldTask.name;xml=@{path=$c.oldTask.xml.path;sha256=(Hash-Text $live.Xml)};sddl=$live.GetSecurityDescriptor(7);sddlSha256=(Hash-Text ($live.GetSecurityDescriptor(7)))}
}elseif($Mode-eq 'VerifyOldEvidence'){
 # Validate the production generator's files against the actual task and parent.
 # No ACL mutation or substitute security inputs are permitted in this check.
 $evidence=Get-Content -LiteralPath $c.oldTaskSecurity -Raw|ConvertFrom-Json
 $live=$folder.GetTask($c.oldTask.name);$current=$live.GetSecurityDescriptor(7);$parent=$folder.GetSecurityDescriptor(7)
 Assert-RegisteredTask $live $old $c.oldTask.name $evidence.oldTaskSddl
 if($current-cne $evidence.oldTaskSddl -or [IO.File]::ReadAllText($c.oldTask.xml.path)-cne $live.Xml){throw 'synthetic_old_evidence_changed'}
 if((Hash-Text $parent)-cne $evidence.parentSddlSha256){throw 'synthetic_parent_evidence_changed'}
 $parentSecurity=Read-TaskPolicySecurity $parent;$oldSecurity=Read-TaskPolicySecurity $current;$explicit=Read-TaskPolicySecurity $evidence.registrationSddl
 $parentOi=@($parentSecurity.DiscretionaryAcl|Where-Object{([int]$_.AceFlags-band 1)-ne 0}).Count
 $oldInherited=@($oldSecurity.DiscretionaryAcl|Where-Object{([int]$_.AceFlags-band 16)-ne 0}).Count
 if($parentOi-eq 0 -or $oldInherited-eq 0){throw 'synthetic_inherited_security_required'}
 if($explicit.Owner.Value-cne $oldSecurity.Owner.Value -or $explicit.Group.Value-cne $oldSecurity.Group.Value){throw 'synthetic_explicit_identity_changed'}
 foreach($ace in $explicit.DiscretionaryAcl){
  if([int]$ace.AceFlags-ne 0 -or $ace.SecurityIdentifier.Value-notin @($c.ownerSid,'S-1-5-18','S-1-5-32-544')){throw 'synthetic_explicit_security_rejected'}
 }
 $expected=Get-TaskPolicyExpectedSecurity $evidence.registrationSddl $parent $c.ownerSid
 $oldCanonical=Convert-TaskSecurity $current;$expectedCanonical=Convert-TaskSecurity $expected
 if($oldCanonical-cne $expectedCanonical -or (Convert-TaskSecurity $evidence.expectedRegisteredSddl)-cne $expectedCanonical){throw 'synthetic_security_roundtrip_changed'}
 $result.parentInheritableAceCount=$parentOi;$result.oldTaskInheritedAceCount=$oldInherited
 $result.registrationExplicitOnly=$true;$result.roundTripEqual=$true
 $result.oldTaskSecurity=$oldCanonical;$result.expectedRegisteredSecurity=$expectedCanonical
}elseif($Mode-eq 'CreateOld'){
 # Historical caller mode now checks the task created before generation.
 $live=$folder.GetTask($c.oldTask.name);Assert-RegisteredTask $live $old $c.oldTask.name $c.oldTask.sddl
 if([IO.File]::ReadAllText($c.oldTask.xml.path)-cne $live.Xml){throw 'synthetic_old_xml_changed'}
 $result.oldTask=@{name=$c.oldTask.name;xml=@{path=$c.oldTask.xml.path;sha256=(Hash-Text $live.Xml)};sddl=$live.GetSecurityDescriptor(7);sddlSha256=(Hash-Text ($live.GetSecurityDescriptor(7)))}
}elseif($Mode-eq 'Check'){
 $expected=$s.NewTask(0);$expected.XmlText=[IO.File]::ReadAllText($c.registrationXml.path)
 $live=$folder.GetTask($c.taskName);Assert-RegisteredTask $live $expected $c.taskName $c.expectedRegisteredSddl
 if($live.Enabled-or $live.GetInstances(0).Count-ne 0-or $live.Definition.Triggers.Count-ne 1){throw 'synthetic_new_safety_rejected'}
 $result.disabled=$true;$result.instancesZero=$true;$result.exactReadback=$true
}elseif($Mode-eq 'AssertOldReject'){
 $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $maintenance 'register-package-switch-login.ps1'),[ref]$tokens,[ref]$errors)
 $f=$ast.Find({param($n)$n-is [Management.Automation.Language.FunctionDefinitionAst]-and $n.Name-ceq 'Assert-OldPackageTask'},$true)
 . ([ScriptBlock]::Create($f.Extent.Text))
 $fake=[pscustomobject]@{Task=[pscustomobject]@{Path=('\'+$c.oldTask.name);Enabled=$true}}
 $fake|Add-Member -MemberType ScriptMethod -Name GetTask -Value {param($name)return $this.Task}
 try{Assert-OldPackageTask $s $fake $c $old.XmlText;throw 'synthetic_active_old_accepted'}catch{if($_.Exception.Message-cne 'old_task_not_stopped'){throw}}
 $result.activeOldRejected=$true
}else{
 $deleted=0
 $names=if($Mode-eq 'CleanupOld'){@($c.oldTask.name)}else{@($c.taskName,$c.oldTask.name)}
 foreach($name in $names){
  $all=$folder.GetTasks(1);$present=$false;for($i=1;$i-le $all.Count;$i++){if($all.Item($i).Name-ceq $name){$present=$true}}
  if(!$present){continue}
  $live=$folder.GetTask($name);$expected=$old
  if($name-ceq $c.taskName){$expected=$s.NewTask(0);$expected.XmlText=[IO.File]::ReadAllText($c.registrationXml.path)}
  if($name-ceq $c.oldTask.name){
   Assert-TaskDefinition $live.Definition $expected
   if($c.oldTask.PSObject.Properties.Name-contains 'sddl'){Assert-RegisteredTask $live $expected $name $c.oldTask.sddl}
   else{Assert-TaskAllowedRights ($live.GetSecurityDescriptor(7)) $c.ownerSid}
  }else{Assert-RegisteredTask $live $expected $name $c.expectedRegisteredSddl}
  if($live.Enabled-or $live.GetInstances(0).Count-ne 0){throw 'synthetic_cleanup_state_rejected'}
  $folder.DeleteTask($name,0);Assert-TaskAbsent $folder $name;$deleted++
 }
 $result.deleted=$deleted
}
Write-OwnedArtifactBytes $OutputPath ([Text.UTF8Encoding]::new($false).GetBytes(($result|ConvertTo-Json -Depth 8))) $c.ownerSid
@{passed=$true;started=$false}|ConvertTo-Json -Compress
