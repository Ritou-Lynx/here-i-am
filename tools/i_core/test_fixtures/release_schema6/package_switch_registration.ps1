# Synthetic task fixture only. Every created task is disabled and nonce-scoped.
param([Parameter(Mandatory=$true)][string]$ConfigurationPath,[Parameter(Mandatory=$true)][ValidateSet('Prepare','CreateOld','Check','Cleanup','AssertOldReject')][string]$Mode,[Parameter(Mandatory=$true)][string]$OutputPath)
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
if($Mode-eq 'Prepare'){
 $definition=$s.NewTask(0);$definition.XmlText=[IO.File]::ReadAllText($c.preparedXml.path);$definition.Settings.Enabled=$false
 Write-OwnedArtifactBytes $c.registrationXml.path ([Text.UTF8Encoding]::new($false).GetBytes($definition.XmlText)) $c.ownerSid
 $parent=$folder.GetSecurityDescriptor(7);$expected=Get-TaskPolicyExpectedSecurity $c.registrationSddl $parent $c.ownerSid
 $result.registrationXml=@{path=$c.registrationXml.path;sha256=(Hash-Text $definition.XmlText)}
 $result.expectedRegisteredSddl=$expected;$result.parentSddlSha256=Hash-Text $parent;$result.inheritedReadOnlyPrincipals=Get-TaskInheritedReadOnlyPrincipals $expected $c.ownerSid
}elseif($Mode-eq 'CreateOld'){
 $created=New-ApprovedTask $s $folder $c.oldTask.name $old.XmlText $c.ownerSid $c.registrationSddl
 $live=$folder.GetTask($c.oldTask.name);Assert-RegisteredTask $live $old $c.oldTask.name $c.expectedRegisteredSddl
 if($live.Enabled-or $live.GetInstances(0).Count-ne 0-or $live.Definition.Triggers.Count-ne 1){throw 'synthetic_old_safety_rejected'}
 [IO.File]::WriteAllText($c.oldTask.xml.path,$live.Xml,[Text.UTF8Encoding]::new($false))
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
 foreach($name in @($c.taskName,$c.oldTask.name)){
  $all=$folder.GetTasks(1);$present=$false;for($i=1;$i-le $all.Count;$i++){if($all.Item($i).Name-ceq $name){$present=$true}}
  if(!$present){continue}
  $live=$folder.GetTask($name);$expected=$old
  if($name-ceq $c.taskName){$expected=$s.NewTask(0);$expected.XmlText=[IO.File]::ReadAllText($c.registrationXml.path)}
  Assert-RegisteredTask $live $expected $name $c.expectedRegisteredSddl
  if($live.Enabled-or $live.GetInstances(0).Count-ne 0){throw 'synthetic_cleanup_state_rejected'}
  $folder.DeleteTask($name,0);Assert-TaskAbsent $folder $name;$deleted++
 }
 $result.deleted=$deleted
}
Write-OwnedArtifactBytes $OutputPath ([Text.UTF8Encoding]::new($false).GetBytes(($result|ConvertTo-Json -Depth 8))) $c.ownerSid
@{passed=$true;started=$false}|ConvertTo-Json -Compress
