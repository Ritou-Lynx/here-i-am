[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
# N2 食物上线第 2 步（会短暂停服）。脚本轮 mode=write：用户在评论上点 👍 后由 watcher 运行。
# 只启动 scripts/deploy/n2/n2-step2.mjs（先核对其 SHA256），用现役 release 里的固定 node.exe。
# 输出每行一个 JSON，不含令牌、本机路径或 SID。
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5) { throw 'host_not_51' }
$env:PSModulePath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\Modules'
foreach ($name in @(Get-ChildItem Env: | Where-Object { $_.Name -like 'NODE_*' -or $_.Name -like 'I_CORE_*' -or $_.Name -like 'GIT_*' } | ForEach-Object { $_.Name })) {
  Remove-Item -LiteralPath ('Env:' + $name)
}
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$mjs = Join-Path $repo 'scripts\deploy\n2\n2-step2.mjs'
$sha = [Security.Cryptography.SHA256]::Create()
# core.autocrlf=true 检出会把 LF 变成 CRLF：原字节或把 CRLF 还原成 LF 后的字节，任一与提交版一致即可。
$bytes = [IO.File]::ReadAllBytes($mjs)
$lf = [Text.Encoding]::UTF8.GetBytes([Text.Encoding]::UTF8.GetString($bytes).Replace("`r`n", "`n"))
try { $actual = @(foreach ($b in @($bytes, $lf)) { ([BitConverter]::ToString($sha.ComputeHash($b))).Replace('-', '').ToLowerInvariant() }) } finally { $sha.Dispose() }
if ($actual -notcontains 'ba92417b85082ea1e98bdbf0efae65f882f754d30f6da7f6262783e6bc8c7b63') { Write-Output '{"step":"launcher","ok":false,"detail":"mjs_hash_mismatch"}'; exit 1 }
$git = @(Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)
if ($git.Count -ne 1) { Write-Output '{"step":"launcher","ok":false,"detail":"git_not_found"}'; exit 1 }
$task = Get-ScheduledTask -TaskName 'HereIAm-iCoreSchema6-d2b-mcp-20261025-129ec194'
$tokens = @()
foreach ($m in [regex]::Matches([string]$task.Actions[0].Arguments, '"([^"]*)"|(\S+)')) {
  if ($m.Groups[1].Success) { $tokens += $m.Groups[1].Value } else { $tokens += $m.Groups[2].Value }
}
$login = $null
for ($i = 0; $i -lt ($tokens.Count - 1); $i++) { if ($tokens[$i] -match '^-(Login)?ConfigurationPath$') { $login = $tokens[$i + 1] } }
if (-not $login) { Write-Output '{"step":"launcher","ok":false,"detail":"login_argument_missing"}'; exit 1 }
$config = [IO.File]::ReadAllText($login) | ConvertFrom-Json
$node = Join-Path $config.release_directory 'runtime\node.exe'
Write-Output '{"step":"launcher","ok":true,"detail":"mjs_hash_ok"}'
& $node $mjs --git $git[0].Source
exit $LASTEXITCODE
