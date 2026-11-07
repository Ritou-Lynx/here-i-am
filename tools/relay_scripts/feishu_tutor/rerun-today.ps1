[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$ErrorActionPreference = 'Stop'
# 脚本轮入口（write）：今天的学习单是三科启用前出的旧格式。把 today.md 挪到备份目录（不删），
# 再触发一次 FeishuTutor-Daily，让导师按新规则重出三科学习单；只回报结构和计数，不贴正文。
function Out-Step($obj) { [Console]::Out.WriteLine(($obj | ConvertTo-Json -Compress)) }
$study = Join-Path $env:USERPROFILE 'feishu-study'
foreach ($p in @((Join-Path $study 'AGENTS.md'), (Join-Path $study 'practice_link.mjs'))) {
  if (-not (Test-Path -LiteralPath $p)) { Out-Step @{ step = 'precheck'; ok = $false; error = 'missing'; file = (Split-Path $p -Leaf) }; exit 2 }
}
if (-not (Select-String -LiteralPath (Join-Path $study 'AGENTS.md') -SimpleMatch 'practice_link.mjs' -Quiet)) { Out-Step @{ step = 'precheck'; ok = $false; error = 'agents_not_updated' }; exit 2 }
$pending = @(Get-ChildItem -LiteralPath (Join-Path $study 'state\outbox') -Filter *.json -File -ErrorAction SilentlyContinue).Count
$inflight = @(Get-ChildItem -LiteralPath (Join-Path $study 'state\outbox\inflight') -File -ErrorAction SilentlyContinue).Count
if ($pending -or $inflight) { Out-Step @{ step = 'precheck'; ok = $false; error = 'pending_outbox'; outbox = $pending; inflight = $inflight }; exit 2 }
$today = Join-Path $study 'today.md'
if (Test-Path -LiteralPath $today) {
  $backup = Join-Path $study ('backup\rerun-today-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
  New-Item -ItemType Directory -Path $backup -Force | Out-Null
  Move-Item -LiteralPath $today -Destination (Join-Path $backup 'today.md')
}
Out-Step @{ step = 'precheck'; ok = $true }

# 3) 试跑每日任务
$task = Get-ScheduledTask -TaskName 'FeishuTutor-Daily' -ErrorAction SilentlyContinue
if (-not $task) { Out-Step @{ step = 'trial_run'; ok = $false; error = 'task_not_found' }; exit 4 }
$started = Get-Date
Start-ScheduledTask -TaskName 'FeishuTutor-Daily'
$logs = Join-Path $study 'logs'
$verdict = $null; $log = $null
$deadline = $started.AddMinutes(16)
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 15
  $log = Get-ChildItem -LiteralPath $logs -Filter 'daily-*.log' -File | Where-Object { $_.LastWriteTime -ge $started.AddSeconds(-5) } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($log) {
    $last = (Get-Content -LiteralPath $log.FullName -Encoding UTF8 | Where-Object { $_.Trim() } | Select-Object -Last 1)
    if ($last) { $last = $last.Trim([char]0xFEFF).Trim() }
    if ($last -eq 'daily_done' -or $last -match '_failed') { $verdict = $last; break }
  }
}
if (-not $verdict) { Out-Step @{ step = 'trial_run'; ok = $false; error = 'timeout_16min'; last = $last }; exit 5 }
$steps = @(Get-Content -LiteralPath $log.FullName -Encoding UTF8 | ForEach-Object { $_.Trim([char]0xFEFF).Trim() } | Where-Object { $_ })
Out-Step @{ step = 'trial_run'; ok = ($verdict -eq 'daily_done'); verdict = $verdict; log_steps = ($steps -join ',') ; minutes = [math]::Round(((Get-Date) - $started).TotalMinutes, 1) }

# 学习单结构（只数标题和链接，不贴正文）
$today = Join-Path $study 'today.md'
if (Test-Path -LiteralPath $today) {
  $lines = @(Get-Content -LiteralPath $today -Encoding UTF8)
  $title = ($lines | Select-Object -First 1)
  $sections = @($lines | Where-Object { $_ -match '^## ' } | ForEach-Object { ($_ -replace '^## ', '') -replace '（.*$', '' })
  $links = @($lines | Where-Object { $_ -match 'https://chatgpt\.com/\?q=' }).Count
  $quoted = @($lines | Where-Object { $_ -match '^> ' }).Count
  Out-Step @{ step = 'today'; title_ok = ($title -match ('^# 学习单 ' + (Get-Date -Format 'yyyy-MM-dd'))); sections = ($sections -join '/'); practice_links = $links; quote_lines = $quoted; lines = $lines.Count }
} else { Out-Step @{ step = 'today'; ok = $false; error = 'today_missing' } }
$report = Join-Path $study 'state\push-report.json'
if (Test-Path -LiteralPath $report) {
  $r = Get-Content -LiteralPath $report -Raw -Encoding UTF8 | ConvertFrom-Json
  $kinds = @($r.results | ForEach-Object { if ($_.file -match '-(ledger_update|ledger_create|practice_create|inbox_mark|doc_write)-') { "$($Matches[1]):$($_.status)" } else { "other:$($_.status)" } } | Group-Object | ForEach-Object { "$($_.Name)x$($_.Count)" })
  Out-Step @{ step = 'push_report'; status = $r.status; error = $r.error; actions = ($kinds -join ',') }
}
$cl = Get-ChildItem -LiteralPath $logs -Filter 'codex-last-*.md' -File | Where-Object { $_.LastWriteTime -ge $started.AddSeconds(-5) } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($cl) { Out-Step @{ step = 'codex_last'; lines = @(Get-Content -LiteralPath $cl.FullName -Encoding UTF8).Count; mentions_link_failure = [bool](Select-String -LiteralPath $cl.FullName -Pattern 'practice_link|prompt_too_long|链接' -Quiet) } }
Out-Step @{ step = 'done'; ok = ($verdict -eq 'daily_done') }
if ($verdict -ne 'daily_done') { exit 6 }
