# One-click launcher for the comic co-reading pipeline (Windows).
#
# Starts TWO node processes that must keep running for "auto-crawl your
# watches" to work:
#   1) comic_server.mjs   — HTTP API the phone app talks to (port 47840).
#   2) crawler_manwa.mjs  — Playwright crawler in DAEMON mode: every
#                           <interval> it re-reads watches.json and crawls
#                           any new chapters of the manga you follow.
#
# Both reuse the login profile from `node probe_manwa.mjs` (you log in once,
# manually). The crawler sees exactly what your account tier sees.
#
# Usage:
#   powershell -File tools\comic_server\start_comic_pipeline.ps1
#   powershell -File tools\comic_server\start_comic_pipeline.ps1 -Interval 60
#   powershell -File tools\comic_server\start_comic_pipeline.ps1 -Silent   # hide node windows (autostart)
#
# Tailscale exposure is a ONE-TIME background config (the Tailscale system
# service restores it on every boot). Plain HTTP on the tailnet (tunnel is
# already encrypted; also avoids the phone rejecting Tailscale's serve cert):
#   tailscale serve --bg --http=8443 http://127.0.0.1:47840   # comic server
#   tailscale serve --bg --http=8081 http://127.0.0.1:11435   # ollama (via Host-rewriting proxy)
# Phone app:
#   漫画书架 服务地址 -> http://host.example.invalid:8443
#   识图模型 Base URL -> http://host.example.invalid:8081/v1
#
# Autostart on login: run install_comic_autostart.ps1 once (Task Scheduler).
# Stop a running (esp. silent) pipeline: stop_comic_pipeline.ps1.

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $here

# Merge the user-level PATH so `node` resolves in non-interactive contexts
# (Task Scheduler / logon). Without this a login-triggered launch can fail
# with "node not found" because the Node dir / %APPDATA%\npm live only on the
# user PATH, not the logon session PATH. (Same trick as start_bridge.ps1.)
$userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
if ($userPath) { $env:PATH = $env:PATH + ';' + $userPath }

$interval = 1440
$silent = $false
for ($i = 0; $i -lt $args.Count; $i++) {
  if ($args[$i] -eq '-Interval' -and $i + 1 -lt $args.Count) {
    $interval = [int]$args[$i + 1]
  } elseif ($args[$i] -eq '-Silent') {
    $silent = $true
  }
}
if ($interval -ge 1440 -and $interval % 1440 -eq 0) {
  $intervalLabel = "每 $([int]($interval / 1440)) 天"
} elseif ($interval -ge 60 -and $interval % 60 -eq 0) {
  $intervalLabel = "每 $([int]($interval / 60)) 小时"
} else {
  $intervalLabel = "每 $interval 分钟"
}
$winStyle = if ($silent) { 'Hidden' } else { 'Normal' }

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  Write-Host "[!] 没找到 node，请先安装 Node.js。" -ForegroundColor Red
  exit 1
}
if (-not (Test-Path (Join-Path $here 'node_modules'))) {
  Write-Host "[*] 首次运行，安装依赖 (playwright)…" -ForegroundColor Yellow
  & npm install
  & npx playwright install chromium
}
if (-not (Test-Path (Join-Path $here '.manwa_profile'))) {
  Write-Host "[!] 没找到登录 profile。请先在弹出的浏览器里登录一次：" -ForegroundColor Yellow
  Write-Host "    node probe_manwa.mjs" -ForegroundColor Yellow
  Write-Host "    登录看到书架后回终端按回车，然后再跑本脚本。" -ForegroundColor Yellow
  exit 1
}

Write-Host ""
Write-Host "启动 comic_server (端口 47840)…" -ForegroundColor Cyan
$svr = Start-Process -FilePath node -ArgumentList 'comic_server.mjs' -WorkingDirectory $here -WindowStyle $winStyle -PassThru

Write-Host "启动 ollama_proxy (127.0.0.1:11435, 改写 Host 供 Tailscale 识图)…" -ForegroundColor Cyan
$prox = Start-Process -FilePath node -ArgumentList 'ollama_proxy.mjs' -WorkingDirectory $here -WindowStyle $winStyle -PassThru

Write-Host "启动 crawler 守护模式 ($intervalLabel 检查一次更新)…" -ForegroundColor Cyan
$crawl = Start-Process -FilePath node `
  -ArgumentList @('crawler_manwa.mjs', '--watches', '--daemon', '--interval', "$interval") `
  -WorkingDirectory $here -WindowStyle $winStyle -PassThru

Write-Host ""
Write-Host "已启动：comic_server PID=$($svr.Id)   crawler PID=$($crawl.Id)" -ForegroundColor Green
if ($silent) {
  Write-Host "静默模式：node 窗口已隐藏。停止请用 stop_comic_pipeline.ps1 或任务管理器结束 node。" -ForegroundColor DarkGray
} else {
  Write-Host "两个 node 窗口保持打开 = 持续运行；关掉窗口 = 停止。" -ForegroundColor DarkGray
}
Write-Host ""
Write-Host "手机 App 填这两个地址（都是 http，不是 https）：" -ForegroundColor Cyan
Write-Host "  漫画书架 服务地址 : http://host.example.invalid:8443" -ForegroundColor White
Write-Host "  识图模型 Base URL : http://host.example.invalid:8081/v1" -ForegroundColor White
Write-Host "  （若报找不到主机，把 host.example.invalid 换成 192.0.2.1）" -ForegroundColor DarkGray
Write-Host ""