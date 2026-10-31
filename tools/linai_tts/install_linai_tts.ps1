[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
# 原生命令（python、tailscale）往 stderr 打警告时，PS 5.1 在 Stop 下会直接抛错，所以用 Continue 并显式检查
$ErrorActionPreference = 'Continue'
# 安装/更新林埃英文语音服务为登录自启（幂等，可重复运行）：
#   %LOCALAPPDATA%\HereIAm\linai-tts\  venv\（首次从测速环境复制）、app\（本目录代码的部署副本）、
#   config.json（首次生成随机 token，之后保留）、参考音频、logs\
#   启动文件夹放一个 VBS，登录后用 pythonw 隐藏运行；不用计划任务，不需要管理员。
#   tailscale serve --bg --https=8445 → 127.0.0.1:47870（Tailscale 服务每次开机自动恢复）。
# 输出每行一个 JSON，不含路径、token、域名。卸载见 uninstall_linai_tts.ps1。
function Out-Json($obj) { [Console]::Out.WriteLine(($obj | ConvertTo-Json -Compress -Depth 6)) }

$src = $PSScriptRoot
$root = Join-Path $env:LOCALAPPDATA 'HereIAm\linai-tts'
$venv = Join-Path $root 'venv'
$app = Join-Path $root 'app'
$cfgPath = Join-Path $root 'config.json'
$refPath = Join-Path $root 'linai-ref-v5.wav'
$port = 47870
$httpsPort = 8445
New-Item -ItemType Directory -Force -Path $root, $app, (Join-Path $root 'logs') -ErrorAction Stop | Out-Null

# 测速环境（MSIX 打包的 AI 应用写 AppData\Local 会被重定向到 Packages\<应用>\LocalCache\Local）
$benchCands = @((Join-Path $env:LOCALAPPDATA 'HereIAm\tts-bench'))
$benchCands += @(Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Packages\*\LocalCache\Local\HereIAm\tts-bench') -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
$bench = $benchCands | Where-Object { Test-Path (Join-Path $_ '.venv\Scripts\python.exe') } | Select-Object -First 1

# 1. venv：已有就保留，没有就整份复制测速 venv（免得再下 2.7 GB 的 torch）
$py = Join-Path $venv 'Scripts\python.exe'
$pyw = Join-Path $venv 'Scripts\pythonw.exe'
if (-not (Test-Path $py)) {
    if (-not $bench) { Out-Json @{ step = 'venv'; ok = $false; error = 'no_venv_and_no_bench' }; exit 2 }
    $rc = (Start-Process robocopy -ArgumentList @("`"$bench\.venv`"", "`"$venv`"", '/E', '/NFL', '/NDL', '/NJH', '/NJS', '/NP', '/R:1', '/W:1') -NoNewWindow -Wait -PassThru).ExitCode
    if ($rc -ge 8) { Out-Json @{ step = 'venv'; ok = $false; error = 'robocopy_failed'; code = $rc }; exit 3 }
    Out-Json @{ step = 'venv'; ok = $true; action = 'copied_from_bench' }
} else {
    Out-Json @{ step = 'venv'; ok = $true; action = 'kept' }
}
$check = & $py -c "import torch, chatterbox.tts_turbo; print(torch.__version__, torch.cuda.is_available())" 2>$null
if ($LASTEXITCODE -ne 0) { Out-Json @{ step = 'venv-check'; ok = $false }; exit 4 }
Out-Json @{ step = 'venv-check'; ok = $true; torch = "$check" }

# 2. 停掉正在跑的旧实例（只认 app\linai_tts_server.py）
$running = @(Get-CimInstance Win32_Process -Filter "Name='pythonw.exe' OR Name='python.exe'" | Where-Object { $_.CommandLine -like '*\linai-tts\app\linai_tts_server.py*' })
foreach ($p in $running) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
if ($running.Count) { Start-Sleep -Seconds 2 }
Out-Json @{ step = 'stop-old'; stopped = $running.Count }

# 3. 部署代码副本
Get-ChildItem $src -File | Where-Object { $_.Extension -in '.py', '.txt', '.json', '.md' } | Copy-Item -Destination $app -Force -ErrorAction Stop
Out-Json @{ step = 'app'; files = @(Get-ChildItem $app -File).Count }

# 4. 参考音频与配置（已有则保留，token 不变）
if (-not (Test-Path $refPath)) {
    $benchRef = if ($bench) { Join-Path $bench 'linai-ref-v5.wav' } else { $null }
    if (-not $benchRef -or -not (Test-Path $benchRef)) { Out-Json @{ step = 'reference'; ok = $false; error = 'reference_missing' }; exit 5 }
    Copy-Item $benchRef $refPath -ErrorAction Stop
}
if (-not (Test-Path $cfgPath)) {
    $bytes = New-Object byte[] 32
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $token = -join ($bytes | ForEach-Object { $_.ToString('x2') })
    $cfg = [ordered]@{ token = $token; reference_wav = $refPath; device = 'cuda'; max_chars = 400; queue_timeout_s = 20 }
    [IO.File]::WriteAllText($cfgPath, ($cfg | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    Out-Json @{ step = 'config'; action = 'created' }
} else {
    Out-Json @{ step = 'config'; action = 'kept' }
}

# 5. 登录自启：启动文件夹 VBS，隐藏窗口
$vbsPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'HereIAm_LinaiTts.vbs'
$server = Join-Path $app 'linai_tts_server.py'
$vbs = @'
Set sh = CreateObject("WScript.Shell")
sh.Run """__PYW__"" ""__SERVER__""", 0, False
'@
Set-Content -LiteralPath $vbsPath -Value ($vbs.Replace('__PYW__', $pyw).Replace('__SERVER__', $server)) -Encoding ASCII -ErrorAction Stop
Out-Json @{ step = 'autostart'; ok = $true }

# 6. 现在就启动并等模型加载
& wscript.exe $vbsPath
[Net.WebRequest]::DefaultWebProxy = New-Object Net.WebProxy  # 本机请求不走系统代理
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$health = $null
$t0 = Get-Date
while (((Get-Date) - $t0).TotalSeconds -lt 300) {
    Start-Sleep -Seconds 3
    try { $health = Invoke-RestMethod -Uri "http://127.0.0.1:$port/v1/tts/health" -TimeoutSec 5 } catch { continue }
    if ($health.model_loaded -or $health.last_error) { break }
}
Out-Json @{ step = 'local-health'; seconds = [int]((Get-Date) - $t0).TotalSeconds; health = $health }
if (-not $health -or -not $health.model_loaded) { exit 6 }

# 7. Tailscale HTTPS 入口
$ts = (Get-Command tailscale -ErrorAction SilentlyContinue).Source
if (-not $ts) { $ts = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe' }
if (-not (Test-Path $ts)) { Out-Json @{ step = 'tailscale'; ok = $false; error = 'tailscale_not_found' }; exit 7 }
$serve = & $ts serve status 2>&1 | Out-String
if ($serve -notmatch ":$httpsPort\b") {
    & $ts serve --bg "--https=$httpsPort" "http://127.0.0.1:$port" 2>&1 | Out-Null
    Out-Json @{ step = 'tailscale-serve'; action = 'added'; exit = $LASTEXITCODE }
} else {
    Out-Json @{ step = 'tailscale-serve'; action = 'kept' }
}
$dns = ((& $ts status --json | Out-String | ConvertFrom-Json).Self.DNSName).TrimEnd('.')
$remote = $null
try { $remote = Invoke-RestMethod -Uri "https://${dns}:$httpsPort/v1/tts/health" -TimeoutSec 15 } catch { $remoteError = $_.Exception.GetType().Name }
Out-Json @{ step = 'tailnet-health'; ok = [bool]($remote -and $remote.model_loaded); error = $remoteError }
Out-Json @{ step = 'done'; ok = [bool]($remote -and $remote.model_loaded) }
