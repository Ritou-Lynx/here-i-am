# Read-only check: leftover Dev Room bridge / keepalive autostart on this PC.
# Prints JSON lines only. Never prints absolute paths, user names or hosts.
$ErrorActionPreference = 'Continue'
$pattern = 'dev_agent_bridge|devroom|start_bridge|start_usb_bridge|47831|tailscale_keepalive'

function Out-Line($obj) { ($obj | ConvertTo-Json -Compress -Depth 4) }

# 1. Scheduled tasks whose name or actions match
$taskHits = 0
try {
  $tasks = Get-ScheduledTask -ErrorAction Stop
  foreach ($t in $tasks) {
    $actionText = ''
    foreach ($a in $t.Actions) { $actionText += ' ' + [string]$a.Execute + ' ' + [string]$a.Arguments }
    if (($t.TaskName -match $pattern) -or ($actionText -match $pattern)) {
      $taskHits++
      $info = $null
      try { $info = Get-ScheduledTaskInfo -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction Stop } catch {}
      Out-Line @{ kind = 'scheduled_task'; name = $t.TaskName; folder = $t.TaskPath; state = [string]$t.State;
        last_run = $(if ($info) { [string]$info.LastRunTime } else { $null });
        matched_in = $(if ($t.TaskName -match $pattern) { 'name' } else { 'action' }) }
    }
  }
  Out-Line @{ kind = 'scheduled_task_summary'; ok = $true; matches = $taskHits; scanned = @($tasks).Count }
} catch {
  Out-Line @{ kind = 'scheduled_task_summary'; ok = $false; error = $_.Exception.GetType().Name }
}

# 2. Startup folders (current user + all users): file names only
$startupHits = 0
foreach ($dir in @([Environment]::GetFolderPath('Startup'), [Environment]::GetFolderPath('CommonStartup'))) {
  if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { continue }
  foreach ($f in Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue) {
    $text = ''
    try { if ($f.Length -lt 65536) { $text = [IO.File]::ReadAllText($f.FullName) } } catch {}
    if (($f.Name -match $pattern) -or ($text -match $pattern)) {
      $startupHits++
      Out-Line @{ kind = 'startup_entry'; file = $f.Name; scope = $(if ($dir -eq [Environment]::GetFolderPath('Startup')) { 'user' } else { 'all_users' }) }
    }
  }
}
Out-Line @{ kind = 'startup_summary'; matches = $startupHits }

# 3. Registry Run keys: value names only
$runHits = 0
foreach ($key in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run')) {
  try {
    $props = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
    foreach ($p in $props.PSObject.Properties) {
      if ($p.Name -like 'PS*') { continue }
      if (($p.Name -match $pattern) -or ([string]$p.Value -match $pattern)) {
        $runHits++
        Out-Line @{ kind = 'run_key'; hive = $key.Substring(0,4); value_name = $p.Name }
      }
    }
  } catch {}
}
Out-Line @{ kind = 'run_key_summary'; matches = $runHits }

# 4. Port 47831 listener and node processes running the bridge
$listening = $false
try { $listening = @(Get-NetTCPConnection -LocalPort 47831 -State Listen -ErrorAction Stop).Count -gt 0 } catch {}
$bridgeProcs = 0
try {
  $procs = Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction Stop
  foreach ($p in $procs) { if ([string]$p.CommandLine -match 'dev_agent_bridge') { $bridgeProcs++ } }
} catch {}
Out-Line @{ kind = 'runtime'; port_47831_listening = $listening; bridge_node_processes = $bridgeProcs }

# 5. Tailscale serve :443 present (no hostnames printed)
$ts = Get-Command tailscale -ErrorAction SilentlyContinue
if ($ts) {
  $status = (& tailscale serve status 2>&1 | Out-String)
  Out-Line @{ kind = 'tailscale_serve'; available = $true; points_to_47831 = [bool]($status -match '47831'); has_8443 = [bool]($status -match ':8443'); has_8447 = [bool]($status -match ':8447') }
} else {
  Out-Line @{ kind = 'tailscale_serve'; available = $false }
}
Out-Line @{ kind = 'done'; ok = $true }
