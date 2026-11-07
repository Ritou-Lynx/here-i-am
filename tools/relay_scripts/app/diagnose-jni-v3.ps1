[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$ErrorActionPreference = 'Continue'
# 脚本轮（read）：GPT-Live 版本构建报 jni_flutter 找不到 reference。只读诊断：回传 Flutter/Dart 版本，
# 以及本机 pub 缓存里 jni 1.0.3 / jni_flutter 1.0.2 几个关键文件的哈希前缀和 JObject 声明行，和云端的对照。
# 不构建、不改缓存、不碰手机。
function Out-Json($obj) { [Console]::Out.WriteLine(($obj | ConvertTo-Json -Compress -Depth 6)) }
function Hash12($f) {
    $fs = [IO.File]::OpenRead($f)
    try { return (-join ([Security.Cryptography.SHA256]::Create().ComputeHash($fs) | ForEach-Object { $_.ToString('x2') })).Substring(0, 12) } finally { $fs.Dispose() }
}

$flutter = (Get-Command 'flutter.bat' -ErrorAction SilentlyContinue).Source
if ($flutter) {
    $v = (& $flutter --version --machine 2>$null | Out-String)
    try {
        $j = $v | ConvertFrom-Json
        Out-Json @{ step = 'flutter'; flutter = $j.frameworkVersion; dart = $j.dartSdkVersion; channel = $j.channel; revision = $j.frameworkRevision }
    } catch { Out-Json @{ step = 'flutter'; parse_failed = $true } }
} else { Out-Json @{ step = 'flutter'; found = $false } }

$caches = @($env:PUB_CACHE, (Join-Path $env:LOCALAPPDATA 'Pub\Cache')) | Where-Object { $_ -and (Test-Path $_) }
$hosted = $null
foreach ($c in $caches) { $h = Join-Path $c 'hosted\pub.dev'; if (Test-Path $h) { $hosted = $h; break } }
Out-Json @{ step = 'pub-cache'; found = [bool]$hosted; jni_dirs = @(if ($hosted) { Get-ChildItem $hosted -Directory -Filter 'jni*' | ForEach-Object { $_.Name } }) }
if ($hosted) {
    $files = @('jni-1.0.3\lib\src\jobject.dart', 'jni-1.0.3\lib\src\accessors.dart', 'jni-1.0.3\lib\jni.dart', 'jni_flutter-1.0.2\lib\src\generated_plugin.dart')
    foreach ($rel in $files) {
        $f = Join-Path $hosted $rel
        if (Test-Path $f) { Out-Json @{ step = 'file'; name = ($rel -replace '\\', '/'); sha256_12 = (Hash12 $f); bytes = (Get-Item $f).Length } }
        else { Out-Json @{ step = 'file'; name = ($rel -replace '\\', '/'); exists = $false } }
    }
    $jo = Join-Path $hosted 'jni-1.0.3\lib\src\jobject.dart'
    if (Test-Path $jo) {
        Out-Json @{ step = 'jobject'; lines = @(Select-String -Path $jo -Pattern '^(class|extension type) JObject|final JReference reference|JReference get reference' | ForEach-Object { "$($_.LineNumber): $($_.Line.Trim())" }) }
    }
}
Out-Json @{ step = 'done'; ok = $true }
