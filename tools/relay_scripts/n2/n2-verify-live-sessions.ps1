[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
# 只读验证：用本 PR 里修过的 stop-schema6-session.ps1 定位活会话，期望恰好 1 个（旧记录 PID 被复用到 session 0 时不再报 Access denied）。
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$env:PSModulePath = Join-Path $PSHOME 'Modules'
function Out-Row($step, $ok, $detail) { [Console]::Out.WriteLine((@{ step = $step; ok = $ok; detail = $detail } | ConvertTo-Json -Compress -Depth 5)) }
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
function Probe {
  . (Join-Path $repo 'tools\i_core\maintenance\stop-schema6-session.ps1')
  $b = Get-Schema6LoginBinding 'HereIAm-iCoreSchema6-d2b-mcp-20261025-129ec194'
  Assert-Schema6NoRecovery $b
  $s = @(Get-Schema6LiveSessions $b)
  try { Out-Row 'live_sessions' ($s.Count -eq 1) @{ count = $s.Count; windowManifestMatches = $(if ($s.Count -eq 1) { $s[0].Window.manifest_sha256 -ceq $b.Login.manifest_sha256 } else { $null }) } }
  finally { foreach ($x in $s) { $x.Lease.Dispose() } }
}
try { Probe } catch { Out-Row 'live_sessions' $false @{ type = $_.Exception.GetType().FullName; message = ([string]$_.Exception.Message -replace '[A-Za-z]:\\[^\s''"]*', '<path>') } ; exit 1 }
