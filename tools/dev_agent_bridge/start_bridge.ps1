param(
  [string]$HostName = "127.0.0.1",
  [int]$Port = 47831,
  [string]$CertPath = "",
  [string]$KeyPath = ""
)

$ErrorActionPreference = "Stop"

$env:DEV_AGENT_BRIDGE_HOST = $HostName
$env:DEV_AGENT_BRIDGE_PORT = "$Port"

if ($CertPath -and $KeyPath) {
  $env:DEV_AGENT_BRIDGE_CERT = $CertPath
  $env:DEV_AGENT_BRIDGE_KEY = $KeyPath
} else {
  Remove-Item Env:\DEV_AGENT_BRIDGE_CERT -ErrorAction SilentlyContinue
  Remove-Item Env:\DEV_AGENT_BRIDGE_KEY -ErrorAction SilentlyContinue
}

node "$PSScriptRoot\dev_agent_bridge.mjs"
