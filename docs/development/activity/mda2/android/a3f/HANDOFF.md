# MDA-2 A3-F Android Activity FGS Handoff

> 状态：isolated Debug-only implementation candidate，等待 W0 独立审计。
>
> 固定基线：`v3-lab@add2c1e6e06a8606fa6e6d58061f7540ca2fa958`
>
> 分支：`codex/mda2-a3f-activity-fgs-20260916`
>
> 候选 HEAD：本文件所在的单一交付提交；W0 必须以 `git rev-parse HEAD` 核对 worker final 回报的完整值。

## 1. 裁决边界

本包实现了 A3-E 条件性接受的唯一候选：由现有 A3-D Debug 入口明确启动/停止的独立 Activity foreground service。它只做未来 prospective observation；没有把 A3-D2 改写为通过，没有构建/安装 APK，没有 adb/手机/真实 UsageEvents/网络/Core/push/publish。

共享 `device.activity.v1` wire、Core、broker canonical sequence/TTL/validation、A3-I secure outbox schema 均未修改。authorization epoch、owner fence、sealed query cursor 和四时钟诊断只存在于 Android 原生/Debug MethodChannel 边界；只有原生已接受的最小信号进入现有 Dart normalizer。因此本包**不需要 shared contract 变更**。

正常 `lib/main.dart`、router、settings、DI 为零引用；native 还要求 hereIAmV3 包且 APK 为 debuggable。服务没有 boot receiver、sticky restart 或后台自恢复。

## 2. 逐路径范围

- `android/app/src/main/kotlin/com/memexlab/memex/activity/ActivityObservationForegroundService.kt`：独立 specialUse FGS、专用通知/停止 action、30 秒 prospective query、广播 query hint、AppOps watcher、foreground/通知可见性复核、bounded pending reduced signals；`START_NOT_STICKY`。
- `android/app/src/main/kotlin/com/memexlab/memex/activity/ActivityPermissionEpochStore.kt`：原子持久 boot/epoch/owner/service/cursor 状态，以及生产服务直接使用的 fail-closed authority state machine。
- `android/app/src/main/kotlin/com/memexlab/memex/activity/ActivityUsageEventSource.kt`：UsageEvents 原始 occurrence timestamp 读取与内存粗化；screen/keyguard 不要求 package，app activity 只在内存映射为固定 coarse category。
- `android/app/src/main/kotlin/com/memexlab/memex/activity/AndroidActivitySignalCollector.kt`：动态 `SCREEN_*` / `USER_PRESENT` receiver 仅调用 query hint；没有 clock，也不能生成 signal。
- `android/app/src/main/kotlin/com/memexlab/memex/activity/ActivitySignalPolicy.kt`：删除 callback-time screen reducer；保留既有 usage/category 策略。
- `android/app/src/main/kotlin/com/memexlab/memex/channels/ActivitySignalChannelHandler.kt`：最小桥接 FGS start/stop/query；Flutter engine detach 不停止独立服务，只有显式 deactivate 停止。
- `android/app/src/main/AndroidManifest.xml`：只新增 `FOREGROUND_SERVICE_SPECIAL_USE` 与独立 `specialUse` service/subtype；未复用其他 service/type。
- `lib/data/services/activity/mda2_android/android_activity_signal_platform.dart`：Debug channel batch 增加 screen signals 与 query/native/Dart ingest 诊断时钟，严格 exact-shape 和 fixed signal types。
- `lib/data/services/activity/mda2_android/android_activity_collector.dart`：已验证的 screen batch 进入原有 screen outbox；记录四时钟供诊断证据。
- `lib/ui/a3d_device_gate/a3d_device_gate_controller.dart`、`a3d_device_gate_screen.dart`：显示 FGS 取舍、独立停止和四时钟最小证据；仍只由 Debug entry 构造。
- `android/app/src/test/kotlin/com/memexlab/memex/activity/ActivitySignalPolicyTest.kt`、`ActivityPermissionEpochAuthorityTest.kt`：原 reducer 回归与 A3-F authority/race/恢复断言。
- `test/data/services/activity/mda2_android/android_activity_collector_test.dart`：screen raw timestamp、四时钟与 privacy channel 断言。
- `test/data/services/activity/mda2_android/verify_a3_android.ps1`：隔离 source-set 纳入 A3-F 生产文件与测试。
- `test/data/services/activity/mda2_android/verify_a3_static.ps1`、`verify_a3d_static.ps1`：保留原守门并显式容纳本包的批准路径；A3-F 新语义由下一项独立守门。
- `test/data/services/activity/mda2_android/verify_a3f_static.ps1`：专用路径、Manifest、生命周期隔离、正常入口零引用、广播无 receipt clock 与 privacy-negative 守门。
- 本文件。

未修改 `I_PROJECT_STATE.md` 或 `DEVLOG.md`；W0 负责全局状态。

## 3. Authority 与 race 处理

1. 启动顺序为：用户 opt-in → `startForeground()` → 证明本 service 的 foreground 状态 → 证明专用通知权限/channel/active notification 可见 → 注册 AppOps watcher → 首次当前 AppOps 检查 → 读取 boot marker → 原子写入新 epoch。任一步失败都不建立 readiness/epoch，并停止服务。
2. persisted state 不是单独 authority。每个 query precheck/postcheck 都重新证明 live service、foreground、notification、watcher、AppOps allowed、同 boot、同 owner fence、同 service instance。notification / foreground / watcher / boot / owner / service 或 query 完整性一旦失证，epoch taint 且 Activity FGS 停止；旧 authority 不能靠下一轮轮询自行复活。
3. query permit 先隔离 batch；raw query 返回后、cursor 原子持久化前再次复核。任一 watcher edge、revoke/regrant、owner/boot/service/visibility 变化会改变 generation 或 taint epoch，旧 permit 不能提交。
4. AppOps edge 一律 taint 当前 epoch。重新看到 allowed 只会在下一次稳定 precheck 从当前时刻建立新 epoch，并返回 `epoch_opened_no_backfill`；该次不查询过去。
5. service stop/onDestroy 显式 taint；force-stop/process death 来不及回调时留下 open/unsealed state。下一次显式启动先把旧 owner 标为 `unclean_previous_owner`，然后从当前新 owner/epoch 开始，旧 tail 不可接受。
6. `UsageEvents.Event.timeStamp` 是唯一 occurrence time。`KEYGUARD_HIDDEN` → `user_present`，`SCREEN_INTERACTIVE` / `SCREEN_NON_INTERACTIVE` 保留 raw timestamp；广播 action 只有 wake hint，无 timestamp 参数。
7. query null、exception、device locked、synthetic expired、stable empty、denied/revoked 使用不同 fixed codes。stable empty 只推进已验证 cursor，返回 `usage_query_empty_unproven`，不声称 inactivity。公开 API 不提供 retention-expiry 与真实 no-activity 的可判别证明，因此服务不会把 empty 提升为二者之一。
8. query cursor 先原子落盘，随后才把 reduced signals 放入 bounded 内存队列；中途死亡最多丢失候选事件，恢复时旧 open tail 仍 unknown，不会伪造事件。package/app/raw event 不写 epoch store、不进 channel/outbox/evidence。

## 4. 自动验证（真实结果）

| 验证 | exit | 结果 |
|---|---:|---|
| `verify_a3_android.ps1` isolated hereIAmV3 Debug source-set | 0 | Kotlin **22/22**；包含 10 项 A3-F authority 测试与既有 12 项 policy 回归；生产 source-set 编译通过 |
| `verify_a3_flutter.ps1 -NoResolve` | 0 | A3 Dart **18/18**；双 analyze 无问题；镜像逐字一致 |
| `verify_a3d_flutter.ps1 -NoResolve` | 0 | A3-D **14/14**；入口/UI/test analyze 无问题；镜像逐字一致 |
| `verify_flutter_synthetic.ps1` | 0 | A1 **56/56**；当前 A2 **31/31**；双 analyze 无问题；镜像逐字一致 |
| `verify_wire.mjs` | 0 | fixture/validator/Core **20/20**；unknown 6、privacy negative 7、duplicate/TTL boundary 通过 |
| `verify_a3f_static.ps1` | 0 | 专用范围、specialUse、无 production entry、无 callback clock、privacy/lifecycle isolation；19 路径 |
| `verify_a3_static.ps1` / `verify_a3d_static.ps1` | 0 / 0 | 原 A3/A3-D 守门在批准的 A3-F 范围内继续成立；各核对 19 路径 |
| `git diff --check` | 0 | whitespace 守门通过 |

以上都是本地自动/合成证据，不是 APK、部署、设备行为或 A3-D acceptance。

## 5. 关键断言覆盖

- 固定 22:01:10.402 occurrence / 00:17:13.448 receipt fixture：新 epoch 从 00:17 开启，查询被 clamp，22:01 raw `KEYGUARD_HIDDEN` 被拒，零 fresh unlock。
- raw keyguard/screen/app timestamp 原样通过；occurrence、query start、query finish、native receive、Dart ingest 保持分离。
- revoke/regrant、快速双 edge、query pre/post race、generation mismatch 不跨 epoch提交。
- service/process death、notification stop、Task Manager/force-stop 等价的 unsealed tail、reboot marker、owner/service mismatch、损坏/不可写 state 全部 fail closed。
- 未 opt-in、非 Debug V3、notification 不可见、foreground 未确认、watcher/boot/permission 不可用均不建立 epoch。
- 静态隔离守门要求 Activity service 不引用/启动/停止/复活 BLE、Companion、check-in，也没有 boot/sticky/work/alarm recovery。
- outbound 只允许 coarse category 与三类 screen/session signal；Dart exact-shape 对 package/app/raw/private 字段整批拒绝。

## 6. 失败历史（未伪装成通过）

- 初次建分支因 worktree Git 元数据权限不足失败；在精确基线核对后仅对 `git switch -c` 使用批准权限，随后成功。
- Android 隔离 harness 首次加入 AndroidX 依赖时，离线缓存缺 `annotation-jvm`；改用 minSdk 26 已有的原生 Android notification/FGS API，未下载或新增项目依赖。
- Kotlin 首轮发现 public service companion 暴露 internal 类型；收紧为 internal 方法。
- epoch file round-trip 首轮发现 open state 的空 `taint_reason` 被错误当损坏；改为要求 key 存在但允许 open 时空值。
- Dart 新 screen 测试首轮使用脱离 rig clock 的旧 timestamp，被现有 freshness 守门正确丢弃；改为同一受控时钟后通过。
- A3-D 首次离线 resolve 在生成 package config 后复现本机 Pub `active_roots` 路径故障，exit 1；随后 `-NoResolve` 复用该映射，14/14 与 analyze 通过。它是环境故障，不是测试通过。

## 7. W0 与真人 Gate 未完成项

- W0 必须独立审查 Android 16 上 `getRunningServices()` 对本 app foreground 证明的实际可靠性；无法证明时保持 `foreground_state_lost`，不能放宽。
- AppOps watcher 的 OEM callback 顺序/遗漏、快速 revoke→regrant、process reclaim、Task Manager Stop、force-stop、reboot、notification permission/channel 禁用均只做了可执行状态机断言，仍需同一新 APK hash 的真人 Gate。
- `UsageStatsManager.queryEvents()` 对目标 OEM 的 `KEYGUARD_HIDDEN`/screen event 完整性与 retention 行为未真机验证；empty 仍是 unknown/no inactivity proof。
- specialUse subtype 的商店申报可接受性、Android/OEM 后台启动限制、持续通知稳定性与耗电预算未验证。
- 必须至少在 SM-S9110 / Android 16 与一台接近 AOSP 的设备，用同一 APK SHA-256 从零重跑 opt-in、通知、正常锁解、delayed broadcast、revoke/regrant race、死亡/重启、隔离与电池矩阵。
- 新 APK hash 产生后，旧 `C43B…F820D` 设备证据不可沿用。A3-D2 继续是 **FAIL**；本包仅可进入 W0 independent review。
