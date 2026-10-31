[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$ErrorActionPreference = 'Stop'

function Out-Json($obj) { [Console]::Out.WriteLine(($obj | ConvertTo-Json -Compress -Depth 6)) }

$bench = Join-Path $env:LOCALAPPDATA 'HereIAm\tts-bench'
$py = Join-Path $bench '.venv\Scripts\python.exe'
$prof = (Resolve-Path (Join-Path $PSScriptRoot '..\..\tts_bench\profile_turbo.py')).Path
$ref = Join-Path $bench 'linai-ref-v5.wav'
if (-not (Test-Path $ref)) { $ref = (Resolve-Path (Join-Path $PSScriptRoot '..\..\tts_bench\linai-ref-v5.wav')).Path }
if (-not (Test-Path $py)) { Out-Json @{ step = 'precheck'; ok = $false; error = 'bench_venv_missing' }; exit 2 }

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

# 只读：不改系统设置，只在测速目录 runs\ 下写测速结果。
Out-Json @{ step = 'power'; active = (powercfg /getactivescheme | Out-String).Trim() }
$a = Invoke-Profile 'A-default' @()
$b = Invoke-Profile 'B-boost' @('--boost')
Out-Json @{ step = 'done'; ok = ($a -and $b) }
