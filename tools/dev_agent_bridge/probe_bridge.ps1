param(
  [string]$BridgeUrl = "http://127.0.0.1:47831",
  [string]$ProjectRoot = "D:\claude-workspace\memex",
  [ValidateSet("claude_code", "codex")]
  [string]$AgentType = "claude_code",
  [string]$Prompt = "Say exactly: hello from dev agent bridge probe"
)

$ErrorActionPreference = "Stop"

$runId = "probe-$([guid]::NewGuid().ToString('N').Substring(0, 8))"

Write-Host "Health:" -ForegroundColor Cyan
Invoke-RestMethod "$BridgeUrl/v1/health" | ConvertTo-Json -Depth 5

$body = @{
  client_run_id = $runId
  agent_type = $AgentType
  mode = "read_only"
  prompt = $Prompt
  project = @{
    id = "memex"
    name = "Here I am"
    root_path = $ProjectRoot
    default_branch = "personal-lab"
    permission_tier = "read_only"
  }
} | ConvertTo-Json -Depth 5

Write-Host "`nStart run: $runId" -ForegroundColor Cyan
Invoke-RestMethod "$BridgeUrl/v1/runs" -Method Post -Body $body -ContentType "application/json" |
  ConvertTo-Json -Depth 5

Start-Sleep -Seconds 20

Write-Host "`nStatus:" -ForegroundColor Cyan
Invoke-RestMethod "$BridgeUrl/v1/runs/$runId" | ConvertTo-Json -Depth 5

Write-Host "`nEvents:" -ForegroundColor Cyan
Invoke-RestMethod "$BridgeUrl/v1/runs/$runId/events?after=0" | ConvertTo-Json -Depth 8
