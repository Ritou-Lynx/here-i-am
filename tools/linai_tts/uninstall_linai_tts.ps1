[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
# 原生命令（python、tailscale）往 stderr 打警告时，PS 5.1 在 Stop 下会直接抛错，所以用 Continue 并显式检查
$ErrorActionPreference = 'Continue'
# 停止林埃英文语音服务并取消登录自启、关掉 Tailscale :8445。保留 venv、配置、日志（删掉 %LOCALAPPDATA%\HereIAm\linai-tts 即彻底清除）。
function Out-Json($obj) { [Console]::Out.WriteLine(($obj | ConvertTo-Json -Compress -Depth 6)) }
$vbsPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'HereIAm_LinaiTts.vbs'
Remove-Item -LiteralPath $vbsPath -Force -ErrorAction SilentlyContinue
$running = @(Get-CimInstance Win32_Process -Filter "Name='pythonw.exe' OR Name='python.exe'" | Where-Object { $_.CommandLine -like '*\linai-tts\app\linai_tts_server.py*' })
foreach ($p in $running) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
$ts = (Get-Command tailscale -ErrorAction SilentlyContinue).Source
if (-not $ts) { $ts = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe' }
if (Test-Path $ts) { & $ts serve --https=8445 off 2>&1 | Out-Null }
Out-Json @{ step = 'done'; autostartRemoved = -not (Test-Path $vbsPath); stopped = $running.Count }
