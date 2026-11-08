[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
# M1（林埃日摘要）第 2 轮 deploy：解密高德 Key 和 ntfy topic、装生成器并测试推送、切 MCP 候选（server bde3ff9f，失败退回 G2）、核对心率入口、注册计划任务 HereIAm-LifeDigest、在剩余时间里试跑一次白天版和晨间播报。动生产。脚本轮 mode=write：用户点 👍 后由 watcher 运行。
# 只启动同目录 m1-deploy.mjs（先核对其 SHA256），用现役 release 里的固定 node.exe。
# 输出每行一个 JSON，不含令牌、登录名、域名、本机路径或 SID。
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5) { throw 'host_not_51' }
$env:PSModulePath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\Modules'
foreach ($name in @(Get-ChildItem Env: | Where-Object { $_.Name -like 'NODE_*' -or $_.Name -like 'I_CORE_*' -or $_.Name -like 'I_REMOTE_MCP_*' -or $_.Name -like 'GIT_*' } | ForEach-Object { $_.Name })) {
  Remove-Item -LiteralPath ('Env:' + $name)
}
$mjs = Join-Path $PSScriptRoot 'm1-deploy.mjs'
$sha = [Security.Cryptography.SHA256]::Create()
# core.autocrlf=true 检出会把 LF 变成 CRLF：原字节或把 CRLF 还原成 LF 后的字节，任一与提交版一致即可。
$bytes = [IO.File]::ReadAllBytes($mjs)
$lf = [Text.Encoding]::UTF8.GetBytes([Text.Encoding]::UTF8.GetString($bytes).Replace("`r`n", "`n"))
try { $actual = @(foreach ($b in @($bytes, $lf)) { ([BitConverter]::ToString($sha.ComputeHash($b))).Replace('-', '').ToLowerInvariant() }) } finally { $sha.Dispose() }
if ($actual -notcontains 'f7b3194b22f9299433d4a3a0316cc1f25d80e5c5d1a40f8f108a4ef9e96be8e7') { Write-Output '{"step":"launcher","ok":false,"detail":"mjs_hash_mismatch"}'; exit 1 }
$git = @(Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)
if ($git.Count -ne 1) { Write-Output '{"step":"launcher","ok":false,"detail":"git_not_found"}'; exit 1 }
$task = Get-ScheduledTask -TaskName 'HereIAm-iCoreSchema6-g2-tools-20261106'
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
& $node $mjs --mode deploy --git $git[0].Source
exit $LASTEXITCODE
