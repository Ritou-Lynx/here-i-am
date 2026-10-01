# MDA-2 A3 — 主 Android 原生信号与安全持久边界

> 2026-09-13；W0 验收主窗计划。集成基线：`v3-lab@c5d7cbfe559eb517b3b1110f27e07dc8308d6442`。
> A2 源码提交：`fe283a7336a7ae53253ef4e5b5419a289e763463`；本地落地收据：`c5d7cbfe559eb517b3b1110f27e07dc8308d6442`。
> 本包形成默认关闭的 Android 原生接线候选与本地自动验证；不安装 APK、不访问真实 UsageEvents、不连接真实 Core、不执行设备或真人 Gate。

## 目标与拆分

A3 分成两个串行部分：

1. **A3-I（本任务）**：在隔离 Worktree 中实现 Kotlin 原生边界、Flutter bridge、应用私有持久目录与 Android Keystore 支持的完整性密钥托管，并接到 A2 的 normalizer/outbox。所有生产入口默认关闭；没有服务端签发的每-source binding 时不得创建 collector。
2. **A3-D（后续真人 Gate）**：W0 选择性集成并完成唯一 hereIAmV3 候选构建后，才另行授权真机 Usage Access、亮屏/解锁、划掉任务、Doze、force-stop、重启和 BLE 同时运行。A3-I 的本地测试不能代替 A3-D。

## A3-I 必须实现

- 新建独立的 Android activity-signal 通道；不得复用会返回 `packageName` / `appName` 的 `PhoneUsageChannelHandler` 作为活动上传路径。
- UsageEvents 查询只在原生侧接收注入的、白名单化的 `package -> coarse category` 映射；通道输出只允许固定类别、事件时间、来源和权限状态。映射缺失、权限拒绝或撤销时不产生活动事件，并返回明确 readiness/coverage 状态。
- 动态监听 `ACTION_SCREEN_ON`、`ACTION_SCREEN_OFF`、`ACTION_USER_PRESENT`，生命周期绑定到 Flutter engine/process；明确它不能证明 force-stop、重启或整夜后台连续采集。
- Dart 侧把平台信号映射到现有 `AndroidActivityNormalizer`，并按 `android_usage_events` / `android_screen_state` 分离 source binding、sequence 和 outbox 目录。不得扩展 `device.activity.v1`、kind、payload 或 Core response wire。
- outbox 根目录使用应用私有 `noBackupFilesDir`（或等价的明确不备份私有目录），通过原生通道返回路径；目录中不得保存 token、包名、应用名或原始 UsageEvents。
- 为 A2 integrity/age-proof authority 建立专用 32-byte 随机密钥仓库，使用已有 `flutter_secure_storage` 的 Android Keystore 后端；首次生成、读取、损坏、缺失与清除均 fail closed，禁止日志输出和备份。不得复用现有 Core device token、同步口令或 BLE 凭据。
- collector 总开关默认关闭；启用构造必须同时具备用户侧 enabled、完整密钥和服务端签发的该 source binding。缺一项只返回 readiness/unknown，不注册接收器、不查询 UsageEvents、不分配 sequence。
- 只提供可注入 sender 接口或保持 A2 sender 边界；本包不实现 HTTP、真实 Core 认证、自动重试调度、WorkManager、Alarm、FGS、boot receiver 或开机自启。
- 异常和审计只使用固定非敏感码与计数；平台异常正文、包名、标签、Intent 内容不得进入 wire、持久文件、日志或测试证据。

## 拥有路径

独立任务可写：

- `android/app/src/main/kotlin/com/memexlab/memex/activity/**`（新建）
- `android/app/src/test/kotlin/com/memexlab/memex/activity/**`（新建）
- `android/app/src/main/kotlin/com/memexlab/memex/channels/ActivitySignalChannelHandler.kt`（新建）
- `android/app/src/main/kotlin/com/memexlab/memex/channels/ChannelRegistrar.kt`（仅注册新通道）
- `lib/data/services/activity/mda2_android/**`
- `test/data/services/activity/mda2_android/**`
- `docs/development/activity/mda2/android/a3/**`

`AndroidManifest.xml` 原则上不改。若实现证明必须修改，先停止并在 handoff 中给出最小 diff 与理由，由 W0 单独裁决。不得修改现有 `PhoneUsageChannelHandler.kt`、`MainActivity.kt`、BLE service/receiver、Companion foreground task、Check-in/Alarm/WorkManager、Core/validator、数据库 schema、DI/UI、根依赖、全局 Roadmap、`I_PROJECT_STATE.md` 或 `DEVLOG.md`。

## 自动验收

- Kotlin 单元测试覆盖：许可 granted/denied/revoked、窗口边界、未知事件过滤、白名单类别化、无映射不输出、屏幕事件固定映射、异常固定码、无包名/应用名泄露。
- Dart 测试覆盖：默认关闭；缺 binding/密钥 fail closed；两个 source 独立目录/序号；私有目录选择；密钥首次生成/复用/损坏/清除；权限撤销产生 unknown/gap 且不沿用旧活动；平台重复/乱序/未来时间不绕过 A2 约束。
- 复跑 A1 `56/56`、A2 `30/30`、现有 wire/Core 合成矩阵；专项 `dart analyze --fatal-infos` 无问题；Android `hereIAmV3Debug` 单元测试任务通过；`git diff --check` 通过。
- 静态负面守门：没有新增网络客户端、明文凭据、FGS/receiver/boot/scheduler、Manifest 改动、现有 BLE 生命周期耦合、包名/应用名进入 Dart/outbox/wire。

## 交付与回收

- 从精确 `v3-lab@c5d7cbfe559eb517b3b1110f27e07dc8308d6442` 创建隔离 Worktree；不得读取或复制 `D:/memex` 的未提交文件。
- 提交一个边界清晰的候选 commit，并在 `docs/development/activity/mda2/android/a3/HANDOFF.md` 记录真实模型、分支、基线、完整 SHA、路径 manifest、测试 exit、失败尝试、支持/不支持及 A3-D Gate 模板。
- 不 push、不 merge、不 handoff 到主目录、不构建/安装 APK、不调用 adb、不访问真实 UsageEvents/Core/凭据/数据库/网络/手机/BLE 数据。
- W0 独立审计固定 commit、关键隐私断言与回归后，才决定是否选择性集成；集成也不等于 A3-D 或 MDA-2 通过。

## 派发记录

- 创建回执：`client-new-thread:ed61cddd-21a1-48b5-820d-0dabc86b80e6`，host `local`。
- 正式 task `01a099d5-e30d-7631-9ffc-2c3687f0975c`；隔离 Worktree `C:/Users/ExampleUser/.codex/worktrees/7990/memex`；任务从干净 `c5d7cbfe559eb517b3b1110f27e07dc8308d6442` 创建分支 `codex/mda2-a3i-android-native-20260913`。
- 路由：L2，`gpt-5.6-sol / high`。
- 初交付 `5f54d5b407ef206ed23899df3ec22b63d8fdc39a` 已由 W0 拒绝：冻结 outbox 在 collector dispose 时被 `lineageBlocked` 分支跳过 close，留下 owner 文件与进程 gate；另有原生查询窗口先于系统 API 校验、MethodChannel request shape 和静态脚本基线绑定缺口。原任务正在追加最小 R1，初交付不得单独集成。
- R1 `c0bf3d49cf145cb2505750bd2d4e4d26e2e1eb9c` 已关闭上述缺口。W0 干净导出独立复跑 A3 Dart `16/16`、A3 Kotlin `12/12`、A1 `56/56`、A2 `30/30`、wire/Core `20/20`，完整 `hereIAmV3Debug` App 单元任务也通过；范围仍为基线到最终候选 14 路径，Manifest 与保护区零 diff。W0 接受其进入选择性本地源码集成；A3-D 仍未启动。见 [R1验收](android/a3_review/c0bf3d49/W0_ACCEPTANCE.md)。
