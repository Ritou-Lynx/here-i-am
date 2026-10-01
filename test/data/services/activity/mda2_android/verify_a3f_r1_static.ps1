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
        '^android/app/src/main/kotlin/com/memexlab/memex/activity/(ActivityDeliveryLedger|ActivityObservationForegroundService|ActivityPermissionEpochStore|ActivityUsageEventSource|ActivitySignalPolicy|AndroidActivitySignalCollector)\.kt$',
        '^android/app/src/main/kotlin/com/memexlab/memex/channels/ActivitySignalChannelHandler\.kt$',
        '^android/app/src/test/kotlin/com/memexlab/memex/activity/[^/]+\.kt$',
        '^lib/data/services/activity/mda2_android/android_activity_(collector|normalizer|signal_platform)\.dart$',
        '^lib/ui/a3d_device_gate/a3d_device_gate_(controller|screen)\.dart$',
        '^test/data/services/activity/mda2_android/[^/]+\.(dart|ps1)$',
        '^docs/development/activity/mda2/android/a3f_r1/HANDOFF\.md$'
    )
    $outside = @($changed | Where-Object { $path = $_; -not ($allowed | Where-Object { $path -match $_ }) })
    if (!$changed.Count -or $outside.Count) { throw "R1 scope violation: $($outside -join ', ')" }
    $protected = @('android/app/src/main/AndroidManifest.xml','android/app/build.gradle.kts','android/settings.gradle.kts','pubspec.yaml','pubspec.lock','lib/data/services/activity/mda2_android/file_activity_outbox_store.dart','lib/main.dart','lib/config','lib/routing','lib/db','tools/i_core','DEVLOG.md','docs/development/I_PROJECT_STATE.md','docs/companion-first/PRODUCT_ROADMAP.md')
    if ($WorkingTree) { & git diff --quiet $base -- $protected } else { & git diff --quiet $base $candidate -- $protected }
    if ($LASTEXITCODE -ne 0) { throw 'R1 changed a protected dependency, manifest, shared storage, wire/Core or global state path.' }
    function Read-Candidate([string]$Path) {
        if ($WorkingTree) { return Get-Content -Raw -LiteralPath $Path }
        return (@(& git show "$candidate`:$Path") -join "`n")
    }
    $native = 'android/app/src/main/kotlin/com/memexlab/memex/activity/'
    $epoch = Read-Candidate ($native + 'ActivityPermissionEpochStore.kt')
    if ($epoch -match 'val start = .*sealedThroughMs' -or $epoch -notmatch 'evidence.observedAtMs - ACTIVITY_RESCAN_AGE_MS') { throw 'Query progress still excludes the eligible live-epoch tail.' }
    $service = Read-Candidate ($native + 'ActivityObservationForegroundService.kt')
    if ($service -match 'pendingScreenSignals.clear' -or $service -notmatch 'deliveryAllowed\(permit.epochId\)' -or $service -notmatch 'delivery.acknowledge' -or $service -notmatch 'return emptyQuery\(decision.fixedCode') { throw 'Native delivery fence/ACK/readiness contract missing.' }
    if ($service -match 'BleHeartRateService|CompanionForegroundTask|CheckinService|BOOT_COMPLETED|START_STICKY|WorkManager|AlarmManager') { throw 'Forbidden lifecycle coupling.' }
    $ledger = Read-Candidate ($native + 'ActivityDeliveryLedger.kt')
    if ($ledger -notmatch 'epoch != batchEpoch' -or $ledger -notmatch 'current.id != batchId' -or $ledger -notmatch 'disposition != "retry"') { throw 'Epoch-bound terminal acknowledgement required.' }
    $dart = Read-Candidate 'lib/data/services/activity/mda2_android/android_activity_signal_platform.dart'
    if ($dart -match 'packageName|appName|rawUsageEvents|package:(http|dio|web_socket_channel)') { throw 'Private/native or network data entered delivery.' }
    $controller = Read-Candidate 'lib/ui/a3d_device_gate/a3d_device_gate_controller.dart'
    if ($controller -notmatch "'publication_completeness': 'unknown'" -or $controller -notmatch '_collector\?\.status \?\? _collectorStatus') { throw 'Live evidence/completeness separation missing.' }
    Write-Output "STATIC_A3F_R1_OK base=$base candidate=$candidate changed_paths=$($changed.Count) protected_diff=0 privacy=pass"
} finally { Pop-Location }
