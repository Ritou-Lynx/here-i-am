param([Parameter(Mandatory=$true)][string]$ControlDirectory,[Parameter(Mandatory=$true)][string]$RunId,[Parameter(Mandatory=$true)][int]$ChildPid,[switch]$CheckDatabase)
$ErrorActionPreference='Stop'
$env:PSModulePath="$PSHOME\Modules"
. (Join-Path $PSScriptRoot 'protected_paths.ps1')
Assert-ProtectedPath $ControlDirectory -Root
$launch=Get-Content -LiteralPath (Join-Path $ControlDirectory 'launch.json') -Raw | ConvertFrom-Json
if($launch.token -ne $RunId -or $launch.lifecycle -ne $PSScriptRoot) { throw 'offline_launch_unbound' }
$parent=Get-Process -Id $launch.parent_pid
$expected=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if($parent.StartTime.ToUniversalTime().Ticks.ToString() -ne $launch.parent_started_ticks -or $parent.Path -ne $expected) { throw 'offline_parent_unbound' }
$ready=Get-Content -LiteralPath (Join-Path $ControlDirectory 'guardian-ready.json') -Raw | ConvertFrom-Json
$guardian=Get-Process -Id $ready.pid
if($ready.run_id -ne $RunId -or $guardian.Path -ne $expected -or $guardian.StartTime.ToUniversalTime().Ticks.ToString() -ne $ready.started_ticks) { throw 'offline_guardian_unbound' }
. (Join-Path $PSScriptRoot 'owned_job.ps1')
if(-not [Schema6OwnedJob]::Contains($RunId,[uint32]$ChildPid)) { throw 'offline_child_not_owned' }
$busy=$false
try { $handle=[IO.File]::Open((Join-Path $launch.state 'shortcut-mail-relay.runtime.lock'),'Open','ReadWrite','None'); $handle.Dispose() } catch [IO.IOException] { $busy=$true }
if(-not $busy) { throw 'offline_lock_not_held' }
$settings=Get-Content -LiteralPath $launch.configuration_file -Raw | ConvertFrom-Json
Assert-ProtectedPath $settings.recovery_custody_directory -Root
$custodyLockPath=Join-Path $settings.recovery_custody_directory 'custody.lock'
Assert-ProtectedPath $custodyLockPath
$custodyBusy=$false
try { $custodyProbe=[IO.File]::Open($custodyLockPath,'Open','ReadWrite','None'); $custodyProbe.Dispose() } catch [IO.IOException] { $custodyBusy=$true }
if(-not $custodyBusy) { throw 'offline_custody_lock_not_held' }
if($CheckDatabase) {
 $databaseHandles=@()
 try {
  foreach($suffix in @('','-wal','-shm','-journal')) {
   $file=Join-Path $launch.state ('i-core.sqlite'+$suffix)
   if($suffix -eq '' -or [IO.File]::Exists($file)) {
    Assert-ProtectedPath $file
    $databaseHandles += [IO.File]::Open($file,'Open','ReadWrite','None')
   }
  }
 } finally { foreach($handle in $databaseHandles) { $handle.Dispose() } }
}
@{parent_pid=$parent.Id;guardian_pid=$guardian.Id;child_pid=$ChildPid;checked=$true} | ConvertTo-Json -Compress
