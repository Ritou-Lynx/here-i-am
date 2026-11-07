[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
# Gemini 连接排查（只读，脚本轮 mode=read）：读现役 MCP 的诊断日志（YYYY-MM-DD.jsonl，UTC 日期），
# 看 Gemini 授权之后哪一步失败（/token、/mcp 的状态码与 RPC 结果）。
# 不改任何文件、不发 HTTP、不碰任务。输出每行一个 JSON，只含固定标签字段：
# 不输出路径、域名、令牌、client_id、origin、callback 原文。
$ErrorActionPreference = 'Stop'
function Out-Row($o) { Write-Output ($o | ConvertTo-Json -Compress -Depth 4) }
if ($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5) { Out-Row @{ step = 'host'; ok = $false; detail = 'host_not_51' }; exit 1 }

$TaskName = 'HereIAm-iCoreSchema6-hr1-heart-20261105'
$Since = [DateTimeOffset]::Parse('2026-11-05T15:00:00Z')
$Days = @('2026-11-05', '2026-11-06')
$Keep = @('timestamp', 'event', 'method', 'path', 'status', 'ua_family', 'callback_class', 'callback_count', 'gemini_kept_count', 'rpc_method', 'tool', 'outcome', 'error_code')

# 1. 现役任务与登录配置（照 Get-Schema6LoginBinding 拆参数：参数名也可能带引号）
$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $task) { Out-Row @{ step = 'task'; ok = $false; detail = 'task_missing' }; exit 1 }
$tokens = @()
foreach ($m in [regex]::Matches([string]$task.Actions[0].Arguments, '"([^"]*)"|(\S+)')) {
  if ($m.Groups[1].Success) { $tokens += $m.Groups[1].Value } else { $tokens += $m.Groups[2].Value }
}
$loginPath = $null
for ($i = 0; $i -lt ($tokens.Count - 1); $i++) { if ($tokens[$i] -match '^-(Login)?ConfigurationPath$') { $loginPath = $tokens[$i + 1] } }
if (-not $loginPath) { Out-Row @{ step = 'task'; ok = $false; detail = 'login_argument_missing' }; exit 1 }
$login = [IO.File]::ReadAllText($loginPath) | ConvertFrom-Json
Out-Row @{ step = 'task'; ok = $true; detail = [string]$task.State }

# 2. 找诊断日志目录：先看运行中 MCP 进程的 --log-dir，再看配置里含 log 的路径字段，最后在状态目录下找日期 jsonl
$logDir = $null; $how = $null
try {
  foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction Stop)) {
    $cl = [string]$p.CommandLine
    if ($cl -notmatch 'server\.mjs') { continue }
    $m = [regex]::Match($cl, '--log-dir(?:=|\s+)(?:"([^"]+)"|(\S+))')
    if ($m.Success) { $logDir = if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }; $how = 'process_argument'; break }
  }
} catch { }

$roots = New-Object System.Collections.Generic.List[string]
function Add-PathFields($obj, [int]$depth) {
  if ($null -eq $obj -or $depth -gt 4) { return }
  foreach ($prop in @($obj.PSObject.Properties)) {
    $v = $prop.Value
    if ($v -is [string]) {
      if ([IO.Path]::IsPathRooted($v) -and $v -notmatch '^\\\\' -and $prop.Name -match 'log') { if (-not $script:logDir -and (Test-Path -LiteralPath $v -PathType Container)) { $script:logDir = $v; $script:how = 'config_field' } }
      if ([IO.Path]::IsPathRooted($v) -and $v -notmatch '^\\\\' -and $prop.Name -match 'director') { if (Test-Path -LiteralPath $v -PathType Container) { $roots.Add($v) } }
    } elseif ($v -is [System.Management.Automation.PSCustomObject]) { Add-PathFields $v ($depth + 1) }
  }
}
Add-PathFields $login 0
try {
  if ($login.mcp_configuration_path) { Add-PathFields ([IO.File]::ReadAllText([string]$login.mcp_configuration_path) | ConvertFrom-Json) 0 }
} catch { }

if (-not $logDir) {
  $best = $null
  foreach ($r in $roots) {
    try {
      $hits = @(Get-ChildItem -LiteralPath $r -Recurse -Depth 4 -File -Filter '*.jsonl' -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}\.jsonl$' })
      foreach ($h in $hits) {
        $first = [IO.File]::ReadLines($h.FullName) | Select-Object -First 1
        if ($first -match '"event":"(http_request|mcp_rpc)"' -and ($null -eq $best -or $h.LastWriteTimeUtc -gt $best.LastWriteTimeUtc)) { $best = $h }
      }
    } catch { }
  }
  if ($best) { $logDir = $best.DirectoryName; $how = 'state_scan' }
}
if (-not $logDir) { Out-Row @{ step = 'log_dir'; ok = $false; detail = 'not_found'; roots = $roots.Count }; exit 1 }
Out-Row @{ step = 'log_dir'; ok = $true; detail = $how }

# 3. 读 15:00Z 之后的记录
$rows = New-Object System.Collections.Generic.List[object]
foreach ($d in $Days) {
  $f = Join-Path $logDir ($d + '.jsonl')
  if (-not (Test-Path -LiteralPath $f)) { continue }
  foreach ($line in [IO.File]::ReadLines($f)) {
    if (-not $line) { continue }
    try { $r = $line | ConvertFrom-Json } catch { continue }
    try { if ([DateTimeOffset]::Parse([string]$r.timestamp) -lt $Since) { continue } } catch { continue }
    $o = [ordered]@{}
    foreach ($k in $Keep) { if ($null -ne $r.$k) { $o[$k] = $r.$k } }
    $rows.Add([pscustomobject]$o)
  }
}
Out-Row @{ step = 'rows'; ok = $true; count = $rows.Count }

# 4. 汇总：按 path/status/ua/callback_class/rpc 结果计数
$groups = $rows | Group-Object -Property path, status, ua_family, callback_class, rpc_method, tool, outcome, error_code | Sort-Object Count -Descending
foreach ($g in $groups) { Out-Row @{ step = 'summary'; n = $g.Count; key = $g.Name } }

# 5. 明细：OAuth 端点与非 Claude 客户端的 /mcp（最多最近 60 条）
$detail = @($rows | Where-Object { $_.path -ne '/mcp' -or $_.ua_family -ne 'claude' })
if ($detail.Count -gt 60) { $detail = $detail[($detail.Count - 60)..($detail.Count - 1)] }
foreach ($r in $detail) { Out-Row $r }
exit 0
