param([string]$MaintenanceDirectory,[string]$StateDirectory,[switch]$HoldLock)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
. (Join-Path $MaintenanceDirectory 'stop-schema6-session.ps1')
$binding=[pscustomobject]@{Login=[pscustomobject]@{state_directory=$StateDirectory}}
$held=$null;$errorCode=$null
try {
 if($HoldLock){$held=[IO.File]::Open((Join-Path $StateDirectory 'shortcut-mail-relay.runtime.lock'),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}
 try {Assert-Schema6ClosedFiles $binding}catch{$errorCode=$_.Exception.Message}
}finally{if($held){$held.Dispose()}}
[Console]::Out.WriteLine((@{format='schema6-closed-files-test-v1';error=$errorCode}|ConvertTo-Json -Compress))
