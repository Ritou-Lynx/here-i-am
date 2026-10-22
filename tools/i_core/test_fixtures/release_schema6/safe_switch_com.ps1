# CI-only COM coverage. The sole action is a bounded, hidden sleep.
param([Parameter(Mandatory=$true)][string]$StopScript)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
if($env:CI-cne 'true' -or $env:SCHEMA6_SYNTHETIC_TASK_TEST-cne '1'){throw 'synthetic_com_ci_gate_required'}
. $StopScript
$script:Schema6TaskAdapter=$null
$service=New-Object -ComObject 'Schedule.Service';$service.Connect();$folder=$service.GetFolder('\')
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$nonce=[Guid]::NewGuid().ToString('N');$name='HereIAm-Synthetic-SafeSwitch-'+$nonce
$executable=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$arguments='-NoProfile -NonInteractive -WindowStyle Hidden -Command "Start-Sleep -Seconds 20"'
$definition=$service.NewTask(0);$definition.RegistrationInfo.Source=$nonce
$definition.Principal.UserId=$sid;$definition.Principal.LogonType=2;$definition.Principal.RunLevel=0
$definition.Settings.Enabled=$false;$definition.Settings.Hidden=$true
$definition.Settings.AllowDemandStart=$true;$definition.Settings.ExecutionTimeLimit='PT1M'
$definition.Settings.DisallowStartIfOnBatteries=$false;$definition.Settings.StopIfGoingOnBatteries=$false
$action=$definition.Actions.Create(0);$action.Path=$executable;$action.Arguments=$arguments
$created=$false
$result=[ordered]@{format='schema6-safe-switch-com-v1';created=$false;read=$false;enabled=$false;disabled=$false;started=$false;run_observed=$false;LastTaskResult=$null;State=$null;stopped=$false;deleted=$false}
function Get-OwnedSyntheticTask {
 $task=$folder.GetTask($name)
 if($name-notmatch '^HereIAm-Synthetic-SafeSwitch-[a-f0-9]{32}$' -or $task.Path-cne ('\'+$name) -or
    $task.Definition.RegistrationInfo.Source-cne $nonce -or $task.Definition.Triggers.Count-ne 0 -or
    $task.Definition.Actions.Count-ne 1 -or $task.Definition.Actions.Item(1).Path-cne $executable -or
    $task.Definition.Actions.Item(1).Arguments-cne $arguments){throw 'synthetic_com_binding_changed'}
 $principal=[Security.Principal.NTAccount]::new($task.Definition.Principal.UserId)
 try{$actualSid=$principal.Translate([Security.Principal.SecurityIdentifier]).Value}catch{$actualSid=$task.Definition.Principal.UserId}
 if($actualSid-cne $sid){throw 'synthetic_com_owner_changed'}
 return $task
}
try{
 $null=$folder.RegisterTaskDefinition($name,$definition,2,$sid,$null,2,$null)
 $created=$true;$result.created=$true
 $snapshot=Invoke-Schema6TaskOperation -Operation Read -TaskName $name
 if($snapshot.Arguments-cne $arguments -or $snapshot.Path-cne $executable -or $snapshot.Enabled){throw 'synthetic_com_read_failed'}
 $result.read=$true
 $null=Invoke-Schema6TaskOperation -Operation Enable -TaskName $name
 if(-not (Get-OwnedSyntheticTask).Enabled){throw 'synthetic_com_enable_failed'};$result.enabled=$true
 $beforeLastRunTime=(Get-OwnedSyntheticTask).LastRunTime
 $null=Invoke-Schema6TaskOperation -Operation Start -TaskName $name
 # Start throws if Run returns no instance; hosted runners may not expose it
 # through GetInstances. Record observation separately from adapter success.
 $result.started=$true
 $instanceObserved=$false
 $deadline=[DateTime]::UtcNow.AddSeconds(15)
 do{
  $task=Get-OwnedSyntheticTask
  $instanceObserved=$task.GetInstances(0).Count-gt 0
  if($instanceObserved -or $task.LastRunTime-ne $beforeLastRunTime){$result.run_observed=$true;break}
  Start-Sleep -Milliseconds 100
 }while([DateTime]::UtcNow-lt $deadline)
 $result.LastTaskResult=[int]$task.LastTaskResult
 $result.State=Invoke-Schema6TaskOperation -Operation State -TaskName $name
 # The production adapter deliberately offers no forced-stop operation. This
 # harmless test action is stopped only when a running instance was observed.
 if($instanceObserved){
  $task.Stop(0)
  $deadline=[DateTime]::UtcNow.AddSeconds(15)
  while((Get-OwnedSyntheticTask).GetInstances(0).Count-ne 0 -and [DateTime]::UtcNow-lt $deadline){Start-Sleep -Milliseconds 100}
  if((Get-OwnedSyntheticTask).GetInstances(0).Count-ne 0){throw 'synthetic_com_stop_failed'};$result.stopped=$true
 }
 $null=Invoke-Schema6TaskOperation -Operation Disable -TaskName $name
 if((Get-OwnedSyntheticTask).Enabled){throw 'synthetic_com_disable_failed'};$result.disabled=$true
}finally{
 if($created){
  $bound=Get-OwnedSyntheticTask;$bound.Enabled=$false
  if($bound.GetInstances(0).Count-ne 0){$bound.Stop(0)}
  $deadline=[DateTime]::UtcNow.AddSeconds(15)
  while((Get-OwnedSyntheticTask).GetInstances(0).Count-ne 0 -and [DateTime]::UtcNow-lt $deadline){Start-Sleep -Milliseconds 100}
  if((Get-OwnedSyntheticTask).GetInstances(0).Count-ne 0){throw 'synthetic_com_cleanup_still_running'}
  $folder.DeleteTask($name,0)
  # A successful hidden-inclusive enumeration proves absence; a generic COM
  # exception cannot accidentally be treated as successful deletion.
  $remaining=$folder.GetTasks(1)
  for($i=1;$i-le $remaining.Count;$i++){if([string]$remaining.Item($i).Name-ieq $name){throw 'synthetic_com_delete_failed'}}
  $result.deleted=$true
 }
 [Console]::Out.WriteLine(($result|ConvertTo-Json -Compress))
}

