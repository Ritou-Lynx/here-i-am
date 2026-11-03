[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$ErrorActionPreference = 'Continue'
# 脚本轮（read）：第 1 轮构建超时后的诊断。只读：找第 1 轮留在临时目录的构建日志，回传抹掉路径的末尾几行，
# 看还有没有残留的 gradle/java/dart 进程，以及 Gradle 缓存和代理设置是否存在。不构建、不安装、不结束进程。
function Out-Json($obj) { [Console]::Out.WriteLine(($obj | ConvertTo-Json -Compress -Depth 6)) }
function Scrub([string]$text) {
    foreach ($p in @($env:USERPROFILE, $env:LOCALAPPDATA, $env:TEMP)) {
        if ($p) { $text = $text.Replace($p, '<path>') }
    }
    $text = $text -replace '[A-Za-z]:\\[^\s"'']*', '<path>'
    return ($text -replace '(?i)https?://[^\s"'']+', '<url>')
}
function Tail-Log($file, $n) {
    if (-not (Test-Path $file)) { return $null }
    return @(Get-Content $file -Tail $n | ForEach-Object { Scrub $_ })
}

$dirs = @(Get-ChildItem -Path $env:TEMP -Directory -Filter 'hereiam-apk-*' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending)
Out-Json @{ step = 'logs'; dirs = $dirs.Count }
if ($dirs.Count -gt 0) {
    $d = $dirs[0].FullName
    foreach ($name in @('pub.log', 'build.log')) {
        $f = Join-Path $d $name
        if (Test-Path $f) {
            $item = Get-Item $f
            Out-Json @{ step = 'log'; name = $name; kb = [math]::Round($item.Length / 1KB, 1);
                created = $item.CreationTime.ToString('HH:mm:ss'); last_write = $item.LastWriteTime.ToString('HH:mm:ss');
                tail = (Tail-Log $f 40) }
        } else {
            Out-Json @{ step = 'log'; name = $name; exists = $false }
        }
    }
}

$procs = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^(java|dart|dartaotruntime|gradle|adb|flutter)' })
Out-Json @{ step = 'processes'; list = @($procs | Group-Object ProcessName | ForEach-Object { "$($_.Name)x$($_.Count)" }) }

$gradleHome = if ($env:GRADLE_USER_HOME) { $env:GRADLE_USER_HOME } else { Join-Path $env:USERPROFILE '.gradle' }
Out-Json @{ step = 'gradle'; home_exists = (Test-Path $gradleHome);
    wrapper_dists = @(Get-ChildItem (Join-Path $gradleHome 'wrapper\dists') -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name });
    caches_exists = (Test-Path (Join-Path $gradleHome 'caches')) }
Out-Json @{ step = 'proxy'; http_proxy = [bool]$env:HTTP_PROXY; https_proxy = [bool]$env:HTTPS_PROXY;
    pub_hosted = [bool]$env:PUB_HOSTED_URL; storage_base = [bool]$env:FLUTTER_STORAGE_BASE_URL }
$gp = Join-Path $gradleHome 'gradle.properties'
if (Test-Path $gp) {
    Out-Json @{ step = 'gradle-properties'; keys = @(Get-Content $gp | Where-Object { $_ -match '^\s*[^#\s][^=]*=' } | ForEach-Object { ($_ -split '=')[0].Trim() }) }
}
Out-Json @{ step = 'done'; ok = $true }
