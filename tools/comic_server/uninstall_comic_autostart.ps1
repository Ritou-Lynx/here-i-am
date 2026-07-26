# Remove the Startup-folder autostart VBS for the comic pipeline.
# Does NOT stop a running pipeline (use stop_comic_pipeline.ps1) and does NOT
# touch the Tailscale :8443 serve (remove with `tailscale serve --https=8443 off`).

$startup = [Environment]::GetFolderPath('Startup')
$vbsPath = Join-Path $startup 'HereIAm_Comic_Pipeline.vbs'

# Also clean up a Task Scheduler task from an older install attempt, if any.
Unregister-ScheduledTask -TaskName 'HereIAm_Comic_Pipeline' -Confirm:$false -ErrorAction SilentlyContinue

if (Test-Path -LiteralPath $vbsPath) {
  Remove-Item -LiteralPath $vbsPath -Force
  Write-Host "[ok] Removed $vbsPath" -ForegroundColor Green
} else {
  Write-Host "[i] $vbsPath not found; nothing to remove." -ForegroundColor DarkGray
}
Write-Host "     (Tailscale :8443 serve left intact; remove with: tailscale serve --https=8443 off)" -ForegroundColor DarkGray