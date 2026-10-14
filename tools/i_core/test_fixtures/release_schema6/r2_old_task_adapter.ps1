# In-memory Scheduler boundary only. Never connects COM, registers, or starts tasks.
$script:syntheticOldTask=[pscustomobject]@{Enabled=[bool]$request.enabled;Path=('\'+$request.task);Xml=[string]$request.xml}
$script:syntheticInstanceCount=[int]$request.instanceCount
$script:syntheticOldTask|Add-Member ScriptMethod GetInstances {param($flags)return [pscustomobject]@{Count=$script:syntheticInstanceCount}}
$script:syntheticOldTask|Add-Member ScriptMethod GetSecurityDescriptor {param($flags)if($flags-ne 7){throw 'synthetic_descriptor_flags'};return $request.sddl}
$script:syntheticFolder=[pscustomobject]@{}
$script:syntheticFolder|Add-Member ScriptMethod GetTask {param($name)if($name-cne $request.task){throw 'synthetic_task_name'};return $script:syntheticOldTask}
$script:syntheticParentReads=0
$script:syntheticFolder|Add-Member ScriptMethod GetSecurityDescriptor {
 param($flags)
 if($flags-ne 7){throw 'synthetic_descriptor_flags'}
 $script:syntheticParentReads++
 if($script:syntheticParentReads -gt 1 -and $request.PSObject.Properties.Name -contains 'parentSddlAfter'){return $request.parentSddlAfter}
 return $request.parentSddl
}
$script:syntheticService=[pscustomobject]@{}
$script:syntheticService|Add-Member ScriptMethod Connect {}
$script:syntheticService|Add-Member ScriptMethod GetFolder {param($name)if($name-cne '\'){throw 'synthetic_folder_name'};return $script:syntheticFolder}
function New-Object([string]$ComObject){
 if($ComObject-cne 'Schedule.Service'){throw 'synthetic_com_scope_rejected'}
 return $script:syntheticService
}

# The model exposes no mutation methods. Verify its observable task/folder fields
# after successful inspection as well; read counters are intentionally excluded.
function Get-SyntheticTaskFolderSnapshot {
 return ([ordered]@{enabled=$script:syntheticOldTask.Enabled;path=$script:syntheticOldTask.Path;xml=$script:syntheticOldTask.Xml;instances=$script:syntheticInstanceCount;sddl=$request.sddl;parentSddl=$request.parentSddl}|ConvertTo-Json -Depth 4 -Compress)
}
$script:syntheticFolderBefore=Get-SyntheticTaskFolderSnapshot
function Assert-SyntheticTaskFolderUnchanged {
 if((Get-SyntheticTaskFolderSnapshot) -cne $script:syntheticFolderBefore){throw 'synthetic_task_folder_changed'}
}
