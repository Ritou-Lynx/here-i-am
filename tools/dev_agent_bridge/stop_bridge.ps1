$ErrorActionPreference = "Stop"

$matches = Get-CimInstance Win32_Process |
  Where-Object { $_.CommandLine -like "*dev_agent_bridge.mjs*" }

if (-not $matches) {
  Write-Host "Dev Agent Bridge is not running."
  exit 0
}

$bridgePort = if ($env:DEV_AGENT_BRIDGE_PORT) {
  $env:DEV_AGENT_BRIDGE_PORT
} else {
  "47831"
}
$cleanupUrl = "http://127.0.0.1:$bridgePort/experimental/v1/runtime/host/stop-app-server"
try {
  $cleanup = Invoke-RestMethod -Method Post -Uri $cleanupUrl -TimeoutSec 3
  if ($cleanup.stopped) {
    Write-Host "Stopped experimental Codex App Server cleanly."
  }
} catch {
  Write-Host "App Server cleanup endpoint unavailable; falling back to child-process cleanup."
}

function Get-DescendantProcessIds {
  param([int]$BridgeParentId)

  $allProcesses = @(Get-CimInstance Win32_Process)
  $pending = [System.Collections.Generic.Queue[int]]::new()
  $descendants = [System.Collections.Generic.List[int]]::new()
  $pending.Enqueue($BridgeParentId)
  while ($pending.Count -gt 0) {
    $currentParentId = $pending.Dequeue()
    foreach ($child in $allProcesses | Where-Object { $_.ParentProcessId -eq $currentParentId }) {
      $childId = [int]$child.ProcessId
      $descendants.Add($childId)
      $pending.Enqueue($childId)
    }
  }
  return $descendants.ToArray()
}

foreach ($process in $matches) {
  if ($process.ProcessId -eq $PID) {
    continue
  }
  $descendantIds = @(Get-DescendantProcessIds -BridgeParentId $process.ProcessId)
  [array]::Reverse($descendantIds)
  foreach ($childId in $descendantIds) {
    Stop-Process -Id $childId -Force -ErrorAction SilentlyContinue
    Write-Host "Stopped Bridge child process $childId."
  }
  Stop-Process -Id $process.ProcessId -Force
  Write-Host "Stopped Dev Agent Bridge process $($process.ProcessId)."
}
