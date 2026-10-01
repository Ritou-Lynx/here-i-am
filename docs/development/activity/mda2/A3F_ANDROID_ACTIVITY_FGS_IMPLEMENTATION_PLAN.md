# MDA-2 A3-F — Android Activity FGS 权威采集实现计划

> 状态：产品 Gate 已接受；源码 `5110ea19` 已通过 W0 独立审计并选择性本地集成，设备 Gate 待重跑。
>
> 固定起点：`v3-lab@add2c1e6e06a8606fa6e6d58061f7540ca2fa958`。
>
> 上游裁决：[A3-E W0 验收](android/a3e_review/45daa2d9/W0_ACCEPTANCE.md)。

## 本轮闭环

实现一个仍由 A3-D Debug 诊断入口显式启停、默认不运行的 Android 候选：独立 Activity foreground service 维持 prospective observation；AppOps watcher、boot/authorization epoch、owner fence 与 query cursor 共同限定可提交区间；screen/keyguard 信号只使用 UsageEvents 原始 occurrence timestamp。动态广播只能唤醒查询，不能提供事件时间。

本包只交付代码、自动断言、静态范围证明、干净 commit 与 handoff。W0 回收通过后才构建唯一 hereIAmV3 APK 并执行真人设备 Gate。

## 用户已接受的产品取舍

- 用户显式 opt-in 后才启动 Activity observation。
- 运行期间使用用途明确、持续可见且带独立停止入口的通知。
- 接受为此产生的额外耗电，以及 Android/OEM 对 FGS 启动、通知和存活的限制。
- 如果通知可见性、服务前台状态或授权连续性无法证明，来源转为 unavailable/unknown 并停止接受事件。

## 拥有路径

### Android

- 新建 `android/app/src/main/kotlin/com/memexlab/memex/activity/ActivityObservationForegroundService.kt`
- 新建 `android/app/src/main/kotlin/com/memexlab/memex/activity/ActivityPermissionEpochStore.kt`
- 新建或拆分 `android/app/src/main/kotlin/com/memexlab/memex/activity/ActivityUsageEventSource.kt`
- 最小修改 `android/app/src/main/kotlin/com/memexlab/memex/activity/AndroidActivitySignalCollector.kt`
- 最小修改 `android/app/src/main/kotlin/com/memexlab/memex/channels/ActivitySignalChannelHandler.kt`
- 最小修改 `android/app/src/main/AndroidManifest.xml`，仅添加该独立 service、准确 FGS permission/type/subtype；不得借用其他 service type
- 对应 `android/app/src/test/kotlin/com/memexlab/memex/activity/**`

### Dart 与诊断入口

- `lib/data/services/activity/mda2_android/**`
- `test/data/services/activity/mda2_android/**`
- `lib/ui/a3d_device_gate/**` 与 `lib/a3d_device_gate_main.dart`，只用于显式 opt-in/start/stop/readiness/coverage/evidence
- 如需补充 A3-D 静态验证，可最小修改现有 `verify_a3d_*` 脚本
- 交接文档：`docs/development/activity/mda2/android/a3f/**`

## 强制边界

- 正常 `main.dart`、生产 router/settings/DI 不接线；A3-F 仍是 Debug 诊断候选。
- 不修改 Core、broker canonical sequence/TTL/validation、A3-I secure outbox schema 或共享 MDA wire/schema。若现有 wire 无法承载必要的 readiness/epoch 证明，停止并在 handoff 提出最小变更，不自行扩大。
- 不触碰、复用或联动 `BleHeartRateService`、Companion foreground task、check-in 的 service、notification channel、owner、start/stop/recovery。
- 零 packageName/appName/accessibility 内容出站；只允许 coarse category、screen/session signal 与最小 coverage/readiness 证明。
- 不 build/install/adb/手机/真实数据，不 push、不发布，不声称 A3-D 通过。
- worker 不创建子 Agent。

## 权威与恢复规则

1. 当前 AppOps `allowed` 只能从“被存活 watcher 与首次复核共同观察到”的时刻开启新 epoch，不能证明此前区间。
2. watcher 注册、首次 check、查询前复核、查询后复核必须形成 fail-closed quarantine；任一 edge/race 使 batch 与旧 epoch tainted。
3. 事件必须位于同一 boot、owner fence、sealed allowed epoch 的 `[begin, end)` 内，且使用 `UsageEvents.Event.timeStamp` 原样时间。
4. process/service death、Task Manager Stop、force-stop、reboot、boot marker 变化、owner mismatch、未封口 tail、持久化异常均产生 unknown gap；恢复后从当前重新开新 epoch。
5. 动态 `SCREEN_*` / `USER_PRESENT` receiver 只发 query hint；callback 时钟不得进入 `signal_at_ms`。
6. query null/exception/empty、permission denied/revoked、设备未解锁、事件过期和无活动必须分开；empty 不能证明 inactivity。
7. 不使用 mtime、短阈值、DPAPI/文件可读、当前 keyguard/AppOps、重启 uptime 或自洽快照推断 authority。

## 必须自动证明

- 固定 22:01 入队、00:17 收到的设备反例不产生 00:17 fresh unlock；无法证明 epoch 时整条拒绝。
- raw `KEYGUARD_HIDDEN`、screen event timestamp 原样通过，query/receive/ingest 时间分离。
- revoke、regrant、快速 revoke→regrant，以及 watcher/check/query 四类竞态不会跨 epoch 提交。
- service/process death、stop、force-stop、reboot、owner mismatch、损坏/未封口持久状态均 fail closed。
- 未 opt-in、notification 不可见、`startForeground` 未成功、后台启动被拒时不建立 readiness/epoch。
- Activity FGS 单独启停、异常和恢复不会启动、停止或复活 BLE、Companion、check-in。
- privacy/static tests 证明 package/app/raw payload 为零，正常应用入口零引用。
- 复跑现有 A3-D、A3、A2、A1 及 wire/Core 相关回归；记录每组真实计数与 exit code。

## W0 回收标准

- worker 分支基线精确绑定 `add2c1e6`，范围只含上述拥有路径与命名 handoff，worktree clean。
- commit 与 handoff 写明实现状态、失败历史、测试命令/计数、剩余 platform/OEM 风险和 shared-contract 判断。
- W0 逐路径审计 Manifest/FGS/epoch/race/privacy/隔离性，独立复跑关键断言与相邻回归。
- 只有 W0 接受后才选择性集成；随后从干净提交执行 critical fixes、构建唯一 hereIAmV3 APK hash，并从零重跑 A3-D 真机矩阵。

## 派发回执

- client task：`client-new-thread:90aa1164-ddc3-4f90-940e-c2965c77cd8a`；真实 thread ID 待桌面任务索引完成后回填
- Worktree：`C:/Users/ExampleUser/.codex/worktrees/628c/memex`
- 分支：`codex/mda2-a3f-activity-fgs-20260916`
- 首次核对：Worktree 已创建，分支已从精确 `add2c1e6e06a8606fa6e6d58061f7540ca2fa958` 建立，当前尚无工作区改动
- 路由：L2，`gpt-5.6-sol / high`

## W0 回收

- 最终源码：`5110ea19dd4e851eb8f620acdeb10d6e43149f93`，19 路径，worker Worktree clean。
- W0 独立复测：Android 22/22、A3 18/18、A3-D 14/14、A1 56/56、A2 31/31、wire/Core 20/20；analyze、mirror identity、A3-F/A3/A3-D 静态守门与 diff check 通过。
- 本地源码集成：`v3-lab@3da91ebc`；正常应用仍未接线，未产生或安装 A3-F APK。
- 验收边界与后续停点见 [W0验收](android/a3f_review/5110ea19/W0_ACCEPTANCE.md)。A3-D2 继续 FAIL，旧设备证据不得转移到新 hash。
