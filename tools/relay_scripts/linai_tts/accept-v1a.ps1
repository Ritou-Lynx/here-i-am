[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$ErrorActionPreference = 'Stop'
# 只读验收：用已有的测速 venv 临时起一次 linai_tts 服务（127.0.0.1:47871），发几句英文，回报耗时后关掉。
# 临时配置和 token 放在 TEMP，结束时删除；不安装任何东西，不改计划任务和系统设置。
function Out-Json($obj) { [Console]::Out.WriteLine(($obj | ConvertTo-Json -Compress -Depth 6)) }

$cands = @()
if ($env:LOCALAPPDATA) {
    $cands += (Join-Path $env:LOCALAPPDATA 'HereIAm\tts-bench')
    # MSIX 打包的桌面 AI 应用写 AppData\Local 会被重定向到 Packages\<应用>\LocalCache\Local
    $cands += @(Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Packages\*\LocalCache\Local\HereIAm\tts-bench') -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
}
$bench = $cands | Where-Object { Test-Path (Join-Path $_ '.venv\Scripts\python.exe') } | Select-Object -First 1
if (-not $bench) { Out-Json @{ step = 'precheck'; ok = $false; error = 'bench_venv_missing' }; exit 2 }
$py = Join-Path $bench '.venv\Scripts\python.exe'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$server = Join-Path $root 'tools\linai_tts\linai_tts_server.py'
$ref = Join-Path $bench 'linai-ref-v5.wav'
if (-not (Test-Path $ref)) { Out-Json @{ step = 'precheck'; ok = $false; error = 'reference_missing' }; exit 2 }

$work = Join-Path $env:TEMP ("linai-tts-accept-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $work | Out-Null
$bytes = New-Object byte[] 24
[Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$token = -join ($bytes | ForEach-Object { $_.ToString('x2') })
$cfgPath = Join-Path $work 'config.json'
[IO.File]::WriteAllText($cfgPath, (@{ token = $token; reference_wav = $ref; device = 'cuda' } | ConvertTo-Json), [Text.UTF8Encoding]::new($false))

$port = 47871
# 本机请求不走系统代理（之前本机 HTTP 请求经代理会超时）
[Net.WebRequest]::DefaultWebProxy = New-Object Net.WebProxy
$env:LINAI_TTS_CONFIG = $cfgPath
$env:LINAI_TTS_PORT = "$port"
$env:PYTHONIOENCODING = 'utf-8'
$proc = Start-Process -FilePath $py -ArgumentList @("`"$server`"") -WorkingDirectory $work -NoNewWindow -PassThru `
    -RedirectStandardOutput (Join-Path $work 'stdout.log') -RedirectStandardError (Join-Path $work 'stderr.log')
$ok = $false
try {
    $health = $null
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt 240) {
        Start-Sleep -Seconds 3
        if ($proc.HasExited) { break }
        try { $health = Invoke-RestMethod -Uri "http://127.0.0.1:$port/v1/tts/health" -TimeoutSec 5 } catch { continue }
        if ($health.model_loaded -or $health.last_error) { break }
    }
    Out-Json @{ step = 'health'; loadSeconds = [int]((Get-Date) - $t0).TotalSeconds; health = $health; exited = $proc.HasExited }
    if (-not $health -or -not $health.model_loaded) {
        $tail = Get-Content (Join-Path $work 'stderr.log') -Tail 6 -ErrorAction SilentlyContinue | ForEach-Object { $_ -replace [regex]::Escape($env:USERPROFILE), '<HOME>' }
        Out-Json @{ step = 'load'; ok = $false; stderrTail = ($tail -join ' | ') }
        exit 3
    }
    $lines = @(
        'Hey.',
        'Mm, I''m here.',
        'Aww... you didn''t have to. [chuckle] It''s so cute.',
        'Come here. You did so well today, and I''m really proud of you. Get some rest, okay?'
    )
    $i = 0
    foreach ($text in $lines) {
        $i++
        $body = [Text.Encoding]::UTF8.GetBytes((@{ text = $text; request_id = "accept-$i" } | ConvertTo-Json -Compress))
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:$port/v1/tts/speak" -Method Post -Body $body -ContentType 'application/json' `
            -Headers @{ Authorization = "Bearer $token" } -UseBasicParsing -TimeoutSec 60
        $sw.Stop()
        $gen = [int]$r.Headers['X-Gen-Ms']; $aud = [int]$r.Headers['X-Audio-Ms']
        Out-Json ([ordered]@{ step = 'speak'; n = $i; status = [int]$r.StatusCode; gen_ms = $gen; audio_ms = $aud
            rtf = $(if ($aud) { [math]::Round($gen / $aud, 2) } else { $null }); roundtrip_ms = $sw.ElapsedMilliseconds; bytes = $r.RawContentLength })
    }
    $bad = 0
    try { Invoke-WebRequest -Uri "http://127.0.0.1:$port/v1/tts/speak" -Method Post -Body '{"text":"Hi."}' -ContentType 'application/json' -UseBasicParsing -TimeoutSec 10 | Out-Null }
    catch { $bad = [int]$_.Exception.Response.StatusCode }
    Out-Json @{ step = 'no-token'; status = $bad }
    $ok = ($bad -eq 401)
} finally {
    if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 1
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
    Out-Json @{ step = 'cleanup'; tempRemoved = -not (Test-Path $work) }
}
Out-Json @{ step = 'done'; ok = $ok }
