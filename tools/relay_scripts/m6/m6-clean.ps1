[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
# M6 删除轮（mode=write，需用户 👍）：从各 AI 工具配置里删掉本机连续性网关（i bootstrap）的残留。
# 只动第 3 轮盘点确认过的文件，且文件内容必须与盘点时一致（sha8 校验），否则跳过该文件。
# 每个文件改前先备份到 %LOCALAPPDATA%\here-i-am-m6-backup\<时间戳>\（worktree 外）。
# 不动：远端 i（Antigravity）、思源/FlexNote、~/.i 目录、Codex 的 backups 与历史文件。
# JSON 改完用本机 node 校验能解析，校验失败就还原。输出每行一个 JSON，不含配置正文与绝对路径。
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5) { throw 'host_not_51' }

function Out-J($obj) { Write-Output ($obj | ConvertTo-Json -Compress -Depth 6) }
function Get-Sha8([byte[]]$b) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash($b))).Replace('-', '').Substring(0, 8).ToLowerInvariant() } finally { $sha.Dispose() }
}
function Resolve-UserPath([string]$p) {
  $p = $p.Replace('%LOCALAPPDATA%', $env:LOCALAPPDATA)
  if ($p.StartsWith('~')) { $p = $env:USERPROFILE + $p.Substring(1) }
  return $p.Replace('/', '\')
}

$stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
$backupRoot = Join-Path $env:LOCALAPPDATA ('here-i-am-m6-backup\' + $stamp)
New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
Out-J ([ordered]@{ step = 'backup_root'; ok = $true; detail = ('%LOCALAPPDATA%/here-i-am-m6-backup/' + $stamp) })

# 读文件：记住 BOM 与换行风格
function Read-Doc([string]$path) {
  $bytes = [IO.File]::ReadAllBytes($path)
  $bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
  $text = [Text.UTF8Encoding]::new($false).GetString($bytes)
  if ($bom) { $text = $text.Substring(1) }
  $nl = "`n"; if ($text.Contains("`r`n")) { $nl = "`r`n" }
  $lines = New-Object 'System.Collections.Generic.List[string]'
  foreach ($l in ($text -split "`r?`n")) { $lines.Add($l) }
  return @{ bytes = $bytes; bom = $bom; nl = $nl; lines = $lines }
}
function Write-Doc([string]$path, $doc) {
  $text = ($doc.lines -join $doc.nl)
  [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new([bool]$doc.bom))
}
function Get-Indent([string]$l) { return $l.Length - $l.TrimStart().Length }

# 找 JSON 对象从 start 行的 { 到匹配 } 的行号（跳过字符串里的括号）
function Find-JsonObjectEnd($lines, [int]$start) {
  $depth = 0; $inStr = $false; $esc = $false
  for ($i = $start; $i -lt $lines.Count; $i++) {
    $l = $lines[$i]
    for ($k = 0; $k -lt $l.Length; $k++) {
      $ch = $l[$k]
      if ($inStr) { if ($esc) { $esc = $false } elseif ($ch -eq '\') { $esc = $true } elseif ($ch -eq '"') { $inStr = $false }; continue }
      if ($ch -eq '"') { $inStr = $true } elseif ($ch -eq '{') { $depth++ } elseif ($ch -eq '}') { $depth--; if ($depth -eq 0) { return $i } }
    }
  }
  return -1
}
# 删掉 [s..e] 行后，若被删段末尾没有逗号（是最后一项），去掉前一个非空行末尾的逗号
function Remove-JsonLines($lines, [int]$s, [int]$e) {
  $hadComma = $lines[$e].TrimEnd().EndsWith(',')
  $lines.RemoveRange($s, $e - $s + 1)
  if (-not $hadComma) {
    for ($j = $s - 1; $j -ge 0; $j--) {
      $t = $lines[$j].TrimEnd()
      if ($t.Length -eq 0) { continue }
      if ($t.EndsWith(',')) { $lines[$j] = $t.Substring(0, $t.Length - 1) }
      break
    }
  }
}

# node：从 Codex 配置里网关条目的 command 取（就是网关用的 node.exe），否则找 PATH
$nodeExe = $null
try {
  $cfg = [IO.File]::ReadAllText((Resolve-UserPath '~/.codex/config.toml'))
  $m = [regex]::Match($cfg, '(?ms)^\s*\[mcp_servers\.i\]\s*$.*?^\s*command\s*=\s*[''"]([^''"]+node\.exe)[''"]')
  if ($m.Success -and (Test-Path -LiteralPath $m.Groups[1].Value)) { $nodeExe = $m.Groups[1].Value }
} catch {}
if (-not $nodeExe) { $c = Get-Command node -ErrorAction SilentlyContinue; if ($c) { $nodeExe = $c.Source } }
Out-J ([ordered]@{ step = 'node'; ok = [bool]$nodeExe })
$checkJs = Join-Path $backupRoot 'check-json.js'
[IO.File]::WriteAllText($checkJs, "const t=require('fs').readFileSync(process.argv[2],'utf8').replace(/^\uFEFF/,'');try{JSON.parse(t);process.stdout.write('ok')}catch(e){process.stdout.write('bad')}", [Text.UTF8Encoding]::new($false))
function Test-Json([string]$path) {
  if (-not $nodeExe) { return 'no_node' }
  $r = & $nodeExe $checkJs $path 2>$null
  return [string]$r
}

$plan = @(
  @{ path = '~/.codex/config.toml'; sha8 = 'a07a5897'; kind = 'toml' },
  @{ path = '~/.codex/AGENTS.md'; sha8 = '998593fb'; kind = 'md' },
  @{ path = '~/.claude.json'; sha8 = '9595fb26'; kind = 'json' },
  @{ path = '~/.claude/CLAUDE.md'; sha8 = 'efaae8ea'; kind = 'md' },
  @{ path = '~/.claude/settings.local.json'; sha8 = '7d83d0ff'; kind = 'perm' },
  @{ path = '%LOCALAPPDATA%/hermes/config.yaml'; sha8 = 'dc3ad3e3'; kind = 'yaml' },
  @{ path = '%LOCALAPPDATA%/hermes/SOUL.md'; sha8 = 'a5d63c45'; kind = 'md' },
  @{ path = '~/.config/opencode/opencode.jsonc'; sha8 = '2aaa757d'; kind = 'json' },
  @{ path = '~/.config/opencode/AGENTS.md'; sha8 = 'efaae8ea'; kind = 'md' }
)
$gatewayRe = 'i_mcp_server|i_continuity_gateway'
$failures = 0
$n = 0
foreach ($item in $plan) {
  $n++
  $shown = $item.path
  $path = Resolve-UserPath $item.path
  try {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Out-J ([ordered]@{ file = $shown; ok = $false; detail = 'missing' }); $failures++; continue }
    $doc = Read-Doc $path
    $sha = Get-Sha8 $doc.bytes
    if ($sha -ne $item.sha8) { Out-J ([ordered]@{ file = $shown; ok = $false; detail = ('changed_since_inventory sha8=' + $sha) }); $failures++; continue }
    $lines = $doc.lines
    $removed = @()

    if ($item.kind -eq 'md') {
      $s = -1; $e = -1
      for ($i = 0; $i -lt $lines.Count; $i++) { if ($s -lt 0 -and $lines[$i].Trim() -eq '<!-- i-continuity:start -->') { $s = $i }; if ($s -ge 0 -and $lines[$i].Trim() -eq '<!-- i-continuity:end -->') { $e = $i; break } }
      if ($s -lt 0 -or $e -lt 0) { throw 'block_not_found' }
      $lines.RemoveRange($s, $e - $s + 1)
      while ($s -lt $lines.Count -and $lines[$s].Trim() -eq '' -and ($s -eq 0 -or $lines[$s - 1].Trim() -eq '')) { $lines.RemoveAt($s) }
      $removed += ('i-continuity block ' + ($e - $s + 1) + ' lines')
    }
    elseif ($item.kind -eq 'toml') {
      # 语音块
      $s = -1; $e = -1
      for ($i = 0; $i -lt $lines.Count; $i++) { if ($s -lt 0 -and $lines[$i].Trim() -eq '# i-realtime-voice:start') { $s = $i }; if ($s -ge 0 -and $lines[$i].Trim() -eq '# i-realtime-voice:end') { $e = $i; break } }
      if ($s -ge 0 -and $e -ge 0) {
        $lines.RemoveRange($s, $e - $s + 1)
        while ($s -lt $lines.Count -and $lines[$s].Trim() -eq '' -and ($s -eq 0 -or $lines[$s - 1].Trim() -eq '')) { $lines.RemoveAt($s) }
        $removed += 'i-realtime-voice block'
      }
      # [mcp_servers.i] 与 [mcp_servers.i.env]
      $s = -1
      for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*\[mcp_servers\.i\]\s*$') { $s = $i; break } }
      if ($s -lt 0) { throw 'mcp_table_not_found' }
      $e = $lines.Count - 1
      for ($i = $s + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[' -and $lines[$i] -notmatch '^\s*\[mcp_servers\.i\.') { $e = $i - 1; break }
      }
      $seg = ($lines.GetRange($s, $e - $s + 1) -join "`n")
      if ($seg -notmatch $gatewayRe) { throw 'mcp_table_not_gateway' }
      while ($e -gt $s -and $lines[$e].Trim() -eq '') { $e-- }
      $lines.RemoveRange($s, $e - $s + 1)
      while ($s -lt $lines.Count -and $lines[$s].Trim() -eq '' -and ($s -eq 0 -or $lines[$s - 1].Trim() -eq '')) { $lines.RemoveAt($s) }
      $removed += 'mcp_servers.i'
    }
    elseif ($item.kind -eq 'json') {
      $count = 0
      for ($guard = 0; $guard -lt 10; $guard++) {
        $s = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
          if ($lines[$i] -match '^\s*"i"\s*:\s*\{') {
            $end = Find-JsonObjectEnd $lines $i
            if ($end -lt 0) { throw 'json_object_unbalanced' }
            if (($lines.GetRange($i, $end - $i + 1) -join "`n") -match $gatewayRe) { $s = $i; break }
          }
        }
        if ($s -lt 0) { break }
        Remove-JsonLines $lines $s $end
        $count++
      }
      if ($count -eq 0) { throw 'gateway_entry_not_found' }
      $removed += ('mcp entry i x' + $count)
    }
    elseif ($item.kind -eq 'perm') {
      $count = 0
      for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if ($lines[$i] -match '^\s*"mcp__i__i_(bootstrap|get_project_state|recall_project|close_session|get_project_overview|get_recent_activity|voice_context|voice_turn|voice_probe)"\s*,?\s*$') { Remove-JsonLines $lines $i $i; $count++ }
      }
      if ($count -eq 0) { throw 'permission_not_found' }
      $removed += ('local gateway permissions x' + $count)
    }
    elseif ($item.kind -eq 'yaml') {
      $s = -1
      for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s{2,}i:\s*$') { $s = $i; break } }
      if ($s -lt 0) { throw 'yaml_entry_not_found' }
      $ind = Get-Indent $lines[$s]
      $e = $s
      for ($i = $s + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq '') { continue }
        if ((Get-Indent $lines[$i]) -gt $ind) { $e = $i } else { break }
      }
      if (($lines.GetRange($s, $e - $s + 1) -join "`n") -notmatch $gatewayRe) { throw 'yaml_entry_not_gateway' }
      $parent = -1
      for ($j = $s - 1; $j -ge 0; $j--) { if ($lines[$j].Trim() -ne '' -and -not $lines[$j].TrimStart().StartsWith('#') -and (Get-Indent $lines[$j]) -lt $ind) { $parent = $j; break } }
      $lines.RemoveRange($s, $e - $s + 1)
      $hasSibling = $false
      for ($j = $parent + 1; $j -lt $lines.Count; $j++) {
        $t = $lines[$j]
        if ($t.Trim() -eq '' -or $t.TrimStart().StartsWith('#')) { continue }
        if ((Get-Indent $t) -gt (Get-Indent $lines[$parent])) { $hasSibling = $true }
        break
      }
      if ($parent -ge 0 -and -not $hasSibling -and $lines[$parent].TrimEnd().EndsWith(':')) { $lines[$parent] = $lines[$parent].TrimEnd() + ' {}' ; $removed += 'parent_now_empty_map' }
      $removed += 'mcp entry i'
    }

    $bk = Join-Path $backupRoot ('{0:D2}-{1}' -f $n, [IO.Path]::GetFileName($path))
    [IO.File]::WriteAllBytes($bk, $doc.bytes)
    $remaining = ($lines -join "`n")
    if ($item.kind -eq 'md' -and $remaining.Trim() -eq '') {
      Remove-Item -LiteralPath $path -Force
      Out-J ([ordered]@{ file = $shown; ok = $true; detail = 'file_only_had_block_deleted'; removed = $removed })
      continue
    }
    Write-Doc $path $doc
    if ($item.kind -in @('json', 'perm')) {
      $v = Test-Json $path
      if ($v -ne 'ok') {
        $orig = Test-Json $bk
        if ($orig -eq 'ok' -or $v -eq 'no_node') {
          [IO.File]::WriteAllBytes($path, $doc.bytes)
          Out-J ([ordered]@{ file = $shown; ok = $false; detail = ('json_check_' + $v + '_restored') }); $failures++; continue
        }
        $removed += 'original_not_strict_json_check_skipped'
      }
    }
    $after = [IO.File]::ReadAllText($path)
    $left = [regex]::Matches($after, 'i_mcp_server|i-continuity:start|i-realtime-voice:start|mcp__i__i_bootstrap').Count
    Out-J ([ordered]@{ file = $shown; ok = ($left -eq 0); detail = ('left_markers=' + $left); removed = $removed })
    if ($left -ne 0) { $failures++ }
  } catch {
    Out-J ([ordered]@{ file = $shown; ok = $false; detail = ('error ' + $_.Exception.Message) }); $failures++
  }
}

$procs = @()
try { foreach ($p in @(Get-CimInstance Win32_Process -ErrorAction Stop)) { if ([string]$p.CommandLine -match 'i_mcp_server') { $procs += $p.Name } } } catch {}
Out-J ([ordered]@{ step = 'summary'; ok = ($failures -eq 0); failures = $failures; gateway_processes_still_running = $procs.Count; note = 'restart_codex_to_drop_running_gateway' })
if ($failures -gt 0) { exit 1 }
exit 0
