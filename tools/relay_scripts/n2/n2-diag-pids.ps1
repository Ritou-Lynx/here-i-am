[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
# 只读诊断：列出所有 session-window 记录里 PID 仍存在的进程，看哪一个 OpenProcess 被拒。
# 只输出序号、进程名、会话号、记录时间与进程启动先后，不输出路径、PID 以外的标识。
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
function Out-Row($step, $ok, $detail) { [Console]::Out.WriteLine((@{ step = $step; ok = $ok; detail = $detail } | ConvertTo-Json -Compress -Depth 5)) }
Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public static class N2Open{[DllImport("kernel32.dll",SetLastError=true)]public static extern IntPtr OpenProcess(uint a,bool i,int id);[DllImport("kernel32.dll")]public static extern bool CloseHandle(IntPtr h);public static int Try(int id){IntPtr h=OpenProcess(0x00101000,false,id);if(h==IntPtr.Zero)return Marshal.GetLastWin32Error();CloseHandle(h);return 0;}}'
$task = Get-ScheduledTask -TaskName 'HereIAm-iCoreSchema6-d2b-mcp-20261025-129ec194'
$tokens = @(); foreach ($m in [regex]::Matches([string]$task.Actions[0].Arguments, '"([^"]*)"|(\S+)')) { if ($m.Groups[1].Success) { $tokens += $m.Groups[1].Value } else { $tokens += $m.Groups[2].Value } }
$loginPath = $null; for ($i = 0; $i -lt ($tokens.Count - 1); $i++) { if ($tokens[$i] -match '^-(Login)?ConfigurationPath$') { $loginPath = $tokens[$i + 1] } }
$login = [IO.File]::ReadAllText($loginPath) | ConvertFrom-Json
$i = 0
foreach ($d in @(Get-ChildItem -LiteralPath $login.control_root -Directory -Filter 'session-*' | Sort-Object LastWriteTimeUtc -Descending)) {
  $f = Join-Path $d.FullName 'session-window.json'; if (-not (Test-Path -LiteralPath $f)) { continue }
  $i++
  $w = [IO.File]::ReadAllText($f) | ConvertFrom-Json
  $p = Get-Process -Id ([int]$w.pid) -ErrorAction SilentlyContinue
  if (-not $p) { continue }
  $started = $null; try { $started = $p.StartTime.ToUniversalTime() } catch {}
  $recorded = (Get-Item -LiteralPath $f).LastWriteTimeUtc
  Out-Row 'alive_record' $true @{ index = $i; name = $p.ProcessName; sessionId = $p.SessionId; openError = [N2Open]::Try([int]$w.pid); startKnown = [bool]$started; startedAfterRecord = $(if ($started) { $started -gt $recorded } else { $null }); recordAgeDays = [math]::Round(((Get-Date).ToUniversalTime() - $recorded).TotalDays, 1); hasExit = (Test-Path -LiteralPath (Join-Path $d.FullName 'session-exit.json')) }
  $p.Dispose()
}
Out-Row 'done' $true @{ records = $i }
