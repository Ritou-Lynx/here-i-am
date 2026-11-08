# WRITE: stop leftover Dev Room bridge and its autostart on this PC.
# 1) back up and remove Startup entries matching the bridge
# 2) stop node processes running dev_agent_bridge
# 3) turn off Tailscale serve https:443 only if it points to 47831
# Prints JSON lines only. Never prints absolute paths, user names or hosts.
$ErrorActionPreference = 'Continue'
$pattern = 'dev_agent_bridge|devroom|start_bridge|start-dev-bridge|start_usb_bridge|47831'
function Out-Line($obj) { ($obj | ConvertTo-Json -Compress -Depth 4) }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $env:LOCALAPPDATA ('here-i-am-devroom-backup\' + $stamp)

# 1. Startup entries (user scope + all users)
$removed = 0; $failed = 0
foreach ($dir in @([Environment]::GetFolderPath('Startup'), [Environment]::GetFolderPath('CommonStartup'))) {
  if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { continue }
  foreach ($f in Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue) {
    $text = ''
    try { if ($f.Length -lt 65536) { $text = [IO.File]::ReadAllText($f.FullName) } } catch {}
    if (($f.Name -match $pattern) -or ($text -match $pattern)) {
      try {
        New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
        Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $backupRoot $f.Name) -Force -ErrorAction Stop
        Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
        $removed++
        Out-Line @{ kind = 'startup_removed'; file = $f.Name; backed_up = $true }
      } catch {
        $failed++
        Out-Line @{ kind = 'startup_remove_failed'; file = $f.Name; error = $_.Exception.GetType().Name }
      }
    }
  }
}
Out-Line @{ kind = 'startup_summary'; removed = $removed; failed = $failed; backup_folder = $(if ($removed -gt 0) { 'LOCALAPPDATA\here-i-am-devroom-backup\' + $stamp } else { $null }) }

# 2. Stop bridge node processes
$stopped = 0; $stopFailed = 0
try {
  $procs = Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction Stop
  foreach ($p in $procs) {
    if ([string]$p.CommandLine -match 'dev_agent_bridge') {
      try { Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop; $stopped++ } catch { $stopFailed++ }
    }
  }
} catch { $stopFailed++ }
Start-Sleep -Seconds 3
$listening = $false
try { $listening = @(Get-NetTCPConnection -LocalPort 47831 -State Listen -ErrorAction Stop).Count -gt 0 } catch {}
Out-Line @{ kind = 'bridge_stop'; stopped = $stopped; failed = $stopFailed; port_47831_listening_after = $listening }

# 3. Tailscale serve https:443 -> 47831
$ts = Get-Command tailscale -ErrorAction SilentlyContinue
if ($ts) {
  $before = (& tailscale serve status 2>&1 | Out-String)
  $turnedOff = $false
  if ($before -match '47831') {
    & tailscale serve --https=443 off 2>&1 | Out-Null
    $turnedOff = ($LASTEXITCODE -eq 0)
  }
  $after = (& tailscale serve status 2>&1 | Out-String)
  Out-Line @{ kind = 'tailscale_serve'; pointed_to_47831_before = [bool]($before -match '47831'); turned_off_443 = $turnedOff;
    points_to_47831_after = [bool]($after -match '47831'); has_8443_after = [bool]($after -match ':8443'); has_8447_after = [bool]($after -match ':8447') }
} else {
  Out-Line @{ kind = 'tailscale_serve'; available = $false }
}
Out-Line @{ kind = 'done'; ok = $true }
