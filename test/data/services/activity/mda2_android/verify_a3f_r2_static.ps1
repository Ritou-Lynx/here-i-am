param(
    [Parameter(Mandatory = $true)][string]$BaseCommit,
    [string]$CandidateCommit = 'HEAD',
    [switch]$WorkingTree
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))
Push-Location $repo
try {
    $base = (& git rev-parse "$BaseCommit`^{commit}").Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Invalid base commit.' }
    if ($WorkingTree) {
        $changed = @(& git diff --name-only $base)
        $changed += @(& git ls-files --others --exclude-standard)
        $candidate = 'WORKING_TREE'
    } else {
        $candidate = (& git rev-parse "$CandidateCommit`^{commit}").Trim()
        if ($LASTEXITCODE -ne 0) { throw 'Invalid candidate commit.' }
        & git merge-base --is-ancestor $base $candidate
        if ($LASTEXITCODE -ne 0) { throw 'Candidate does not descend from base.' }
        $changed = @(& git diff --name-only $base $candidate)
    }
    $changed = @($changed | Where-Object { $_ } | Sort-Object -Unique)
    $allowed = @(
        '^android/app/src/main/kotlin/com/memexlab/memex/activity/(ActivityObservationForegroundService|ActivityStartupConfirmation)\.kt$',
        '^android/app/src/main/kotlin/com/memexlab/memex/channels/ActivitySignalChannelHandler\.kt$',
        '^android/app/src/test/kotlin/com/memexlab/memex/activity/ActivityStartup(Confirmation|ServiceIntegration)Test\.kt$',
        '^test/data/services/activity/mda2_android/verify_a3(_android|f_r2_static)\.ps1$',
        '^docs/development/activity/mda2/android/a3f_r2/HANDOFF\.md$'
    )
    $outside = @($changed | Where-Object { $path = $_; -not ($allowed | Where-Object { $path -match $_ }) })
    if (!$changed.Count -or $outside.Count) { throw "R2 scope violation: $($outside -join ', ')" }
    $protected = @('android/app/src/main/AndroidManifest.xml','android/app/build.gradle.kts','android/settings.gradle.kts','pubspec.yaml','pubspec.lock','lib/data/services/activity/mda2_android/file_activity_outbox_store.dart','lib/main.dart','lib/config','lib/routing','lib/db','tools/i_core','DEVLOG.md','docs/development/I_PROJECT_STATE.md','docs/companion-first/PRODUCT_ROADMAP.md')
    if ($WorkingTree) { & git diff --quiet $base -- $protected } else { & git diff --quiet $base $candidate -- $protected }
    if ($LASTEXITCODE -ne 0) { throw 'R2 changed a protected dependency, manifest, shared storage, wire/Core or global state path.' }
    function Read-Candidate([string]$Path) {
        if ($WorkingTree) { return Get-Content -Raw -LiteralPath $Path }
        return (@(& git show "$candidate`:$Path") -join "`n")
    }
    $native = 'android/app/src/main/kotlin/com/memexlab/memex/activity/'
    $service = Read-Candidate ($native + 'ActivityObservationForegroundService.kt')
    $startup = Read-Candidate ($native + 'ActivityStartupConfirmation.kt')
    $channel = Read-Candidate 'android/app/src/main/kotlin/com/memexlab/memex/channels/ActivitySignalChannelHandler.kt'
    if ($service -notmatch 'SystemClock.elapsedRealtime' -or $service -notmatch 'FOREGROUND_SERVICE_IMMEDIATE' -or $service -notmatch 'scheduleStartupConfirmation' -or $service -notmatch 'startup.isActive\(requestToken, service.serviceInstanceId\)') { throw 'R2 asynchronous confirmation or dispatch fence missing.' }
    if ($service -match 'Thread.sleep|context.stopService|BleHeartRateService|CompanionForegroundTask|CheckinService|BOOT_COMPLETED|START_STICKY|WorkManager|AlarmManager') { throw 'Forbidden blocking or lifecycle coupling.' }
    if ($startup -notmatch 'attempt.owner != owner' -or $startup -notmatch 'attempt.answered' -or $channel -notmatch 'startupReplies.invalidate\(detach = true\)') { throw 'R2 instance or callback fence missing.' }
    if ($channel -match '"packageName"|"appName"|"rawUsageEvents"|java.net|okhttp') { throw 'Private/native or transport data entered bridge.' }
    Write-Output "STATIC_A3F_R2_OK base=$base candidate=$candidate changed_paths=$($changed.Count) protected_diff=0 privacy=pass"
} finally { Pop-Location }
