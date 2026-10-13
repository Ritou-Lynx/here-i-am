# CI-only disabled nonce task registration; Stop/Inspect retain read-only adapters.
param([Parameter(Mandatory=$true)][string]$InputPath,[Parameter(Mandatory=$true)][string]$MaintenanceDirectory,[ValidateSet('Register','Unregister','Stop','Inspect')][string]$Mode)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
if($env:GITHUB_ACTIONS -cne 'true'){throw 'r1_fixture_ci_only'}
. (Join-Path $MaintenanceDirectory 'stop-schema6-session.ps1')
$inputData=Get-Content -LiteralPath $InputPath -Raw|ConvertFrom-Json
$script:fixtureTask=$inputData.task
$script:Schema6TaskAdapter={param($Operation,$TaskName)
 if($TaskName -cne $script:fixtureTask.Name){throw 'r1_unknown_task'}
 $running=$null -ne (Get-Process -Id $inputData.initialPid -ErrorAction SilentlyContinue)
 switch($Operation){
  'Read'{return [pscustomobject]@{Name=$script:fixtureTask.Name;Arguments=$script:fixtureTask.Arguments;Path=$script:fixtureTask.Path;WorkingDirectory=$script:fixtureTask.WorkingDirectory;Enabled=$true;State=$(if($running){4}else{3})}}
  'State'{if($running){return 4};return 3}
  default{throw 'r1_task_mutation_forbidden'}
 }
}

function Get-R1OwnedTask($Folder,[string]$Name,[string]$Nonce){
 $owned=$Folder.GetTask($Name)
 if($owned.Path -cne ('\'+$Name) -or $owned.Definition.RegistrationInfo.Source -cne $Nonce -or
    $owned.Definition.Triggers.Count -ne 0 -or $owned.Definition.Actions.Count -ne 1 -or
    $owned.Definition.Actions.Item(1).Path -cne $script:fixtureTask.Path -or
    $owned.Definition.Actions.Item(1).Arguments -cne $script:fixtureTask.Arguments -or
    $owned.Definition.Actions.Item(1).WorkingDirectory -cne $script:fixtureTask.WorkingDirectory){throw 'r1_com_task_binding_changed'}
 $principal=$owned.Definition.Principal.UserId
 try{$owner=[Security.Principal.NTAccount]::new($principal).Translate([Security.Principal.SecurityIdentifier]).Value}catch{$owner=$principal}
 if($owner -cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'r1_com_owner_changed'}
 if($owned.Enabled -or $owned.State -ne 1 -or $owned.GetInstances(0).Count -ne 0 -or $owned.LastRunTime.Year -ge 2000 -or $owned.Definition.Settings.AllowDemandStart){throw 'r1_com_task_must_remain_unused_disabled'}
 return $owned
}
function Invoke-R1FixtureTask([switch]$Register){
 $name=$script:fixtureTask.Name
 if($name -cnotmatch '\AHereIAm-Synthetic-R1-Pairing-([a-f0-9]{32})\z'){throw 'r1_com_nonce_name_required'}
 $nonce=$Matches[1]
 $service=New-Object -ComObject 'Schedule.Service';$service.Connect();$folder=$service.GetFolder('\')
 if($Register){
  $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  $definition=$service.NewTask(0);$definition.RegistrationInfo.Source=$nonce
  $definition.Principal.UserId=$sid;$definition.Principal.LogonType=3;$definition.Principal.RunLevel=0
  $definition.Settings.Enabled=$false;$definition.Settings.Hidden=$true;$definition.Settings.AllowDemandStart=$false
  $action=$definition.Actions.Create(0);$action.Path=$script:fixtureTask.Path;$action.Arguments=$script:fixtureTask.Arguments;$action.WorkingDirectory=$script:fixtureTask.WorkingDirectory
  # TASK_CREATE only: never update or replace any existing task.
  $null=$folder.RegisterTaskDefinition($name,$definition,2,$sid,$null,3,$null)
  $null=Get-R1OwnedTask $folder $name $nonce
  $script:Schema6TaskAdapter=$null
  $snapshot=Invoke-Schema6TaskOperation -Operation Read -TaskName $name
  if($snapshot.Enabled -or $snapshot.Arguments -cne $script:fixtureTask.Arguments){throw 'r1_com_readback_failed'}
  [Console]::Out.WriteLine((@{format='r1-task-register-v1';registered=$true;disabled=$true;neverStarted=$true}|ConvertTo-Json -Compress))
 }else{
  # Enumeration proves absence even if registration failed before creating it.
  $tasks=$folder.GetTasks(1);$found=$false
  for($i=1;$i -le $tasks.Count;$i++){if([string]$tasks.Item($i).Name -ceq $name){$found=$true}}
  if($found){$null=Get-R1OwnedTask $folder $name $nonce;$folder.DeleteTask($name,0)}
  $remaining=$folder.GetTasks(1)
  for($i=1;$i -le $remaining.Count;$i++){if([string]$remaining.Item($i).Name -ieq $name){throw 'r1_com_delete_failed'}}
  [Console]::Out.WriteLine((@{format='r1-task-unregister-v1';existed=$found;deleted=$true;neverStarted=$true}|ConvertTo-Json -Compress))
 }
}
try{
 switch($Mode){
  'Register'{Invoke-R1FixtureTask -Register}
  'Unregister'{Invoke-R1FixtureTask}
  'Stop'{
   $result=Invoke-Schema6SessionStop -TaskName $script:fixtureTask.Name
   [Console]::Out.WriteLine((@{format='r1-stop-v1';status=$result.status}|ConvertTo-Json -Compress))
  }
  'Inspect'{
   # Pairing code is received only through stdin, never process arguments.
   $probe=[Console]::In.ReadToEnd()|ConvertFrom-Json
   $found=0;$clean=$true
   $snapshot=@(Get-CimInstance Win32_Process)
   foreach($expectedPid in $probe.pids){
    $process=@($snapshot|Where-Object {$_.ProcessId -eq [int]$expectedPid})
    if($process.Count -ne 1 -or [string]::IsNullOrEmpty($process[0].CommandLine)){throw 'r1_process_probe_missing'}
    $found++
   }
   # Inspect the complete CI process snapshot, including supervisor/guardian/backup children.
   foreach($process in $snapshot){
    if($process.CommandLine -and $process.CommandLine.Contains([string]$probe.code)){$clean=$false}
   }
   [Console]::Out.WriteLine((@{format='r1-process-inspection-v1';count=$found;noPlaintext=$clean}|ConvertTo-Json -Compress))
  }
 }
}catch{
 # Exception text is deliberately suppressed: no failed assertion may print code.
 [Console]::Error.WriteLine('r1_pairing_fixture_failed')
 exit 1
}
