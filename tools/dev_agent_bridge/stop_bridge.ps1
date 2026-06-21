$ErrorActionPreference = "Stop"

$matches = Get-CimInstance Win32_Process |
  Where-Object { $_.CommandLine -like "*dev_agent_bridge.mjs*" }

if (-not $matches) {
  Write-Host "Dev Agent Bridge is not running."
  exit 0
}

foreach ($process in $matches) {
  if ($process.ProcessId -eq $PID) {
    continue
  }
  Stop-Process -Id $process.ProcessId -Force
  Write-Host "Stopped Dev Agent Bridge process $($process.ProcessId)."
}
