[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$ErrorActionPreference = 'Stop'
# 脚本轮入口（write）：运行 tools\linai_tts\install_linai_tts.ps1，安装/更新林埃英文语音服务的登录自启与 Tailscale :8445。
$installer = (Resolve-Path (Join-Path $PSScriptRoot '..\..\linai_tts\install_linai_tts.ps1')).Path
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $installer
exit $LASTEXITCODE
