# MDA-0 Device Capability & Hardware Baseline (proposed evidence)

> Status: **proposed baseline, not an approved shared contract**
> Scope owner: M0-P1 only; no production schema, ingress, topology, retention, or device state is approved here.
> Repository baseline examined: `7fa6cbb9e44fe1771aae44c579d5e3a2f9e393f1` (2026-08-29).
> Design input examined but not in this worktree Git baseline: `D:/memex/docs/companion-first/MULTI_DEVICE_ACTIVITY_ROADMAP.md`.

## Reading rules

| Label | Meaning |
|---|---|
| **Implemented** | Code or a committed handoff exists in this repository. It is not a physical-device claim. |
| **Officially possible** | A first-party platform document exposes a relevant API or system automation. It has no repository implementation and requires a later approved design. |
| **Unknown / hardware gate** | Requires the named target device and the listed manual observation. No test or software build substitutes for it. |
| **Unsupported in this MVP** | No supported path in the current product scope. It must remain unavailable rather than inferred. |

All activity evidence must retain its own source and freshness. `network.present`, Core `/health`, a Tailscale peer, an app foreground heartbeat, a silent interval without proven continuous coverage, no reply, and one heart-rate stream are **not** evidence that a person is awake, quiet, asleep, or medically well. They can only produce the explicitly stated low-information/`unknown` result.

## Cross-device evidence matrix

| Endpoint | Current evidence status | Allowed signal categories (not an event-schema approval) | `coverage_mode` | TTL / SLO evidence | Explicitly unknown or unsupported | Human gate |
|---|---|---|---|---|---|---|
| Private Windows | **Officially possible**, no activity-probe code found | session change; idle bucket; suspend/resume; probe heartbeat | Proposed `continuous` only while a later probe can prove its whole coverage window; session-scoped idle only | **TBD**. Roadmap suggests a 15–30 s idle sample; no implementation/SLO evidence | Window title, process name, keystrokes, screen content; all real probe coverage; Core availability during sleep/logout/shutdown | Required: lock/unlock, input, long reading/no input, video, suspend/resume, network loss, probe restart |
| Main Android | Usage query and Android BLE HRS are **implemented**; continuous activity collector is not | on-demand usage aggregate; app foreground heartbeat; proposed screen/user-present + UsageEvents; BLE HRS quality | Usage query/heartbeat: `discrete_best_effort` / `heartbeat_only`, never negative coverage. BLE quality may declare `continuous` only after the COROS hardware Gate proves the stated window | BLE: stale after 15 s, reconnect after 60 s without sample (implemented). All activity collector TTL/SLO **TBD** | App heartbeat ≠ device interaction; continuous screen/unlock/UsageEvents coverage; remote activity ingress | Required: grant/revoke Usage Access, screen/lock test, task swipe/reboot/Doze, Core loss, BLE coexistence |
| Second Android | **Officially possible / proposed only** (Tasker first)。真机为 Xiaomi 2203121C / Android 15；Lynx 已安装 Tasker 6.6.20，但未配置 profile。完整 Here I am 已预先存在且未运行，是目标边界冲突，不作为探针 | future user-configured screen, unlock, charging, selected local app category, probe heartbeat；当前只完成系统锁定/解锁与充电重连快照 | `discrete_best_effort`；当前无事件/receipt/outbox，故远端仍 `unsupported / unknown` | **TBD**；Tasker 通知、Usage Access、device-idle whitelist、Accessibility/notification listener 均未就绪，无 delivery SLO | Full Here I am、数据库复制、可靠 backfill、连续负向证据；预装完整 App 不扩大允许范围 | Required: 另行批准 profile/权限/小米后台策略后，验证 offline/retry、独立 token revoke；MDA-0 不配置 |
| iPhone (no app) | **Officially possible only** through user-configured Shortcuts; no implementation | Sleep Focus, charge/uncharge, and only target-iPhone-confirmed discrete triggers | `discrete_best_effort`; each successful automation proves only itself | **TBD**. No assumed background delivery or continuous coverage | General screen-on/off, lock/unlock, device-unlock, or continuous foreground-app stream; webhook until chosen ingress passes Gate | Required: choose safe ingress, configure each trigger, prove HTTPS, bad token, replay, revoke and disabled trigger behavior |
| COROS optical HR band | Android receiver is **implemented**；真机已部分证明 `COROS 光学心率臂带（设备标识仅保留本机）` 可按标准 HRS `0x180D` 被发现、选择并提供 BPM，但整套硬件 Gate 未完成 | 目前只有 BPM 与连接/freshness；历史样本未出现 contact supported、energy 或 RR | 19:54 历史候选已通过正式 30 分钟、蓝牙切换与后台豁免重启；任务移除/MARs 与普通 relaunch 仍失败。23:14 新候选完成整夜锁屏耐久与故障自动恢复，但严格连续性失败；不能宣告 `continuous` | 正式 8 小时：28,494 samples，1 个 363.156 s gap；full Doze 将 25 s Handler watchdog 延迟约 321 s。隔离 B–A–B 工程复现通过：B1/A/B2=`254.7/131.8/211.2 mAh/h`，B 平均相对 A 高约 `101.1 mAh/h` | 最终同哈希零大 gap 8 小时、gateway 内部耗电分解与产品预算、确切离腕→复戴 stall、Service/Handler/GATT 集成覆盖、MARs/relaunch、默认/回退后台自愈与 stale snapshot 纠正、sleep inference | Required: 保留整夜耐久/恢复 PASS 与严格连续性 FAIL 的拆分；B–A–B 只证明 gateway 相关整机增量工程可复现，B2 跨小版本且不可写成纯射频功耗或预算 PASS。以最终候选重跑零 gap 8 小时；保留 MARs 与集成测试 P2 |

## Evidence boundaries shared by every endpoint

- The current Core has pairing/chat/change-feed/cursor acknowledgement, not an activity domain, activity scope, probe revoke API, presence API, or activity retention policy. `capabilities_json` is registry metadata, not server-enforced scope. See [`i_core_store.mjs`](../../../../tools/i_core/i_core_store.mjs#L161-L201), [`i_core_server.mjs`](../../../../tools/i_core/i_core_server.mjs#L63-L158), and [`i core README`](../../../../tools/i_core/README.md#L1-L11).
- A later activity design must separately establish device/probe binding, permissions, receive-time ownership, epoch/fencing, retention and delete semantics. This baseline records the blocker only; it does not supply that shared contract.
- Main Android is the only installed full product endpoint. Windows, second Android and iPhone must not receive the complete app, its database, chat, Memory V3, User-truth or Core read access.
- Signal time belongs to the producing device; arrival time belongs to the eventual receiver/Core. Until that receiver exists, no current feature has a cross-device receipt time.

## Windows — private computer light probe

| Area | Baseline and evidence | Permission / responsibility | Stop or revoke | Failure / privacy downgrade |
|---|---|---|---|---|
| Session change | **Officially possible.** `WTSRegisterSessionNotification` registers a window for `WM_WTSSESSION_CHANGE`; a matching unregister is required before destruction. [Microsoft documentation](https://learn.microsoft.com/en-us/windows/win32/api/wtsapi32/nf-wtsapi32-wtsregistersessionnotification) | Proposed user-session probe; session notification is generated locally. No repo collector exists. | Future per-probe disable/uninstall must unregister and erase its local queue; Core-side revoke is a shared-contract blocker. | Remote Desktop Services can be unavailable at registration; record probe error/`unknown`, not a session state. Do not collect window/process names. |
| Input idle | **Officially possible.** `GetLastInputInfo` returns the last input time only for the calling session; its tick count is not guaranteed monotonic. [Microsoft documentation](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getlastinputinfo) | No elevated permission identified for a user-session API; capability is session-scoped, not all sessions. Bucket locally rather than send input. | Disable sampling / exit probe; no collector currently exists. | Treat clock/tick anomalies, session mismatch, sleep and probe silence as `unknown`. Long reading/video can be idle while the user is awake. |
| Power and heartbeat | **Proposed only.** Roadmap calls for suspend/resume and low-rate probe health. Existing Core runs on the same Windows computer and defaults to loopback. [iCore README](../../../../tools/i_core/README.md#L30-L40) | Future probe owns its own lifecycle; Core health/network only prove transport availability. | Disable the probe independently of iCore; no planned task or service is created by this document. | Logout, sleep, shutdown, Core crash, network loss or heartbeat loss yield `unknown`; never “quiet” or “asleep.” |

**Windows manual record fields:** device/probe version; Windows build; local time + monotonic elapsed time; signal observed time; receiver time if later implemented; lock/unlock result; idle bucket only (not keys); power transition; probe state/error; network/Core state separately; coverage start/end; disable result; tester verdict.

## Main Android — full Companion and local BLE receiver

| Area | Implemented repository evidence | Required permission / responsible time | Stop or revoke | Failure / privacy downgrade |
|---|---|---|---|---|
| Usage summary | `PhoneUsageService` is Android-only and calls `queryUsageStats`; it returns per-package aggregate foreground duration and `lastTimeUsed`, on demand. [`phone_usage_service.dart`](../../../../lib/data/services/phone_usage_service.dart#L54-L103), [`PhoneUsageChannelHandler.kt`](../../../../android/app/src/main/kotlin/com/memexlab/memex/channels/PhoneUsageChannelHandler.kt#L66-L108) | Special Usage Access AppOp; code sends the user to settings and checks it. Signal time is the queried OS aggregate; no receiving-time/Core activity event exists. | Revoke Usage Access in system settings; later collector must offer its own pause/delete. | Permission denial/query error/no query is `unknown`. Existing code exposes package/app names to the requesting feature; no activity design is approved to upload them—future path must categorize locally. |
| Foreground heartbeat | The app marks foreground at Android startup; existing check-in timing is a service heartbeat gate, not an activity collector. [`main.dart`](../../../../lib/main.dart#L197-L207), [`checkin_service.dart`](../../../../lib/data/services/checkin_service.dart#L465-L488) | No person-interaction permission. Timestamp belongs to the app locally. | Existing app lifecycle only; later activity pause is not implemented. | `hereiam.foreground` means this app was foregrounded, **not** unlocked/interactive/awake; silence is not sleep. |
| Screen/unlock and UsageEvents | **Officially possible / future only.** Android offers `UsageStatsManager`; Roadmap requires dynamic screen/user-present monitoring and query-events catch-up. [Android API reference](https://developer.android.com/reference/android/app/usage/UsageStatsManager) | Usage Access for usage statistics; concrete receiver/export/background behavior and target Android version remain design work. | Must expose collector pause and system permission revoke; neither exists today. | OEM kill, Doze, receiver loss, missing permission or a coverage gap = `unknown`, not `quiet_observed`. |
| BLE HRS | Dedicated Android `connectedDevice` foreground service uses `0x180D` and `0x2A37`, has bounded reconnect and local status. [`BleHeartRateService.kt`](../../../../android/app/src/main/kotlin/com/memexlab/memex/ble/BleHeartRateService.kt#L31-L76), [`BLE handoff`](../../handoffs/BLE_HEART_RATE_GATEWAY.md#L7-L25) | Android 12+ `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT`; connected-device FGS and notification state are declared. [`AndroidManifest.xml`](../../../../android/app/src/main/AndroidManifest.xml#L22-L55) Signal time is phone receipt time. | Settings can stop or forget; service handles `ACTION_STOP`/`ACTION_FORGET`. [`BleHeartRateService.kt`](../../../../android/app/src/main/kotlin/com/memexlab/memex/ble/BleHeartRateService.kt#L148-L166) | Explicit status includes permission denied, Bluetooth off, stale, disconnect and malformed data. No sample becomes no sleep conclusion. Keep raw samples app-private; no cross-device BPM export is approved. |

Android foreground services have platform launch/type restrictions; the API’s existence does not promise OEM survival. [Android FGS overview](https://developer.android.com/develop/background-work/services/fgs). The implemented HRS thresholds are only receiver freshness behavior: stale after 15 s, reconnect after 60 s. [`BleHeartRateService.kt`](../../../../android/app/src/main/kotlin/com/memexlab/memex/ble/BleHeartRateService.kt#L94-L109)

**Main-Android manual record fields:** model/OEM/Android build; app commit/APK identity; Usage Access and Bluetooth/notification/FGS states; local signal time; HRS status/reason/last-sample age; screen/lock test result if future collector is installed; coverage start/end; app kill/reboot/Doze result; no raw app title, notification body or BPM in shared activity test records.

Current real-device observations are recorded separately in [`MULTI_DEVICE_REAL_DEVICE_RECORD.md`](MULTI_DEVICE_REAL_DEVICE_RECORD.md); they are read-only snapshots, not proof of a production collector or continuous coverage.

## Second Android — minimum probe, Tasker first

| Area | Status | Required permission / responsibility | Stop or revoke | Failure / privacy downgrade |
|---|---|---|---|---|
| Tasker profiles | **Proposed only.** No Tasker profile, APK, token or ingress exists in this repository. The selected initial concept is user-configured screen/unlock/charging and local app category, not the full app. | Each Android/Tasker permission and battery exemption is a manual Gate. A future probe alone creates signal time; receiver time needs later ingress. | Disable profile/task; revoke its future independent write-only credential. | Any missed/delayed automation, low battery, network error, killed Tasker or absent outbox is `unknown`. |
| Sidecar APK | **Unsupported unless a later Goal approves it after Tasker failure.** | Would require Android runtime/special permissions and a separate design. | Uninstall plus later credential/data removal. | Do not silently widen scope or copy the primary database. |

Privacy minimum: convert an allowed local app to a user-approved category before any eventual upload; no package/app name, content, keys, screen, notification or chat data. A heartbeat proves only a completed post, never continuous observation.

**Second-Android manual record fields:** device/OEM/OS; Tasker version/profile identifier (not secret); exact enabled triggers; required-permission/battery states; intended category only; local trigger time; request outcome/error; offline interval; manual disable/re-enable; independent token revoke outcome once available; coverage remains `discrete_best_effort`.

## iPhone — Shortcuts, no self-developed app

| Area | Status / first-party boundary | Permission / responsibility | Stop or revoke | Failure / privacy downgrade |
|---|---|---|---|---|
| Shortcuts triggers | **Officially possible only.** Apple documents automation trigger configuration; actual offerings vary by target iOS. [Apple Shortcuts triggers](https://support.apple.com/en-au/guide/shortcuts/apde31e9638b/ios) | User configures each automation. Signal time is the automation’s local run; future receiver time is separate. | Disable/delete each automation. Future credential must be independently revocable. | A missing/non-automatic/unavailable trigger, failed automation or no network is `unknown`. Do not substitute another trigger. |
| HTTPS POST | **Officially possible only.** Shortcuts can request URL content; it is not a deployed project ingress. [Apple HTTP action](https://support.apple.com/en-gb/guide/shortcuts/apd58d46713f/ios) | User-configured HTTPS request; choose and test one safe ingress before any real token. | Remove shortcut action and revoke the future write key. | There is no approved URL/token/Tailscale/public relay in this baseline. Until HTTPS, bad-credential, replay and revocation tests pass, webhook is **unsupported**. |
| General activity / App flow | **Unsupported in this MVP.** No claim of generic screen-on/off, lock/unlock, unlock, or continuous foreground-app flow. A later Screen Time path would require an iOS app plus Apple’s Family Controls entitlement process. [Apple entitlement documentation](https://developer.apple.com/documentation/FamilyControls/requesting-the-family-controls-entitlement) | Not applicable to this no-app scope. | Not applicable. | Must remain `unknown`; an iPhone’s network presence or a successful Focus/charge automation cannot fill the gaps. |

Permitted candidate events are only target-device-proven Sleep Focus on/off and power connected/disconnected. Optional app-open/close can be listed only after the same iPhone proves it is available and reliable; upload a local category rather than an app name. Focus expresses user intent, not sleep.

**iPhone manual record fields:** iPhone model; iOS version; selected trigger name/category; whether it is configured to run automatically; local run time; protected ingress choice (not URL or secret); HTTP status/error; receiver time if later implemented; duplicate/replay/bad-token/revoke result; disable result; coverage = `discrete_best_effort`; tester verdict.

## COROS — physical HRS baseline

### What software currently supports

The Android gateway filters standard Heart Rate Service advertising (`0x180D`), subscribes to Heart Rate Measurement (`0x2A37`), parses 8/16-bit BPM, contact flags, optional energy and every optional RR interval, and stores a phone timestamp. [`BLE handoff`](../../handoffs/BLE_HEART_RATE_GATEWAY.md#L7-L25) The Flutter state surface separately reports unconfigured, permission denied, Bluetooth off, connecting, live, stale, reconnecting, disconnected, unsupported, malformed data and unknown. [`ble_heart_rate_gateway.dart`](../../../../lib/data/services/ble_heart_rate_gateway.dart#L6-L113)

This is an Android receiver capability, **not** proof that a COROS device advertises those UUIDs, supports broadcast mode, emits optional fields, reconnects after lock screen, or operates through a night. COROS cloud/app synchronization, private protocols, raw PPG, motion, sleep stages and offline backfill are outside this baseline.

### Required real-device procedure (do not mark passed here)

| Step | Lynx action | Record fields | Pass condition | Failure classification |
|---|---|---|---|---|
| 1. Identity | Record exact device/band/firmware and phone/APK identity; enable the device’s documented broadcast mode if it exists. | Model, firmware, band position, phone model/OS, app commit/APK. | Device is identifiable; no capability is assumed. | `unknown_hardware_mode` |
| 2. HRS field probe | In the existing V3 settings, explicitly scan/select; observe only the displayed standard-HRS results. | Scan timestamp, visible name/ID redacted as needed, selected/not found, service/characteristic result, first sample age. | `0x180D` + `0x2A37` observed and BPM samples arrive. | `unsupported_standard_hrs` or `unknown_scan_environment` |
| 3. Optional fields | Observe UI/diagnostic status while wearing and briefly removing/repositioning the band. | BPM present; contact supported/detected value; RR seen; energy present; malformed reason; gap timestamps. | Record facts only; no optional field is required to pass basic BPM. | `field_absent` (not a defect unless promised by hardware) |
| 4. Lock-screen precheck | Lock phone for 30 minutes with app UI hidden; do not interact except documented observation. | Start/end, sample age, stale/reconnect/disconnect reasons, foreground notification visibility, battery delta. | Samples remain fresh for the declared period, or all gaps/statuses are visible. | `background_continuity_unknown` |
| 5. Long run | One 8-hour lock-screen run on the same installed candidate. | Start/end, total gap count/duration, last sample age, status timeline, phone/band battery start/end, comfort. | Continuity is measured, not presumed; all gaps are explainable. | `overnight_gate_failed` / `unknown` |
| 6. Recovery | Separately test out-of-range, Bluetooth off/on, app process kill and device reboot. | Action time, expected/actual status, reconnect time, gap event, whether user reopened/enabled. | Recovery or its denial is exposed as status; no invented samples. | `recovery_failed` / `background_start_denied` / `unknown` |
| 7. Stop/delete | Use Stop then Forget from the existing UI and confirm no further connection attempt. | Action, resulting status, config forgotten, local diagnostic deletion observation. | Stop/forget is visible. It does not approve any future cross-device deletion semantics. | `local_stop_or_forget_failed` |

### COROS safety interpretation

- Fresh BPM or a lower/higher single BPM is **not** awake, resting, asleep, stressed, or a medical conclusion.
- `rrSeen == false`, absent contact, stale samples, device silence, or connection quality only identify receiver/hardware uncertainty.
- Only after a successful hardware Gate may a later approved contract expose *quality/freshness/gap*; it still must not export raw per-beat values by default or derive sleep from this source alone.

## Cross-endpoint close, revoke and minimum privacy checklist

| Endpoint | Current close path | Future activity-contract blocker | Minimum data allowed in manual baseline |
|---|---|---|---|
| Windows | No activity probe exists. Existing iCore scheduled-task uninstall is separate and must not be run for this task. | Independent probe disable, credential revoke, queue/event deletion and backup expiry. | signal category, time, idle bucket, error/coverage; no titles/keys/content. |
| Main Android | System Usage Access revoke; BLE Stop/Forget implemented. | Activity collector pause/delete, remote probe revoke and activity-data deletion. | readiness/status/gap/sample age; no raw BPM or app name in cross-device evidence. |
| Second Android | Disable Tasker profile (future). | Write-only credential revoke, device queue cleanup and deletion proof. | category and delivery result only. |
| iPhone | Disable/delete automation (future). | Write-only credential revoke, ingress deletion/replay protection. | chosen trigger category and delivery result only. |
| COROS | BLE Stop/Forget implemented on main Android. | Any shared activity projection/delete policy is separate; current samples are local receiver diagnostics. | model/firmware, HRS field presence, freshness/gaps, battery/comfort. |

## Open risks and blockers for the acceptance window

1. The Roadmap input is untracked in the main worktree, so it cannot by itself become a versioned/approved contract.
2. Windows’s iCore and prospective probe are co-located. Sleep, logout and shutdown make remote aggregation unavailable; topology selection belongs to M0-P3/user review.
3. iPhone has neither a chosen secure ingress nor a verified trigger set. It is currently `unsupported` for webhook delivery and `unknown` for activity between discrete automations.
4. COROS 的标准 HRS/BPM、历史候选恢复/30 分钟与真人舒适度证据保留。23:14 重连返修候选的正式 8 小时窗口产生 28,494 samples，证明锁屏耐久、本次故障自动恢复和跨日/显式缺口记录，但出现 363.156 秒真实 gap，故严格连续性失败。旧 retry 永久丢失未复现；新风险是 25 秒 Handler-only connect watchdog 在 full Doze 中晚到约 321 秒。原整夜 100%→84% 不能直接归因 BLE；后续 Companion FGS/BLE 隔离 B–A–B 已按工程口径通过，估算 gateway 相关整机增量约 `101.1 mAh/h`，但不是纯射频标定或预算 PASS。任务移除/MARs 仍失败，整套硬件 Gate 继续部分通过。
5. Any request to add server scopes, tokens, endpoint schemas, storage/retention, Tailscale, a scheduled task, Tasker profile, iPhone shortcut, APK, or real-device test changes the shared/runtime contract and must return to the acceptance window for authorization.

## Document self-check

- Every **implemented** statement above links to a repository file or committed handoff.
- Every **officially possible** platform statement links to Microsoft, Android, or Apple first-party documentation.
- Every endpoint contains an unknown/unsupported boundary and a manual Gate. No Gate is recorded as passed.
- This file proposes evidence baselines only. It does not define or approve `device.activity.v1`, retention, ingress, topology, permissions scopes, or production behavior.
