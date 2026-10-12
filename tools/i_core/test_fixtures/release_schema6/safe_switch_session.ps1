# Synthetic native-session adapter. Does not connect to Task Scheduler.
param([string]$InputPath,[Parameter(Mandatory=$true)][string]$MaintenanceDirectory,[ValidateSet('','close-fails','recovery-lock')][string]$MockFailure='')
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
. (Join-Path $MaintenanceDirectory 'stop-schema6-session.ps1')
. (Join-Path $MaintenanceDirectory 'switch-login-task.ps1')
# Pure orchestration test mode: every native boundary is replaced before use.
# It creates no process, file, lock, session or scheduled task.
if($MockFailure){
 $script:mockMutations=[Collections.Generic.List[string]]::new();$script:mockStarted=$false
 function Get-Schema6LoginBinding([string]$Name){return [pscustomobject]@{Task=[pscustomobject]@{Name=$Name};Login=[pscustomobject]@{state_directory=[IO.Path]::GetTempPath()};McpPort=1}}
 function Assert-Schema6NoRecovery($Binding){if($script:mockStarted -and $MockFailure-eq 'recovery-lock'){throw 'synthetic_recovery_lock'}}
 function Assert-Schema6TaskUnchanged([string]$Name,$Binding){Assert-Schema6NoRecovery $Binding}
 function Get-Schema6SessionDirectories($Binding){return @()}
 function Invoke-Schema6SessionStop([string]$TaskName){return [pscustomobject]@{status='clean_closed'}}
 function Invoke-Schema6StopBinding {param($Binding,[string[]]$PreviousSessions,[switch]$RequireCleanNewSessions);if($script:mockStarted -and $MockFailure-eq 'close-fails'){throw 'synthetic_close_failed'};return [pscustomobject]@{status='already_stopped'}}
 function Assert-Schema6ClosedFiles($Binding){Assert-Schema6NoRecovery $Binding}
 function Wait-Schema6LoginReady {param([string]$Name,$Binding,[string[]]$PreviousSessions,[int]$TimeoutSeconds,[string]$HealthUrl);throw 'synthetic_ready_failed'}
 $script:Schema6TaskAdapter={param($Operation,$TaskName)
  if($Operation-notin @('Enable','Disable','Start')){throw 'synthetic_unexpected_native_operation'}
  $script:mockMutations.Add($Operation+':'+$TaskName)
  if($Operation-eq 'Start'){$script:mockStarted=$true}
 }
 $code=Invoke-Schema6LoginSwitch -FromTask 'Synthetic-A' -ToTask 'Synthetic-B' -ReadyTimeoutSeconds 1
 [Console]::Out.WriteLine((@{format='schema6-safe-switch-mock-v1';code=$code;mutations=@($script:mockMutations.ToArray())}|ConvertTo-Json -Depth 4 -Compress))
 exit 0
}
$inputData=Get-Content -LiteralPath $InputPath -Raw|ConvertFrom-Json
$script:fixtureTasks=@{};$script:fixtureProcesses=@{};$script:fixtureMutations=[Collections.Generic.List[string]]::new()
foreach($task in $inputData.tasks){$script:fixtureTasks[$task.Name]=$task}
$script:fixtureProcesses[$inputData.from]=[Diagnostics.Process]::GetProcessById([int]$inputData.initialPid)
$script:fixtureDrift=$false
$script:Schema6TaskAdapter={
 param($Operation,$TaskName)
 if(-not $script:fixtureTasks.ContainsKey($TaskName)){throw 'synthetic_unknown_task'}
 $task=$script:fixtureTasks[$TaskName]
 switch($Operation){
  'Read' {
   $arguments=$task.Arguments
   if($TaskName-eq $inputData.to -and ($inputData.scenario-eq 'bad-pin' -or $script:fixtureDrift)){$arguments=$arguments.Replace($task.ConfigurationSha256,('0'*64))}
   return [pscustomobject]@{Name=$task.Name;Arguments=$arguments;Path=$task.Path;WorkingDirectory=$task.WorkingDirectory;Enabled=$task.Enabled;State=$(if($script:fixtureProcesses.ContainsKey($TaskName)-and -not $script:fixtureProcesses[$TaskName].HasExited){4}else{3})}
  }
  'State' {
   $running=$script:fixtureProcesses.ContainsKey($TaskName)-and -not $script:fixtureProcesses[$TaskName].HasExited
   if($running){return 4};return 3
  }
  'Enable' {$task.Enabled=$true;$script:fixtureMutations.Add('Enable:'+$TaskName);return}
  'Disable' {$task.Enabled=$false;$script:fixtureMutations.Add('Disable:'+$TaskName);return}
  'Start' {
   if(-not $task.Enabled){throw 'synthetic_disabled_start'}
   $script:fixtureMutations.Add('Start:'+$TaskName)
   $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$task.Path;$info.Arguments=$task.Arguments
   $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
   $process=[Diagnostics.Process]::new();$process.StartInfo=$info
   if(-not $process.Start()){throw 'synthetic_start_failed'}
   # Drain output asynchronously so a real native host can never block on pipes.
   $null=$process.StandardOutput.ReadToEndAsync();$null=$process.StandardError.ReadToEndAsync()
   $script:fixtureProcesses[$TaskName]=$process
   if($inputData.scenario-eq 'drift' -and $TaskName-eq $inputData.to){
    # Drift only after a real B session reaches Core + MCP ready. Its immutable
    # task snapshot remains available to the rollback's normal-close path.
    $deadline=[DateTime]::UtcNow.AddSeconds(180);$ready=$false
    while([DateTime]::UtcNow-lt $deadline -and -not $process.HasExited){
     foreach($session in @(Get-ChildItem -LiteralPath $task.ControlRoot -Directory)){
      foreach($control in @(Get-ChildItem -LiteralPath $session.FullName -Directory -Filter 'control-*')){
       if((Test-Path -LiteralPath (Join-Path $control.FullName 'ready.json')) -and (Test-Path -LiteralPath (Join-Path $control.FullName 'mcp-start.json'))){$ready=$true}
      }
     }
     if($ready){break};Start-Sleep -Milliseconds 100
    }
    if(-not $ready){throw 'synthetic_drift_target_never_ready'}
    $script:fixtureDrift=$true
   }
   return
  }
  default {throw 'synthetic_operation_rejected'}
 }
}
$result=[ordered]@{format='schema6-safe-switch-test-v1';code=$null;stopStatus=$null;error=$null;cleanup=$false}
try{
 if($inputData.scenario-eq 'stop'){
  $stopped=Invoke-Schema6SessionStop -TaskName $inputData.from
  $result.stopStatus=$stopped.status;$result.code=0
  $again=Invoke-Schema6SessionStop -TaskName $inputData.from;$result.secondStopStatus=$again.status
 }else{
  $result.code=Invoke-Schema6LoginSwitch -FromTask $inputData.from -ToTask $inputData.to -ReadyTimeoutSeconds 180 -DryRun:($inputData.scenario-eq 'dry-run')
 }
 $result.mutations=@($script:fixtureMutations.ToArray())
 $result.enabledA=[bool]$script:fixtureTasks[$inputData.from].Enabled
 $result.enabledB=[bool]$script:fixtureTasks[$inputData.to].Enabled
 $result.originalAlive=-not $script:fixtureProcesses[$inputData.from].HasExited
 $result.active=@($script:fixtureProcesses.Keys|Where-Object{-not $script:fixtureProcesses[$_].HasExited})
}catch{$result.error=$_.Exception.Message}
finally{
 $script:fixtureDrift=$false
 # Restore the test-only wrong hash before cleanup; production uses the cached
 # bound stop internally for rollback, which is the behavior under test.
 $inputData.scenario='cleanup'
 try{
  foreach($name in @($script:fixtureProcesses.Keys)){
   if(-not $script:fixtureProcesses[$name].HasExited){$null=Invoke-Schema6SessionStop -TaskName $name}
  }
  $result.cleanup=$true
 }catch{$result.cleanup=$false;$result.cleanupError=$_.Exception.Message}
 foreach($process in $script:fixtureProcesses.Values){$process.Dispose()}
}
[Console]::Out.WriteLine(($result|ConvertTo-Json -Depth 6 -Compress))
if($result.error -or -not $result.cleanup){exit 1}

