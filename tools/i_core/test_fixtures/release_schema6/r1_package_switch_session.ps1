# CI-only Task Scheduler adapter; Starts execute the real candidate login script.
param([Parameter(Mandatory=$true)][string]$InputPath,[Parameter(Mandatory=$true)][string]$MaintenanceDirectory,[ValidateSet('Stop','Switch')][string]$Mode)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
if($env:GITHUB_ACTIONS -cne 'true'){throw 'r1_fixture_ci_only'}
. (Join-Path $MaintenanceDirectory 'stop-schema6-session.ps1')
. (Join-Path $MaintenanceDirectory 'switch-login-task.ps1')
$inputData=Get-Content -LiteralPath $InputPath -Raw|ConvertFrom-Json
$script:tasks=@{};$script:processes=@{};$script:mutations=[Collections.Generic.List[string]]::new()
foreach($task in $inputData.tasks){$script:tasks[$task.Name]=$task}
if($Mode -eq 'Stop'){$script:processes[$inputData.from]=[Diagnostics.Process]::GetProcessById([int]$inputData.initialPid)}
$script:Schema6TaskAdapter={param($Operation,$TaskName)
 if(-not $script:tasks.ContainsKey($TaskName)){throw 'r1_unknown_task'}
 $task=$script:tasks[$TaskName]
 $running=$script:processes.ContainsKey($TaskName) -and -not $script:processes[$TaskName].HasExited
 switch($Operation){
  'Read'{return [pscustomobject]@{Name=$task.Name;Arguments=$task.Arguments;Path=$task.Path;WorkingDirectory=$task.WorkingDirectory;Enabled=$task.Enabled;State=$(if($running){4}else{3})}}
  'State'{if($running){return 4};return 3}
  'Enable'{$task.Enabled=$true;$script:mutations.Add('Enable:'+$TaskName);return}
  'Disable'{$task.Enabled=$false;$script:mutations.Add('Disable:'+$TaskName);return}
  'Start'{
   $script:mutations.Add('Start:'+$TaskName)
   if($TaskName -cne $inputData.to){throw 'r1_old_task_restart_forbidden'}
   if(-not $task.Enabled){throw 'r1_disabled_start'}
   $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$task.Path;$info.Arguments=$task.Arguments
   $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
   # Remove disallowed inherited settings again at the native child boundary.
   foreach($key in @($info.EnvironmentVariables.Keys)){if($key -like 'NODE_*' -or $key -like 'I_CORE_*'){$info.EnvironmentVariables.Remove($key)}}
   $process=[Diagnostics.Process]::new();$process.StartInfo=$info
   if(-not $process.Start()){throw 'r1_start_failed'}
   $null=$process.StandardOutput.ReadToEndAsync();$null=$process.StandardError.ReadToEndAsync()
   $script:processes[$TaskName]=$process;return
  }
  default{throw 'r1_unexpected_task_operation'}
 }
}
$result=[ordered]@{format='r1-switch-session-v1';code=$null;ready=$false;cleanup=$false;error=$null}
try{
 if($Mode -eq 'Stop'){$stopped=Invoke-Schema6SessionStop -TaskName $inputData.from;$result.code=0;$result.stopStatus=$stopped.status}
 else{
  $result.code=Invoke-Schema6LoginSwitch -FromTask $inputData.from -ToTask $inputData.to -ReadyTimeoutSeconds 180 -NoRollback
  $result.ready=($result.code -eq 0 -and $script:processes.ContainsKey($inputData.to) -and -not $script:processes[$inputData.to].HasExited)
  $result.enabledOld=[bool]$script:tasks[$inputData.from].Enabled;$result.enabledNew=[bool]$script:tasks[$inputData.to].Enabled
 }
 $result.mutations=@($script:mutations.ToArray())
}catch{$result.error='r1_switch_fixture_failed'}
finally{
 try{
  foreach($name in @($script:processes.Keys)){if(-not $script:processes[$name].HasExited){$null=Invoke-Schema6SessionStop -TaskName $name}}
  $result.cleanup=$true
 }catch{$result.cleanup=$false}
 foreach($process in $script:processes.Values){$process.Dispose()}
}
[Console]::Out.WriteLine(($result|ConvertTo-Json -Depth 5 -Compress))
if($result.error -or -not $result.cleanup){exit 1}
