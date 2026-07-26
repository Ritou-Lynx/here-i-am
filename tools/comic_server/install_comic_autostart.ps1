# Install logon autostart for the comic pipeline by dropping a tiny VBS into
# the user's Startup folder. This needs NO special privileges (unlike Task
# Scheduler, which can hit "Access denied" in non-interactive contexts) and,
# because it just launches a normal login-time process, it has none of Task
# Scheduler's daemon-hostile defaults (72h execution limit, no-run-on-battery)
# -- which matters on a laptop running an always-on crawler.
#
# The VBS uses WScript.Shell.Run with window style 0 (SW_HIDE) to hide the
# powershell host; start_comic_pipeline.ps1 -Silent then hides the two node
# consoles. Result: fully silent autostart.
#
# The Tailscale :8443 exposure is a one-time `tailscale serve --bg` config the
# Tailscale system service restores every boot; this script only ensures it.
#
# Run once:
#   powershell -ExecutionPolicy Bypass -File tools\comic_server\install_comic_autostart.ps1
# Remove later with uninstall_comic_autostart.ps1.

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$startScript = Join-Path $here 'start_comic_pipeline.ps1'
$vbsName = 'HereIAm_Comic_Pipeline.vbs'
$startup = [Environment]::GetFolderPath('Startup')
$vbsPath = Join-Path $startup $vbsName

if (-not (Test-Path $startScript)) {
  Write-Host "[!] start_comic_pipeline.ps1 not found at $startScript" -ForegroundColor Red
  exit 1
}

# Clean up a Task Scheduler task from an older install attempt, if any.
Unregister-ScheduledTask -TaskName 'HereIAm_Comic_Pipeline' -Confirm:$false -ErrorAction SilentlyContinue

# Ensure Tailscale background serves exist (idempotent).
#   :443  https -> dev_agent_bridge (127.0.0.1:47831)   [DevRoom]
#   :8443 http  -> comic_server   (127.0.0.1:47840)     [漫画书架]
#   :8081 http  -> ollama_proxy   (127.0.0.1:11435)     [识图 Ollama, Host 改写]
$serve = & tailscale serve status 2>&1 | Out-String
if ($serve -notmatch ':443\b') {
  Write-Host "[*] Registering Tailscale serve :443 (DevRoom Bridge) ..." -ForegroundColor Yellow
  & tailscale serve --bg --https=443 http://127.0.0.1:47831 2>&1 | Out-Null
}
if ($serve -notmatch ':8443') {
  Write-Host "[*] Registering Tailscale serve :8443 (comic) ..." -ForegroundColor Yellow
  & tailscale serve --bg --http=8443 http://127.0.0.1:47840 2>&1 | Out-Null
}
if ($serve -notmatch ':8081') {
  Write-Host "[*] Registering Tailscale serve :8081 (ollama) ..." -ForegroundColor Yellow
  & tailscale serve --bg --http=8081 http://127.0.0.1:11435 2>&1 | Out-Null
}

# VBS template: __PATH__ is replaced literally (no regex semantics). The ""
# around __PATH__ are VBS escaped quotes so the path survives as one argument.
$vbsTemplate = @'
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""__PATH__"" -Silent", 0, False
'@
$vbs = $vbsTemplate.Replace('__PATH__', $startScript)
Set-Content -LiteralPath $vbsPath -Value $vbs -Encoding ASCII

Write-Host "[ok] Autostart installed: $vbsPath" -ForegroundColor Green
Write-Host "     Runs at every logon (silent). To test right now:" -ForegroundColor DarkGray
Write-Host "       wscript.exe `"$vbsPath`"" -ForegroundColor White
Write-Host "     Stop a running pipeline: stop_comic_pipeline.ps1" -ForegroundColor DarkGray
Write-Host "     Remove autostart: uninstall_comic_autostart.ps1" -ForegroundColor DarkGray