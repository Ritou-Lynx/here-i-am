# C1 source-only update bridge. Importing only defines functions.
[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'stop-schema6-session.ps1')
. (Join-Path $PSScriptRoot 'register_task_primitives.ps1')
. (Join-Path $PSScriptRoot '../release_schema6/lifecycle/protected_paths.ps1')

function Get-Schema6UpdateTaskLocation([string]$Name) {
 if([string]::IsNullOrWhiteSpace($Name) -or $Name -match '[\x00-\x1f/]'){throw 'task_name_invalid'}
 $qualified='\'+$Name.TrimStart('\');$parts=$qualified.Substring(1).Split('\')
 if(@($parts|Where-Object{$_ -eq '' -or $_ -eq '.' -or $_ -eq '..'}).Count){throw 'task_name_invalid'}
 $separator=$qualified.LastIndexOf('\')
 return [pscustomobject]@{Path=$qualified;Folder=$(if($separator -eq 0){'\'}else{$qualified.Substring(0,$separator)});Name=$qualified.Substring($separator+1)}
}
# Only this boundary knows COM. Tests may install a process-local callback;
# stdin cannot select an adapter, and the production API never starts tasks.
function Invoke-Schema6UpdateTaskOperation([string]$Operation,[string]$Name,$Data) {
 $adapter=Get-Variable Schema6McpSourceTaskAdapter -Scope Script -ErrorAction SilentlyContinue
 if($adapter -and $adapter.Value){return (& $adapter.Value $Operation $Name $Data)}
 $location=Get-Schema6UpdateTaskLocation $Name
 $service=New-Object -ComObject 'Schedule.Service';$service.Connect();$folder=$service.GetFolder($location.Folder)
 if($Operation -eq 'Exists'){
  $tasks=$folder.GetTasks(1)
  for($i=1;$i -le $tasks.Count;$i++){if([string]$tasks.Item($i).Name -ieq $location.Name){return $true}}
  return $false
 }
 if($Operation -eq 'Snapshot'){
  $task=$folder.GetTask($location.Name);$definition=$task.Definition
  if($definition.Actions.Count -ne 1 -or $definition.Actions.Item(1).Type -ne 0){throw 'single_exec_login_action_required'}
  $action=$definition.Actions.Item(1)
  return [pscustomobject]@{taskXml=[string]$task.Xml;taskSddl=[string]$task.GetSecurityDescriptor(7);Arguments=[string]$action.Arguments;Path=[string]$action.Path;WorkingDirectory=[string]$action.WorkingDirectory;Enabled=[bool]$task.Enabled}
 }
 if($Operation -notin @('Plan','Create')){throw 'update_task_operation_invalid'}
 $definition=$service.NewTask(0);$definition.XmlText=[string]$Data.taskXml
 if($definition.Actions.Count -ne 1 -or $definition.Actions.Item(1).Type -ne 0){throw 'single_exec_login_action_required'}
 $definition.Actions.Item(1).Arguments=[string]$Data.Arguments;$definition.Settings.Enabled=$false
 $logon=[int]$definition.Principal.LogonType
 if($logon -notin @(2,3,4,5)){throw 'task_password_or_unsupported_logon_type'}
 if($Operation -eq 'Plan'){return [pscustomobject]@{taskXml=[string]$definition.XmlText}}
 $principal=if($logon -eq 4){[string]$definition.Principal.GroupId}else{[string]$definition.Principal.UserId}
 if([string]::IsNullOrWhiteSpace($principal)){throw 'task_principal_required'}
 # TASK_CREATE, never CREATE_OR_UPDATE. A racing duplicate fails closed.
 $null=$folder.RegisterTaskDefinition($location.Name,$definition,2,$principal,$null,$logon,[string]$Data.taskSddl)
 return (Invoke-Schema6UpdateTaskOperation 'Snapshot' $Name $null)
}
function Set-Schema6UpdateLoginArguments([string]$Arguments,[string]$LoginPath,[string]$LoginSha256) {
 $null=Assert-Schema6PlainPath $LoginPath
 if($LoginPath.Contains('"') -or $LoginPath -match '[\x00-\x1f]' -or $LoginSha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'new_login_arguments_invalid'}
 Initialize-Schema6MaintenanceNative
 $tokens=[Schema6MaintenanceHost]::Arguments($Arguments)
 # Record raw token spans using Windows quote/backslash rules; do not reserialize
 # unrelated tokens (including their whitespace and original quoting).
 $spans=@();$i=0
 while($i -lt $Arguments.Length){
  while($i -lt $Arguments.Length -and ($Arguments[$i] -eq ' ' -or $Arguments[$i] -eq "`t")){$i++}
  if($i -ge $Arguments.Length){break};$start=$i;$quoted=$false;$slashes=0
  while($i -lt $Arguments.Length){
   $char=$Arguments[$i]
   if(-not $quoted -and ($char -eq ' ' -or $char -eq "`t")){break}
   if($char -eq '"' -and ($slashes % 2) -eq 0){$quoted=-not $quoted}
   if($char -eq '\'){$slashes++}else{$slashes=0};$i++
  }
  if($quoted){throw 'login_task_arguments_ambiguous'}
  $spans+=,[pscustomobject]@{Start=$start;Length=$i-$start}
 }
 if($spans.Count -ne $tokens.Count){throw 'login_task_arguments_ambiguous'}
 $changes=@();$seen=@{}
 for($i=0;$i -lt $tokens.Count;$i++){
  $key=switch -Regex ($tokens[$i]){'^-(Login)?ConfigurationPath$' {'path'};'^-(Login)?ConfigurationSha256$' {'hash'};default {$null}}
  if($key){
   if($seen.ContainsKey($key) -or $i+1 -ge $tokens.Count){throw 'login_task_arguments_ambiguous'}
   $seen[$key]=$true;$i++;$span=$spans[$i];$value=if($key -eq 'path'){$LoginPath}else{$LoginSha256}
   $raw=$Arguments.Substring($span.Start,$span.Length)
   if($raw.StartsWith('"') -or $value -match '\s'){$value='"'+$value+'"'}
   $changes+=,[pscustomobject]@{Start=$span.Start;Length=$span.Length;Value=$value}
  }
 }
 if($seen.Count -ne 2){throw 'login_task_configuration_arguments_required'}
 foreach($change in @($changes|Sort-Object Start -Descending)){$Arguments=$Arguments.Remove($change.Start,$change.Length).Insert($change.Start,$change.Value)}
 return $Arguments
}
function Get-Schema6UpdateSource([string]$FromTask,[string]$NewTask) {
 $from=Get-Schema6UpdateTaskLocation $FromTask;$to=Get-Schema6UpdateTaskLocation $NewTask
 if($from.Path -ieq $to.Path){throw 'new_task_must_differ'}
 if(Invoke-Schema6UpdateTaskOperation 'Exists' $NewTask $null){throw 'new_task_already_exists'}
 $binding=Get-Schema6LoginBinding $FromTask
 $snapshot=Invoke-Schema6UpdateTaskOperation 'Snapshot' $FromTask $null
 foreach($key in @('Arguments','Path','WorkingDirectory','Enabled')){if($snapshot.$key -cne $binding.Task.$key){throw 'source_task_changed'}}
 return [pscustomobject]@{loginPath=$binding.ConfigurationPath;loginSha256=$binding.ConfigurationSha256;taskXml=$snapshot.taskXml;taskSddl=$snapshot.taskSddl;Arguments=$snapshot.Arguments;Path=$snapshot.Path;WorkingDirectory=$snapshot.WorkingDirectory}
}
function Assert-Schema6UpdateSource($Current,$Source) {
 foreach($key in @('loginPath','loginSha256','taskXml','taskSddl')){
  if(-not $Source -or -not ($Source.PSObject.Properties.Name -contains $key) -or [string]$Current.$key -cne [string]$Source.$key){throw ('source_snapshot_changed:'+ $key)}
 }
}
function Assert-Schema6UpdateCandidate([string]$Runtime) {
 if([string]::IsNullOrWhiteSpace($Runtime)){throw 'candidate_runtime_required'}
 Assert-ProtectedPath $Runtime -Root
 if(-not [IO.Directory]::Exists($Runtime)){throw 'candidate_runtime_directory_required'}
 # Check each child before descending. Never recurse through an unchecked link.
 $pending=[Collections.Generic.Stack[string]]::new();$pending.Push($Runtime)
 while($pending.Count -gt 0){
  $directory=$pending.Pop()
  Assert-ProtectedPath $directory
  foreach($item in @(Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop)){
   Assert-ProtectedPath $item.FullName
   if($item.PSIsContainer){$pending.Push($item.FullName)}
  }
 }
}
function Invoke-Schema6McpSourceTask($Request) {
 $ErrorActionPreference='Stop'
 if($Request.operation -eq 'write'){
  . (Join-Path $PSScriptRoot 'owned_artifacts.ps1')
  $allowed=@('mcp.json','daily-backup-config.json','login.json','login-task.xml','field-diff.json');$seen=@{}
  if(@($Request.files).Count -eq 0){throw 'output_files_required'}
  foreach($file in $Request.files){if($file.name -cnotin $allowed -or $seen.ContainsKey($file.name) -or $file.text -isnot [string]){throw 'output_file_rejected'};$seen[$file.name]=$true}
  $owner=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  Invoke-Schema6Step 'update.write.directory' {New-OwnedArtifactDirectory $Request.out $owner}
  foreach($file in $Request.files){Invoke-Schema6Step ('update.write.'+$file.name) {Write-OwnedArtifactBytes (Join-Path $Request.out $file.name) ([Text.UTF8Encoding]::new($false).GetBytes($file.text)) $owner}}
  return [pscustomobject]@{written=$true}
 }
 if($Request.operation -notin @('read','check','register')){throw 'update_operation_invalid'}
 $current=Invoke-Schema6Step 'update.task.read' {Get-Schema6UpdateSource $Request.fromTask $Request.newTask}
 if($Request.operation -eq 'read'){return [pscustomobject]@{loginPath=$current.loginPath;loginSha256=$current.loginSha256;taskXml=$current.taskXml;taskSddl=$current.taskSddl}}
 Invoke-Schema6Step 'update.task.snapshot' {Assert-Schema6UpdateSource $current $Request.source}
 Invoke-Schema6Step 'update.candidate.paths' {
  if($Request.PSObject.Properties.Name -notcontains 'candidateRuntime' -or $Request.candidateRuntime -isnot [string]){throw 'candidate_runtime_required'}
  Assert-Schema6UpdateCandidate $Request.candidateRuntime
 }
 Invoke-Schema6Step 'update.task.security' {$null=Convert-TaskSecurity $current.taskSddl}
 $hasLogin=$Request.PSObject.Properties.Name -contains 'loginPath'
 if(-not $hasLogin){if($Request.operation -eq 'register'){throw 'new_login_arguments_required'};return [pscustomobject]@{checked=$true}}
 $arguments=Set-Schema6UpdateLoginArguments $current.Arguments $Request.loginPath $Request.loginSha256
 $data=[pscustomobject]@{taskXml=$current.taskXml;taskSddl=$current.taskSddl;Arguments=$arguments}
 $plan=Invoke-Schema6Step 'update.task.plan' {Invoke-Schema6UpdateTaskOperation 'Plan' $Request.newTask $data}
 if($Request.operation -eq 'check'){return [pscustomobject]@{checked=$true;taskXml=$plan.taskXml}}
 Invoke-Schema6Step 'update.task.login' {$null=Read-Schema6Json $Request.loginPath $Request.loginSha256}
 Invoke-Schema6Step 'update.task.recheck' {Assert-Schema6UpdateSource (Get-Schema6UpdateSource $Request.fromTask $Request.newTask) $Request.source}
 $registered=Invoke-Schema6Step 'update.task.register' {Invoke-Schema6UpdateTaskOperation 'Create' $Request.newTask $data}
 Invoke-Schema6Step 'update.task.readback' {
  if($registered.Enabled){throw 'new_task_readback_failed:enabled'}
  if($registered.Arguments -cne $arguments){throw 'new_task_readback_failed:arguments'}
  if($registered.Path -cne $current.Path){throw 'new_task_readback_failed:path'}
  if($registered.WorkingDirectory -cne $current.WorkingDirectory){throw 'new_task_readback_failed:working_directory'}
  # Match the existing registration contract: only redundant equal-SID/flags
  # allow ACEs collapse. Owner/group/protection and effective rights stay exact.
  if((Convert-TaskSecurity $registered.taskSddl) -cne (Convert-TaskSecurity $current.taskSddl)){throw 'new_task_readback_failed:security'}
  $binding=Get-Schema6LoginBinding $Request.newTask
  if($binding.ConfigurationPath -cne $Request.loginPath -or $binding.ConfigurationSha256 -cne $Request.loginSha256){throw 'new_login_binding_readback_failed'}
  $old=Invoke-Schema6UpdateTaskOperation 'Snapshot' $Request.fromTask $null
  if($old.taskXml -cne $current.taskXml -or $old.taskSddl -cne $current.taskSddl){throw 'source_task_changed_after_registration'}
 }
 return [pscustomobject]@{registered=$true;enabled=$false;taskXml=$registered.taskXml}
}
if($MyInvocation.InvocationName -ne '.'){
 [Console]::InputEncoding=[Text.UTF8Encoding]::new($false)
 [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
 try{
  $ErrorActionPreference='Stop'
  $request=[Console]::In.ReadToEnd()|ConvertFrom-Json -ErrorAction Stop
  $result=Invoke-Schema6McpSourceTask $request
  [Console]::Out.WriteLine((@{step='update.task.result';ok=$true;detail='completed';result=$result}|ConvertTo-Json -Depth 12 -Compress))
 }catch{Write-Schema6Step 'update.task.result' $false $_.Exception.Message;exit 2}
}
