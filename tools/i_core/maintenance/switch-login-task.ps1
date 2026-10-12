[CmdletBinding()]
param(
 [string]$FromTask,[string]$ToTask,
 [ValidateRange(1,3600)][int]$ReadyTimeoutSeconds=180,
 [string]$PublicHealthUrl,[switch]$DryRun
)
. (Join-Path $PSScriptRoot 'stop-schema6-session.ps1')

function Assert-Schema6TaskUnchanged([string]$Name,$Binding) {
 $now=Get-Schema6LoginBinding $Name
 if($now.Task.Arguments -cne $Binding.Task.Arguments -or $now.Task.Path -ine $Binding.Task.Path -or $now.Task.WorkingDirectory -ine $Binding.Task.WorkingDirectory -or $now.ConfigurationPath -ine $Binding.ConfigurationPath -or $now.ConfigurationSha256 -cne $Binding.ConfigurationSha256){throw 'login_task_changed_during_switch'}
 Assert-Schema6NoRecovery $now
}
function Get-Schema6SessionDirectories($Binding) {
 return @(Get-ChildItem -LiteralPath $Binding.Login.control_root -Directory -Filter 'session-*' -ErrorAction Stop|ForEach-Object {$_.FullName})
}
function Test-Schema6Port([int]$Port,[int]$TimeoutMilliseconds) {
 $client=[Net.Sockets.TcpClient]::new();$pending=$null
 try {
  $pending=$client.BeginConnect('127.0.0.1',$Port,$null,$null)
  if(-not $pending.AsyncWaitHandle.WaitOne($TimeoutMilliseconds) -or -not $client.Connected){return $false}
  $client.EndConnect($pending);return $true
 }finally{if($pending){$pending.AsyncWaitHandle.Close()};$client.Close()}
}
function Test-Schema6PublicHealth([string]$Url,[int]$TimeoutMilliseconds) {
 $request=[Net.HttpWebRequest]::Create($Url);$request.Method='GET'
 $request.Timeout=$TimeoutMilliseconds;$request.ReadWriteTimeout=$TimeoutMilliseconds
 $request.AllowAutoRedirect=$false;$response=$null
 try {$response=$request.GetResponse();return ([int]$response.StatusCode -eq 200)}
 catch {
  # A transient network failure is observable, then retried within the same
  # readiness deadline. The final timeout remains a failure and triggers rollback.
  Write-Schema6Step 'switch.public_health_probe' $false $_.Exception.Message
  return $false
 }finally{if($response){$response.Close()};$request.Abort()}
}
function Wait-Schema6LoginReady {
 param([string]$Name,$Binding,[string[]]$PreviousSessions,[int]$TimeoutSeconds,[string]$HealthUrl)
 $watch=[Diagnostics.Stopwatch]::StartNew()
 while($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds){
  Assert-Schema6TaskUnchanged $Name $Binding
  $taskState=Invoke-Schema6TaskOperation -Operation State -TaskName $Name
  $sessions=@(Get-Schema6LiveSessions $Binding)
  try {
   if($sessions.Count -gt 1){throw 'multiple_live_sessions_manual_review_required'}
   foreach($s in $sessions){
    if($PreviousSessions -contains $s.Directory){continue}
    # Only the latest generation can satisfy readiness. A stopped prior Core
    # inside the same host must never stand in for a pending restart.
    $generations=@(Get-ChildItem -LiteralPath $s.Directory -Directory -Filter 'control-*'|Sort-Object LastWriteTimeUtc -Descending)
    foreach($d in @($generations|Select-Object -First 1)){
     $launchPath=Join-Path $d.FullName 'launch.json';$readyPath=Join-Path $d.FullName 'ready.json';$mcpPath=Join-Path $d.FullName 'mcp-start.json'
     if(-not (Test-Path -LiteralPath $launchPath) -or -not (Test-Path -LiteralPath $readyPath) -or -not (Test-Path -LiteralPath $mcpPath)){continue}
     if((Test-Path -LiteralPath (Join-Path $d.FullName 'mcp-stop.json')) -or (Test-Path -LiteralPath (Join-Path $d.FullName 'session-close.json')) -or (Test-Path -LiteralPath (Join-Path $d.FullName 'child.json'))){throw 'new_session_ended_before_ready'}
     $launch=Read-Schema6Json $launchPath;$ready=Read-Schema6Json $readyPath;$mcp=Read-Schema6Json $mcpPath
     $marker=Read-Schema6Json (Join-Path $Binding.Login.state_directory 's6-lifecycle.json')
     if($marker.phase -cne 'listening' -or $marker.token -cne $launch.token -or $marker.configuration_sha256 -cne $Binding.Login.core_configuration_sha256){throw 'new_session_lifecycle_not_listening'}
     foreach($identity in @(@{Pid=$ready.pid;Ticks=$null;Receipt=$readyPath},@{Pid=$mcp.pid;Ticks=$mcp.started_ticks;Receipt=$mcpPath})){
      $process=[Diagnostics.Process]::GetProcessById([int]$identity.Pid)
      try{if($process.HasExited -or $process.StartTime.ToUniversalTime().Ticks -gt (Get-Item -LiteralPath $identity.Receipt).LastWriteTimeUtc.Ticks -or ($identity.Ticks -and $process.StartTime.ToUniversalTime().Ticks -ne [long]$identity.Ticks)){throw 'new_session_process_not_live'}}finally{$process.Dispose()}
     }
     if($launch.token -cne $ready.token -or $launch.token -cne $mcp.core_token -or $ready.pid -ne $mcp.core_pid -or $mcp.core_ready_bound -ne $true -or $ready.configuration_sha256 -cne $Binding.Login.core_configuration_sha256 -or $ready.manifest_sha256 -cne $s.Window.manifest_sha256 -or $launch.configuration_file -ine $Binding.Login.core_configuration_path -or $launch.state -ine $Binding.Login.state_directory -or $mcp.listen_port -ne $Binding.McpPort){throw 'new_session_ready_binding_mismatch'}
     if($taskState -ne 4){continue}
     $remaining=[int]($TimeoutSeconds*1000-$watch.ElapsedMilliseconds)
     if($remaining -le 0){break}
     if(-not (Test-Schema6Port $Binding.CorePort ([Math]::Min(250,$remaining)))){continue}
     $remaining=[int]($TimeoutSeconds*1000-$watch.ElapsedMilliseconds);if($remaining -le 0){break}
     if(-not (Test-Schema6Port $Binding.McpPort ([Math]::Min(250,$remaining)))){continue}
     if($HealthUrl){
      $remaining=[int]($TimeoutSeconds*1000-$watch.ElapsedMilliseconds);if($remaining -le 0){break}
      if(-not (Test-Schema6PublicHealth $HealthUrl ([Math]::Min(5000,$remaining)))){continue}
     }
     Assert-Schema6TaskUnchanged $Name $Binding
     return
    }
   }
  }finally{foreach($s in $sessions){$s.Lease.Dispose()}}
  $remaining=[int]($TimeoutSeconds*1000-$watch.ElapsedMilliseconds)
  if($remaining -gt 0){Start-Sleep -Milliseconds ([Math]::Min(200,$remaining))}
 }
 throw 'new_session_ready_timeout'
}
function Invoke-Schema6LoginSwitch {
 param([string]$FromTask,[string]$ToTask,[ValidateRange(1,3600)][int]$ReadyTimeoutSeconds=180,[string]$PublicHealthUrl,[switch]$DryRun)
 $from=$null;$to=$null;$previous=@()
 try {
  $bindings=Invoke-Schema6Step 'switch.preflight' {
   if([string]::IsNullOrWhiteSpace($FromTask) -or [string]::IsNullOrWhiteSpace($ToTask) -or $FromTask.TrimStart('\').Equals($ToTask.TrimStart('\'),[StringComparison]::OrdinalIgnoreCase)){throw 'two_distinct_tasks_required'}
   if($PublicHealthUrl){$uri=[Uri]$PublicHealthUrl;if(-not $uri.IsAbsoluteUri -or $uri.Scheme -notin @('http','https') -or $uri.UserInfo -or $uri.Fragment){throw 'public_health_url_invalid'}}
   $old=Get-Schema6LoginBinding $FromTask;$next=Get-Schema6LoginBinding $ToTask
   if(-not $old.Login.state_directory.Equals($next.Login.state_directory,[StringComparison]::OrdinalIgnoreCase)){throw 'same_data_root_required'}
   if(-not $old.McpPort -or -not $next.McpPort){throw 'both_core_and_mcp_ports_required'}
   Assert-Schema6NoRecovery $old;Assert-Schema6NoRecovery $next
   return [pscustomobject]@{From=$old;To=$next}
  }
  $from=$bindings.From;$to=$bindings.To
  if($DryRun){Write-Schema6Step 'switch.result' $true 'dry_run_passed';return 0}
  $null=Invoke-Schema6Step 'switch.stop_old' {Assert-Schema6TaskUnchanged $FromTask $from;Invoke-Schema6StopBinding $from}
 }catch{Write-Schema6Step 'switch.stopped' $false $_.Exception.Message;return 2}
 try {
  $previous=Get-Schema6SessionDirectories $to
  Invoke-Schema6Step 'switch.disable_old' {Invoke-Schema6TaskOperation -Operation Disable -TaskName $FromTask}
  Invoke-Schema6Step 'switch.enable_new' {Assert-Schema6TaskUnchanged $ToTask $to;Invoke-Schema6TaskOperation -Operation Enable -TaskName $ToTask}
  Invoke-Schema6Step 'switch.start_new' {Assert-Schema6TaskUnchanged $ToTask $to;Invoke-Schema6TaskOperation -Operation Start -TaskName $ToTask}
  Invoke-Schema6Step 'switch.ready_new' {Wait-Schema6LoginReady -Name $ToTask -Binding $to -PreviousSessions $previous -TimeoutSeconds $ReadyTimeoutSeconds -HealthUrl $PublicHealthUrl}
  Write-Schema6Step 'switch.result' $true 'switched';return 0
 }catch{Write-Schema6Step 'switch.failure' $false $_.Exception.Message}
 try {
  # Use the read-only preflight snapshot to close the exact new scope even when
  # its task arguments have since drifted. Never follow the changed arguments.
  $null=Invoke-Schema6Step 'rollback.stop_new' {Invoke-Schema6StopBinding -Binding $to -PreviousSessions $previous -RequireCleanNewSessions}
  Invoke-Schema6Step 'rollback.closed_files' {Assert-Schema6ClosedFiles $to}
  Invoke-Schema6Step 'rollback.disable_new' {Invoke-Schema6TaskOperation -Operation Disable -TaskName $ToTask}
  Invoke-Schema6Step 'rollback.validate_old' {Assert-Schema6TaskUnchanged $FromTask $from}
  $previous=Get-Schema6SessionDirectories $from
  Invoke-Schema6Step 'rollback.enable_old' {Invoke-Schema6TaskOperation -Operation Enable -TaskName $FromTask}
  Invoke-Schema6Step 'rollback.start_old' {Invoke-Schema6TaskOperation -Operation Start -TaskName $FromTask}
  Invoke-Schema6Step 'rollback.ready_old' {Wait-Schema6LoginReady -Name $FromTask -Binding $from -PreviousSessions $previous -TimeoutSeconds $ReadyTimeoutSeconds -HealthUrl $PublicHealthUrl}
  Write-Schema6Step 'switch.result' $false 'rolled_back';return 1
 }catch{Write-Schema6Step 'rollback.stopped_manual_review' $false $_.Exception.Message;return 2}
}
if($MyInvocation.InvocationName -ne '.') {
 $ErrorActionPreference='Stop'
 $code=Invoke-Schema6LoginSwitch -FromTask $FromTask -ToTask $ToTask -ReadyTimeoutSeconds $ReadyTimeoutSeconds -PublicHealthUrl $PublicHealthUrl -DryRun:$DryRun
 exit $code
}
