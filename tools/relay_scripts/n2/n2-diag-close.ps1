[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
# 只读诊断：在 watcher 的运行环境里逐步重放 close-input 的检查，找出 A1 失败的那一步。
# 不发 WM_CLOSE、不改任务/STATE/配置；只读文件、查进程。输出每行一个 JSON，路径与 SID 已脱敏。
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$env:PSModulePath = Join-Path $PSHOME 'Modules'
function Out-Row($step, $ok, $detail) { [Console]::Out.WriteLine((@{ step = $step; ok = $ok; detail = $detail } | ConvertTo-Json -Compress -Depth 5)) }
function Clean([string]$m) { if ($null -eq $m) { return '' }; $m = $m -replace '[A-Za-z]:\\[^\s''"]*', '<path>' -replace 'S-1-5-[0-9-]+', '<sid>'; if ($m.Length -gt 200) { $m = $m.Substring(0, 200) }; return $m }
function Try-Step($name, [scriptblock]$body) {
  try { $v = & $body; Out-Row $name $true $v; return $true }
  catch { Out-Row $name $false @{ type = $_.Exception.GetType().FullName; message = (Clean $_.Exception.Message); inner = (Clean ([string]$_.Exception.InnerException)) }; return $false }
}
$me = [Security.Principal.WindowsIdentity]::GetCurrent()
$proc = [Diagnostics.Process]::GetCurrentProcess()
Out-Row 'context' $true @{ psVersion = [string]$PSVersionTable.PSVersion; edition = $PSVersionTable.PSEdition; language = [string]$ExecutionContext.SessionState.LanguageMode; sessionId = $proc.SessionId; interactive = [Environment]::UserInteractive; elevated = (New-Object Security.Principal.WindowsPrincipal($me)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator); is64 = [Environment]::Is64BitProcess; tempSet = [bool]$env:TEMP }
$task = Get-ScheduledTask -TaskName 'HereIAm-iCoreSchema6-d2b-mcp-20261025-129ec194'
$tokens = @(); foreach ($m in [regex]::Matches([string]$task.Actions[0].Arguments, '"([^"]*)"|(\S+)')) { if ($m.Groups[1].Success) { $tokens += $m.Groups[1].Value } else { $tokens += $m.Groups[2].Value } }
$loginPath = $null; for ($i = 0; $i -lt ($tokens.Count - 1); $i++) { if ($tokens[$i] -match '^-(Login)?ConfigurationPath$') { $loginPath = $tokens[$i + 1] } }
$login = [IO.File]::ReadAllText($loginPath) | ConvertFrom-Json
$mcp = [IO.File]::ReadAllText($login.mcp_configuration_path) | ConvertFrom-Json
$out = Split-Path -Parent (Split-Path -Parent $mcp.working_directory)
$mt = Join-Path $out 'tools-fb401d45\tools\i_core\maintenance'
Out-Row 'owner' $true @{ sameUser = ($me.User.Value -ceq $login.owner_sid); taskState = [string]$task.State; toolsCopy = (Test-Path -LiteralPath $mt); runDirExists = (Test-Path -LiteralPath (Join-Path $out 'n2-step2-run')) }
$null = Try-Step 'get_filehash' { (Get-Command Get-FileHash -ErrorAction Stop).Source }
$null = Try-Step 'add_type' { if (-not ('N2DiagProbe' -as [type])) { Add-Type -TypeDefinition 'public static class N2DiagProbe{public static int One(){return 1;}}' }; [N2DiagProbe]::One() }
$null = Try-Step 'icacls_temp' { $t = Join-Path ([IO.Path]::GetTempPath()) ('n2diag-' + [guid]::NewGuid().ToString('N')); [void](New-Item -ItemType Directory -Path $t); try { & (Join-Path $env:SystemRoot 'System32\icacls.exe') $t '/inheritance:r' '/grant:r' ('*' + $me.User.Value + ':(OI)(CI)F') '*S-1-5-18:(OI)(CI)F' | Out-Null; $LASTEXITCODE } finally { Remove-Item -LiteralPath $t -Recurse -Force } }
$runDir = Join-Path $out 'n2-step2-run'
if (Test-Path -LiteralPath $runDir) {
  $null = Try-Step 'run_dir_private' { $a = Get-Acl -LiteralPath $runDir; $bad = @($a.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]) | Where-Object { $_.AccessControlType -eq 'Allow' -and $_.IdentityReference.Value -notin @($me.User.Value, 'S-1-5-18', 'S-1-5-32-544') }).Count; $c = $runDir; $rp = $false; while ($c) { if (([IO.File]::GetAttributes($c) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $rp = $true }; $p = [IO.Directory]::GetParent($c); $c = if ($p) { $p.FullName } else { $null } }; @{ protected = $a.AreAccessRulesProtected; ownerIsMe = ($a.GetOwner([Security.Principal.SecurityIdentifier]).Value -ceq $me.User.Value); otherAllow = $bad; reparseInChain = $rp; files = @(Get-ChildItem -LiteralPath $runDir -Force | ForEach-Object { $_.Name }) } }
}
function Probe-Sessions {
  . (Join-Path $mt 'stop-schema6-session.ps1')
  $b = $null
  if (-not (Try-Step 'binding' { $script:b = Get-Schema6LoginBinding 'HereIAm-iCoreSchema6-d2b-mcp-20261025-129ec194'; 'ok' })) { return }
  $b = $script:b
  $null = Try-Step 'no_recovery' { Assert-Schema6NoRecovery $b; 'ok' }
  $null = Try-Step 'native_init' { Initialize-Schema6MaintenanceNative; 'ok' }
  $records = @()
  foreach ($d in @(Get-ChildItem -LiteralPath $b.Login.control_root -Directory -Filter 'session-*' | Sort-Object LastWriteTimeUtc -Descending)) {
    $f = Join-Path $d.FullName 'session-window.json'; if (-not (Test-Path -LiteralPath $f)) { continue }
    $w = [IO.File]::ReadAllText($f) | ConvertFrom-Json
    $alive = $false; $sid = $null; try { $p = Get-Process -Id ([int]$w.pid) -ErrorAction Stop; $alive = $true; $sid = $p.SessionId; $p.Dispose() } catch {}
    $records += @{ windowSessionId = $(if ($w.PSObject.Properties.Name -contains 'session_id') { $w.session_id } else { $null }); hostAlive = $alive; hostSessionId = $sid; hookReady = $w.hook_ready }
  }
  Out-Row 'session_records' $true @{ count = $records.Count; first3 = @($records | Select-Object -First 3) }
  $null = Try-Step 'live_sessions' { $s = @(Get-Schema6LiveSessions $b); $n = $s.Count; foreach ($x in $s) { $x.Lease.Dispose() }; @{ count = $n } }
}
Probe-Sessions
Out-Row 'done' $true 'read_only'
