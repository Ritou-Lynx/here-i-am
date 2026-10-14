# In-memory Scheduler boundary only. Never connects COM, registers, or starts tasks.
$script:syntheticOldTask=[pscustomobject]@{Enabled=[bool]$request.enabled;Path=('\'+$request.task);Xml=[string]$request.xml}
$script:syntheticInstanceCount=[int]$request.instanceCount
$script:syntheticOldTask|Add-Member ScriptMethod GetInstances {param($flags)return [pscustomobject]@{Count=$script:syntheticInstanceCount}}
$script:syntheticOldTask|Add-Member ScriptMethod GetSecurityDescriptor {param($flags)if($flags-ne 7){throw 'synthetic_descriptor_flags'};return $request.sddl}
$script:syntheticFolder=[pscustomobject]@{}
$script:syntheticFolder|Add-Member ScriptMethod GetTask {param($name)if($name-cne $request.task){throw 'synthetic_task_name'};return $script:syntheticOldTask}
$script:syntheticFolder|Add-Member ScriptMethod GetSecurityDescriptor {param($flags)if($flags-ne 7){throw 'synthetic_descriptor_flags'};return $request.parentSddl}
$script:syntheticService=[pscustomobject]@{}
$script:syntheticService|Add-Member ScriptMethod Connect {}
$script:syntheticService|Add-Member ScriptMethod GetFolder {param($name)if($name-cne '\'){throw 'synthetic_folder_name'};return $script:syntheticFolder}
function New-Object([string]$ComObject){
 if($ComObject-cne 'Schedule.Service'){throw 'synthetic_com_scope_rejected'}
 return $script:syntheticService
}
