#!/usr/bin/env pwsh
# =============================================================================
# verify_critical_fixes.ps1
# =============================================================================
# Tool-agnostic pre-build verification. Run before `flutter build`.
# Works with any AI tool (Claude Code, Codex, HERMES) or manually.
#
# Usage:
#   powershell -File scripts\verify_critical_fixes.ps1
#
# Exit code: 0 = all fixes verified, 1 = one or more checks failed.
#
# The authoritative registry of critical fixes lives OUTSIDE this repo at:
#   ~/.claude/projects/D--memex/memory/critical_fixes_registry.md
# This script is the executable version of that registry.
# If filter-branch reverts this script, regenerate it from the memory file.
# =============================================================================

$ErrorActionPreference = "Stop"
$allPassed = $true

Write-Host ""
Write-Host "=== Critical Fixes Verification ===" -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------------------------
# Fix 1: Chat input enabled during AI streaming
# ---------------------------------------------------------------------------
# The TextField must NOT have enabled: !isStreaming (but AddButton and
# VoiceInputButton legitimately do). We verify by checking the positive
# presence of the fix comment.
Write-Host "[1/3] Chat input enabled during AI streaming..." -NoNewline
$fixComment = Select-String -Path "lib\ui\character\widgets\persona_chat_screen.dart" `
    -Pattern "Input stays enabled during streaming" -SimpleMatch | Select-Object -First 1
if (-not $fixComment) {
    Write-Host " FAIL" -ForegroundColor Red
    Write-Host "  BUG: TextField may have enabled: !isStreaming (line in PersonaChatInputBar)" -ForegroundColor Red
    Write-Host "  FIX: Remove enabled: !isStreaming from the TextField widget only." -ForegroundColor Yellow
    $allPassed = $false
} else {
    Write-Host " OK" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Fix 2: Sleep date semantics in all 3 agent files
# ---------------------------------------------------------------------------
Write-Host "[2/3] Sleep date semantics (WAKE-UP date) in agent prompts..." -NoNewline
$files = @(
    "lib\agent\built_in_tools\coros_mcp_tool.dart",
    "lib\agent\skills\companion_agent\companion_agent_skill.dart",
    "lib\agent\companion_agent\companion_agent.dart"
)
$missing = @()
foreach ($f in $files) {
    $match = Select-String -Path $f -Pattern "WAKE-UP date|wake-up date|睡眠数据" | Select-Object -First 1
    if (-not $match) {
        $missing += $f
    }
}
if ($missing.Count -gt 0) {
    Write-Host " FAIL" -ForegroundColor Red
    foreach ($m in $missing) {
        Write-Host "  MISSING: $m does not contain sleep date semantics guidance" -ForegroundColor Red
    }
    Write-Host "  FIX: Add sleep date guidance. See memory critical_fixes_registry entry Fix 2." -ForegroundColor Yellow
    $allPassed = $false
} else {
    Write-Host " OK" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Fix 3: health_strategies.dart has dateTo design comment
# ---------------------------------------------------------------------------
Write-Host "[3/3] health_strategies.dart documents dateTo design..." -NoNewline
$result = Select-String -Path "lib\data\services\health_strategies.dart" `
    -Pattern "WAKE UP (dateTo)" -SimpleMatch | Select-Object -First 1
if (-not $result) {
    Write-Host " FAIL" -ForegroundColor Red
    Write-Host "  MISSING: _aggregateSleep should document why it uses dateTo (wake-up date)" -ForegroundColor Red
    $allPassed = $false
} else {
    Write-Host " OK" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ""
if ($allPassed) {
    Write-Host "=== All checks passed. Safe to build. ===" -ForegroundColor Green
    exit 0
} else {
    Write-Host "=== VERIFICATION FAILED. Fix the issues above before building. ===" -ForegroundColor Red
    exit 1
}
