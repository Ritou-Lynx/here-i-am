# MDA-2 A3-E W0 架构验收

> 日期：2026-09-16
>
> worker：`01a0a5e9-8177-7ca3-a4fe-62e528a3d455`
>
> 候选：`45daa2d9e7a8aa28ddf044ebfc70c31e0c4313d9`
>
> 基线：`6ea772f18bb1ad7b50a5a04eafc3e972af91116c`

## 裁决

W0 接受两份 docs-only 交付为**条件性架构候选**，不接受为实现、Android 后台权威已成立、A3-D passed 或设备验收。

唯一可继续评审的方向是：用户明确 opt-in 后启动独立、可见的 Activity foreground service；在服务存活期间监听 AppOps edge，持久化 boot/authorization epoch/owner fence/query cursor，并只提交落在同一已证明 epoch 内、带 UsageEvents 原始发生时间的粗粒度 screen/session 事件。

以下路线保持 no-go：

- 读取 UsageEvents 后仅凭当前 AppOps allowed 回填历史；
- 用动态 `ACTION_USER_PRESENT` / screen broadcast 的 callback 收件时间生成 occurrence time；
- 用短时间阈值、mtime、重启后 uptime、当前 keyguard/AppOps 或自洽快照推断连续 authority；
- 把 foreground-only 说成持续后台 coverage；
- 复用 BLE 或 Companion 的 foreground service、通知、owner 或启动/停止生命周期。

如果产品要求覆盖观察进程死亡区间，并证明期间从未发生 revoke/regrant，公开 Android API 没有历史 AppOps 审计能力；该要求下 Android screen source 应保持 no-go。

## 独立证据

- 固定反例：SM-S9110 / Android 16 将 `ACTION_USER_PRESENT` 从 `2026-09-15 22:01:10.402` 延迟至 `2026-09-16 00:17:13.448` 投递；现实现以 `System.currentTimeMillis` 写成 fresh `session.unlocked`，所以 A3-D2 FAIL。
- Android 14 官方行为允许 cached app 的 context-registered broadcast 延迟到离开 cached 后再投递，且可能合并。
- `ACTION_USER_PRESENT` 没有原始发生时间字段；UsageEvents 的 screen/keyguard event 提供原始 timestamp，但当前 AppOps 状态不证明历史连续授权。
- Android 14+ foreground service 必须声明合适 type/permission；未覆盖的有效用途可能使用 `specialUse`，需要 manifest subtype，并接受 Play review。Android 12+ 后台启动 FGS 另有明确限制。
- Android 13+ 通知权限拒绝不会自动免除 FGS notification；若产品要求用户持续可见，通知不可见时必须停用或保持 unknown。

核对的主要源码边界：

- `AndroidActivitySignalCollector.kt` 的动态 receiver 目前使用注入 clock 作为事件时间；
- `ActivitySignalChannelHandler.kt` 当前 owner 绑定 Flutter engine，且 Usage Access 只查询当前状态；
- Dart wire 当前没有 authorization epoch/fence；
- 现有 broker sequence/TTL、secure outbox、BLE 与 Companion 生命周期不属于本包改动范围。

## 范围与验证

- 候选相对基线只新增 `AUTHORITATIVE_SCREEN_SOURCE_OPTIONS.md` 与 `HANDOFF.md`，共 443 行。
- worker worktree clean；`git diff --check 6ea772f1..45daa2d9` exit 0。
- W0 核对官方 Android 一手文档、关键源码路径、设备反例和 fail-closed 边界。
- 主线选择性集成为 `c240a83f26e4235821b8b0472e9c091f1e6c2ed7`；父提交为固定基线，两份文件 blob 与候选一致，集成后 index 为空。
- 本次没有 Kotlin/Dart/Manifest/Gradle/Core/wire/schema/UI 修改，没有 build、install、adb、手机操作、真实数据采集、push 或发布。

## 下一 Gate

先由 Lynx 决定是否接受明确 opt-in、持续通知、额外耗电以及 OEM/商店限制。只有接受后，W0 才创建独立实现包；实现必须生成新的唯一 APK hash，并从零重跑 A3-D 全矩阵及 BLE 隔离 Gate。否则保留 foreground-only/unknown，停止 Android 后台 screen source。
