[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [switch]$StartNow
)

$ErrorActionPreference = 'Stop'
$taskName = 'HereIAm-iCore'
$ownershipMarker = 'HereIAm-iCore managed/v1 8d9d3f9a-23d6-4c96-883c-6a9d31d1fda1'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repositoryRoot = Split-Path -Parent (Split-Path -Parent $scriptRoot)
$startScript = Join-Path $scriptRoot 'start_i_core_service.ps1'

if (-not (Test-Path -LiteralPath $startScript -PathType Leaf)) {
  throw "iCore service launcher was not found: $startScript"
}

$nodePath = (Get-Command node -ErrorAction Stop).Source
$powerShellPath = (Get-Command powershell.exe -ErrorAction Stop).Source
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$startScript`" -NodePath `"$nodePath`""

$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($null -ne $existingTask -and $existingTask.Description -ne $ownershipMarker) {
  throw "Refusing to replace an unowned scheduled task named $taskName."
}

$action = New-ScheduledTaskAction `
  -Execute $powerShellPath `
  -Argument $arguments `
  -WorkingDirectory $repositoryRoot
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $currentUser
$trigger.Delay = 'PT10S'
$principal = New-ScheduledTaskPrincipal `
  -UserId $currentUser `
  -LogonType Interactive `
  -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet `
  -AllowStartIfOnBatteries `
  -DontStopIfGoingOnBatteries `
  -StartWhenAvailable `
  -RestartCount 5 `
  -RestartInterval (New-TimeSpan -Minutes 1) `
  -ExecutionTimeLimit ([TimeSpan]::Zero) `
  -MultipleInstances IgnoreNew
$definition = New-ScheduledTask `
  -Action $action `
  -Trigger $trigger `
  -Principal $principal `
  -Settings $settings `
  -Description $ownershipMarker

if ($PSCmdlet.ShouldProcess($taskName, 'Register current-user logon task')) {
  Register-ScheduledTask `
    -TaskName $taskName `
    -InputObject $definition `
    -Force | Out-Null
}

if ($StartNow -and $PSCmdlet.ShouldProcess($taskName, 'Start scheduled task')) {
  Start-ScheduledTask -TaskName $taskName
}

[pscustomobject]@{
  task_name = $taskName
  user = $currentUser
  trigger = 'AtLogOn+PT10S'
  run_level = 'Limited'
  start_now_requested = [bool]$StartNow
  node_path = $nodePath
  launcher = $startScript
}
