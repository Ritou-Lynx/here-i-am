param(
  [int]$Port = 47831
)

$ErrorActionPreference = "Stop"

$stateDir = Join-Path $PSScriptRoot ".state"
$certPath = Join-Path $stateDir "localhost-cert.pem"
$keyPath = Join-Path $stateDir "localhost-key.pem"
$openssl = Get-Command openssl -ErrorAction SilentlyContinue

if (-not $openssl) {
  throw "openssl is required to generate the local HTTPS certificate."
}

New-Item -ItemType Directory -Force -Path $stateDir | Out-Null

if (-not (Test-Path $certPath) -or -not (Test-Path $keyPath)) {
  & $openssl.Source req `
    -x509 `
    -newkey rsa:2048 `
    -nodes `
    -days 30 `
    -keyout $keyPath `
    -out $certPath `
    -subj "/CN=localhost" `
    -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"
}

$adb = Get-Command adb -ErrorAction SilentlyContinue
if ($adb) {
  & $adb.Source reverse "tcp:$Port" "tcp:$Port" | Out-Null
  Write-Host "ADB reverse ready: device https://127.0.0.1:$Port -> this computer."
} else {
  Write-Host "adb was not found. Set up port forwarding manually before phone testing."
}

& "$PSScriptRoot\start_bridge.ps1" `
  -HostName "127.0.0.1" `
  -Port $Port `
  -CertPath $certPath `
  -KeyPath $keyPath
