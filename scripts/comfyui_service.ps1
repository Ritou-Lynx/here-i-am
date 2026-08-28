#requires -version 5
<#
  ComfyUI 自启 + 崩溃重启包装脚本.

  计划任务 "ComfyUI Tailscale Service" 在登录时触发本脚本; 脚本常驻循环,
  ComfyUI 退出就重新拉起, 并在 10 分钟内退出超过 5 次时退避 5 分钟, 避免
  驱动损坏 / 端口被占时无限重启刷满日志.

  只绑定 Tailscale 接口 (不监听 0.0.0.0): ComfyUI 没有任何认证, 0.0.0.0 会
  把生图服务暴露给笔记本连接的任何 Wi-Fi 局域网. 用 --listen <tailscale-ip>
  后, Tailscale 断开时 ComfyUI 会连带失效——这是有意的安全取舍.

  用法 (手动测试):
    powershell -File scripts\comfyui_service.ps1

  注册为登录计划任务:
    见同目录其它脚本或用任务计划程序, Action 指向本文件, Trigger = AtLogOn.

  可调参数见下方 $ComfyRoot / $Tailscale / $Port.
#>

# --- 可调配置 (按机器改这里) ---------------------------------------------------
$ComfyRoot = 'D:\ComfyUI\ComfyUI_windows_portable'
$Tailscale = 'C:\Program Files\Tailscale\tailscale.exe'
$Port      = 8188
# -------------------------------------------------------------------------------

$Python = Join-Path $ComfyRoot 'python_embeded\python.exe'
$MainPy = Join-Path $ComfyRoot 'ComfyUI\main.py'
$LogDir = Join-Path $ComfyRoot 'logs'
$Log    = Join-Path $LogDir 'service.log'
$OutLog = Join-Path $LogDir 'comfyui_stdout.log'
$ErrLog = Join-Path $LogDir 'comfyui_stderr.log'

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Write-Log($msg) {
  $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
  try { Add-Content -Path $Log -Value $line -Encoding UTF8 } catch { }
}

function Reset-LogIfLarge($path, $maxMb) {
  if ((Test-Path $path) -and ((Get-Item $path).Length -gt ($maxMb * 1MB))) {
    Move-Item -Path $path -Destination "$path.old" -Force -ErrorAction SilentlyContinue
  }
}

# Returns the Tailscale IPv4 address once it is actually bound to a local adapter.
function Wait-TailscaleIp($timeoutSec) {
  $deadline = (Get-Date).AddSeconds($timeoutSec)
  while ((Get-Date) -lt $deadline) {
    if (Test-Path $Tailscale) {
      $ip = $null
      try { $ip = (& $Tailscale ip -4 2>$null | Select-Object -First 1) } catch { }
      if ($ip -and ($ip.Trim() -match '^\d{1,3}(\.\d{1,3}){3}$')) {
        $ip = $ip.Trim()
        $bound = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                 Where-Object { $_.IPAddress -eq $ip }
        if ($bound) { return $ip }
      }
    }
    Start-Sleep -Seconds 5
  }
  return $null
}

Write-Log 'service wrapper started'
$recentExits = New-Object System.Collections.Generic.Queue[datetime]

while ($true) {
  Reset-LogIfLarge $Log 5
  Reset-LogIfLarge $OutLog 20
  Reset-LogIfLarge $ErrLog 20

  # Bind only to Tailscale: ComfyUI has no auth, so 0.0.0.0 would expose it to
  # every network this laptop joins.
  $ip = Wait-TailscaleIp 300
  if (-not $ip) {
    Write-Log 'no Tailscale IPv4 bound after 300s; retrying in 60s'
    Start-Sleep -Seconds 60
    continue
  }

  Write-Log "starting ComfyUI on ${ip}:${Port}"
  $args = @('-s', $MainPy, '--windows-standalone-build', '--listen', $ip, '--port', "$Port")
  try {
    $proc = Start-Process -FilePath $Python -ArgumentList $args `
      -WorkingDirectory $ComfyRoot -NoNewWindow -PassThru `
      -RedirectStandardOutput $OutLog -RedirectStandardError $ErrLog
  } catch {
    Write-Log "failed to launch: $($_.Exception.Message)"
    Start-Sleep -Seconds 60
    continue
  }

  $proc.WaitForExit()
  Write-Log "ComfyUI exited with code $($proc.ExitCode)"

  # Crash-loop backoff: more than 5 exits inside 10 minutes means something is
  # broken (bad driver, port taken, corrupt install) — stop hammering it.
  $now = Get-Date
  $recentExits.Enqueue($now)
  while ($recentExits.Count -gt 0 -and ($now - $recentExits.Peek()).TotalMinutes -gt 10) {
    [void]$recentExits.Dequeue()
  }
  if ($recentExits.Count -gt 5) {
    Write-Log 'more than 5 exits in 10 min; backing off for 5 min (check comfyui_stderr.log)'
    Start-Sleep -Seconds 300
    $recentExits.Clear()
  } else {
    Start-Sleep -Seconds 5
  }
}