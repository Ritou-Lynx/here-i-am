# MDA-2 A3-I 初交付 W0 审查

> 固定候选：`5f54d5b407ef206ed23899df3ec22b63d8fdc39a`；父项：`c5d7cbfe559eb517b3b1110f27e07dc8308d6442`。结论：拒绝，等待同任务追加 R1；不得单独集成。

## 固定对象与范围

- task：`01a099d5-e30d-7631-9ffc-2c3687f0975c`；Worktree：`7990/memex`；分支：`codex/mda2-a3i-android-native-20260913`。
- rollout `turn_context` 独立核实为 `gpt-5.6-sol / high`。
- commit 恰有 14 条路径：13 条新增、`ChannelRegistrar.kt` 一行注册；均在 A3-I 拥有路径内。
- `AndroidManifest.xml`、旧 `PhoneUsageChannelHandler.kt`、`MainActivity.kt`、根依赖、Core、DB、BLE、Check-in、全局状态均相对父项零 diff；Manifest Git blob 在父项与候选均为 `69ac7dfaf315cb3f207a1fe4745f21963a573596`。

## 阻断发现

### P1 — 冻结 outbox 的 owner gate 未在 dispose 释放

`AndroidActivityCollector._closeStores()` 在 `store.lineageBlocked` 时直接跳过。A2 的 `lineageBlocked` 同时表示 closed、poisoned 或持久 frozen；frozen store 仍持有 owner lease，且 `close()` 可正常释放。

W0 从固定 commit 的 Git 干净导出副本新增第 15 项回归：初始化两个 source 后，直接让 usage outbox 以不允许 kind 触发 `scope_denied` 并进入 frozen；随后调用 `collector.dispose()`。原 14 项先通过，新回归实际失败：期望 owner 被移除，实际 `ownerRemainedAfterDispose=true`。测试 finally 直接调用同一 frozen store 的 `close()` 后可完成清理，证明被遗漏的是 A3 close 路径。

影响：同进程仍占有 `owner.gate`，后继初始化只能停在 owner active/recovery，违反显式停用必须释放本地 ownership 的生命周期契约。当前候选不得集成。

## 同轮返修要求

1. 对持有的非空 store 关闭，不以 `lineageBlocked` 代替 ownership 状态；新增 frozen usage/screen dispose 后 owner 移除、后继可取得 gate 的回归。
2. `queryUsageEvents` 必须在调用 `UsageStatsManager.queryEvents` 前拒绝负数、空或反向窗口。
3. `activate` / `queryUsageEvents` 的 MethodChannel request 必须在 receiver/query/state mutation 前拒绝 unknown/missing keys。
4. `verify_a3_static.ps1` 必须比较显式 Base commit 与 Candidate commit。初交付在已提交干净树运行 `git diff HEAD` 得到 `changed_paths=0`，不能作为候选范围或保护路径证明；W0 已独立用父项到候选补做 14 路径核验。

## 边界

- 没有集成、push、APK、adb、真机、真实 UsageEvents/Core/凭据/数据库/网络/BLE 或 A3-D Gate。
- W0 干净导出测试 scratch 只在当前 W0 的 `tmp/mda2-a3-w0-review-5f54d5b4`；不改 worker commit。
