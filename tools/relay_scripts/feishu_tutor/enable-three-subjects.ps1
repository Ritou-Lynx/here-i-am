[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$ErrorActionPreference = 'Stop'
# 脚本轮入口（write）：学习导师启用三科（#83）。
# 1) 用临时配置加上“英语”“数据分析”跑 check，不通过就什么都不改；
# 2) 备份后换上 config.json、学习目录的 AGENTS.md、subjects.md，复制 practice_link.mjs；
# 3) 触发计划任务 FeishuTutor-Daily 试跑一次，只回报日志结论和学习单结构，不贴正文。
# 原生命令的 stderr 经 2>&1 在 PS5.1 里会变成 ErrorRecord，Stop 会直接抛出；运行原生命令时临时用 Continue。
function Out-Step($obj) { [Console]::Out.WriteLine(($obj | ConvertTo-Json -Compress)) }

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$src = Join-Path $repo 'tools\feishu_tutor'
$tool = Join-Path $env:USERPROFILE 'feishu-tutor-tool'
$study = Join-Path $env:USERPROFILE 'feishu-study'
$config = Join-Path $tool 'config.json'
foreach ($p in @($config, (Join-Path $tool 'sync\feishu_sync.mjs'), (Join-Path $study 'AGENTS.md'), (Join-Path $study 'subjects.md'),
                 (Join-Path $src 'STUDY_AGENTS.md'), (Join-Path $src 'examples\subjects-three.md'), (Join-Path $src 'study\practice_link.mjs'))) {
  if (-not (Test-Path -LiteralPath $p)) { Out-Step @{ step = 'precheck'; ok = $false; error = 'missing'; file = (Split-Path $p -Leaf) }; exit 2 }
}
$node = (Get-Command node -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $node) { Out-Step @{ step = 'precheck'; ok = $false; error = 'node_not_found' }; exit 2 }
$pending = @(Get-ChildItem -LiteralPath (Join-Path $study 'state\outbox') -Filter *.json -File -ErrorAction SilentlyContinue).Count
$inflight = @(Get-ChildItem -LiteralPath (Join-Path $study 'state\outbox\inflight') -File -ErrorAction SilentlyContinue).Count
if ($pending -or $inflight) { Out-Step @{ step = 'precheck'; ok = $false; error = 'pending_outbox'; outbox = $pending; inflight = $inflight }; exit 2 }
Out-Step @{ step = 'precheck'; ok = $true }

# 1) 临时配置 + check（JSON 一律用 node 改）
$trial = Join-Path $tool 'config.three-subjects.json'
$js = Join-Path ([IO.Path]::GetTempPath()) ('add-subjects-{0}.js' -f [Guid]::NewGuid().ToString('N'))
[IO.File]::WriteAllText($js, @'
const fs = require('fs');
const [from, to] = process.argv.slice(2);
const c = JSON.parse(fs.readFileSync(from, 'utf8').replace(/^﻿/, ''));
const before = c.subjects.slice();
for (const s of ['英语', '数据分析']) if (!c.subjects.includes(s)) c.subjects.push(s);
fs.writeFileSync(to, JSON.stringify(c, null, 2) + '\n', 'utf8');
console.log(JSON.stringify({ step: 'config_trial', ok: true, before: before.length, after: c.subjects.length }));
'@, [Text.UTF8Encoding]::new($false))
$ErrorActionPreference = 'Continue'
try { & $node $js $config $trial; if ($LASTEXITCODE -ne 0) { throw 'config_trial_failed' } } finally { Remove-Item -LiteralPath $js -Force -ErrorAction SilentlyContinue }
$checkOut = & $node (Join-Path $tool 'sync\feishu_sync.mjs') check --config $trial --state (Join-Path $study 'state') 2>&1 | ForEach-Object { "$_" }
$checkExit = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
if ($checkExit -ne 0) {
  Remove-Item -LiteralPath $trial -Force -ErrorAction SilentlyContinue
  Out-Step @{ step = 'check'; ok = $false; exit = $checkExit; output = (($checkOut | Select-Object -Last 3) -join ' | ') }
  exit 3
}
Out-Step @{ step = 'check'; ok = $true; output = (($checkOut | Select-Object -Last 1) -join '') }

# 2) 备份并替换
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $study ('backup\three-subjects-' + $stamp)
New-Item -ItemType Directory -Path $backup -Force | Out-Null
Copy-Item -LiteralPath $config -Destination (Join-Path $backup 'config.json')
Copy-Item -LiteralPath (Join-Path $study 'AGENTS.md') -Destination (Join-Path $backup 'AGENTS.md')
Copy-Item -LiteralPath (Join-Path $study 'subjects.md') -Destination (Join-Path $backup 'subjects.md')
if (Test-Path -LiteralPath (Join-Path $study 'practice_link.mjs')) { Copy-Item -LiteralPath (Join-Path $study 'practice_link.mjs') -Destination (Join-Path $backup 'practice_link.mjs') }
Move-Item -LiteralPath $trial -Destination $config -Force
Copy-Item -LiteralPath (Join-Path $src 'STUDY_AGENTS.md') -Destination (Join-Path $study 'AGENTS.md') -Force
Copy-Item -LiteralPath (Join-Path $src 'examples\subjects-three.md') -Destination (Join-Path $study 'subjects.md') -Force
Copy-Item -LiteralPath (Join-Path $src 'study\practice_link.mjs') -Destination (Join-Path $study 'practice_link.mjs') -Force
$linkProbe = Join-Path ([IO.Path]::GetTempPath()) ('probe-{0}.txt' -f [Guid]::NewGuid().ToString('N'))
[IO.File]::WriteAllText($linkProbe, "测试 テスト test", [Text.UTF8Encoding]::new($false))
$ErrorActionPreference = 'Continue'
$probe = & $node (Join-Path $study 'practice_link.mjs') $linkProbe 2>&1 | ForEach-Object { "$_" }
Remove-Item -LiteralPath $linkProbe -Force -ErrorAction SilentlyContinue
$ErrorActionPreference = 'Stop'
Out-Step @{ step = 'install'; ok = $true; backup = ('backup\three-subjects-' + $stamp); link_probe = (($probe -join '') -like 'https://chatgpt.com/?q=*') }

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
Out-Step @{ step = 'done'; ok = ($verdict -eq 'daily_done') }
if ($verdict -ne 'daily_done') { exit 6 }
