param(
    [Parameter(Mandatory = $true)][string]$FlutterSdk,
    [Parameter(Mandatory = $true)][string]$AndroidSdk,
    [Parameter(Mandatory = $true)][string]$Gradle,
    [Parameter(Mandatory = $true)][string]$JavaHome,
    [switch]$ReuseHarness,
    [string]$VerificationRoot
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))
$scratchRoot = if ($VerificationRoot) { [IO.Path]::GetFullPath($VerificationRoot) } else { [IO.Path]::GetFullPath($PSScriptRoot) }
$harness = [IO.Path]::GetFullPath((Join-Path $scratchRoot '.verification_android'))
$android = Join-Path $harness 'android'
if (!$harness.StartsWith($scratchRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Android verification scratch escaped its owned test directory.'
}
if (!(Test-Path -LiteralPath $Gradle)) { throw 'An existing Gradle installation is required.' }
if (!(Test-Path -LiteralPath $FlutterSdk)) { throw 'An existing Flutter SDK is required.' }
if (!(Test-Path -LiteralPath $AndroidSdk)) { throw 'An existing Android SDK is required.' }
if (!(Test-Path -LiteralPath (Join-Path $JavaHome 'bin/java.exe'))) { throw 'An existing JDK is required.' }
$flutterJar = [IO.Path]::GetFullPath((Join-Path $FlutterSdk 'bin/cache/artifacts/engine/android-x64/flutter.jar'))
if (!(Test-Path -LiteralPath $flutterJar)) { throw 'An existing Flutter Android embedding jar is required.' }

if ((Test-Path -LiteralPath $harness) -and !$ReuseHarness) { Remove-Item -LiteralPath $harness -Recurse -Force }
New-Item -ItemType Directory -Path (Join-Path $android 'app/src/main/kotlin') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $android 'app/src/test/kotlin') -Force | Out-Null
$utf8NoBom = New-Object Text.UTF8Encoding($false)
$flutterPath = [IO.Path]::GetFullPath($FlutterSdk).Replace('\', '/')
$androidPath = [IO.Path]::GetFullPath($AndroidSdk).Replace('\', '/')
$flutterJarPath = $flutterJar.Replace('\', '/')

[IO.File]::WriteAllText((Join-Path $android 'local.properties'), "flutter.sdk=$flutterPath`nsdk.dir=$androidPath`n", $utf8NoBom)
[IO.File]::WriteAllText((Join-Path $android 'settings.gradle.kts'), @'
pluginManagement {
    repositories { google(); mavenCentral(); gradlePluginPortal() }
}
plugins {
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { google(); mavenCentral() }
}
rootProject.name = "mda2-a3-android-verification"
include(":app")
'@, $utf8NoBom)
[IO.File]::WriteAllText((Join-Path $android 'build.gradle.kts'), @'
plugins {
    id("com.android.application") apply false
    id("org.jetbrains.kotlin.android") apply false
}
'@, $utf8NoBom)
$appGradle = @"
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}
android {
    namespace = "com.memexlab.memex"
    compileSdk = 36
    defaultConfig { minSdk = 26 }
    flavorDimensions += "market"
    productFlavors {
        create("hereIAmV3") { dimension = "market" }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = JavaVersion.VERSION_17.toString() }
    testOptions.unitTests.all {
        it.systemProperty("activity.service.source", file("src/main/kotlin/com/memexlab/memex/activity/ActivityObservationForegroundService.kt").absolutePath)
        it.systemProperty("activity.channel.source", file("src/main/kotlin/com/memexlab/memex/channels/ActivitySignalChannelHandler.kt").absolutePath)
    }
}
dependencies {
    implementation(files("$flutterJarPath"))
    testImplementation("junit:junit:4.13.2")
}
"@
New-Item -ItemType Directory -Path (Join-Path $android 'app') -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $android 'app/build.gradle.kts'), $appGradle, $utf8NoBom)
New-Item -ItemType Directory -Path (Join-Path $android 'app/src/main') -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $android 'app/src/main/AndroidManifest.xml'), '<manifest xmlns:android="http://schemas.android.com/apk/res/android" />', $utf8NoBom)

$owned = @(
    'app/src/main/kotlin/com/memexlab/memex/activity/ActivityStartupConfirmation.kt',
    'app/src/main/kotlin/com/memexlab/memex/activity/ActivityObservationControlState.kt',
    'app/src/test/kotlin/com/memexlab/memex/activity/ActivityObservationControlStateTest.kt',
    'app/src/test/kotlin/com/memexlab/memex/activity/ActivityStartupConfirmationTest.kt',
    'app/src/main/kotlin/com/memexlab/memex/activity/ActivitySignalPolicy.kt',
    'app/src/main/kotlin/com/memexlab/memex/activity/ActivityDeliveryLedger.kt',
    'app/src/test/kotlin/com/memexlab/memex/activity/ActivityDeliveryLedgerTest.kt',
    'app/src/test/kotlin/com/memexlab/memex/activity/LatePublicationTest.kt',
    'app/src/test/kotlin/com/memexlab/memex/activity/ActivityStartupServiceIntegrationTest.kt',
    'app/src/main/kotlin/com/memexlab/memex/activity/AndroidActivitySignalCollector.kt',
    'app/src/main/kotlin/com/memexlab/memex/activity/ActivityUsageEventSource.kt',
    'app/src/main/kotlin/com/memexlab/memex/activity/ActivityPermissionEpochStore.kt',
    'app/src/main/kotlin/com/memexlab/memex/activity/ActivityObservationForegroundService.kt',
    'app/src/main/kotlin/com/memexlab/memex/channels/ActivitySignalChannelHandler.kt',
    'app/src/test/kotlin/com/memexlab/memex/activity/ActivitySignalPolicyTest.kt',
    'app/src/test/kotlin/com/memexlab/memex/activity/ActivityPermissionEpochAuthorityTest.kt'
)
foreach ($relative in $owned) {
    $source = Join-Path (Join-Path $repo 'android') $relative
    $destination = Join-Path (Join-Path $android 'app') $relative.Substring(4)
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination
}

$priorJavaHome = $env:JAVA_HOME
try {
    $env:JAVA_HOME = [IO.Path]::GetFullPath($JavaHome)
    & $Gradle -p $android testHereIAmV3DebugUnitTest --tests 'com.memexlab.memex.activity.*' --offline --no-daemon --console plain
    if ($LASTEXITCODE -ne 0) { throw 'A3 Android unit tests failed.' }
} finally {
    $env:JAVA_HOME = $priorJavaHome
}

foreach ($relative in $owned) {
    $original = (Get-FileHash -LiteralPath (Join-Path (Join-Path $repo 'android') $relative) -Algorithm SHA256).Hash
    $mirror = (Get-FileHash -LiteralPath (Join-Path (Join-Path $android 'app') $relative.Substring(4)) -Algorithm SHA256).Hash
    if ($original -ne $mirror) { throw "Android test mirror drift: $relative" }
}
Write-Output 'Verified isolated hereIAmV3Debug Android source set matches all tested A3 Kotlin files byte for byte.'
