# MDA-2 A3-E：Android 权威屏幕 / 解锁来源选项

> 状态：W0 审计候选；仅架构与证据，不是实现、集成、部署或 A3-D 通过。
>
> 固定审计基线：`v3-lab@6ea772f18bb1ad7b50a5a04eafc3e972af91116c`
>
> 设备反例：SM-S9110 / Android 16 上，`ACTION_USER_PRESENT` 于
> `2026-09-15 22:01:10.402` 进入系统广播队列；进程处于 cached/background 时未收到，直到
> `2026-09-16 00:17:13.448` 进程 active 后才由 `mBroadcastConsumerDeferClear` 投递。

## 1. 结论先行

**唯一建议进入后续设计审查的方案是选项 2：独立、用户可见的 Activity FGS，结合 AppOps 边沿、持久化授权 epoch/fence，以及 `UsageStatsManager.queryEvents()` 返回的原始事件时间。**

这个建议严格限于**未来的、前瞻式、失败即 unknown 的覆盖**：

- `UsageEvents.Event.getTimeStamp()` 是事件发生时间，可以避免把延迟收到广播的时刻伪装成解锁时刻。
- 当前 `AppOpsManager.checkOpNoThrow()` 只证明查询当下的状态；它不能证明 cached、进程死亡或服务未运行期间没有发生“撤销 → 重授”。
- `startWatchingMode()` 可以在一个存活的观察进程中监听 mode 变化，但官方 API 没有提供一份可在进程死亡后补读的 AppOps 历史审计日志，也没有承诺回调本身携带权限改变的原始发生时间。
- 因而，只有落在**同一 boot、同一 owner fence、观察服务连续存活、授权 epoch 已建立且未被 taint、查询游标已持久化**的区间内，原始 UsageEvents 才可进入受支持证据链。
- 任一连续性断裂、AppOps 边沿、服务停止、Task Manager Stop、重启、意外 owner 变化或未封口尾段，都必须保留为 `unknown`；重新看到“当前已授权”只能从现在开启新 epoch，不能回填旧区间。

所以本工作包同时给出两个判断：

1. **对历史反例回填：明确 no-go。** 不能用 00:17 的当前 AppOps 状态为 22:01 的事件补造授权证明。
2. **对未来持续观察：选项 2 是唯一候选。** 它仍需独立实现工作包、自动断言和同一 APK 的真人设备 Gate；在 Gate 前不构成 acceptance。

## 2. 当前链路为何失败

### 2.1 代码证据

当前原生采集器把动态广播回调的接收时钟直接作为信号时间：

- `android/app/src/main/kotlin/com/memexlab/memex/activity/AndroidActivitySignalCollector.kt:50-61`：`onReceive()` 调用 `clockMs()`，再把该值交给信号 sink。
- 同文件 `:66-79`：动态监听 `ACTION_SCREEN_ON`、`ACTION_SCREEN_OFF`、`ACTION_USER_PRESENT`；Android 13+ 使用 exported runtime receiver，以便接收由特权 SystemUI UID 发出的受保护广播。
- `android/app/src/main/kotlin/com/memexlab/memex/channels/ActivitySignalChannelHandler.kt:31-47`、`:50-61`、`:177-182`：receiver 生命周期绑定 Flutter engine/channel handler；engine 销毁会注销 receiver，不具备独立后台观察所有权。
- 同文件 `:82-117`：激活时把 `System::currentTimeMillis` 注入 receiver。
- 同文件 `:119-154`：每次 UsageEvents 查询前只检查**当前** Usage Access 状态。
- `android/app/src/main/kotlin/com/memexlab/memex/activity/AndroidActivitySignalCollector.kt:32-47`：UsageEvents 路径已经保留 `event.timeStamp`，这部分时间语义是可复用的。
- `lib/data/services/activity/mda2_android/android_activity_signal_platform.dart:119-168`、`:195-211`：平台响应只有当前 permission 状态与简化信号；没有授权 epoch、owner fence 或覆盖证明。
- `lib/data/services/activity/mda2_android/android_activity_collector.dart:97-197`：现有恢复逻辑会拒绝既有状态并要求显式恢复，但没有 Android AppOps 历史授权证明。
- `lib/ui/a3d_device_gate/a3d_device_gate_controller.dart:319-387`：诊断控制器以“现在”建立 query 起点并推进窗口；它不是持续后台权威观察器。
- `test/data/services/activity/mda2_android/a3d_device_gate_test.dart:287-319`：已有 revoke/regrant 断言覆盖的是合成的即时状态切换，不证明真实 cached / process-dead 间隔内的授权历史。

### 2.2 Android 官方行为与设备反例一致

Android 14 起，系统可以把 context-registered 的低优先级广播在应用 cached 时排队，在应用离开 cached 状态后再投递；官方点名 `ACTION_SCREEN_ON` 为可能延迟的广播。系统还可能合并重复广播。这与 SM-S9110 的 `mBroadcastConsumerDeferClear` 证据一致：

- [Android 14 behavior changes: cached-state broadcasts](https://developer.android.com/about/versions/14/behavior-changes-all#cached-broadcasts)
- [Broadcasts overview: effects on process state](https://developer.android.com/develop/background-work/background-tasks/broadcasts#effects-process-state)

`Intent.ACTION_USER_PRESENT` 的官方契约只说明“设备唤醒且 keyguard 消失后发送”，没有定义一个随 Intent 传递的原始发生时间：

- [Intent.ACTION_USER_PRESENT](https://developer.android.com/reference/android/content/Intent#ACTION_USER_PRESENT)

因此，动态 receiver 的 `System.currentTimeMillis()` 是**接收时间**，不是**信号发生时间**。在反例中：

```text
真实/入队时刻          2026-09-15 22:01:10.402
cached 延迟            2 h 16 m 03.046 s
receiver 接收时刻      2026-09-16 00:17:13.448
当前实现写入           session.unlocked@00:17:13.448   <- 错误的新鲜信号
正确处理               不使用广播接收时刻；若 22:01 所属授权 epoch 不可证明，则 unknown
```

短阈值、文件 mtime、当前 AppOps、当前 keyguard 状态或“通常会及时投递”都不能把这段未知历史变成证据。

## 3. 共同的权威性判定

一个 Android screen/unlock observation 只有同时满足以下条件才可被称为本项目范围内的权威来源：

1. **发生时间有来源契约。** `signal_at_ms` 来自 Android 事件记录的原始 timestamp，而不是 callback / poll / bridge / enqueue / receive 时间。
2. **授权覆盖可证明。** 从事件发生到被本地提交，整个必要区间都位于同一已证明授权 epoch；当前状态不能证明过去。
3. **观察所有权连续。** boot marker、owner fence、service/process instance 和 query cursor 能排除旧 owner、重启和并发写者。
4. **断裂保留 unknown。** 权限变化、进程死亡、服务停止、系统重启、Task Manager Stop、强行停止、数据过期或游标缺口均不推断。
5. **最小化。** 只输出 MDA-2 已允许的粗类别与 screen/session 信号；不得把 package/app 名、窗口内容或可访问性节点混入该通道。
6. **用户可知且可撤销。** 持续后台观察必须有独立 opt-in、持久通知和独立停止入口；停止采集不能依赖或影响 BLE / Companion FGS。

`UsageStatsManager.queryEvents(begin, end)` 需要用户在 Settings 授予 Usage Access，返回窗口按 begin-inclusive / end-exclusive 查询；事件仅保留有限天数，设备未解锁时也可能不可用：

- [UsageStatsManager.queryEvents](https://developer.android.com/reference/android/app/usage/UsageStatsManager#queryEvents(long,long))
- [Manifest.permission.PACKAGE_USAGE_STATS](https://developer.android.com/reference/android/Manifest.permission#PACKAGE_USAGE_STATS)
- [Settings.ACTION_USAGE_ACCESS_SETTINGS](https://developer.android.com/reference/android/provider/Settings#ACTION_USAGE_ACCESS_SETTINGS)

`UsageEvents.Event.KEYGUARD_HIDDEN`（API 28）记录 keyguard 隐藏，通常对应用户解锁；`SCREEN_INTERACTIVE` / `SCREEN_NON_INTERACTIVE` 可补充屏幕交互状态。`getTimeStamp()` 的契约是事件发生时间，epoch milliseconds：

- [UsageEvents.Event.KEYGUARD_HIDDEN](https://developer.android.com/reference/android/app/usage/UsageEvents.Event#KEYGUARD_HIDDEN)
- [UsageEvents.Event.SCREEN_INTERACTIVE](https://developer.android.com/reference/android/app/usage/UsageEvents.Event#SCREEN_INTERACTIVE)
- [UsageEvents.Event.getTimeStamp](https://developer.android.com/reference/android/app/usage/UsageEvents.Event#getTimeStamp())

这些 API 证明“事件时间来自哪里”，但**不单独证明查询区间内 Usage Access 始终有效**。

## 4. 选项比较

| 选项 | 能证明什么 | 不能证明什么 | 隐私 / 权限 | 死亡、OEM、恢复 | 产品代价 | 结论 |
|---|---|---|---|---|---|---|
| 1. 仅前台观察，后台全 unknown | 应用真实处于前台且 receiver 当场收到时，可描述 receive-time 观察；不误报后台 | 不能覆盖锁屏、其他 app、cached 或进程死亡期间；广播仍没有原始发生时间 | 最小权限、无常驻通知、低电耗 | 离开前台即主动关闭覆盖，不尝试恢复 | 最低 | 安全 fallback；不能满足 MDA-2 的持续来源目标 |
| 2. 独立 user-visible Activity FGS + AppOps edges + epoch/fence + UsageEvents 原始时间 | 在同一已证明 live/allowed epoch 内，能把原始 UsageEvents 时间与连续观察证据绑定 | 普通 app API 不能为服务死亡期提供 AppOps 历史审计；不能回填未知尾段 | Usage Access + FGS 权限/类型 + 持久通知；只保留粗信号 | FGS 提高进程重要性但不保证不死；任一断裂 taint/封口，恢复只建新 epoch | 常驻通知、电池、OEM 与 Play 审核成本最高 | **唯一建议进入后续设计与设备 Gate 的候选；前瞻式、失败即 unknown** |
| 3. 其他官方 event-time / 用户自动化 | 部分接口能提供当前状态、通用事件时间或用户配置的“解锁”触发 | 无普通 app 可用的“解锁原始时间 + 历史授权连续性”组合 | 可访问性权限过宽；自动化增加第三方依赖；特权 keyguard 权限不可得 | 同样受进程/权限/自动化执行延迟影响 | 复杂且风险高 | 拒绝作为 `session.unlocked` 权威来源；最多独立 best-effort 来源 |

## 5. 选项 1：前台观察，后台明确 unknown

这是当前最保守的可交付语义：只在应用前台、当前 receiver 所有权有效时消费即时观察；一旦应用离开前台就结束覆盖，后台时间明确为 `unknown`。

### 可证明

- 当前进程活跃、receiver 已注册、callback 在本地被接收。
- 在不把 receive time 称为 occurrence time 的前提下，可以作为 UI 诊断提示或“此刻看到状态改变”的 best-effort observation。
- 不需要常驻 FGS，不新增 notification / special-use 声明。

### 不可证明

- `ACTION_USER_PRESENT` 的真正发生时间。
- cached 时广播是否被排队、合并或丢失。
- 应用后台、死亡、重启、强停后的任何连续活动。
- 当前 Usage Access 状态之前是否发生 revoke/regrant。

### 判断

它符合 fail-closed 与最小隐私原则，可作为“用户拒绝持续观察”时的安全 fallback；但它把 MDA-2 需要的大部分自然活动区间留为 unknown，所以不能单独修复 A3-D2。

## 6. 选项 2：独立 Activity FGS + epoch/fence + UsageEvents

### 6.1 为什么必须是独立服务

Android 把 foreground service 定义为执行用户可感知任务、并显示状态栏通知的服务。Android 12+ 还限制从后台启动 FGS；Android 14+ 要求声明匹配的 service type 与权限。没有适合活动观察的标准类型时，`specialUse` 需要 `FOREGROUND_SERVICE_SPECIAL_USE`、manifest subtype 说明，并可能进入 Play Console 审查：

- [Foreground services overview](https://developer.android.com/develop/background-work/services/fgs)
- [Restrictions on starting a foreground service from the background](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start)
- [Declare foreground services and request permissions](https://developer.android.com/develop/background-work/services/fgs/declare)
- [Foreground service types: special use](https://developer.android.com/develop/background-work/services/fgs/service-types#special-use)

Activity 观察的授权、通知、生命周期和停止语义与心率 BLE、Companion 都不同。复用它们会把“停止活动观察”错误地耦合到健康设备或陪伴功能，也会模糊用户看到的通知目的。因此未来实现必须使用新的独立 service、notification channel、owner fence 和 stop path；现有 BLE / Companion FGS 保持不变。

### 6.2 建议的证据状态机

```text
OFF / UNKNOWN
  -- user opt-in + Activity FGS visible + watcher registered + current grant observed --> OPEN_EPOCH

OPEN_EPOCH
  -- query UsageEvents --> QUARANTINED_BATCH
  -- durable cursor + same boot/fence + no taint --> COMMITTED_BATCH
  -- AppOps edge / owner loss / service stop / process death evidence --> TAINTED_TAIL

TAINTED_TAIL
  -- close old epoch; discard/quarantine unprovable tail; emit readiness/coverage gap --> UNKNOWN

UNKNOWN
  -- current grant merely allowed --> still UNKNOWN for the past
  -- new explicit live start and observed grant --> NEW OPEN_EPOCH from now only
```

必要的持久化内部证据至少包括：schema version、boot marker、随机 epoch id、owner fence、service instance、epoch opened-at、最后已封口的 begin-inclusive/end-exclusive query cursor、最后观察到的 AppOps mode、taint reason、close status。任何恢复都以这些显式字段为准，不以 mtime、进程 uptime 猜测或“文件能解密”代替 authority。

### 6.3 AppOps 边沿的作用与边界

`AppOpsManager.startWatchingMode()` 官方定义为监听指定 op/package 的 mode 变化；callback 可在指定 executor 上调度。它适合在存活服务内触发 epoch taint/close，但文档未提供一个进程死亡后可重放的历史日志，也未给 callback 一个权限边沿的原始 occurrence timestamp：

- [AppOpsManager.startWatchingMode](https://developer.android.com/reference/android/app/AppOpsManager#startWatchingMode(java.lang.String,java.lang.String,int,java.util.concurrent.Executor,android.app.AppOpsManager.OnOpChangedListener))

因此正确顺序是：

1. 用户显式启动独立 Activity FGS，并确认它已进入 foreground。
2. 建立新 owner fence 与 boot marker。
3. 注册 AppOps watcher，再读取当前 `OPSTR_GET_USAGE_STATS`；把这两个动作间的竞态按 fail-closed 处理。
4. 只有从“当前允许被本服务观察到”的持久时刻起，打开新 epoch；绝不追溯到服务启动之前。
5. UsageEvents batch 先隔离；只有 event timestamp 落在该 epoch 的已封口区间内，且提交时 boot/fence/permission 状态仍一致，才写入现有 MDA-2 signal 通道。
6. 任一 AppOps callback 先 taint 当前开放尾段并关闭 epoch。即使 callback 后读到 allowed，也只能新开 epoch，不能判断中间是否经历了 revoked/regranted。
7. 进程/服务重启看到上次 epoch 未正常封口时，旧尾段永久 unknown；当前 allowed 只允许从恢复后的新时刻开始。

这套设计不声称普通 Android API 提供数学上无遗漏的权限审计。若产品验收标准要求“即使观察进程死亡，也必须证明期间没有 revoke/regrant”，则 Android 普通第三方应用没有满足该标准的公开接口，结论应维持 no-go，而不是降低 authority 定义。

### 6.4 FGS 也不是存活证明

foreground service 会提高进程重要性，但 Android 仍可终止进程。用户从 Android 13 Task Manager 点 Stop 时，系统会停止整个 app、移除通知，而且不会向应用发送 callback。cached 进程则可能随时被杀：

- [Processes and app lifecycle](https://developer.android.com/guide/components/activities/process-lifecycle)
- [Handle user stopping an app that has a foreground service](https://developer.android.com/develop/background-work/services/fgs/handle-user-stopping)

电池限制与 OEM 行为也不能被抽象掉；restricted 状态可能阻止后台工作或 FGS 启动，Low Power Standby 甚至可限制 foreground service 的网络和 wakelock：

- [Background optimization](https://developer.android.com/topic/performance/background-optimization)
- [PowerManager low power standby](https://developer.android.com/reference/android/os/PowerManager#isLowPowerStandbyEnabled())

`START_STICKY`、BOOT receiver、通知仍在、短暂心跳或“通常能恢复”都不是连续 authority。未见正常封口，直接 unknown。

### 6.5 通知与用户控制

持续观察必须有用途明确、不可借用的常驻通知和停止入口。Android 13+ 即使用户拒绝 `POST_NOTIFICATIONS`，FGS 仍必须提供 notification，但它可能只出现在 Task Manager 而不在 notification drawer：

- [Notification runtime permission and foreground services](https://developer.android.com/develop/ui/compose/notifications/notification-permission#fgs)

对 Here I am 的“用户可见持续观察”承诺而言，若通知不能在预期位置持续可见，未来实现应把来源标为 unavailable/unknown 并停止，而不是悄悄运行。具体 UX、manifest 与 Play policy 均属于后续 W0 审批范围，本包不修改。

## 7. 选项 3：其他接口与用户自动化

### 7.1 KeyguardManager listener：普通应用不可用

`KeyguardManager.addKeyguardLockedStateListener()` 需要 `SUBSCRIBE_TO_KEYGUARD_LOCKED_STATE`；该权限的 protection level 是 `signature|privileged|module|role`，面向持有 ASSISTANT role 等特权主体。listener 只给当前 locked boolean，不提供历史 occurrence timestamp：

- [KeyguardManager](https://developer.android.com/reference/android/app/KeyguardManager)
- [Manifest.permission.SUBSCRIBE_TO_KEYGUARD_LOCKED_STATE](https://developer.android.com/reference/android/Manifest.permission#SUBSCRIBE_TO_KEYGUARD_LOCKED_STATE)

`isDeviceLocked()` / `isKeyguardLocked()` 也只是查询当前状态，不能恢复历史。该路线对普通发布应用 no-go。

### 7.2 AccessibilityService：语义不匹配且采集面过宽

AccessibilityEvent 有 event time，但它描述可访问性 UI 事件，不是受契约保证的“用户解锁”系统事件。AccessibilityService 面向帮助残障用户，可跨应用接触 package/class/source 和窗口内容；用户可随时禁用，进程死亡后也无授权历史：

- [AccessibilityService](https://developer.android.com/reference/android/accessibilityservice/AccessibilityService)
- [AccessibilityEvent.getEventTime](https://developer.android.com/reference/android/view/accessibility/AccessibilityEvent#getEventTime())
- [Create an accessibility service](https://developer.android.com/guide/topics/ui/accessibility/service)
- [Google Play AccessibilityService policy](https://support.google.com/googleplay/android-developer/answer/10964491)

为了一个 coarse screen/unlock 信号请求这一权限不符合数据最小化，且不能解决 epoch 证明问题。拒绝。

### 7.3 Device admin / enterprise APIs：不提供通用解锁流

`DeviceAdminReceiver.ACTION_PASSWORD_SUCCEEDED` 只在先前失败之后的密码成功等设备管理场景使用，不是普通消费应用的每次解锁事件；引入 admin/enterprise 控制也明显超出产品边界。拒绝。

- [DeviceAdminReceiver.ACTION_PASSWORD_SUCCEEDED](https://developer.android.com/reference/android/app/admin/DeviceAdminReceiver#ACTION_PASSWORD_SUCCEEDED)

### 7.4 用户控制自动化：只能是独立 best-effort 来源

Tasker 官方文档提供 `Display Unlocked` event；但 `%TIMEMS` 是变量求值时的当前毫秒，文档没有把它定义为 Android 解锁事件的原始 OS timestamp。自动化 app 自己也可能遭遇延迟、权限变化、进程停止和 OEM 限制：

- [Tasker event reference: Display Unlocked](https://tasker.joaoapps.com/userguide/en/help/eh_index.html)
- [Tasker variables: TIMEMS](https://tasker.joaoapps.com/userguide/en/variables.html)

若未来由用户自行配置，只能进入单独标注的 `discrete_best_effort` 来源，并保留 automation-handled-at；不得混入 `session.unlocked` 权威链，也不得以其“看起来及时”补 A3-D。

## 8. 最小未来改动面（非本包授权）

以下仅定义未来独立实现工作包的 owned paths；本提交没有修改它们：

### Android owned paths

- 新建 `android/app/src/main/kotlin/com/memexlab/memex/activity/ActivityObservationForegroundService.kt`
- 新建 `android/app/src/main/kotlin/com/memexlab/memex/activity/ActivityPermissionEpochStore.kt`
- 新建或拆分 `android/app/src/main/kotlin/com/memexlab/memex/activity/ActivityUsageEventSource.kt`
- 最小调整 `android/app/src/main/kotlin/com/memexlab/memex/channels/ActivitySignalChannelHandler.kt`，只负责 UI/control bridge，不再拥有后台 receiver 生命周期
- 对应 `android/app/src/test/kotlin/com/memexlab/memex/activity/**`

### Dart owned paths

- `lib/data/services/activity/mda2_android/**`：只接收已证明的 readiness/coverage 与现有粗信号；不扩大 package/app 数据面
- `test/data/services/activity/mda2_android/**`

### 必须由 W0 单独审批的 shared paths

- `android/app/src/main/AndroidManifest.xml`：新 service、FGS permission/type/subtype
- 用户 opt-in、通知说明和独立 stop 控制对应的 UI/l10n
- 如现有内部 wire 无法表达 coverage/epoch readiness，再由 W0 决定是否需要最小共享契约变更；worker 不先改 Core/schema

明确禁止复用或修改 `BleHeartRateService`、`companion_foreground_task.dart` 及其 notification/channel/start-stop 生命周期。

## 9. 未来自动断言

后续实现若获授权，至少要有以下可复核断言：

1. 动态 broadcast callback 的本地 receive time 永不映射为 `signal_at_ms`；广播最多是 query wake hint。
2. `KEYGUARD_HIDDEN` / screen events 的 `event.timeStamp` 原样通过，query/receive/ingest 时间单独保存或仅用于诊断。
3. 事件只有在同 boot、同 owner fence、同已封口 allowed epoch 内才可提交；边界遵守 `[begin, end)`。
4. 设备反例 fixture：22:01 入队、00:17 收到时，不得生成 00:17 的 fresh unlock；授权 epoch 不可证明时整条拒绝。
5. AppOps revoke、regrant、快速 revoke→regrant、注册 watcher 与首次 check 的竞态都会 taint/close 旧 epoch；当前 allowed 不重开过去。
6. 进程死亡、service death、Task Manager Stop、force-stop、reboot、boot marker 变化、owner mismatch、未封口 cursor 均产生 unknown gap。
7. 恢复逻辑不读取 mtime，不用短阈值，不因 DPAPI/文件可读、当前 AppOps 或 restarted uptime 推断连续性。
8. UsageEvents 过期、设备未解锁、query null/exception/empty 与 permission denied 分开表达；empty 不等于 inactivity proof。
9. 只有 coarse category 与 screen/session signal 可出站；packageName/appName/accessibility payload 必须为零。
10. Activity FGS 与 BLE、Companion 的 service、notification channel、start、stop、owner 和故障互不影响。
11. 未 opt-in、通知可见性不满足、FGS 未真正进入 foreground 或后台启动被拒时，source readiness 只能 unavailable/unknown。
12. 不改变现有 A3-I secure outbox、broker canonical sequence/TTL、A3-D recovery boundary；任何共享 wire/schema 需求先停给 W0。

## 10. 同一 APK 真人设备 Gate

未来 candidate 必须先通过自动断言，再在**同一构建产物 SHA-256** 上执行以下真人 Gate；SM-S9110 / Android 16 是必测设备，另加至少一个接近 AOSP 的对照设备。测试记录需分开 `event occurred`、`platform query`、`native receive`、`Dart ingest` 四个时间。

1. **明确 opt-in 与常驻通知**：用户启动 Activity FGS；通知文本准确说明活动/屏幕观察；停止入口只停止 Activity source，不影响 BLE/Companion。
2. **正常锁屏/解锁**：`KEYGUARD_HIDDEN` 原始时间与独立人工时间标记相符；动态广播仅作 hint。
3. **复现 delayed broadcast**：应用 cached 后锁屏/解锁，再唤活；晚到的 `ACTION_USER_PRESENT` 不生成“刚刚解锁”。若原始 UsageEvent 位于完整 proven epoch，可按原时间提交；否则 unknown。
4. **真实 revoke/regrant**：FGS 运行时由用户在系统 Settings 撤销 Usage Access，期间产生 screen/app activity，再重授；gap 中零条事件可被接受，新 epoch 只能从重新观察授权之后开始。
5. **权限变化竞态**：在 poll/query 前后重复 revoke/regrant，确认隔离 batch 不会跨 tainted epoch 提交。
6. **进程与服务死亡**：分别测试普通进程被回收、OEM restricted、Task Manager Stop、force-stop、系统重启；未封口尾段必须 unknown，恢复不得自动回填。
7. **通知权限拒绝**：验证产品按设计停用/unknown，不形成用户不可见的持续观察。
8. **电池与 OEM**：在预先声明的观察时长、设备状态和版本下记录耗电、唤醒、通知稳定性与丢失；是否可接受由 W0/用户依据事先确定的产品预算判断，不在事后发明短阈值。
9. **隔离性**：活动服务反复启停、崩溃和权限变化时，BLE、Companion、check-in 不被启动、停止或复活。
10. **卸载/清数据/降级恢复**：持久 epoch/fence 不被旧状态误认；无法证明就拒绝并要求显式重新开始。

任何一项失败都只说明该 candidate 未通过相应 Gate；不得以 build/test 通过、通知仍在、一次及时投递或当前 AppOps allowed 宣布 A3-D passed。

## 11. 本工作包边界

- 已完成：官方文档与当前源代码只读审计、设备反例建模、三个方案比较、唯一候选与 no-go 边界、未来 owned paths/assertions/device Gate。
- 未完成：实现、manifest/Gradle/dependency 修改、Core/wire/schema 变更、构建、安装、adb、手机操作、真实数据采集、发布、push、W0 合并或 A3-D 验收。
- 当前状态：**A3-E docs-only W0 audit candidate；A3-D2 仍为 FAIL，A3-D 未通过。**
