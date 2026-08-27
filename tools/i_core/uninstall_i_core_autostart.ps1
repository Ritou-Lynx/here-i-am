[CmdletBinding(SupportsShouldProcess = $true)]
param()

$ErrorActionPreference = 'Stop'
$taskName = 'HereIAm-iCore'
$ownershipMarker = 'HereIAm-iCore managed/v1 8d9d3f9a-23d6-4c96-883c-6a9d31d1fda1'
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

if ($null -eq $task) {
  [pscustomobject]@{ task_name = $taskName; removed = $false; reason = 'not_installed' }
  exit 0
}

if ($task.Description -ne $ownershipMarker) {
  throw "Refusing to remove an unowned scheduled task named $taskName."
}

if ($task.State -eq 'Running' -and $PSCmdlet.ShouldProcess($taskName, 'Stop running task')) {
  Stop-ScheduledTask -TaskName $taskName
}
if ($PSCmdlet.ShouldProcess($taskName, 'Unregister task')) {
  Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

# This script intentionally does not touch tools/i_core/.state or any iCore data.
[pscustomobject]@{ task_name = $taskName; removed = $true; data_removed = $false }
