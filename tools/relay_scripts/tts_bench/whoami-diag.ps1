[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$ErrorActionPreference = 'Continue'
# 只读诊断：脚本轮的运行身份与能否看到各用户的测速目录。用户名只输出 SHA256 前 8 位。
function Out-Json($obj) { [Console]::Out.WriteLine(($obj | ConvertTo-Json -Compress -Depth 6)) }
function H($s) { if (-not $s) { return $null }; $b = [Text.Encoding]::UTF8.GetBytes($s); (-join ([Security.Cryptography.SHA256]::Create().ComputeHash($b) | ForEach-Object { $_.ToString('x2') })).Substring(0, 8) }
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$integrity = (whoami /groups | Select-String 'Mandatory Label' | ForEach-Object { ($_ -split '\s{2,}')[0] }) -join ';'
Out-Json @{ step = 'identity'; userHash = (H $env:USERNAME); identityHash = (H ($id.Name -split '\\')[-1]); profileLeafHash = (H (Split-Path $env:USERPROFILE -Leaf))
    localAppDataUnderProfile = ($env:LOCALAPPDATA -and $env:USERPROFILE -and $env:LOCALAPPDATA.StartsWith($env:USERPROFILE)); integrity = $integrity
    isAdmin = ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
foreach ($d in @(Get-ChildItem 'C:\Users' -Directory -Force -ErrorAction SilentlyContinue)) {
    $p = Join-Path $d.FullName 'AppData\Local\HereIAm\tts-bench\.venv\Scripts\python.exe'
    $state = try { if (Test-Path -LiteralPath $p -ErrorAction Stop) { 'found' } else { 'absent' } } catch { 'denied: ' + $_.Exception.GetType().Name }
    $hia = try { [bool](Get-ChildItem -LiteralPath (Join-Path $d.FullName 'AppData\Local\HereIAm') -ErrorAction Stop | Select-Object -First 1) } catch { 'err: ' + $_.Exception.GetType().Name }
    Out-Json @{ step = 'profile'; nameHash = (H $d.Name); benchPython = $state; hereIAmListable = $hia }
}
Out-Json @{ step = 'done'; ok = $true }
