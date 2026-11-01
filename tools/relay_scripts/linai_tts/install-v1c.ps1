[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$ErrorActionPreference = 'Stop'
# 脚本轮入口（write）：运行 tools\linai_tts\install_linai_tts.ps1，安装/更新林埃英文语音服务的登录自启与 Tailscale :8445。
$installer = (Resolve-Path (Join-Path $PSScriptRoot '..\..\linai_tts\install_linai_tts.ps1')).Path
# 脚本轮只校验本文件的哈希，所以这里再钉住安装脚本的版本
$expected = '2b8bfd866545b8c5e44879cbc2908bfc15601d0e9f8ed886c52691153f74c625'
$actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $installer).Hash.ToLower()
if ($actual -ne $expected) { [Console]::Out.WriteLine('{"step":"precheck","ok":false,"error":"installer_hash_mismatch"}'); exit 9 }
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $installer
exit $LASTEXITCODE
