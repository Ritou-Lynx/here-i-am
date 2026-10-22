# CI-only, in-memory Task Scheduler boundary. No tasks or Core processes are created.
param(
 [Parameter(Mandatory=$true)][string]$MaintenanceDirectory,
 [ValidateSet('success','success-old-disabled','preflight','stop-old','sessions','disable-old','enable-new','start-new','ready-new','rollback-stop','rollback-closed','rollback-ready')][string]$Scenario,
 [ValidateSet('absent','false','true')][string]$Mode='absent',
 [switch]$DryRun
)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
if($env:CI -cne 'true'){throw 'synthetic_ci_gate_required'}
$requestedDryRun=$DryRun
. (Join-Path $MaintenanceDirectory 'switch-login-task.ps1')
$script:operations=[Collections.Generic.List[string]]::new()
$script:events=[Collections.Generic.List[string]]::new()
$script:enabled=@{'Synthetic-A'=($Scenario -ne 'success-old-disabled');'Synthetic-B'=$false}
$script:started=@{'Synthetic-A'=0;'Synthetic-B'=0}
function Get-Schema6LoginBinding([string]$Name) {
 if($Scenario -eq 'preflight'){throw 'synthetic_preflight_failed'}
 return [pscustomobject]@{Task=[pscustomobject]@{Name=$Name};Login=[pscustomobject]@{state_directory='C:\synthetic-state'};McpPort=47899}
}
function Assert-Schema6NoRecovery($Binding) {}
function Assert-Schema6TaskUnchanged([string]$Name,$Binding) {}
function Invoke-Schema6StopBinding {
 param($Binding,[string[]]$PreviousSessions=@(),[switch]$RequireCleanNewSessions)
 $script:events.Add('Stop:'+$Binding.Task.Name)
 if($Binding.Task.Name -eq 'Synthetic-A' -and $Scenario -eq 'stop-old'){throw 'synthetic_stop_failed'}
 if($RequireCleanNewSessions -and $Scenario -eq 'rollback-stop'){throw 'synthetic_rollback_stop_failed'}
}
function Assert-Schema6ClosedFiles($Binding) {
 $script:events.Add('Closed:'+$Binding.Task.Name)
 if($Scenario -eq 'rollback-closed'){throw 'synthetic_rollback_closed_failed'}
}
function Get-Schema6SessionDirectories($Binding) {
 $script:events.Add('Sessions:'+$Binding.Task.Name)
 if($Binding.Task.Name -eq 'Synthetic-B' -and $Scenario -eq 'sessions'){throw 'synthetic_sessions_failed'}
 return @()
}
function Wait-Schema6LoginReady {
 param([string]$Name,$Binding,[string[]]$PreviousSessions,[int]$TimeoutSeconds,[string]$HealthUrl)
 $script:events.Add('Ready:'+$Name)
 if($Name -eq 'Synthetic-B' -and ($Scenario -eq 'ready-new' -or $Scenario.StartsWith('rollback-'))){throw 'synthetic_ready_failed'}
 if($Name -eq 'Synthetic-A' -and $Scenario -eq 'rollback-ready'){throw 'synthetic_rollback_ready_failed'}
}
$script:Schema6TaskAdapter={
 param($Operation,$Name)
 $script:events.Add($Operation+':'+$Name)
 if(($Operation -eq 'Disable' -and $Name -eq 'Synthetic-A' -and $Scenario -eq 'disable-old') -or
    ($Operation -eq 'Enable' -and $Name -eq 'Synthetic-B' -and $Scenario -eq 'enable-new') -or
    ($Operation -eq 'Start' -and $Name -eq 'Synthetic-B' -and $Scenario -eq 'start-new')){throw 'synthetic_task_failed'}
 $script:operations.Add($Operation+':'+$Name)
 switch($Operation){
  'Enable' {$script:enabled[$Name]=$true}
  'Disable' {$script:enabled[$Name]=$false}
  'Start' {if(-not $script:enabled[$Name]){throw 'synthetic_disabled'};$script:started[$Name]++}
  default {throw 'unexpected_task_operation'}
 }
}
$arguments=@{FromTask='Synthetic-A';ToTask='Synthetic-B';ReadyTimeoutSeconds=1;DryRun=$requestedDryRun}
if($Mode -eq 'true'){$arguments.NoRollback=$true}
if($Mode -eq 'false'){$arguments.NoRollback=$false}
$output=[IO.StringWriter]::new([Globalization.CultureInfo]::InvariantCulture)
$previousOutput=[Console]::Out
try {
 [Console]::SetOut($output)
 $code=Invoke-Schema6LoginSwitch @arguments
}finally{[Console]::SetOut($previousOutput)}
$report=[ordered]@{
 format='schema6-r1-no-rollback-v1';code=$code
 outputBase64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($output.ToString()))
 operations=@($script:operations.ToArray());events=@($script:events.ToArray())
 enabledA=$script:enabled['Synthetic-A'];enabledB=$script:enabled['Synthetic-B']
 startedA=$script:started['Synthetic-A'];startedB=$script:started['Synthetic-B']
}
[Console]::Out.WriteLine(($report|ConvertTo-Json -Depth 5 -Compress))
exit $code
