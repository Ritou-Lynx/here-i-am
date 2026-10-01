# MDA-2 A3-E Handoff

> 状态：docs-only W0 audit candidate
>
> 基线：`v3-lab@6ea772f18bb1ad7b50a5a04eafc3e972af91116c`
>
> 结论不是 acceptance、implementation、deployment 或 A3-D passed。

## 1. 交付范围

本工作包只新增：

- `docs/development/activity/mda2/android/a3e/AUTHORITATIVE_SCREEN_SOURCE_OPTIONS.md`
- `docs/development/activity/mda2/android/a3e/HANDOFF.md`

没有修改生产 Kotlin/Dart、Manifest、Gradle、依赖、Core、wire、schema、BLE、check-in、UI；没有 build/install/adb/手机/真实数据/push/publish。

## 2. 审计输入

### 固定失败反例

- 设备：SM-S9110 / Android 16
- `ACTION_USER_PRESENT` 入队：`2026-09-15 22:01:10.402`
- cached/background 阶段未交付
- active 后交付：`2026-09-16 00:17:13.448`
- 系统线索：`mBroadcastConsumerDeferClear`
- 当前实现会用 `System.currentTimeMillis` 把 receipt time 写成 `signal_at_ms`，从而把旧事件伪装成 fresh `session.unlocked`
- A3-D2 保持 FAIL

### 当前源代码定位

- `android/app/src/main/kotlin/com/memexlab/memex/activity/AndroidActivitySignalCollector.kt:17-25`：当前 AppOps check
- 同文件 `:32-47`：UsageEvents raw `event.timeStamp`
- 同文件 `:50-88`：动态 receiver，callback 使用接收时钟
- `android/app/src/main/kotlin/com/memexlab/memex/channels/ActivitySignalChannelHandler.kt:31-61`、`:82-154`、`:177-182`：Flutter-engine-bound owner、receiver 激活、当前权限查询与 shutdown
- `lib/data/services/activity/mda2_android/android_activity_signal_platform.dart:98-168`、`:195-211`：当前 wire 无 authorization epoch/fence
- `lib/data/services/activity/mda2_android/android_activity_collector.dart:97-197`、`:200-243`：现有 recovery/poll 边界
- `lib/ui/a3d_device_gate/a3d_device_gate_controller.dart:319-387`：前台诊断 poll window
- `test/data/services/activity/mda2_android/a3d_device_gate_test.dart:287-319`、`:443-480`：合成 revocation/recovery 与 stale owner 断言

### 官方资料

完整链接与逐项分析在 `AUTHORITATIVE_SCREEN_SOURCE_OPTIONS.md`。核心依据：

- Android 14 官方说明 cached context-registered broadcasts 可延迟到进程离开 cached 后再投递，并可能合并。
- `ACTION_USER_PRESENT` 没有原始发生时间字段。
- UsageEvents 提供 `KEYGUARD_HIDDEN`、screen events 和原始 `getTimeStamp()`。
- PACKAGE_USAGE_STATS 是用户在 Settings 授予的 special access；当前 AppOps 不是历史证明。
- AppOps watcher 可监听存活期 mode changes，但没有公开的可补读历史审计契约。
- FGS 必须用户可感知且有 notification；后台启动、service type、Task Manager Stop、电池和 OEM 均有额外限制。
- Keyguard state listener 需要普通第三方 app 不具备的 privileged/role permission；Accessibility 与 Device Admin 不满足最小化与语义；Tasker 只能作为独立 best-effort 自动化来源。

## 3. 决策

### 唯一推荐

后续若继续，只评审这一条：

**独立、用户可见的 Activity FGS + AppOps edge watcher + 持久化 boot/epoch/owner fence/query cursor + UsageEvents 原始 event timestamp。**

约束：

- 只做未来 prospective coverage。
- 只有 fully proven live/allowed epoch 内的事件可提交。
- AppOps change、service/process death、Task Manager Stop、force-stop、reboot、owner mismatch 或未封口尾段一律 unknown。
- 当前 AppOps allowed 只能从当前时刻新建 epoch，永不回填旧 gap。
- 动态 screen/user-present 广播只能是 query wake hint，不能提供 `signal_at_ms`。
- Activity FGS 必须与 BLE、Companion 的 service、notification、owner、start/stop 完全隔离。

### 明确 no-go

- 对 22:01→00:17 反例做历史回填。
- foreground-only 方案声称持续后台 coverage。
- 单独使用 UsageEvents + 当前 AppOps 声称历史授权连续。
- 用短阈值、mtime、当前 keyguard/AppOps、恢复后 uptime 或“通常及时”当 authority。
- Keyguard current-state、AccessibilityService、DeviceAdmin 或 Tasker 直接生成权威 `session.unlocked`。
- 复用 BLE/Companion FGS。

如果 W0 要求在观察进程死亡期间也能证明“没有 revoke/regrant”，普通 Android public API 没有足够的历史审计接口；该要求下应保持平台 no-go。

## 4. 未来实现所有权

需要一个新的独立实现工作包，建议 owned paths：

- `android/app/src/main/kotlin/com/memexlab/memex/activity/ActivityObservationForegroundService.kt`（new）
- `android/app/src/main/kotlin/com/memexlab/memex/activity/ActivityPermissionEpochStore.kt`（new）
- `android/app/src/main/kotlin/com/memexlab/memex/activity/ActivityUsageEventSource.kt`（new/split）
- `android/app/src/main/kotlin/com/memexlab/memex/channels/ActivitySignalChannelHandler.kt`（仅 bridge 最小改动）
- `android/app/src/test/kotlin/com/memexlab/memex/activity/**`
- `lib/data/services/activity/mda2_android/**`
- `test/data/services/activity/mda2_android/**`

以下 shared paths 必须由 W0 明确审批/集成，不交给孤立 worker 静默修改：

- `android/app/src/main/AndroidManifest.xml`
- Activity observation 的 opt-in / persistent notification / stop UI 与 l10n
- 任何被证明必要的共享 wire/schema/Core 变更

禁止触碰/复用：现有 BLE foreground service、Companion foreground task、check-in 生命周期。

## 5. 必须自动证明的断言

1. 广播 receive time 不再成为 occurrence time。
2. UsageEvents raw timestamp 原样通过。
3. event 只有在同 boot/fence 的 sealed allowed epoch `[begin,end)` 内可提交。
4. 22:01/00:17 fixture 不产生 fresh unlock；unknown authorization span 不提交。
5. revoke/regrant 与 watcher/check/query race 会 taint 旧 epoch；当前 allowed 不补过去。
6. death/stop/reboot/owner mismatch/unsealed tail 保持 unknown。
7. recovery 不依赖短阈值、mtime、当前 AppOps 或自洽快照。
8. query empty/null/expired/locked/denied/revoked 分开，不把 empty 当 inactivity proof。
9. 出站仍只有 coarse category/screen signal；零 package/app/accessibility 内容。
10. Activity、BLE、Companion 三套 FGS lifecycle 隔离。
11. 没有明确 opt-in、用户可见 notification 或 foreground 成功时，不建立 epoch。
12. 不改变 A3-I outbox 与 broker-owned sequence/TTL/validation 权威。

## 6. 真人设备 Gate

使用同一 APK SHA-256，至少 SM-S9110 / Android 16 加一台接近 AOSP 的设备：

- 正常 lock/unlock：以 raw `KEYGUARD_HIDDEN` 时间提交。
- cached delayed broadcast：晚到广播不得生成 fresh unlock；epoch 不可证则 unknown。
- 用户在 Settings 真实 revoke Usage Access，期间活动，再 regrant：gap 零接受，新 epoch 从 regrant 被观察后开始。
- 在 query 前后制造 revoke/regrant race：quarantined batch 不能越过 tainted epoch。
- 分别测试 process reclaim、OEM restricted、Task Manager Stop、force-stop、reboot：未封口尾段 unknown，绝不自动回填。
- 拒绝 notification permission/通知不可见：source 按设计 unavailable/unknown，不隐形运行。
- 记录预先声明窗口内的耗电、唤醒、通知稳定性与 OEM 差异；由 W0/用户依据事先产品预算验收，不事后发明阈值。
- 独立启停/故障 Activity FGS 不影响 BLE、Companion、check-in。
- 分开保存 occurrence/query/native receive/Dart ingest 时间和 APK/device identity。

Gate 未全部通过前，状态只能是 candidate / blocked / failed；不能写 A3-D passed。

## 7. W0 回收检查

- 确认提交相对固定基线只含上述两份 Markdown。
- 复核所有官方链接仍指向 Android/Google/Tasker 原始资料。
- 复核代码 path/line 与候选 commit 一致；如果 W0 基线已前进，重新取行号，不机械沿用本 handoff。
- 决定是否接受“prospective fail-closed coverage”作为产品定义；若要求死亡期 AppOps 无遗漏证明，记录平台 no-go。
- 如接受方向，先拆出独立实现包与 shared Manifest/UI 审批，再安排自动断言；最后才构建唯一 APK 并执行真人 Gate。

## 8. 当前未完成项

- 未实现 Activity FGS / epoch store / watcher。
- 未验证 AppOps callback 在目标 OEM、进程状态与 rapid revoke/regrant 下的实际顺序和丢失行为。
- 未验证 specialUse FGS 的商店/发布可接受性。
- 未测电池、通知、OEM、重启或权限 Gate。
- 未构建/安装候选 APK。
- 未证明 A3-D2，A3-D 仍未通过。
