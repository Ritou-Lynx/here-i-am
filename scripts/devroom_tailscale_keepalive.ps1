param(
  [Parameter(Mandatory = $true)]
  [string]$Target,

  [int]$IntervalSeconds = 30,

  [string]$BridgeHealthUrl = "http://127.0.0.1:47831/v1/health",

  [string]$LogPath = "$env:LOCALAPPDATA\HereIAm\devroom-tailscale-keepalive.log"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($IntervalSeconds -lt 10) {
  throw "IntervalSeconds must be at least 10 to avoid noisy polling."
}

function Write-KeepaliveLog {
  param([string]$Message)

  $dir = Split-Path -Parent $LogPath
  if ($dir -and -not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }

  $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  Add-Content -LiteralPath $LogPath -Value "[$timestamp] $Message"
}

function Test-TailscalePeer {
  param([string]$Peer)

  $tailscale = Get-Command "tailscale" -ErrorAction SilentlyContinue
  if ($tailscale) {
    & $tailscale.Source ping --c 1 --timeout 5s $Peer *> $null
    if ($LASTEXITCODE -eq 0) {
      return $true
    }
  }

  return Test-Connection -ComputerName $Peer -Count 1 -Quiet -ErrorAction SilentlyContinue
}

Write-KeepaliveLog "Starting Dev Room Tailscale keepalive. target=$Target interval=${IntervalSeconds}s bridge=$BridgeHealthUrl"

$successCount = 0
while ($true) {
  try {
    $peerOk = Test-TailscalePeer -Peer $Target
    $bridgeOk = $false

    try {
      $response = Invoke-WebRequest -Uri $BridgeHealthUrl -UseBasicParsing -TimeoutSec 5
      $bridgeOk = $response.StatusCode -ge 200 -and $response.StatusCode -lt 300
    } catch {
      $bridgeOk = $false
    }

    if ($peerOk -and $bridgeOk) {
      $successCount++
      if ($successCount % 120 -eq 0) {
        Write-KeepaliveLog "Healthy. target=$Target bridge=$BridgeHealthUrl"
      }
    } else {
      Write-KeepaliveLog "Keepalive warning. target_ok=$peerOk bridge_ok=$bridgeOk"
    }
  } catch {
    Write-KeepaliveLog "Keepalive error: $($_.Exception.Message)"
  }

  Start-Sleep -Seconds $IntervalSeconds
}
