# A3-D Android OEM 延迟解锁失败记录

> W0 真机裁决：2026-09-16。设备 `SM-S9110` / Android 16；诊断源码 `v3-lab@6ea772f18bb1ad7b50a5a04eafc3e972af91116c`。

## 候选绑定

- hereIAmV3 Debug APK SHA-256：`C43B3767DD894F69F60A52F010CEEF4676FA293241E3D804BDF8A8D22D0F820D`
- 包名：`com.memexlab.hereiam.v3`
- 版本：`1.0.30 (113)`
- 设备安装后的 `base.apk` 与候选 hash 一致。

## 已通过的短场景

- 未显式开始时无 receiver、Usage query、outbox 或 sequence。
- Usage Access 的 denied → grant → revoke → regrant 行为成立；重授前的活动没有回填，只记录授权后的新粗类别事件。
- 前台人工锁屏、亮屏、解锁三事件成立；只保存固定类型、时间与计数，不含包名、App 名或 raw UsageEvents。
- force-stop 后 owner 保留；重启诊断保持 `recovery_authority_required`；显式 reset 删除精确诊断根，随后可重新开始。
- 真正的短 Doze 达到 `IDLE`，进程与动态 receiver 存活；退出 forced idle 后系统恢复 `ACTIVE`。

这些通过项只属于同一 APK 的局部设备证据，不足以覆盖后述失败，也不建立生产 binding、传输、调度或 BLE 共存结论。

## 阻断失败

三星把 2026-09-15 22:01:10.402 入队的 `ACTION_USER_PRESENT` 保留到应用回到活动进程。系统记录显示该 receiver 在 2026-09-16 00:17:13.448 才以 `mBroadcastConsumerDeferClear` 投递，`scheduled +2h16m3s46ms`。应用随后写入：

```text
sequence=3
kind=session.unlocked
signal_at_ms=1789489033614
```

当前实现从 `BroadcastReceiver.onReceive` 调用 `System.currentTimeMillis()`，所以写入的是投递时间，而不是解锁发生时间。两小时旧广播因而被伪装成刚发生的高置信解锁，违反 fail-closed freshness 与 OEM gap 约束。

本机原始证据位于 `tmp/mda2-a3d-device-evidence/RFCWC01PBKK/C43B3767/oem_deferred_unlock_failure_20260916_001820/`。关键材料为 `broadcasts_full.txt:18826`、`decoded_screen_events.json`、screen state/owner/anchor 及同窗设备锁定状态。

## W0 修复审计

W0 评估过以 `UsageStatsManager.queryEvents` 的 `KEYGUARD_HIDDEN` / screen event 原始时间戳替代广播收件时间。它能拒绝明显过期的两小时事件，但不能证明应用处于 cached/dead 状态时 Usage Access 没有经历撤销再重授；当前 AppOps 查询只能证明查询当下已授权，仍可能回填撤销区间。进程内 watcher、activation time 或 mtime 也不能补足这段连续授权权威。

因此该修补不进入候选。隔离树中的试验 diff 已撤销，生产源没有新增修改或 commit。

## 裁决与后续边界

- A3-D2 Doze/OEM Gate：**FAIL**。
- 当前 `C43B…F820D` 候选冻结；不继续 BLE 共存验收，不把局部通过项提升为 A3-D 设备通过。
- 下一工作包必须先定义 Android 屏幕/解锁的可信发生时间和连续授权 epoch。若需要 FGS、AppOps 监听、持久授权权威或新 source semantics，必须作为独立范围提案；不得在 A3-D 诊断补丁中静默加入。
- 任一新 APK hash 必须从零重跑默认关闭、权限、屏幕、process death、Doze/OEM 与 BLE 矩阵。

## 恢复

诊断结束后已覆盖恢复原正式 APK。设备 `base.apk` SHA-256 与安装前备份一致：`E1B39E9B14A8407BE54E9D0E26FBD99AF8F1B52CEC423041D0E93AE570F8EB37`，版本 `1.0.30 (113)`。恢复时蓝牙系统开关为关闭，BLE 为 `STATE_DISCONNECTED`；W0 未替用户改变该开关。
