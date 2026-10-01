param([Parameter(Mandatory=$true)][int]$ProcessId)
$ErrorActionPreference = 'Stop'
$target = [Diagnostics.Process]::GetProcessById($ProcessId)
$handle = $target.Handle
if ($target.MainModule.FileName -ne (Join-Path $PSHOME 'powershell.exe')) { throw 'unexpected_supervisor_image' }
Write-Output 'handle-bound'
if (-not $target.WaitForExit(30000)) { throw 'supervisor_exit_timeout' }
@{exit_confirmed=$target.HasExited; exit_code=$target.ExitCode} | ConvertTo-Json -Compress
$target.Dispose()
