[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
# 记账 E3 第 2 轮 deploy：建新 Core 包（v3-lab #98 合并点）和 MCP 候选（server 63acb514），写 expense.json，然后关现役会话、离线换包、登记新任务并切换（停服约 2–3 分钟），核对 Core 已开通记账。动生产。脚本轮 mode=write：用户点 👍 后由 watcher 运行。
# 只启动同目录 e3-deploy.mjs（先核对它和 e3-common.mjs 的 SHA256），用现役 release 里的固定 node.exe。
# 输出每行一个 JSON，不含令牌、登录名、域名、本机路径或 SID。
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5) { throw 'host_not_51' }
$env:PSModulePath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\Modules'
foreach ($name in @(Get-ChildItem Env: | Where-Object { $_.Name -like 'NODE_*' -or $_.Name -like 'I_CORE_*' -or $_.Name -like 'I_REMOTE_MCP_*' -or $_.Name -like 'GIT_*' } | ForEach-Object { $_.Name })) {
  Remove-Item -LiteralPath ('Env:' + $name)
}
# core.autocrlf=true 检出会把 LF 变成 CRLF：原字节或把 CRLF 还原成 LF 后的字节，任一与提交版一致即可。
function Test-Pinned([string]$file, [string]$expected) {
  $sha = [Security.Cryptography.SHA256]::Create()
  $bytes = [IO.File]::ReadAllBytes($file)
  $lf = [Text.Encoding]::UTF8.GetBytes([Text.Encoding]::UTF8.GetString($bytes).Replace("`r`n", "`n"))
  try { $actual = @(foreach ($b in @($bytes, $lf)) { ([BitConverter]::ToString($sha.ComputeHash($b))).Replace('-', '').ToLowerInvariant() }) } finally { $sha.Dispose() }
  return ($actual -contains $expected)
}
$mjs = Join-Path $PSScriptRoot 'e3-deploy.mjs'
if (-not (Test-Pinned $mjs 'c5515a6ab5ca83dd5efc8962a358dabb68b26c28b3c12aef781c6ec1b8304381')) { Write-Output '{"step":"launcher","ok":false,"detail":"mjs_hash_mismatch"}'; exit 1 }
if (-not (Test-Pinned (Join-Path $PSScriptRoot 'e3-common.mjs') '9de63918aae113e23417f6f98b6c47681d637cbe86ed0d65bc528d7856045aa5')) { Write-Output '{"step":"launcher","ok":false,"detail":"common_hash_mismatch"}'; exit 1 }
$git = @(Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)
if ($git.Count -ne 1) { Write-Output '{"step":"launcher","ok":false,"detail":"git_not_found"}'; exit 1 }
$task = Get-ScheduledTask -TaskName 'HereIAm-iCoreSchema6-m1-digest-20261107'
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
