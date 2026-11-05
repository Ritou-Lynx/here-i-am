[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
# 原生命令（flutter、adb、gradle）会往 stderr 打进度，PS 5.1 在 Stop 下会直接抛错，所以用 Continue 并显式检查退出码
$ErrorActionPreference = 'Continue'
# 脚本轮（write）：构建 Here I Am V3 debug APK，经 USB adb 覆盖安装到唯一连着的手机并启动。
# 构建放在工作树外的固定目录（本机应用数据下的 HereIAm\apk-build）：每轮把工作树源码镜像过去再构建，
# build/ 和 .dart_tool/ 保留，第二次起是增量构建。构建限时 16 分钟，没完成就停下报 build_incomplete，
# 已编译的部分留着，下一轮接着编（watcher 每轮上限 20 分钟）。
# 只做覆盖安装（-r），签名不符就停下报错，绝不卸载（卸载会清掉 App 数据）。
# 输出每行一个 JSON，不含路径、设备序列号、账号。构建日志只回传末尾几行，且抹掉本机路径。
function Out-Json($obj) { [Console]::Out.WriteLine(($obj | ConvertTo-Json -Compress -Depth 6)) }

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$package = 'com.memexlab.hereiam.v3'
$work = Join-Path $env:LOCALAPPDATA 'HereIAm\apk-build'
$apk = Join-Path $work 'build\app\outputs\flutter-apk\app-hereiamv3-debug.apk'
$buildBudgetMinutes = 16
$logDir = Join-Path $env:TEMP ('hereiam-apk-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

function Scrub([string]$text) {
    foreach ($p in @($work, $repo, $env:USERPROFILE, $env:LOCALAPPDATA, $env:TEMP)) {
        if ($p) { $text = $text.Replace($p, '<path>') }
    }
    return ($text -replace '[A-Za-z]:\\[^\s"'']*', '<path>')
}
function Tail-Log($file, $n = 15) {
    if (-not (Test-Path $file)) { return @() }
    return @(Get-Content $file -Tail $n -Encoding UTF8 | ForEach-Object { Scrub $_ })
}
function Find-Tool($name, $cands) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($c in $cands) { if ($c -and (Test-Path $c)) { return $c } }
    return $null
}

# 1. 工具
$flutter = Find-Tool 'flutter.bat' @(
    (Join-Path $env:USERPROFILE 'flutter\bin\flutter.bat'),
    (Join-Path $env:USERPROFILE 'dev\flutter\bin\flutter.bat'),
    'C:\src\flutter\bin\flutter.bat', 'C:\flutter\bin\flutter.bat', 'D:\flutter\bin\flutter.bat',
    (Join-Path $env:LOCALAPPDATA 'flutter\bin\flutter.bat'))
$sdkRoots = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, (Join-Path $env:LOCALAPPDATA 'Android\Sdk')) | Where-Object { $_ }
$adb = Find-Tool 'adb.exe' @($sdkRoots | ForEach-Object { Join-Path $_ 'platform-tools\adb.exe' })
Out-Json @{ step = 'tools'; flutter = [bool]$flutter; adb = [bool]$adb }
if (-not $flutter -or -not $adb) { exit 2 }

# 2. 手机：必须正好一台、已授权
& $adb start-server 2>&1 | Out-Null
$lines = @(& $adb devices 2>$null | Select-Object -Skip 1 | Where-Object { $_ -match '\S' })
$ready = @($lines | Where-Object { $_ -match '\tdevice$' })
$unauth = @($lines | Where-Object { $_ -match '\tunauthorized$' })
Out-Json @{ step = 'device'; ready = $ready.Count; unauthorized = $unauth.Count; other = ($lines.Count - $ready.Count - $unauth.Count) }
if ($ready.Count -ne 1) {
    $err = if ($unauth.Count) { 'unauthorized_tap_allow_on_phone' } elseif ($ready.Count -eq 0) { 'no_device' } else { 'multiple_devices' }
    Out-Json @{ step = 'device'; ok = $false; error = $err }
    exit 3
}
$serial = ($ready[0] -split "`t")[0]
$installed = [bool](& $adb -s $serial shell pm list packages $package 2>$null | Select-String -SimpleMatch "package:$package")
Out-Json @{ step = 'device'; ok = $true; app_installed = $installed }

# 3. 构建前检查（在工作树里跑）
Set-Location $repo
$verify = Join-Path $repo 'scripts\verify_critical_fixes.ps1'
if (Test-Path $verify) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verify *> (Join-Path $logDir 'verify.log')
    Out-Json @{ step = 'verify-critical-fixes'; exit = $LASTEXITCODE }
    if ($LASTEXITCODE -ne 0) { Out-Json @{ step = 'verify-critical-fixes'; tail = (Tail-Log (Join-Path $logDir 'verify.log')) }; exit 4 }
}

# 4. 镜像源码到固定构建目录（保留构建缓存和 Flutter 生成的本机配置）
New-Item -ItemType Directory -Force -Path $work | Out-Null
$rc = Join-Path $logDir 'robocopy.log'
& robocopy.exe $repo $work /MIR /NFL /NDL /NJH /NP /R:1 /W:1 `
    /XD build .dart_tool .git .gradle .cxx .idea `
    /XF .git debug.keystore local.properties .flutter-plugins .flutter-plugins-dependencies *> $rc
$rcExit = $LASTEXITCODE

# debug 签名：debug.keystore 不进仓库，只在本机主仓库里。必须用同一把，否则覆盖安装会因签名不符失败。
# 从工作树对应的主仓库（git common dir 的上一级）复制到构建目录，只回传是否找到和哈希前缀。
$keyDest = Join-Path $work 'android\app\debug.keystore'
$common = (& git -C $repo rev-parse --path-format=absolute --git-common-dir 2>$null | Select-Object -First 1)
$keySrc = $null
if ($common) {
    $cand = Join-Path (Split-Path -Parent ([IO.Path]::GetFullPath($common.Trim()))) 'android\app\debug.keystore'
    if (Test-Path $cand) { $keySrc = $cand }
}
if ($keySrc) { Copy-Item -Force $keySrc $keyDest }
$keyInfo = @{ step = 'signing'; source_found = [bool]$keySrc; present = (Test-Path $keyDest) }
if (Test-Path $keyDest) {
    $kfs = [IO.File]::OpenRead($keyDest)
    try { $keyInfo.sha256_12 = (-join ([Security.Cryptography.SHA256]::Create().ComputeHash($kfs) | ForEach-Object { $_.ToString('x2') })).Substring(0, 12) } finally { $kfs.Dispose() }
}
Out-Json $keyInfo
if (-not (Test-Path $keyDest)) { Out-Json @{ step = 'signing'; ok = $false; error = 'debug_keystore_not_found' }; exit 9 }
Out-Json @{ step = 'sync'; ok = ($rcExit -lt 8); exit = $rcExit; incremental = (Test-Path (Join-Path $work 'build')) }
if ($rcExit -ge 8) { Out-Json @{ step = 'sync'; tail = (Tail-Log $rc) }; exit 5 }

# 5. 构建（限时）
Set-Location $work
$t0 = Get-Date
& $flutter pub get *> (Join-Path $logDir 'pub.log')
if ($LASTEXITCODE -ne 0) { Out-Json @{ step = 'pub-get'; ok = $false; tail = (Tail-Log (Join-Path $logDir 'pub.log')) }; exit 5 }
# pub 缓存里的包目录可能残缺（目录在、lib 里的文件没了），pub get 不会发现。逐个检查用到的缓存包：
# 缺 lib 或 pubspec.yaml 的整个删掉，再 pub get 一次重新下载。只动 pub 缓存里的这几个目录。
function Get-BrokenPackages {
    $cfg = Join-Path $work '.dart_tool\package_config.json'
    if (-not (Test-Path $cfg)) { return @() }
    $broken = @()
    foreach ($pkg in (Get-Content $cfg -Raw -Encoding UTF8 | ConvertFrom-Json).packages) {
        if ($pkg.rootUri -notmatch '^file:///') { continue }
        $dir = [Uri]::UnescapeDataString(($pkg.rootUri -replace '^file:///', '')) -replace '/', '\'
        if ($dir -notmatch '\\hosted\\') { continue }
        $lib = Join-Path $dir 'lib'
        $ok = (Test-Path (Join-Path $dir 'pubspec.yaml')) -and (Test-Path $lib) -and
            [bool](Get-ChildItem $lib -Recurse -File -Filter '*.dart' -ErrorAction SilentlyContinue | Select-Object -First 1)
        if (-not $ok) { $broken += [pscustomobject]@{ name = (Split-Path -Leaf $dir); dir = $dir } }
    }
    return $broken
}
$broken = @(Get-BrokenPackages)
Out-Json @{ step = 'pub-cache-check'; broken = @($broken | ForEach-Object { $_.name }) }
if ($broken.Count -gt 0) {
    foreach ($b in $broken) { Remove-Item -Recurse -Force $b.dir -ErrorAction SilentlyContinue }
    & $flutter pub get *> (Join-Path $logDir 'pub2.log')
    if ($LASTEXITCODE -ne 0) { Out-Json @{ step = 'pub-get-repair'; ok = $false; tail = (Tail-Log (Join-Path $logDir 'pub2.log')) }; exit 5 }
    $still = @(Get-BrokenPackages)
    Out-Json @{ step = 'pub-cache-repair'; ok = ($still.Count -eq 0); still_broken = @($still | ForEach-Object { $_.name }) }
    if ($still.Count -gt 0) { exit 5 }
    Remove-Item -Recurse -Force (Join-Path $work '.dart_tool\flutter_build') -ErrorAction SilentlyContinue
}
$pkgCfg = Join-Path $work '.dart_tool\package_config.json'
if (Test-Path $pkgCfg) {
    $jniRoots = @((Get-Content $pkgCfg -Raw -Encoding UTF8 | ConvertFrom-Json).packages | Where-Object { $_.name -like 'jni*' } |
        ForEach-Object { "$($_.name)=" + (($_.rootUri -split '/') | Where-Object { $_ -match '^jni' } | Select-Object -Last 1) })
    Out-Json @{ step = 'packages'; jni = $jniRoots }
}
if (Test-Path $apk) { Remove-Item -Force $apk }
# Dart 编译缓存每轮清掉重编（只花一两分钟）：上一轮若在编译中途被限时停掉，残留的增量缓存会导致
# 莫名其妙的编译错误。Gradle 的 Java/Kotlin/原生产物仍然保留。
foreach ($stale in @((Join-Path $work '.dart_tool\flutter_build'), (Join-Path $work 'build\app\intermediates\flutter'))) {
    if (Test-Path $stale) { Remove-Item -Recurse -Force $stale -ErrorAction SilentlyContinue }
}
$buildLog = Join-Path $logDir 'build.log'
$proc = Start-Process -FilePath 'cmd.exe' -WorkingDirectory $work -WindowStyle Hidden -PassThru `
    -ArgumentList @('/c', "`"`"$flutter`" build apk --debug --flavor hereIAmV3 > `"$buildLog`" 2>&1`"")
$null = $proc.Handle  # PS 5.1：先取句柄，否则退出后拿不到 ExitCode
$finished = $proc.WaitForExit($buildBudgetMinutes * 60 * 1000)
$seconds = [int]((Get-Date) - $t0).TotalSeconds
if (-not $finished) {
    & taskkill.exe /T /F /PID $proc.Id 2>&1 | Out-Null
    Out-Json @{ step = 'build'; ok = $false; error = 'build_incomplete'; seconds = $seconds; note = 'compiled_parts_kept_rerun_continues'; tail = (Tail-Log $buildLog 8) }
    exit 8
}
$buildExit = $proc.ExitCode
if ($buildExit -ne 0 -or -not (Test-Path $apk)) {
    Out-Json @{ step = 'build'; ok = $false; exit = $buildExit; seconds = $seconds; tail = (Tail-Log $buildLog 25) }
    exit 6
}
$sha = [Security.Cryptography.SHA256]::Create()
$fs = [IO.File]::OpenRead($apk)
try { $apkSha = -join ($sha.ComputeHash($fs) | ForEach-Object { $_.ToString('x2') }) } finally { $fs.Dispose() }
Out-Json @{ step = 'build'; ok = $true; seconds = $seconds; mb = [math]::Round((Get-Item $apk).Length / 1MB, 1); sha256_12 = $apkSha.Substring(0, 12) }

# 6. 覆盖安装（不卸载）并启动
& $adb -s $serial shell am force-stop $package 2>&1 | Out-Null
$inst = (& $adb -s $serial install -r -d -t $apk 2>&1 | Out-String)
$ok = $inst -match 'Success'
$code = if ($ok) { $null } elseif ($inst -match '(INSTALL_[A-Z_]+)') { $Matches[1] } else { 'unknown' }
Out-Json @{ step = 'install'; ok = $ok; error = $code }
if (-not $ok) {
    if ($code -eq 'INSTALL_FAILED_UPDATE_INCOMPATIBLE') { Out-Json @{ step = 'install'; note = 'signature_differs_not_uninstalling' } }
    exit 7
}
& $adb -s $serial shell monkey -p $package -c android.intent.category.LAUNCHER 1 2>&1 | Out-Null
$ver = (& $adb -s $serial shell dumpsys package $package 2>$null | Select-String 'versionName=' | Select-Object -First 1)
Out-Json @{ step = 'launch'; ok = $true; version = ("$ver".Trim() -replace '^.*versionName=', '') }
Remove-Item -Recurse -Force $logDir -ErrorAction SilentlyContinue
Out-Json @{ step = 'done'; ok = $true }
