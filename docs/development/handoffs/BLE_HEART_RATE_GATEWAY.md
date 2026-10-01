# BLE Heart Rate Gateway — P1/P2 handoff

## Integration identity

- Goal: `GOAL-20260829-ble-heart-rate-gateway`
- Work packages: P1 native Android HRS gateway; P2 Flutter gateway, device settings, and Health surface
- Branch: `codex/ble-heart-rate-gateway`
- Worktree: `.worktrees/ble-heart-rate-gateway`
- Baseline: `30a73ce3625a01b75ebb6076628a24908452cade`
- Commit: the commit containing this handoff

## Implemented support

- A dedicated Android `connectedDevice` foreground service owns the selected device's GATT connection, HRS discovery, 0x2A37 subscription, reconnect policy, and persistence. It does not share the media/microphone `flutter_foreground_task` service and does not control the global Bluetooth adapter.
- Scanning is HRS-filtered (0x180D), lasts 3–20 seconds, starts only from the settings page after an explicit tap, and never connects to scan results automatically. Selection is app-local and does not call `createBond()`.
- The parser accepts 8-bit and 16-bit BPM, contact support/status with SIG bit semantics, optional energy, and every optional RR interval in 1/1024-second units. Zero BPM, missing fields, invalid RR length, and unexpected bytes are rejected rather than promoted to samples.
- Samples receive phone timestamps. UI/native snapshots distinguish unconfigured, stopped, connecting, live, stale, reconnecting, disconnected, permission denied, Bluetooth off, unsupported, malformed data, and service-start denial reasons.
- Reconnect uses bounded delays of 2, 5, 15, 30, 60, then 300 seconds. A generation-bound 25-second connection/discovery/first-sample watchdog prevents stuck connects. A sample is shown stale after 15 seconds and its GATT is recycled after 60 seconds without a sample.
- `START_STICKY`, Bluetooth state recovery, boot recovery, foreground-start denial reporting, GATT generation guards, and device-switch teardown are implemented. Notification BPM updates are limited to about once per 60 seconds while state changes remain immediate.
- Configuration and snapshots are user-isolated in app-private preferences using a SHA-256-derived local user key. Samples and gap/status events are append-only JSONL at `files/ble_heart_rate/<user-key>/YYYY-MM-DD.jsonl`, daily rotated and retained for 14 days.
- Sample I/O is ordered on one lazy executor, buffered, flushed about every 7 seconds, and drained on service destruction. Snapshot persistence is limited to about once per 30 seconds for stable samples; first/forced writes and state transitions remain immediate, and wall-clock rollback starts a fresh persistence window. Realtime EventChannel delivery is not delayed by persistence.
- Flutter exposes only snapshot/platform state, permission request, settings opens, filtered scan, select/enable, stop, forget, and recent diagnostics. Non-Android implementations are safe no-ops/empty streams.
- Personal Center → 设备与连接 includes “实时心率设备”. The Health panel begins with a tappable realtime card showing the actual connection state, last sample, and whether RR has ever appeared.

## Verification completed

- `flutter test test/data/services/ble_heart_rate_gateway_test.dart test/ui/companion/live_heart_rate_card_test.dart test/ui/settings/widgets/heart_rate_device_settings_page_test.dart` — passed, 6 tests.
- `flutter test test/ui/settings/widgets/personal_center_screen_test.dart --plain-name "device connections exposes the realtime HRS entry"` — passed, 1 test.
- `flutter analyze` on the new gateway, settings page, realtime card, Personal Center entry, and their tests — no issues.
- Including the touched legacy `companion_health_panel.dart` in analysis reports 11 pre-existing warnings in old, unchanged regions; the new Health-card integration reports no new issue.
- `gradle -p android testHereIAmV3DebugUnitTest --tests com.memexlab.memex.ble.HeartRateMeasurementParserTest` — passed and includes `compileHereIAmV3DebugKotlin` for hereIAmV3 Debug.
- 2026-09-10 closeout rerun: current `compileHereIAmV3DebugKotlin` and all BLE Kotlin tests passed (`50/50`, zero failures/errors/skips). The repository's dynamic AndroidX test metadata could not be resolved online, so this focused rerun used an uncommitted temporary init script to pin already cached test-only versions; it is not a full APK or production dependency-graph Gate.
- `powershell -File scripts/verify_critical_fixes.ps1` — all three guards passed.
- No full APK build, install, release, or push was performed by this work package.

## Shared contract impact

- Adds two platform channel names: `com.memexlab.memex/ble_heart_rate` and `com.memexlab.memex/ble_heart_rate_events`.
- Adds Android foreground service type permission `FOREGROUND_SERVICE_CONNECTED_DEVICE`, one non-exported service, one boot receiver, and JUnit 4 for local Android unit tests.
- Reuses the repository's existing Bluetooth scan/connect and pre-Android-12 location declarations; it adds no raw-device permission, no new location permission, no Drift table, and no Memory/SharedLife/Facts write.
- Existing `flutter_blue_plus` consumers remain independent; the native gateway neither closes their GATT objects nor changes adapter state.

## Hardware validation and known limits

- Android only. iOS/desktop return an unsupported/empty safe state.
- Standard HRS advertising and 0x2A37 are required. COROS app/cloud, legacy HealthService, Samsung Wear, proprietary services, and OS pairing are deliberately out of scope.
- COROS hardware validation completed on Samsung `SM-S9110`: standard HRS discovery, live BPM, screen-off background collection, Bluetooth off/on, process/reboot recovery under the required unrestricted/never-sleep setting, off-wrist gap recording, deep-Doze watchdog wakeup/recovery, and wearable comfort all passed.
- Exact candidate SHA-256 `3056968EA16D10245B7AD4A40B81CF7124C8A4B64B95798E235E6AA201E761D4` passed the natural-wear unplugged eight-hour window `2026-09-10 00:30:44.302–08:30:44.302`: 28,870 samples, maximum gap 4.872 seconds, zero gaps above 15 seconds, and zero status/gap records. This closes v1 continuity, not product battery acceptance.
- Samsung task removal can still trigger MARs to force-stop the whole package. The v1 operating prerequisite is to keep Here I am unrestricted and in Samsung's never-sleep list and not swipe away its task; durable recovery from that OEM force-stop is follow-up work.
- Notification denial is reported separately. Android may keep the service running while hiding its visible notification, subject to OS/OEM behavior.
- The eight-hour BatteryStats level fell from 92% to 36%. That is whole-phone load and cannot be attributed solely to BLE; product battery budget and gateway cost decomposition remain follow-up work.
- The observed COROS stream provides BPM only; RR/contact/energy were not observed. BPM alone is not sleep/wake, anxiety, off-wrist, or medical evidence.
- Raw JSONL remains an app-private 14-day buffer. The confirmed local one-year Health Vault, export/sync, expiry deletion, and read-only MCP are a separate unimplemented Goal.
- Non-blocking P2: malformed measurements before the first valid sample set `malformedData`; the current connect watchdog does not classify that status as an active-attempt timeout. A later valid callback still restores `live`; hardening this rare no-valid-callback case requires a new APK and fresh Gate.
