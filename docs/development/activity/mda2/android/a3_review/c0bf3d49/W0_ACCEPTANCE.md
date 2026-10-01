# MDA-2 A3-I R1 W0 独立验收

> 固定候选：`c0bf3d49cf145cb2505750bd2d4e4d26e2e1eb9c`；父项：`5f54d5b407ef206ed23899df3ec22b63d8fdc39a`；集成基线：`c5d7cbfe559eb517b3b1110f27e07dc8308d6442`。
> 结论：通过本地源码验收，允许 W0 选择性集成最终 14 路径；初交付 `5f54d5b4` 不单独集成。

## 裁决

- 初交付的阻断项已经关闭：collector 释放所有已取得的 store，不再用 `lineageBlocked` 跳过 ownership 清理；冻结 usage 与 screen 两条 lineage 均验证 owner 删除，且相同 binding/key 的精确后继可重新取得并关闭 gate。
- UsageEvents 窗口在系统查询前验证；负数、空窗与反向窗不会调用原生查询。`activate` / `queryUsageEvents` 只接受精确键集合与整数时间，非法形状在 receiver、查询或状态变化前拒绝。
- 仍使用独立 activity-signal 通道。包名只在 Kotlin 进程内映射为固定 coarse category；Dart/outbox/wire 不接收包名、应用名或原始 UsageEvents。
- collector 保持默认关闭。缺 user enabled、32-byte 专用密钥或对应 source binding 时，不注册 receiver、不查询 UsageEvents、不创建 outbox/sequence。
- usage 与 screen 使用独立 binding、目录、sequence 和 owner；持久根位于 `noBackupFilesDir`，密钥由 `flutter_secure_storage` 的 Android Keystore 后端托管，`resetOnError=false`，损坏或缺失 fail closed。

## W0 独立验证

- 从 Git commit 导出到干净临时目录，未使用 worker 工作树未提交文件。
- A3 Dart：`16/16`；source/test analyze 无问题；测试镜像与候选文件逐字节一致。
- A3 Kotlin 隔离 `hereIAmV3Debug` source set：`12/12`，`BUILD SUCCESSFUL`；镜像与候选文件逐字节一致。
- A1：`56/56`；A2：`30/30`；两组 analyze 无问题；镜像与候选文件逐字节一致。
- 既有 wire/Core：fixture `20/20`、内存 Core `20/20`；6 项未知诊断、7 项隐私负例、duplicate/TTL 边界通过。
- 完整 App `testHereIAmV3DebugUnitTest`：`BUILD SUCCESSFUL`，723 个任务。因无网络且本机没有 `androidx.test:runner:1.2+` 动态版本清单，临时生成元数据排除了生产代码未使用的 `integration_test` dev plugin，并补入相应生成 registrant；候选、应用源码和生产插件未改。
- 静态范围脚本以显式 Base/Candidate 比较通过：14 条路径；Manifest blob 在基线和候选均为 `69ac7dfaf315cb3f207a1fe4745f21963a573596`；`git diff --check` 通过。

## 接受范围

接受最终 Base..Candidate 的 14 条路径：3 个 Kotlin 实现、1 行 channel 注册、1 个 Kotlin 测试、3 个 Dart 实现、1 个 Dart 测试、3 个验证脚本、测试 `.gitignore` 与 A3 handoff。`AndroidManifest.xml`、旧 `PhoneUsageChannelHandler.kt`、`MainActivity.kt`、根依赖、Core、DB、BLE、Check-in、调度器及 UI 均零 diff。

## 保留 Gate

本裁决只接受默认关闭的本地源码接线。它不证明真实 Usage Access、屏幕广播持续性、划掉任务、Doze、force-stop、重启、OEM 后台限制、Keystore 真机行为、BLE 共存或一晚连续性。未构建/安装 APK，未调用 adb，未访问真实 UsageEvents、Core、凭据、数据库、网络、手机或 BLE 数据。A3-D 必须另行形成唯一 APK 哈希并由 Lynx 完成真机 Gate。
