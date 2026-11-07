[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
# HR1 上线前只读检查：现役任务、候选哈希、心率端口、Tailscale、维护工具副本；候选只构建在工作树 build/ 里并做一次读检查。脚本轮 mode=read。
# 只启动同目录 hr1.mjs（先核对其 SHA256），用现役 release 里的固定 node.exe。
# 输出每行一个 JSON，不含令牌、登录名、域名、本机路径或 SID。
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5) { throw 'host_not_51' }
$env:PSModulePath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\Modules'
foreach ($name in @(Get-ChildItem Env: | Where-Object { $_.Name -like 'NODE_*' -or $_.Name -like 'I_CORE_*' -or $_.Name -like 'I_REMOTE_MCP_*' -or $_.Name -like 'GIT_*' } | ForEach-Object { $_.Name })) {
  Remove-Item -LiteralPath ('Env:' + $name)
}
$mjs = Join-Path $PSScriptRoot 'hr1.mjs'
$sha = [Security.Cryptography.SHA256]::Create()
# core.autocrlf=true 检出会把 LF 变成 CRLF：原字节或把 CRLF 还原成 LF 后的字节，任一与提交版一致即可。
$bytes = [IO.File]::ReadAllBytes($mjs)
$lf = [Text.Encoding]::UTF8.GetBytes([Text.Encoding]::UTF8.GetString($bytes).Replace("`r`n", "`n"))
try { $actual = @(foreach ($b in @($bytes, $lf)) { ([BitConverter]::ToString($sha.ComputeHash($b))).Replace('-', '').ToLowerInvariant() }) } finally { $sha.Dispose() }
if ($actual -notcontains '5d319d4713caa13698bdb36c82f100fb598ce3637b4ac76bb7dc716422958028') { Write-Output '{"step":"launcher","ok":false,"detail":"mjs_hash_mismatch"}'; exit 1 }
$git = @(Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)
if ($git.Count -ne 1) { Write-Output '{"step":"launcher","ok":false,"detail":"git_not_found"}'; exit 1 }
$task = Get-ScheduledTask -TaskName 'HereIAm-iCoreSchema6-st1-study-20261103'
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
& $node $mjs --mode inspect --git $git[0].Source
exit $LASTEXITCODE
