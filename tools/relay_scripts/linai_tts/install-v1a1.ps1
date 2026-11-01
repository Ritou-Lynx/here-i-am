[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$ErrorActionPreference = 'Stop'
# 脚本轮入口（write）：V1a.1 更新林埃英文语音服务（Tailscale 身份鉴权），再跑一遍幂等安装脚本。
$installer = (Resolve-Path (Join-Path $PSScriptRoot '..\..\linai_tts\install_linai_tts.ps1')).Path
# 脚本轮只校验本文件的哈希，所以这里再钉住安装脚本的版本
$expected = '19707679a637a3437f1326eccdb7d9667efd6546e245903de46e750b636780d1'
$sha = [Security.Cryptography.SHA256]::Create()
$stream = [IO.File]::OpenRead($installer)
try { $actual = -join ($sha.ComputeHash($stream) | ForEach-Object { $_.ToString('x2') }) } finally { $stream.Dispose() }
if ($actual -ne $expected) { [Console]::Out.WriteLine('{"step":"precheck","ok":false,"error":"installer_hash_mismatch"}'); exit 9 }
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $installer
exit $LASTEXITCODE
