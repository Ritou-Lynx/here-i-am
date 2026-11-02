[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$ErrorActionPreference = 'Stop'
# 脚本轮入口（write）：启用 Gemini 同步。找到 Google Drive 电脑版的“我的云端硬盘”，建“here-i-am 学习同步”文件夹；
# 备份后更新工具目录的 run-daily.ps1、sync\export_gemini.mjs，配置加 gemini_export_dir；立即导出一次。
# 原生命令运行时临时用 Continue，避免 PS5.1 把 stderr 当终止错误。
function Out-Step($obj) { [Console]::Out.WriteLine(($obj | ConvertTo-Json -Compress)) }
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$src = Join-Path $repo 'tools\feishu_tutor'
$tool = Join-Path $env:USERPROFILE 'feishu-tutor-tool'
$study = Join-Path $env:USERPROFILE 'feishu-study'
$config = Join-Path $tool 'config.json'
foreach ($p in @($config, (Join-Path $tool 'run-daily.ps1'), (Join-Path $src 'run-daily.ps1'), (Join-Path $src 'sync\export_gemini.mjs'), (Join-Path $study 'today.md'))) {
  if (-not (Test-Path -LiteralPath $p)) { Out-Step @{ step = 'precheck'; ok = $false; error = 'missing'; file = (Split-Path $p -Leaf) }; exit 2 }
}
$node = (Get-Command node -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $node) { Out-Step @{ step = 'precheck'; ok = $false; error = 'node_not_found' }; exit 2 }

# Google Drive 电脑版：某个盘符下有“My Drive”或“我的云端硬盘”
$myDrive = $null
foreach ($d in (Get-PSDrive -PSProvider FileSystem)) {
  foreach ($name in @('My Drive', ([string][char]0x6211 + [char]0x7684 + [char]0x4E91 + [char]0x7AEF + [char]0x786C + [char]0x76D8))) {
    $candidate = Join-Path $d.Root $name
    if (-not $myDrive -and (Test-Path -LiteralPath $candidate -PathType Container)) { $myDrive = $candidate }
  }
}
if (-not $myDrive) { Out-Step @{ step = 'drive'; ok = $false; error = 'google_drive_desktop_not_found' }; exit 3 }
$out = Join-Path $myDrive 'here-i-am 学习同步'
New-Item -ItemType Directory -Path $out -Force | Out-Null
Out-Step @{ step = 'drive'; ok = $true; folder = (Split-Path $myDrive -Leaf) + '\here-i-am 学习同步' }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $study ('backup\gemini-export-' + $stamp)
New-Item -ItemType Directory -Path $backup -Force | Out-Null
Copy-Item -LiteralPath $config -Destination (Join-Path $backup 'config.json')
Copy-Item -LiteralPath (Join-Path $tool 'run-daily.ps1') -Destination (Join-Path $backup 'run-daily.ps1')
Copy-Item -LiteralPath (Join-Path $src 'run-daily.ps1') -Destination (Join-Path $tool 'run-daily.ps1') -Force
Copy-Item -LiteralPath (Join-Path $src 'sync\export_gemini.mjs') -Destination (Join-Path $tool 'sync\export_gemini.mjs') -Force

$js = Join-Path ([IO.Path]::GetTempPath()) ('set-export-{0}.js' -f [Guid]::NewGuid().ToString('N'))
[IO.File]::WriteAllText($js, @'
const fs = require('fs');
const [file, dir] = process.argv.slice(2);
const c = JSON.parse(fs.readFileSync(file, 'utf8').replace(/^﻿/, ''));
c.gemini_export_dir = dir;
fs.writeFileSync(file + '.tmp', JSON.stringify(c, null, 2) + '\n', 'utf8');
fs.renameSync(file + '.tmp', file);
console.log(JSON.stringify({ step: 'config', ok: true }));
'@, [Text.UTF8Encoding]::new($false))
$ErrorActionPreference = 'Continue'
try { & $node $js $config $out } finally { Remove-Item -LiteralPath $js -Force -ErrorAction SilentlyContinue }
$exportOut = & $node (Join-Path $tool 'sync\export_gemini.mjs') --study $study --out $out 2>&1 | ForEach-Object { "$_" }
$exportExit = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
$files = @(Get-ChildItem -LiteralPath $out -Filter '*.md' -File | ForEach-Object { '{0}:{1}KB' -f $_.Name, [math]::Ceiling($_.Length / 1024) })
Out-Step @{ step = 'export'; ok = ($exportExit -eq 0); output = ($exportOut -join ' '); files = ($files -join ', '); backup = ('backup\gemini-export-' + $stamp) }
Out-Step @{ step = 'done'; ok = ($exportExit -eq 0) }
if ($exportExit -ne 0) { exit 4 }
