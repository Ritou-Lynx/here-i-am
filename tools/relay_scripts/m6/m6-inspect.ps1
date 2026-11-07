[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
# M6 只读盘点：找出各 AI 工具里本机连续性网关（i bootstrap）留下的配置，不做任何改动。脚本轮 mode=read。
# 找三类痕迹：MCP 条目 i（本机网关 i_mcp_server.mjs，或远端 i）、全局指导块 i-continuity、Codex 语音块 i-realtime-voice。
# 另报 ~/.i 目录概况、相关计划任务、正在跑的网关进程。思源、FlexNote 的 MCP 只报“保留”，不展开。
# 输出每行一个 JSON；路径只显示 ~ / %APPDATA% / %LOCALAPPDATA% 相对形式，网址、绝对路径、长令牌一律打码，.md 文件不输出正文。
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5) { throw 'host_not_51' }
$started = Get-Date
$budgetSeconds = 600

function Out-J($obj) { Write-Output ($obj | ConvertTo-Json -Compress -Depth 8) }

$rootMap = @()
foreach ($pair in @(@('%LOCALAPPDATA%', $env:LOCALAPPDATA), @('%APPDATA%', $env:APPDATA), @('~', $env:USERPROFILE))) {
  if ($pair[1]) { $rootMap += ,@($pair[0], ([IO.Path]::GetFullPath($pair[1])).TrimEnd('\')) }
}
function Show-Path([string]$p) {
  foreach ($r in $rootMap) {
    if ($p.StartsWith($r[1] + '\', [StringComparison]::OrdinalIgnoreCase)) { return ($r[0] + '/' + $p.Substring($r[1].Length + 1).Replace('\', '/')) }
  }
  return '<other>/' + [IO.Path]::GetFileName($p)
}
function Hide-Text([string]$s) {
  if ($null -eq $s) { return '' }
  $s = [regex]::Replace($s, 'https?://[^\s"''`,;]+', '<url>')
  $s = [regex]::Replace($s, '[A-Za-z]:(?:\\\\|\\|/)[^"''\s,;`]*', { param($m) $v = $m.Value; $i = [Math]::Max($v.LastIndexOf('\'), $v.LastIndexOf('/')); '<path>/' + $v.Substring($i + 1) })
  $s = [regex]::Replace($s, '(?i)((?:token|secret|password|passphrase|api[_-]?key|authorization|bearer|cookie)[^:=]{0,20}["'']?\s*[:=]\s*)\S+', '$1<redacted>')
  $s = [regex]::Replace($s, '[A-Za-z0-9_\-+/=]{32,}', '<long>')
  foreach ($n in @($env:USERNAME, $env:COMPUTERNAME, $env:USERDOMAIN)) { if ($n -and $n.Length -ge 3) { $s = [regex]::Replace($s, [regex]::Escape($n), '<name>', 'IgnoreCase') } }
  $s = $s.Trim()
  if ($s.Length -gt 160) { $s = $s.Substring(0, 160) + '...' }
  return $s
}
function Get-Sha8([byte[]]$b) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash($b))).Replace('-', '').Substring(0, 8).ToLowerInvariant() } finally { $sha.Dispose() }
}

$markers = [ordered]@{
  gateway_server = 'i_mcp_server'
  gateway_dir = 'i_continuity_gateway'
  i_runtime = '[\\/]\.i(?:\\\\|\\|/)+runtime'
  client_id = 'I_CLIENT_ID'
  guidance_block = 'i-continuity:start'
  realtime_block = 'i-realtime-voice:start'
  bootstrap_word = 'i_bootstrap'
  close_session = 'i_close_session'
  voice_tools = 'i_voice_(?:context|turn|probe)'
}
$entryPatterns = @('^\s*"i"\s*:\s*\{', '^\s*\[mcp_servers\.i(?:\.env)?\]\s*$', '^\s{2,}i:\s*$', '^\s*"name"\s*:\s*"i"\s*,?\s*$')
$keepPattern = '(?i)siyuan|flexnote|思源'

function Get-Tool([string]$shown) {
  $l = $shown.ToLowerInvariant()
  foreach ($t in @('codex', 'opencode', 'hermes', 'antigravity', 'gemini', 'cursor', 'windsurf', 'codeium', 'trae', 'kiro', 'qwen', 'codebuddy', 'workbuddy', 'cline', 'roo', 'goose', 'continue', 'iflow', 'kimi', 'crush', 'zed', 'lingma', 'augment', 'claude')) {
    if ($l.Contains($t)) { return $t }
  }
  if ($l -match '/code/user/') { return 'vscode' }
  return 'other'
}

$seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$hitFiles = 0
$keepFiles = 0
$scanned = 0

function Inspect-File([string]$path, [long]$maxBytes) {
  if (-not $seen.Add($path)) { return }
  $script:scanned++
  try { $fi = New-Object IO.FileInfo $path } catch { return }
  if (-not $fi.Exists) { return }
  $shown = Show-Path $path
  if ($fi.Length -gt $maxBytes) { Out-J ([ordered]@{ kind = 'skipped'; path = $shown; reason = 'too_large'; bytes = $fi.Length }); return }
  try { $bytes = [IO.File]::ReadAllBytes($path) } catch { Out-J ([ordered]@{ kind = 'skipped'; path = $shown; reason = 'read_failed' }); return }
  $text = [Text.Encoding]::UTF8.GetString($bytes)
  $hits = [ordered]@{}
  foreach ($k in $markers.Keys) { $c = [regex]::Matches($text, $markers[$k]).Count; if ($c -gt 0) { $hits[$k] = $c } }
  $lines = $text -split "`r?`n"
  $isMd = $path -match '\.(md|markdown|txt)$'
  $entries = @()
  for ($i = 0; $i -lt $lines.Count; $i++) {
    foreach ($p in $entryPatterns) {
      if ($lines[$i] -match $p) {
        $ctx = @()
        $end = [Math]::Min($lines.Count - 1, $i + 14)
        for ($j = $i; $j -le $end; $j++) {
          if ($j -gt $i -and ($lines[$j] -match '^\s*\[' -and $lines[$j] -notmatch '^\s*\[mcp_servers\.i\.' -and $lines[$j] -notmatch '^\s*\[\s*$' -and $lines[$j] -notmatch '^\s*\["')) { break }
          $ctx += ('{0}: {1}' -f ($j + 1), (Hide-Text $lines[$j]))
          if ($j -gt $i -and $lines[$j] -match '^\s*\}\s*,?\s*$' -and ($lines[$j].Length - $lines[$j].TrimStart().Length) -le ($lines[$i].Length - $lines[$i].TrimStart().Length)) { break }
        }
        $raw = ($lines[$i..$end] -join "`n")
        $class = 'unknown'
        if ($raw -match 'i_mcp_server|i_continuity_gateway|[\\/]\.i(?:\\\\|\\|/)+runtime') { $class = 'local_gateway' }
        elseif ($raw -match '(?i)mcp-remote|https?://|"url"|serverUrl|httpUrl|streamable') { $class = 'remote' }
        $entry = [ordered]@{ line = $i + 1; 'class' = $class }
        if (-not $isMd) { $entry['context'] = $ctx }
        $entries += $entry
        break
      }
    }
  }
  $blocks = @()
  foreach ($b in @(@('i-continuity', '<!-- i-continuity:start -->', '<!-- i-continuity:end -->'), @('i-realtime-voice', '# i-realtime-voice:start', '# i-realtime-voice:end'))) {
    $s = -1; $e = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($s -lt 0 -and $lines[$i].Trim() -eq $b[1]) { $s = $i }; if ($s -ge 0 -and $lines[$i].Trim() -eq $b[2]) { $e = $i; break } }
    if ($s -ge 0) { $blocks += [ordered]@{ block = $b[0]; start = $s + 1; end = $(if ($e -ge 0) { $e + 1 } else { $null }); lines_in_file = $lines.Count } }
  }
  $markerLines = @()
  if (-not $isMd) {
    for ($i = 0; $i -lt $lines.Count -and $markerLines.Count -lt 12; $i++) {
      foreach ($k in $markers.Keys) { if ($lines[$i] -match $markers[$k]) { $markerLines += ('{0}: {1}' -f ($i + 1), (Hide-Text $lines[$i])); break } }
    }
  } else {
    for ($i = 0; $i -lt $lines.Count -and $markerLines.Count -lt 12; $i++) {
      foreach ($k in $markers.Keys) { if ($lines[$i] -match $markers[$k]) { $markerLines += ('{0}: <{1}>' -f ($i + 1), $k); break } }
    }
  }
  $keep = [regex]::Matches($text, $keepPattern).Count
  if ($hits.Count -gt 0 -or $entries.Count -gt 0 -or $blocks.Count -gt 0) {
    $script:hitFiles++
    if ($script:hitFiles -gt 60) { return }
    Out-J ([ordered]@{ kind = 'hit'; tool = (Get-Tool $shown); path = $shown; bytes = $fi.Length; mtime = $fi.LastWriteTime.ToString('yyyy-MM-dd HH:mm'); sha8 = (Get-Sha8 $bytes); markers = $hits; i_entries = $entries; blocks = $blocks; marker_lines = $markerLines; siyuan_flexnote_mentions = $keep })
  } elseif ($keep -gt 0 -and $path -match '\.(json|jsonc|toml|ya?ml)$') {
    $script:keepFiles++
    if ($script:keepFiles -gt 30) { return }
    Out-J ([ordered]@{ kind = 'keep'; tool = (Get-Tool $shown); path = $shown; siyuan_flexnote_mentions = $keep; note = 'not_touched' })
  }
}

# 1) 已知位置（含大文件，如 .claude.json）
$known = @(
  '~\.codex\config.toml', '~\.codex\AGENTS.md', '~\.codex\AGENTS.override.md',
  '~\.claude.json', '~\.claude\CLAUDE.md', '~\.claude\settings.json', '~\.claude\settings.local.json', '~\.claude\.mcp.json',
  '%APPDATA%\Claude\claude_desktop_config.json',
  '~\.hermes\config.yaml', '~\.hermes\SOUL.md', '%LOCALAPPDATA%\hermes\config.yaml', '%LOCALAPPDATA%\hermes\SOUL.md',
  '~\.config\opencode\opencode.json', '~\.config\opencode\opencode.jsonc', '~\.config\opencode\config.json', '~\.config\opencode\AGENTS.md',
  '%APPDATA%\opencode\opencode.json', '%APPDATA%\opencode\opencode.jsonc', '~\.opencode\opencode.json',
  '~\.gemini\config\mcp_config.json', '~\.gemini\antigravity\mcp_config.json', '~\.gemini\settings.json', '~\.gemini\GEMINI.md',
  '~\.cursor\mcp.json', '~\.codeium\windsurf\mcp_config.json', '~\.kiro\settings\mcp.json', '~\.qwen\settings.json', '~\.iflow\settings.json',
  '~\.codebuddy\mcp.json', '~\.codebuddy\settings.json', '~\.workbuddy\mcp.json', '~\.workbuddy\settings.json',
  '%APPDATA%\Code\User\mcp.json', '%APPDATA%\Code\User\settings.json', '%APPDATA%\Trae\User\mcp.json', '%APPDATA%\Cursor\User\settings.json',
  '%APPDATA%\Code\User\globalStorage\saoudrizwan.claude-dev\settings\cline_mcp_settings.json',
  '~\.config\goose\config.yaml', '~\.continue\config.yaml', '~\.continue\config.json'
)
$knownReport = @()
foreach ($k in $known) {
  $p = $k.Replace('%LOCALAPPDATA%', $env:LOCALAPPDATA).Replace('%APPDATA%', $env:APPDATA)
  if ($p.StartsWith('~')) { $p = $env:USERPROFILE + $p.Substring(1) }
  if (Test-Path -LiteralPath $p -PathType Leaf) { $knownReport += $k.Replace('\', '/'); Inspect-File $p 52428800 }
}
Out-J ([ordered]@{ kind = 'known_present'; files = $knownReport })

# 2) 泛扫：用户目录下的点目录 + 漫游/本地应用数据里像 AI 工具的目录
$skipDirs = '^(node_modules|\.git|\.mcp-auth|\.i|cache|caches|code cache|gpucache|cachedata|cacheddata|logs?|tmp|temp|extensions|workspacestorage|history|sessions|projects|shell-snapshots|todos|file-history|blob_storage|indexeddb|local storage|session storage|service worker|crashpad|\.npm|\.cache|\.nuget|\.gradle|\.android|\.cargo|\.rustup|\.pub-cache|\.m2|\.conda|\.ollama|\.vscode|\.dartserver|\.dotnet|\.pyenv|\.local|\.ssh|\.gnupg|\.docker|\.kube|\.aws|\.azure|venv|\.venv|site-packages|dist|build|out|worktrees|\.worktrees|relay-worktrees|repos|src|packages|vendor)$'
$toolDir = '(?i)codex|claude|opencode|hermes|gemini|antigravity|cursor|windsurf|codeium|^code$|trae|kiro|qwen|codebuddy|workbuddy|cline|roo|goose|continue|iflow|kimi|crush|zed|lingma|augment|marscode|comate|copilot|tongyi'
$mdNames = '(?i)^(agents|claude|gemini|soul|qwen|iflow|rules|global_rules|instructions|memory|user_rules|custom_instructions).*\.md$'
$queue = New-Object 'System.Collections.Generic.Queue[object]'
try { foreach ($d in [IO.Directory]::GetDirectories($env:USERPROFILE)) { $n = [IO.Path]::GetFileName($d); if ($n.StartsWith('.') -and $n -notmatch $skipDirs) { $queue.Enqueue(@($d, 0)) } } } catch {}
foreach ($base in @($env:APPDATA, $env:LOCALAPPDATA, (Join-Path $env:USERPROFILE '.config'))) {
  if (-not $base -or -not (Test-Path -LiteralPath $base)) { continue }
  try { foreach ($d in [IO.Directory]::GetDirectories($base)) { if ([IO.Path]::GetFileName($d) -match $toolDir) { $queue.Enqueue(@($d, 0)) } } } catch {}
}
$truncated = $false
while ($queue.Count -gt 0) {
  if (((Get-Date) - $started).TotalSeconds -gt $budgetSeconds) { $truncated = $true; break }
  $item = $queue.Dequeue(); $dir = $item[0]; $depth = $item[1]
  try { $di = New-Object IO.DirectoryInfo $dir; if ($di.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue } } catch { continue }
  try { $files = [IO.Directory]::GetFiles($dir) } catch { continue }
  foreach ($f in $files) {
    $n = [IO.Path]::GetFileName($f)
    if ($n -match '(?i)\.(json|jsonc|toml|ya?ml)$' -or $n -match $mdNames) { Inspect-File $f 2097152 }
  }
  if ($depth -lt 4) {
    try { foreach ($d in [IO.Directory]::GetDirectories($dir)) { if ([IO.Path]::GetFileName($d) -notmatch $skipDirs) { $queue.Enqueue(@($d, $depth + 1)) } } } catch {}
  }
}

# 3) ~/.i 目录概况（只报子项名、文件数、大小，不读内容；projects.json 只报项目数）
$iHome = Join-Path $env:USERPROFILE '.i'
if (Test-Path -LiteralPath $iHome) {
  $children = @()
  foreach ($c in (Get-ChildItem -LiteralPath $iHome -Force)) {
    if ($c.PSIsContainer) {
      $fs = @(Get-ChildItem -LiteralPath $c.FullName -Recurse -File -Force -ErrorAction SilentlyContinue)
      $children += [ordered]@{ name = $c.Name; type = 'dir'; files = $fs.Count; bytes = ($fs | Measure-Object Length -Sum).Sum; newest = $(if ($fs.Count) { ($fs | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime.ToString('yyyy-MM-dd') } else { $null }) }
    } else {
      $children += [ordered]@{ name = $c.Name; type = 'file'; bytes = $c.Length; mtime = $c.LastWriteTime.ToString('yyyy-MM-dd') }
    }
  }
  $projectCount = $null
  try { $reg = [IO.File]::ReadAllText((Join-Path $iHome 'projects.json')) | ConvertFrom-Json; $projectCount = @($reg.projects).Count } catch {}
  Out-J ([ordered]@{ kind = 'i_home'; exists = $true; children = $children; registered_projects = $projectCount })
} else {
  Out-J ([ordered]@{ kind = 'i_home'; exists = $false })
}

# 4) 计划任务里引用网关的
$tasks = @()
try {
  foreach ($t in (Get-ScheduledTask -ErrorAction Stop)) {
    $act = (@($t.Actions) | ForEach-Object { [string]$_.Execute + ' ' + [string]$_.Arguments }) -join ' '
    if ($act -match 'i_device_sync|i_continuity_gateway|i_mcp_server|[\\/]\.i[\\/]runtime|sync_i_devices') { $tasks += [ordered]@{ name = $t.TaskName; state = [string]$t.State } }
  }
} catch { $tasks = @('query_failed') }
Out-J ([ordered]@{ kind = 'scheduled_tasks'; matches = $tasks })

# 5) 正在跑的本机网关进程（只报父进程名）
$procs = @()
try {
  $all = @(Get-CimInstance Win32_Process -ErrorAction Stop)
  $byId = @{}; foreach ($p in $all) { $byId[[int]$p.ProcessId] = $p }
  foreach ($p in $all) {
    if ([string]$p.CommandLine -match 'i_mcp_server') {
      $parent = $byId[[int]$p.ParentProcessId]
      $procs += [ordered]@{ name = $p.Name; parent = $(if ($parent) { $parent.Name } else { $null }) }
    }
  }
} catch { $procs = @('query_failed') }
Out-J ([ordered]@{ kind = 'gateway_processes'; matches = $procs })

# 6) 命令行工具是否存在（不调用）
$cli = [ordered]@{}
foreach ($c in @('codex', 'claude', 'hermes', 'opencode', 'gemini', 'qwen')) { $cli[$c] = [bool](Get-Command $c -ErrorAction SilentlyContinue) }
Out-J ([ordered]@{ kind = 'cli_present'; tools = $cli })

Out-J ([ordered]@{ kind = 'summary'; files_scanned = $scanned; hit_files = $hitFiles; keep_files = $keepFiles; sweep_truncated = $truncated; seconds = [int]((Get-Date) - $started).TotalSeconds })
exit 0
