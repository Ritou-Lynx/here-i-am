# Test-only scheduler adapter, persisted between Node bridge calls. No COM task.
param([Parameter(Mandatory=$true)][string]$StatePath,[Parameter(Mandatory=$true)][string]$Bridge)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
[Console]::InputEncoding=[Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
. $Bridge
$script:fixture=Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8|ConvertFrom-Json
$script:Schema6TaskAdapter={param($Operation,$Name)
 if($Operation -ne 'Read'){throw 'synthetic_read_only_adapter'}
 $task=@($script:fixture.tasks|Where-Object{$_.Name -ieq $Name})
 if($task.Count -ne 1){throw 'synthetic_task_missing'};return $task[0]
}
$script:Schema6McpSourceTaskAdapter={param($Operation,$Name,$Data)
 if($script:fixture.PSObject.Properties.Name -contains 'injectedError'){throw [string]$script:fixture.injectedError}
 $tasks=@($script:fixture.tasks|Where-Object{$_.Name -ieq $Name})
 if($Operation -eq 'Exists'){return $tasks.Count -gt 0}
 if($Operation -eq 'Snapshot'){
  if($tasks.Count -ne 1){throw 'synthetic_task_missing'};$task=$tasks[0]
  return [pscustomobject]@{taskXml=$task.taskXml;taskSddl=$task.taskSddl;Arguments=$task.Arguments;Path=$task.Path;WorkingDirectory=$task.WorkingDirectory;Enabled=$task.Enabled}
 }
 $xml=[xml]$Data.taskXml;$xml.Task.Actions.Exec.Arguments=[string]$Data.Arguments;$xml.Task.Settings.Enabled='false'
 if($Operation -eq 'Plan'){return [pscustomobject]@{taskXml=$xml.OuterXml}}
 if($Operation -ne 'Create' -or $tasks.Count -gt 0){throw 'synthetic_create_rejected'}
 Initialize-Schema6MaintenanceNative;$args=[Schema6MaintenanceHost]::Arguments($Data.Arguments)
 $at=[Array]::IndexOf($args,'-LoginConfigurationPath');$hashAt=[Array]::IndexOf($args,'-LoginConfigurationSha256')
 $login=Read-Schema6Json $args[$at+1] $args[$hashAt+1]
 $task=[pscustomobject]@{Name=$Name;Path=[string]$xml.Task.Actions.Exec.Command;Arguments=$Data.Arguments;WorkingDirectory=[string]$xml.Task.Actions.Exec.WorkingDirectory;Enabled=$false;State=3;taskXml=$xml.OuterXml;taskSddl=$Data.taskSddl;ConfigurationSha256=$args[$hashAt+1];ControlRoot=$login.control_root}
 $script:fixture.tasks=@($script:fixture.tasks)+@($task)
 [IO.File]::WriteAllText($StatePath,($script:fixture|ConvertTo-Json -Depth 15),[Text.UTF8Encoding]::new($false))
 return (& $script:Schema6McpSourceTaskAdapter 'Snapshot' $Name $null)
}
try{
 $request=[Console]::In.ReadToEnd()|ConvertFrom-Json
 $result=Invoke-Schema6McpSourceTask $request
 [Console]::Out.WriteLine((@{step='update.task.result';ok=$true;detail='completed';result=$result}|ConvertTo-Json -Depth 12 -Compress))
}catch{Write-Schema6Step 'update.task.result' $false $_.Exception.Message;exit 2}
