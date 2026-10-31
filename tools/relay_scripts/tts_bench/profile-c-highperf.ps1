[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$ErrorActionPreference = 'Stop'

function Out-Json($obj) { [Console]::Out.WriteLine(($obj | ConvertTo-Json -Compress -Depth 6)) }

$cands = @()
if ($env:LOCALAPPDATA) { $cands += (Join-Path $env:LOCALAPPDATA 'HereIAm\tts-bench') }
if ($env:USERPROFILE) { $cands += (Join-Path $env:USERPROFILE 'AppData\Local\HereIAm\tts-bench') }
$cands += @(Get-ChildItem 'C:\Users\*\AppData\Local\HereIAm\tts-bench' -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
# MSIX 打包的桌面 AI 应用写 AppData\Local 会被重定向到 Packages\<应用>\LocalCache\Local
if ($env:LOCALAPPDATA) { $cands += @(Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Packages\*\LocalCache\Local\HereIAm\tts-bench') -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) }
$bench = $cands | Where-Object { Test-Path (Join-Path $_ '.venv\Scripts\python.exe') } | Select-Object -First 1
if ($bench) { Out-Json @{ step = 'bench-found'; where = $(if ($bench -like '*\Packages\*\LocalCache\*') { 'msix-localcache' } else { 'default' }) } }
if (-not $bench) {
    # 默认位置没有：在用户目录和各固定盘里浅层查找名为 tts-bench 的目录
    $roots = @()
    if ($env:USERPROFILE) { $roots += @{ path = $env:USERPROFILE; depth = 5 } }
    $roots += @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object { @{ path = $_.DeviceID + '\'; depth = 3 } })
    foreach ($r in $roots) {
        $found = Get-ChildItem $r.path -Directory -Recurse -Depth $r.depth -Filter 'tts-bench' -ErrorAction SilentlyContinue |
            Where-Object { Test-Path (Join-Path $_.FullName '.venv\Scripts\python.exe') } | Select-Object -First 1
        if ($found) { $bench = $found.FullName; break }
    }
    if (-not $bench) {
        # 再找任何装了 chatterbox 的 venv：...\Lib\site-packages\chatterbox\tts_turbo.py → venv 根 → 其父目录当测速目录
        foreach ($r in $roots) {
            $hit = Get-ChildItem $r.path -File -Recurse -Depth ($r.depth + 5) -Filter 'tts_turbo.py' -ErrorAction SilentlyContinue |
                Where-Object { $_.DirectoryName -like '*\Lib\site-packages\chatterbox' } | Select-Object -First 1
            if ($hit) {
                $venv = $hit.Directory.Parent.Parent.Parent.FullName
                if (Test-Path (Join-Path $venv 'Scripts\python.exe')) { $bench = Split-Path $venv -Parent; $venvName = Split-Path $venv -Leaf; break }
            }
        }
    }
    if ($bench) {
        $where = if ($env:USERPROFILE -and $bench.StartsWith($env:USERPROFILE)) { 'home' } else { 'drive ' + $bench.Substring(0, 2) }
        Out-Json @{ step = 'bench-found'; where = $where; venv = $venvName }
    }
}
if (-not $bench) {
    $hia = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'HereIAm' } else { $null }
    $kids = if ($hia -and (Test-Path $hia)) { @(Get-ChildItem $hia -Directory | ForEach-Object { $_.Name }) } else { @() }
    $tb = Join-Path $hia 'tts-bench'
    $tbKids = if ($hia -and (Test-Path $tb)) { @(Get-ChildItem $tb -Force | ForEach-Object { $_.Name }) } else { @() }
    Out-Json @{ step = 'precheck'; ok = $false; error = 'bench_venv_missing'; isSystem = ($env:USERNAME -eq 'SYSTEM' -or $env:USERNAME -like '*$'); localAppDataSet = [bool]$env:LOCALAPPDATA
        hereIAmDirs = ($kids -join ','); ttsBenchEntries = ($tbKids -join ','); candidates = $cands.Count }
    exit 2
}
if (-not $venvName) { $venvName = '.venv' }
$py = Join-Path $bench "$venvName\Scripts\python.exe"
$prof = (Resolve-Path (Join-Path $PSScriptRoot '..\..\tts_bench\profile_turbo.py')).Path
$ref = Join-Path $bench 'linai-ref-v5.wav'
if (-not (Test-Path $ref)) { $ref = (Resolve-Path (Join-Path $PSScriptRoot '..\..\tts_bench\linai-ref-v5.wav')).Path }

$busy = Get-CimInstance Win32_Process -Filter "Name='python.exe'" | Where-Object { $_.CommandLine -like '*profile_turbo.py*' }
if ($busy) { Out-Json @{ step = 'precheck'; ok = $false; error = 'another_profile_run_in_progress'; count = @($busy).Count }; exit 3 }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

function Invoke-Profile($label, [string[]]$extra) {
    $dir = Join-Path $bench "runs\$stamp-$label"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $argList = @("`"$prof`"", '--ref', "`"$ref`"", '--only-baseline') + $extra
    $env:PYTHONIOENCODING = 'utf-8'
    $p = Start-Process -FilePath $py -ArgumentList $argList -WorkingDirectory $dir -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput (Join-Path $dir 'stdout.log') -RedirectStandardError (Join-Path $dir 'stderr.log')
    $json = Join-Path $dir 'profile.json'
    if ($p.ExitCode -ne 0 -or -not (Test-Path $json)) {
        $tail = Get-Content (Join-Path $dir 'stderr.log') -Tail 8 -ErrorAction SilentlyContinue | ForEach-Object { $_ -replace [regex]::Escape($env:USERPROFILE), '<HOME>' }
        Out-Json @{ step = $label; ok = $false; exitCode = $p.ExitCode; stderrTail = ($tail -join ' | ') }
        return $false
    }
    $r = Get-Content $json -Raw -Encoding UTF8 | ConvertFrom-Json
    Out-Json @{ step = "$label-env"; cpu = $r.env.cpu; power = $r.env.power_scheme; ac = $r.env.on_ac_power; gpuMem = $r.env.gpu_mem_used_total; boost = $r.boost; load_s = $r.load_s }
    foreach ($row in $r.rows) {
        Out-Json ([ordered]@{ step = $label; s = $row.sentence; rep = $row.rep; rtf = $row.rtf; audio_s = $row.audio_s
            t3_ms_tok = $row.t3_ms_per_token; s3gen = $row.s3gen; gpu_util = $row.gpu.util_avg; gpu_mhz = $row.gpu.sm_clock_avg
            gpu_w = $row.gpu.power_avg_w; cpu_perf = $row.gpu.cpu_perf_pct_avg; cpu_util = $row.gpu.cpu_utility_pct_avg })
    }
    return $true
}

# 会改系统设置：临时切到“高性能”电源方案，跑完无论成败都恢复原方案。
$orig = [regex]::Match((powercfg /getactivescheme | Out-String), '[0-9a-fA-F-]{36}').Value
Out-Json @{ step = 'power-before'; guid = $orig }
$ok = $false
try {
    powercfg /setactive SCHEME_MIN | Out-Null
    if ($LASTEXITCODE -ne 0) { Out-Json @{ step = 'power-switch'; ok = $false }; exit 4 }
    Out-Json @{ step = 'power-switch'; active = (powercfg /getactivescheme | Out-String).Trim() }
    $ok = Invoke-Profile 'C-highperf-boost' @('--boost')
} finally {
    if ($orig) { powercfg /setactive $orig | Out-Null }
    $now = [regex]::Match((powercfg /getactivescheme | Out-String), '[0-9a-fA-F-]{36}').Value
    Out-Json @{ step = 'power-restored'; ok = ($now -eq $orig); guid = $now }
}
Out-Json @{ step = 'done'; ok = $ok }
