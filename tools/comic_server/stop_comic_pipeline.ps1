# 停止漫画共读 pipeline 的两个 node 进程（comic_server + crawler daemon）。
# 静默 / 自启模式下没有窗口可关，用这个脚本停止。
# 按命令行特征精确匹配，不会误杀其它 node 进程。

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$targets = @('comic_server.mjs', 'crawler_manwa.mjs', 'ollama_proxy.mjs')

$procs = Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue |
  Where-Object {
    $cmd = $_.CommandLine
    if (-not $cmd) { return $false }
    $hit = $false
    foreach ($t in $targets) { if ($cmd.Contains($t)) { $hit = $true; break } }
    return $hit
  }

if (-not $procs) {
  Write-Host "没有运行中的漫画 pipeline 进程。" -ForegroundColor DarkGray
  exit 0
}

foreach ($p in $procs) {
  Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
  Write-Host "已停止 node PID=$($p.ProcessId)" -ForegroundColor Green
}